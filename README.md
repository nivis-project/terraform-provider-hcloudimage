# terraform-provider-hcloudimage

[![CI](https://github.com/nivis-project/terraform-provider-hcloudimage/actions/workflows/ci.yml/badge.svg)](https://github.com/nivis-project/terraform-provider-hcloudimage/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/nivis-project/terraform-provider-hcloudimage/branch/main/graph/badge.svg)](https://codecov.io/gh/nivis-project/terraform-provider-hcloudimage)
[![License: MPL-2.0](https://img.shields.io/badge/License-MPL_2.0-brightgreen.svg)](./LICENSE)

A Terraform / OpenTofu provider that uploads a raw disk image into a Hetzner
Cloud project and turns it into a reusable snapshot, using the rescue-server
upload trick (via [`hcloud-upload-image`](https://github.com/apricote/hcloud-upload-image)).

- One resource — `hcloudimage_image` — uploads an image (from a URL or a local
  path) and snapshots it.
- One data source — `hcloudimage_snapshot` — looks up an existing snapshot by ID
  or label selector.
- First-class OpenTofu support (examples validated under both `terraform` and
  `tofu` in CI).
- Hermetic, reproducible Nix build; consumable by Nivis from a Nix-built provider
  mirror without touching a public registry.

## Quickstart

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

resource "hcloudimage_image" "nixos" {
  image_path   = "result/nixos-hetzner.raw.xz"
  image_sha256 = filesha256("result/nixos-hetzner.raw.xz") # ForceNew trigger for local files
  architecture = "x86"
  compression  = "xz"
  location     = "nbg1"
  labels       = { os = "nixos", creator = "nivis" }
}

resource "hcloud_server" "demo" {
  name        = "nixos-demo"
  image       = hcloudimage_image.nixos.id
  server_type = "cx22"
  location    = "nbg1"
}
```

See [`examples/`](./examples) for runnable configurations and [`docs/`](./docs)
for the generated reference.

**URL vs path tradeoff:** `image_url` has the rescue server pull the image
directly (fast, off your uplink); `image_path` streams the file from the apply
host over SSH (bounded by your upload bandwidth). Use `filesha256(var.image_path)`
for `image_sha256` so local-file changes trigger a new snapshot.

## Install

### From a registry (once published)

Use the `required_providers` block above; `terraform init` / `tofu init` fetches
it.

### From the Nix mirror (registry-less, for Nivis)

The flake builds a filesystem-mirror layout so the provider resolves without a
public registry:

```sh
nix build .#provider-mirror   # -> ./result/registry.terraform.io/nivis-project/hcloudimage/...
```

Point a CLI config at it:

```hcl
# ~/.terraformrc
provider_installation {
  filesystem_mirror {
    path    = "/path/to/result"
    include = ["registry.terraform.io/nivis-project/hcloudimage"]
  }
  direct { exclude = ["registry.terraform.io/nivis-project/hcloudimage"] }
}
```

For tight iteration, `dev_overrides` pointing at `nix build .#default`'s
`result/bin` also works.

## Development

Everything runs through the Nix flake (no `flake-utils`; plain `forAllSystems`):

```sh
nix develop            # dev shell: go, golangci-lint, terraform, opentofu, tfplugindocs, goreleaser, hcloud-upload-image
nix build .#default    # build the provider (buildGoModule, pinned vendorHash)
nix flake check        # unit + the hermetic NixOS-VM lifecycle test (the DoD gate)
make test              # go unit + lifecycle tests
make validate-examples # terraform + tofu validate over examples/
make docs              # regenerate docs/ (CI fails on drift)
```

## Testing

Three layers (see the design in `openspec/specs/`):

1. **Unit** — schema, validators, config→request mapping, uploader fake. Runs
   everywhere with no network.
2. **Hermetic lifecycle** (`checks.hermetic-e2e`, gated by `nix flake check`) —
   a NixOS VM runs `init → plan → apply → destroy` under both `terraform` and
   `tofu` with the fake uploader, proving the full protocol path with zero cloud
   cost. **This is the definition-of-done gate.**
3. **Acceptance** (billable, gated) — see below.

### Acceptance tests (billable)

Real tests against a live Hetzner project. They are **skipped** unless
configured, so `go test ./...` stays green without credentials.

To run them you need (these are the human-provided prerequisites):

- `HCLOUD_TOKEN` for a **separate, isolated, budget-limited** Hetzner project
  (set a spend alert).
- A test fixture image built by the flake, to a **dedicated** out-link so other
  `nix build`s (docs, `nix flake check`) don't clobber the `result` symlink:
  `nix build .#test-image-x86 --out-link result-fixture` (or `.#test-image-arm`)
  → `result-fixture/*.raw.xz`.
- The throwaway SSH key in `test/fixtures/` (baked into the fixture; used to SSH
  into the booted server).

```sh
export HCLOUD_TOKEN=...            # isolated CI project
export TF_ACC=1
# Must be ABSOLUTE: the test's filesha256() resolves image_path relative to the
# module dir (a temp dir), not your shell. Use the dedicated result-fixture link
# so an empty glob can't collapse the path to $PWD.
export HCLOUDIMAGE_ACC_IMAGE_PATH="$PWD/$(ls result-fixture/*.raw.xz)"
export HCLOUDIMAGE_ACC_SSH_KEY="$PWD/test/fixtures/throwaway_ed25519"
export HCLOUDIMAGE_ACC_RUN_ARM=0   # set 1 to include the arm leg

# Server type / location default to cx22 / cax11 in nbg1. Availability varies by
# location and account, so override if a type isn't offered where you run (the
# error looks like: "server type cx22 not found"). Find valid types with:
#   nix develop --command hcloud server-type list         # requires HCLOUD_TOKEN
#   nix develop --command hcloud datacenter list          # location availability
# then e.g.:
# export HCLOUDIMAGE_ACC_LOCATION=hel1
# export HCLOUDIMAGE_ACC_SERVER_TYPE_X86=cpx11   # AMD shared, widely available
# export HCLOUDIMAGE_ACC_SERVER_TYPE_ARM=cax11

nix develop --command go test ./internal/provider -run TestAccImage_RealHetzner -v -timeout 60m
```

The acceptance test composes the official `hcloud` provider, boots a server from
the produced snapshot, and **SSHes into the guest** to read `/etc/os-release` —
proving real reachability, not just that the hypervisor reports `running`.

**Cost & safety controls** (in the test code and in your own project — no CI
workflow ever touches Hetzner):

- cheapest server types only (`cx22` / `cax11`), smallest fixture, short timeouts;
- `hcloud` provider pinned to `~> 1.48`;
- deferred cleanup that runs even on failure;
- if a run crashes hard enough to leak resources, sweep the orphans yourself:
  `nix develop --command hcloud-upload-image cleanup`;
- the arm leg is toggle-gated (`HCLOUDIMAGE_ACC_RUN_ARM=1`), so you only pay
  for it when you ask for it.

### The aarch64 build path

`test-image-arm` and the `linux/arm64` provider binary need an aarch64 build
path. The project supports all three; pick per your infrastructure:

- **native aarch64 runner** — fastest, no emulation;
- **remote builder** — configure a `nix.conf` `builders =` entry pointing at an
  aarch64 machine;
- **binfmt / QEMU emulation** — set `boot.binfmt.emulatedSystems = [
  "aarch64-linux" ]` on a NixOS host, or use `qemu-user` on other systems. CI
  uses this by default so the hosted x86 runner can build the arm fixture.

The fixture derivation asserts the guest architecture, so the arm leg can never
silently upload an x86 image.

## License

[MPL-2.0](./LICENSE).
