## 1. Implementation

- [x] 1.1 Delete `.github/workflows/acceptance.yml` (nightly + push-to-main billable
      live-Hetzner run; green no-op today because `HCLOUD_TOKEN` was never provisioned)
- [x] 1.2 Delete `.github/workflows/cleanup.yml` (nightly orphan sweep; 59/59 scheduled runs
      failed with `You need to set the HCLOUD_TOKEN environment variable`)
- [x] 1.3 Keep `internal/provider/image_acc_test.go` as-is — it is `TF_ACC`/`HCLOUD_TOKEN`-gated
      and skips cleanly, so `go test ./...` stays green and the real path remains available
      to anyone who wants to run it against their own project
- [x] 1.4 README: retitle the "Cost & safety controls (enforced in CI, `acceptance.yml`)"
      block — the controls now live in the test code and the operator's own project. Drop the
      `cleanup.yml` orphan-sweep bullet and the fork-PR/concurrency bullets (no workflow to
      speak of); add a line that orphans are swept by running
      `nix develop --command hcloud-upload-image cleanup` locally after a crashed run
- [x] 1.5 BRIEFING.md: mark §8.3/§15 `acceptance.yml` + `cleanup.yml` and the §16 DoD
      checklist line as superseded by this change rather than rewriting the briefing —
      it is the historical seed document
- [x] 1.6 CHANGELOG.md: add an `Unreleased` → `Removed` entry for the two workflows

## 2. Verification

- [x] 2.1 `ls .github/workflows/` shows exactly `ci.yml` and `release.yml`
- [x] 2.2 `grep -rn "HCLOUD_TOKEN\|schedule:" .github/workflows/` returns nothing
- [x] 2.3 `nix develop --command go test ./...` passes with no Hetzner token in the
      environment (acceptance tests skip, as the spec requires)
- [x] 2.4 `openspec validate --strict drop-billable-hetzner-ci` passes
- [ ] 2.5 After merge, confirm no new `Cleanup orphans` run appears:
      `gh run list --workflow=cleanup.yml` (the workflow file is gone, so nothing schedules)
