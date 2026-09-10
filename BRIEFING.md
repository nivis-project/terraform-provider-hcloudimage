# Briefing: `terraform-provider-hcloudimage`

**Purpose.** A production-quality Terraform/OpenTofu provider that uploads a raw disk image into a Hetzner Cloud project and turns it into a reusable snapshot, using the rescue-server upload trick. Built to be consumed by Nivis, publishable to both public registries, and demonstrably a quality provider (tests, coverage, CI, signed releases).

**Repo:** `github.com/nivis-project/terraform-provider-hcloudimage`
**Registry address:** `nivis-project/hcloudimage`
**License:** MPL-2.0

---

## 0. How to use this document (for the implementing agent)

This is a complete specification. Implement it end to end. Where a concrete config is given (goreleaser, manifest, workflow triggers, schema attributes) treat it as a requirement, not a suggestion — those are the error-prone bits. Where behaviour is described in prose, satisfy the behaviour; you choose the code.

**Definition of done is Section 12.** Do not consider the task complete until every box there is green, including the hermetic NixOS-VM lifecycle test passing under `nix flake check`. Human-only prerequisites (Section 14 — GPG key, registry onboarding, GitHub secrets) are out of scope for the agent; stub/document them and move on.

---

## 1. Locked decisions

| Decision | Choice |
|---|---|
| Language / framework | Go, `terraform-plugin-framework` (protocol v6). **Not** SDKv2. |
| Go version | Latest stable at implementation time; pin in `go.mod` and flake. |
| Upload engine | Depend on `github.com/apricote/hcloud-upload-image/hcloudimages/v2`. |
| Distribution | Public Terraform Registry **and** OpenTofu Registry, both fed by GitHub releases. |
| E2E realism | Real, billable acceptance tests against a live Hetzner project in gated CI. |
| Provider surface | One resource `hcloudimage_image` + one data source `hcloudimage_snapshot`. |
| Image source | `image_url` **or** `image_path`, mutually exclusive. All four compressions. |
| Build | Nix flake, `buildGoModule`, hermetic. |
| Guest architectures | `x86` **and** `arm` (arm64/CAX) supported from day one. |
| E2E test image | Minimal **Alpine** generic-cloud image, throwaway SSH key baked in, built/pinned via Nix. NixOS is a documented fallback. |
| E2E server creation | Real workflow via the official `hetznercloud/hcloud` provider composed in the same config. |

---

## 2. Goals & non-goals

**Goals**
- A single-purpose provider that does the upload-to-snapshot flow reliably and is pleasant to read as reference code.
- First-class OpenTofu compatibility, validated in CI (examples run under both `terraform` and `tofu`).
- Consumable by Nivis via a Nix-built provider mirror, without touching a public registry.
- Signals of quality visible to outsiders: green CI badges, coverage badge, generated docs, signed releases, changelog.

**Non-goals**
- Multi-cloud. The rescue-server trick is Hetzner-specific; the provider is deliberately Hetzner-only.
- Building the disk image itself. That is the user's job (e.g. `outskirtslabs/nixos-hetzner`). The provider consumes a finished `.raw[.xz|.bz2|.zst]`.
- Managing servers/networks. Users compose this provider with the official `hcloud` provider.

---

## 3. Provider surface specification

### 3.1 Provider configuration

| Attribute | Type | Req | Notes |
|---|---|---|---|
| `token` | string, sensitive | opt | Hetzner API token. Falls back to `HCLOUD_TOKEN` env var when unset. |
| `endpoint` | string | opt | Override hcloud API endpoint (testing/mock). Defaults to the SDK default. |
| `poll_interval` | string (duration) | opt | Optional passthrough for action polling. |

### 3.2 Resource `hcloudimage_image`

Creates a temporary rescue server, writes the image, snapshots it, cleans up. On destroy, deletes the snapshot.

| Attribute | Type | Req | ForceNew | Notes |
|---|---|---|---|---|
| `image_url` | string | one-of | yes | Public `https://` URL. Mutually exclusive with `image_path`. |
| `image_path` | string | one-of | yes | Local file path on the apply host. Streams over SSH. Mutually exclusive with `image_url`. |
| `image_sha256` | string | cond | yes | **Required when `image_path` is set.** The ForceNew trigger for local files. Users set it via `filesha256(var.image_path)`. Ignored/optional for `image_url` (URL string change is the trigger). |
| `architecture` | string | yes | yes | `x86` or `arm`. Maps to `hcloud.ArchitectureX86` / `ArchitectureARM`. |
| `compression` | string | opt | yes | `none` (default) \| `bz2` \| `xz` \| `zstd`. |
| `format` | string | opt | yes | `raw` (default) \| `qcow2` if the library supports it. Keep minimal; validate the set. |
| `server_type` | string | opt | yes | Override the temporary server type. Defaults per architecture (see Appendix). |
| `location` | string | opt | yes | Temporary server location. Default `fsn1`. |
| `image_size` | int64 | opt | yes | Optional pre-write size validation, passed through to the library. |
| `description` | string | opt | **no** | Updated in place on the snapshot without re-upload. |
| `labels` | map(string) | opt | **no** | Merged onto library defaults; managed in place without re-upload. Enforce Hetzner label rules (no `/` in values). |
| `id` | int64 | computed | — | Snapshot image ID. |
| `effective_labels` | map(string) | computed | — | Final label set on the snapshot (user + library defaults). |

**Behaviours (must hold):**
- Exactly one of `image_url` / `image_path` set — enforce with a config validator, not just docs.
- `image_sha256` required iff `image_path` set — config validator.
- Changing any ForceNew attribute triggers `RequiresReplace` (re-upload → new snapshot).
- Changing `description` or `labels` updates the existing snapshot in place; no rescue server, no re-upload.
- `Read` fetches the snapshot by ID; if it no longer exists, remove from state (no error).
- `Delete` deletes the snapshot image.
- Support a `timeouts` block (create/read/delete) — uploads are slow.
- Cleanup must be robust: on any failure mid-upload, the library's own cleanup runs (`DebugSkipResourceCleanup=false`). Do **not** expose a skip-cleanup escape hatch in the public schema; if needed for debugging, gate it behind an env var only.

### 3.3 Data source `hcloudimage_snapshot`

Look up an existing snapshot so users can reference images they did not create in this state.

| Attribute | Type | Req | Notes |
|---|---|---|---|
| `id` | int64 | one-of | Look up by image ID. |
| `with_selector` | string | one-of | Hetzner label selector; must resolve to exactly one snapshot or error. |
| `most_recent` | bool | opt | If a selector matches many, pick newest when `true`; otherwise error on ambiguity. |
| `name` / `description` / `labels` / `architecture` / `created` | various | computed | Populated from the resolved image. |

---

## 4. Upload engine integration

### 4.1 The seam (testability requirement)

Do **not** call `hcloudimages` directly from the resource. Define an internal interface and inject it. This is what makes the hermetic tests possible without mocking HTTP/SSH.

```go
// internal/provider/uploader.go
type Uploader interface {
    Upload(ctx context.Context, opts UploadRequest) (imageID int64, effectiveLabels map[string]string, err error)
    Delete(ctx context.Context, imageID int64) error
    Get(ctx context.Context, imageID int64) (*SnapshotInfo, error)
}
```

- `uploader_hcloud.go` — the real implementation, wrapping `hcloudimages.Client` + `hcloud.Client`.
- `uploader_fake.go` — in-memory fake used by unit and hermetic lifecycle tests. Records calls, returns synthetic IDs, simulates "snapshot deleted out of band".

The resource depends only on `Uploader`. The provider wires the real one; tests wire the fake.

### 4.2 Mapping config → library

`UploadRequest` maps to `hcloudimages.UploadOptions` (embeds `WriteOptions`):
- `image_url` → `WriteOptions.ImageURL` (rescue server pulls it; fast, off your uplink).
- `image_path` → open file → `WriteOptions.ImageReader` (streams from apply host over SSH; bounded by your upload bandwidth).
- `compression` → `WriteOptions.ImageCompression` (`CompressionNone/BZ2/XZ/ZSTD`).
- `format` → `WriteOptions.ImageFormat`.
- `architecture` → `UploadOptions.Architecture`; `server_type`/`location`/`description`/`labels` → their fields.
- Return `*hcloud.Image` → `.ID` into `id`, resolved labels into `effective_labels`.

Document the url-vs-path bandwidth tradeoff in the resource docs — it is the one non-obvious operational fact.

---

## 5. Required HCL example (must live in the repo)

`examples/resources/hcloudimage_image/resource.tf` — the "it works with Terraform" proof:

```hcl
terraform {
  required_providers {
    hcloudimage = {
      source  = "nivis-project/hcloudimage"
      version = "~> 0.1"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
  }
}

provider "hcloudimage" {} # reads HCLOUD_TOKEN
provider "hcloud" {}

variable "image_path" {
  type    = string
  default = "result/nixos-hetzner.raw.xz"
}

# Upload a locally built NixOS image and snapshot it.
resource "hcloudimage_image" "nixos" {
  image_path    = var.image_path
  image_sha256  = filesha256(var.image_path) # ForceNew trigger for local files
  architecture  = "x86"
  compression   = "xz"
  location      = "nbg1"

  labels = {
    os      = "nixos"
    creator = "nivis"
  }
}

# Boot a real server from the resulting snapshot.
resource "hcloud_server" "demo" {
  name        = "nixos-demo"
  image       = hcloudimage_image.nixos.id
  server_type = "cx22"
  location    = "nbg1"
}

output "snapshot_id" {
  value = hcloudimage_image.nixos.id
}
```

Also provide `examples/provider/provider.tf` and `examples/data-sources/hcloudimage_snapshot/data-source.tf`. All examples must `terraform validate` **and** `tofu validate` in CI.

---

## 6. Repository layout

```
terraform-provider-hcloudimage/
├── main.go
├── go.mod / go.sum
├── internal/provider/
│   ├── provider.go
│   ├── image_resource.go
│   ├── image_data_source.go
│   ├── uploader.go            # interface
│   ├── uploader_hcloud.go     # real impl (hcloudimages/v2)
│   ├── uploader_fake.go       # test fake
│   ├── validators.go          # mutual-exclusion, sha256-required, label rules
│   └── *_test.go              # unit tests
├── examples/                  # runnable HCL (Section 5)
├── docs/                      # tfplugindocs output (generated, committed)
├── templates/                 # optional tfplugindocs templates
├── test/e2e/                  # NixOS VM test + acceptance helpers
├── test/fixtures/             # Nix derivations for Alpine test images (amd64/aarch64)
├── .github/workflows/
│   ├── ci.yml                 # lint + unit + hermetic (every PR)
│   └── release.yml            # goreleaser on tag
├── .goreleaser.yml
├── terraform-registry-manifest.json
├── flake.nix / flake.lock
├── .golangci.yml
├── GNUmakefile                # dev entrypoints; mirrors flake apps
├── README.md
├── CHANGELOG.md
└── LICENSE                    # MPL-2.0
```

---

## 7. Nix / flake

`flake.nix` must expose:
- **`devShells.default`** — `go`, `golangci-lint`, `terraform`, `opentofu`, `tfplugindocs`, `goreleaser`, `gnumake`, and `hcloud-upload-image` (for manual orphan cleanup). Optionally the outskirts image builder for local e2e.
- **`packages.default`** — the provider via `buildGoModule` with pinned `vendorHash`.
- **`checks.hermetic-e2e`** — the NixOS-VM lifecycle test (Section 8.2), so `nix flake check` gates it.
- **`packages.provider-mirror`** — a filesystem-mirror layout (`registry.terraform.io/nivis-project/hcloudimage/<version>/<os>_<arch>/`) so Nivis consumes the locally built binary without a registry. Document the `dev_overrides` alternative for tight iteration.
- **`packages.test-image-{x86,arm}`** — reproducible, version-pinned derivations that produce the acceptance-test fixtures: a minimal Alpine generic-cloud raw image (`amd64` and `aarch64`) with a throwaway SSH public key baked in, recompressed to `.raw.xz`. See §8.3. These are what the billable acceptance job uploads.

Everything hermetic and reproducible; no network in the build beyond fixed-output vendoring.

**aarch64 builder note.** Building `packages.test-image-arm` and the `linux/arm64` provider binary needs an aarch64 build path. Assume none is guaranteed in CI: support all three of a native aarch64 runner, a configured remote builder, and `boot.binfmt` / QEMU emulation, and document which the project actually uses. The arm acceptance job must not silently fall back to an x86 image.

---

## 8. Testing strategy (three layers)

### 8.1 Unit (Go, pure, no network) — runs everywhere, always
- Schema correctness; validators (mutual exclusion, `image_sha256` requirement, label rules).
- Plan-modifier behaviour: ForceNew set fires `RequiresReplace`; `description`/`labels` do not.
- Config → `UploadRequest` mapping (every compression, both sources, arch mapping).
- Resource lifecycle against `uploader_fake` via `terraform-plugin-testing`'s test framework with the fake injected.
- Target: high coverage of `internal/provider`. Report to Codecov.

### 8.2 Hermetic lifecycle (NixOS VM) — the DoD gate, free, in CI
A `pkgs.testers.runNixOSTest` that:
1. Builds the provider, installs it into a filesystem mirror inside the VM.
2. Runs real `terraform`/`tofu` `init → plan → apply → destroy` against a config using the provider, with the **fake uploader** compiled in (build tag or an `HCLOUDIMAGE_FAKE=1` provider mode pointing at an in-VM stub).
3. Asserts: apply creates state with a synthetic `id`; changing `image_sha256` forces replacement in the next plan; changing `labels` does **not**; destroy removes state.

This proves the full Terraform ↔ provider protocol path hermetically, under both `terraform` and `tofu`, with zero cloud cost. It is the definition-of-done gate.

*Optional maximal-fidelity variant (nice-to-have, not required):* run a real `sshd` inside the VM as a stand-in "rescue server" and a stub hcloud API that hands the library that VM's address, so the real `hcloudimages` code path actually SSHes and writes an image to a loopback file. Only pursue if cheap; otherwise the fake-uploader path above is sufficient for DoD.

### 8.3 Acceptance (real Hetzner, billable) — gated
Standard `TF_ACC=1` acceptance tests using the real uploader and `HCLOUD_TOKEN`.

**Test fixture — the image.** Use a **minimal Alpine generic-cloud image**, not NixOS, built and pinned by `packages.test-image-{x86,arm}` (§7):
- Smallest real bootable Linux (tens of MB) → directly lowers per-run upload time and cost on nightly runs, and keeps the suite from *looking* NixOS-coupled (optics for a public provider).
- **Bake a throwaway SSH public key** into the image (`/root/.ssh/authorized_keys` + `sshd` enabled + DHCP). This makes the test cloud-init-free and distro-agnostic — do **not** rely on Hetzner's cloud-init key injection.
- Recompress to `.raw.xz` in the derivation.
- *Fallback:* a minimal NixOS image is acceptable if baking the key into Alpine proves too fiddly; the fixture being NixOS does not make the provider NixOS-only. Alpine is the recommendation.

**Test topology — compose both providers.** The acceptance config is real user-shaped HCL exercised in one `apply`, matching the §5 example:
1. `hcloudimage_image.test` uploads the fixture and snapshots it.
2. `hcloud_server.test` (official `hetznercloud/hcloud` provider) boots from `hcloudimage_image.test.id`.
3. Terraform's own dependency graph orders create/destroy (server torn down before snapshot) automatically.

This deliberately uses the official provider as the *consumer* of your snapshot ID rather than the raw SDK, because the single most important thing the e2e proves is provider-to-provider interop: that the int64 `id` your resource emits flows straight into `hcloud_server.image` with no stringify/parse dance.

**The truth assertions:**
- Snapshot exists with expected `architecture` and merged labels (including the library's `apricote.de/created-by`).
- Server boots and the guest is actually reachable — **SSH from the CI runner into the Hetzner server** (outbound from runner; no inbound-to-runner infra), authenticate with the baked throwaway key, read `/etc/os-release`. "Server reports `running`" alone is **not** a sufficient signal (it fires at hypervisor power-on regardless of rootfs integrity).
- Re-upload semantics against real snapshots (ForceNew) and in-place `label`/`description` updates.

**Architecture coverage.** Run the whole flow for **both** `x86` (CX server + amd64 fixture) and `arm` (CAX server + aarch64 fixture). arm is a first-class Hetzner tier; a provider claiming solidity should prove both. The arm run roughly doubles the billable matrix (and CAX no longer undercuts CX), so it's toggle-gated in CI — see §9.

**Cost/safety controls (mandatory):**
- Cheapest server types only (`cx22` / `cax11`); smallest viable fixture; short timeouts.
- Pin the `hcloud` provider to a version range in the test config so an upstream release can't turn the suite red for unrelated reasons.
- Deferred cleanup that runs even on test failure; fail loudly if cleanup fails.
- ~~A scheduled `cleanup.yml` job runs `hcloud-upload-image cleanup` (label-scoped) to sweep orphans left by crashed runs.~~ Orphans are swept by running `hcloud-upload-image cleanup` locally.
- ~~Never run acceptance tests on PRs from forks (secret exposure).~~ No workflow runs them at all.

> **Superseded by change `drop-billable-hetzner-ci` (2026-09-10):** `acceptance.yml` and
> `cleanup.yml` no longer exist. Billable live-Hetzner CI was dropped as disproportionate for
> an open-source component; the `TF_ACC`/`HCLOUD_TOKEN`-gated acceptance suite stays in the
> tree as an opt-in local run. See `openspec/specs/acceptance-tests/`.

---

## 9. CI/CD (GitHub Actions)

**`ci.yml`** — on `pull_request` and `push`:
- `golangci-lint`; `go build`; `go test ./...` (unit) with coverage → Codecov.
- Matrix `terraform validate` + `tofu validate` over `examples/`.
- `nix flake check` → runs the hermetic lifecycle test (8.2).
- Verify generated docs are up to date (`tfplugindocs generate` produces no diff).

**`acceptance.yml`** — *removed; superseded by `drop-billable-hetzner-ci`. The description below is historical:*
- Uses repo secret `HCLOUD_TOKEN`. Concurrency-limited (one at a time). `TF_ACC=1 go test`.
- Pulls **both** `nivis-project/hcloudimage` (local build) and `hetznercloud/hcloud` — the acceptance config composes them (§8.3). The hermetic layer (8.2) does **not** need `hcloud`; don't wire it there.
- Architecture matrix: `x86` always; `arm` gated behind a `workflow_dispatch` input / label (default off on nightly to contain cost) but **always run before a release**. arm builds/uses the aarch64 fixture (§7 builder note).
- Always-run cleanup step.

**`release.yml`** — on tag `v*.*.*`:
- `goreleaser release --clean`, GPG-signing artifacts (Section 10).

~~**`cleanup.yml`** — nightly `schedule`: label-scoped orphan sweep against the CI project.~~
*Removed; superseded by `drop-billable-hetzner-ci`.*

---

## 10. Release management

Registry publication for both Terraform and OpenTofu is fed by identically signed GitHub release artifacts.

**`.goreleaser.yml` essentials:**
- Builds for `linux/darwin/windows/freebsd` × `amd64/arm64/arm/386` (standard provider matrix).
- Archive name: `{{ .ProjectName }}_{{ .Version }}_{{ .Os }}_{{ .Arch }}.zip`.
- Produces `{{ .ProjectName }}_{{ .Version }}_SHA256SUMS` and a `.sig` signed with GPG (`signs:` block using `GPG_FINGERPRINT`).
- `terraform-registry-manifest.json` copied into each archive.
- `changelog` from conventional commits.

**`terraform-registry-manifest.json`:**
```json
{ "version": 1, "metadata": { "protocol_versions": ["6.0"] } }
```

**Signing / secrets:** `GPG_PRIVATE_KEY`, `PASSPHRASE`, `GPG_FINGERPRINT` as repo secrets. The public key is registered with the registry namespace (human step, Section 14).

**Terraform Registry:** publishes by connecting the GitHub repo + GPG key to the `nivis-project` namespace; picks up tagged releases automatically.

**OpenTofu Registry:** reuses the same signed release artifacts; onboarding is a submission to `github.com/opentofu/registry` referencing the repo and GPG key. Confirm the current submission procedure at implementation time — treat as a documented human step.

Adopt SemVer; start at `v0.1.0`. Keep `CHANGELOG.md` (Keep a Changelog style).

---

## 11. Docs

- `tfplugindocs` generates `docs/` from schema descriptions + `examples/`. Committed and diff-checked in CI.
- Every attribute needs a meaningful `MarkdownDescription`. Include the url-vs-path bandwidth note and the `filesha256()` pattern in the resource doc.
- `README.md`: what it is, install (registry + Nix mirror), quickstart pointing at the example, badges (CI, coverage, registry, license).

---

## 12. Definition of Done (checklist)

- [ ] `hcloudimage_image` resource with the full schema, validators, and ForceNew/in-place semantics of Section 3.2.
- [ ] `hcloudimage_snapshot` data source (by ID and by selector).
- [ ] Real uploader wraps `hcloudimages/v2`; resource depends only on the `Uploader` interface.
- [ ] Runnable HCL examples (Section 5); `terraform validate` **and** `tofu validate` pass.
- [ ] Unit tests with high `internal/provider` coverage; Codecov wired.
- [ ] **Hermetic NixOS-VM lifecycle test passes under `nix flake check`** (apply/replace/in-place/destroy), under both `terraform` and `tofu`.
- [ ] Acceptance tests exist, are gated, and pass against a real project: config composes `hcloudimage_image` + official `hcloud_server`; boots from the snapshot; asserts guest reachability via SSH with a baked throwaway key (not just `running`); covers **both** `x86` and `arm`; contains cost controls + guaranteed cleanup.
- [ ] `packages.test-image-{x86,arm}` produce reproducible Alpine `.raw.xz` fixtures with the baked key.
- [ ] `ci.yml` and `release.yml` present and correct. *(Superseded by `drop-billable-hetzner-ci`: `acceptance.yml` and `cleanup.yml` were dropped — no CI workflow may consume billable Hetzner resources.)*
- [ ] `goreleaser` config produces signed, registry-shaped artifacts; `terraform-registry-manifest.json` present.
- [ ] `tfplugindocs`-generated `docs/` committed and diff-clean in CI.
- [ ] `flake.nix` exposes devShell, package, `checks.hermetic-e2e`, and `provider-mirror`.
- [ ] MPL-2.0 `LICENSE`, `README.md` with badges, `CHANGELOG.md`.
- [ ] Nivis can consume the provider from the Nix mirror end to end (documented, and exercised by the hermetic test's mirror install).

---

## 13. Suggested milestones (incremental, each independently verifiable)

1. **Scaffold**: module, provider server, empty resource, flake devShell + `buildGoModule`. Gate: `go build`, `nix develop`.
2. **Schema + validators + fake uploader**: full resource/data-source schema, config validators, unit tests green.
3. **Lifecycle against fake**: plan/apply/destroy + ForceNew/in-place behaviour under `terraform-plugin-testing`.
4. **Real uploader**: wire `hcloudimages/v2` behind the interface; examples + `validate`.
5. **Hermetic NixOS-VM test** wired into `flake check`. ← DoD gate.
6. **CI**: `ci.yml` (lint/unit/hermetic/validate/docs-diff).
7. **Fixtures + acceptance**: `packages.test-image-{x86,arm}` (Alpine + baked key); `acceptance.yml` composing the official `hcloud` provider, SSH-reachability assertion, cost controls, `cleanup.yml`; verified against a real project for both `x86` and `arm`. *(The two workflows were later dropped — see `drop-billable-hetzner-ci`; the suite itself is an opt-in local run.)*
8. **Release**: goreleaser + signing + manifest + docs; cut `v0.1.0`.
9. **Registry + mirror**: publish; document Nivis mirror consumption.

---

## 14. Human-only prerequisites (NOT for the agent)

The agent stubs/documents these; you do them:
- Create the `nivis-project` GitHub repo and org settings.
- Generate a GPG key; add public key to the Terraform Registry namespace; keep private key + passphrase.
- GitHub secrets: `HCLOUD_TOKEN` (a dedicated, budget-limited Hetzner project), `GPG_PRIVATE_KEY`, `PASSPHRASE`, `GPG_FINGERPRINT`, `CODECOV_TOKEN`.
- Terraform Registry: connect repo + key to `nivis-project`.
- OpenTofu Registry: submit to `opentofu/registry`.

---

## 15. Cost & safety guardrails (summary)

- Use a **separate, isolated Hetzner project** for CI with a spend alert.
- Acceptance tests: cheapest server types, smallest image, short timeouts, guaranteed cleanup. *(Superseded by `drop-billable-hetzner-ci`: the nightly orphan sweep, fork-PR exclusion and concurrency limit were CI-workflow controls; no workflow touches Hetzner any more, so orphans are swept locally with `hcloud-upload-image cleanup`.)*
- No skip-cleanup knob in the public schema.

---

## Appendix — verified `hcloudimages/v2` facts

- Module path: `github.com/apricote/hcloud-upload-image/hcloudimages/v2`.
- Construct: `hcloudimages.NewClient(hcloud.NewClient(hcloud.WithToken(...)))`; call `client.Upload(ctx, UploadOptions{...}) (*hcloud.Image, error)`.
- `WriteOptions` fields: `ImageURL *url.URL`, `ImageReader io.Reader`, `ImageCompression Compression`, `ImageFormat Format`, `ImageSize int64`, `Server *hcloud.Server`.
- `UploadOptions` adds: `Architecture`, `ServerType *hcloud.ServerType`, `Description *string`, `Labels map[string]string`, `Location *hcloud.Location`, `DebugSkipResourceCleanup bool`.
- Compression constants: `CompressionNone` (""), `CompressionBZ2`, `CompressionXZ`, `CompressionZSTD`.
- Library always adds label `apricote.de/created-by=hcloud-upload-image` — surface it in `effective_labels`.
- Default temporary server types: `x86 → cx23`, `arm → cax11`. Default location `fsn1`.
- Snapshot deletion on destroy uses the `hcloud` client's `Image.Delete`.

*Confirm exact field/const names against the pinned version before coding; the module is at major v2.*
