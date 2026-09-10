## REMOVED Requirements

### Requirement: Gated acceptance and cleanup workflows
The repository SHALL provide `acceptance.yml` (workflow_dispatch + push-to-main + nightly,
never on fork PRs, concurrency-limited, always-run cleanup) and `cleanup.yml` (nightly
label-scoped orphan sweep).

#### Scenario: Never runs on fork PRs
- **WHEN** a pull request from a fork is opened
- **THEN** the acceptance workflow does not run (secrets are not exposed)

**Reason for removal:** billable live-Hetzner CI is disproportionate for an open-source
component. Neither workflow ever did real work — `HCLOUD_TOKEN` was never provisioned, so
`cleanup.yml` failed on all 59 of its scheduled runs and `acceptance.yml` reported a green
no-op (the Go tests skipped for want of the token). The acceptance *suite* is unaffected and
stays runnable on demand; only the CI workflows that wanted a paid Hetzner project are gone.

## ADDED Requirements

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
