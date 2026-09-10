# acceptance-tests Specification

## Purpose
TBD - created by archiving change fixtures-and-acceptance. Update Purpose after archive.

## Requirements

### Requirement: Acceptance tests compose both providers and prove reachability
The acceptance suite SHALL, when `TF_ACC=1` and `HCLOUD_TOKEN` are set, upload a fixture
via `hcloudimage_image`, boot an `hcloud_server` from the snapshot id, and assert the guest
is reachable by SSHing from the runner with the baked throwaway key and reading
`/etc/os-release` — not merely that the server reports `running`.

#### Scenario: Skipped without credentials
- **WHEN** `TF_ACC` or `HCLOUD_TOKEN` is unset
- **THEN** the acceptance tests are skipped, keeping `go test ./...` green without secrets

#### Scenario: Reachability asserted via SSH
- **WHEN** the acceptance test runs against a real project
- **THEN** it SSHes into the booted server and confirms the guest OS, and cleans up even on
  failure

### Requirement: Acceptance covers both architectures with cost controls
The suite SHALL cover both `x86` (cx22 + amd64 fixture) and `arm` (cax11 + aarch64
fixture), with arm toggle-gated, cheapest server types, short timeouts, a pinned `hcloud`
provider version, and guaranteed cleanup.

#### Scenario: arm run uses the aarch64 fixture
- **WHEN** the arm acceptance path runs
- **THEN** it uses the aarch64 fixture and a cax11 server, not an x86 fallback

### Requirement: No CI workflow consumes billable Hetzner resources
No workflow under `.github/workflows/` SHALL require a Hetzner API token or create billable
Hetzner resources. Every automated check SHALL be runnable by any contributor — including on
a fork — without a Hetzner account. Exercising the real Hetzner path is a deliberate local
step, documented in the README, never a scheduled or push-triggered job.

#### Scenario: No workflow references a Hetzner token
- **WHEN** the workflows under `.github/workflows/` are inspected
- **THEN** none of them references `HCLOUD_TOKEN`, and none invokes `hcloud` or
  `hcloud-upload-image` against the live API

#### Scenario: No scheduled jobs remain
- **WHEN** the workflow triggers are inspected
- **THEN** no workflow declares a `schedule:` trigger, so a dormant repository costs nothing
  and reports no recurring failures

#### Scenario: Fork contributors get full CI
- **WHEN** a pull request is opened from a fork
- **THEN** the complete CI suite runs — lint, build, unit tests, examples validation,
  `nix flake check`, and the docs drift check — with no secrets required
