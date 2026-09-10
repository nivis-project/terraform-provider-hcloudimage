# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- CI workflows that required a paid Hetzner project: `acceptance.yml` (nightly and
  push-to-main live e2e) and `cleanup.yml` (nightly label-scoped orphan sweep). Billable
  live-infra CI is disproportionate for an open-source component, and neither workflow ever
  did real work — `HCLOUD_TOKEN` was never provisioned. The `TF_ACC`-gated acceptance suite
  stays in the tree as an opt-in local run; `ci.yml` and `release.yml` (both hermetic) are
  unaffected.

## [0.1.0]

Initial release — the PoC / alpha base.

### Added

- `hcloudimage_image` resource: uploads a raw disk image (from `image_url` or
  `image_path`) into a Hetzner Cloud project and snapshots it via the rescue-server upload
  trick, with the full schema of the briefing (compression, format, architecture,
  server_type, location, image_size, description, labels, computed `id` and
  `effective_labels`, and a `timeouts` block).
- Config validators: exactly one of `image_url`/`image_path`, `image_sha256` required iff
  `image_path`, enum validation for architecture/compression/format, and the Hetzner
  label-value rule.
- ForceNew vs in-place semantics: ForceNew attributes trigger replacement; `description`
  and `labels` update in place.
- `hcloudimage_snapshot` data source: lookup by ID or label selector (with `most_recent`).
- Real upload engine via `github.com/apricote/hcloud-upload-image/hcloudimages/v2`, wired
  behind an internal `Uploader` interface (with an in-memory fake for tests).
- Runnable HCL examples validated under both Terraform and OpenTofu.
- Unit tests, a lifecycle test suite against the fake, and a hermetic NixOS-VM lifecycle
  test gating `nix flake check` (init/plan/apply/destroy under both `terraform` and `tofu`).
- Billable acceptance tests composing the official `hcloud` provider and asserting guest
  reachability over SSH, with reproducible Alpine `.raw.xz` fixtures for x86 and arm.
- Nix flake: dev shell, `buildGoModule` package, provider mirror, and test-image fixtures
  (plain nix, no flake-utils).
- CI (`ci.yml`), gated acceptance (`acceptance.yml`), orphan cleanup (`cleanup.yml`), and
  release (`release.yml`) workflows.
- Generated `docs/`, this changelog, and goreleaser + registry-manifest release tooling.

[Unreleased]: https://github.com/nivis-project/terraform-provider-hcloudimage/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nivis-project/terraform-provider-hcloudimage/releases/tag/v0.1.0
