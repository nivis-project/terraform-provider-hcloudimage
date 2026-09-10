# drop-billable-hetzner-ci

Remove the two GitHub Actions workflows that need a paid Hetzner project —
`acceptance.yml` (billable nightly live e2e) and `cleanup.yml` (nightly orphan sweep) —
because billable live-infra CI is disproportionate for an open-source component. `ci.yml`
and `release.yml` stay; both are fully hermetic. The `TF_ACC`-gated acceptance suite stays
in the tree as an opt-in local run.

Diagnosed from a red nightly `Cleanup orphans` run
([34459397245](https://github.com/nivis-project/terraform-provider-hcloudimage/actions/runs/34459397245)):
the `HCLOUD_TOKEN` secret was never provisioned, so the sweep failed on all 59 of its runs
and the acceptance workflow reported a green no-op.

Authored with the `tinychange` OpenSpec schema (lean specs → tasks; no proposal or design).
Collaborators can install it from
<https://github.com/speclib/openspec-tinychange-schema> — see its `AGENT_INSTALL.md`, or run
`/mip:tinychange-explore`. The schema is vendored at `openspec/schemas/tinychange/`.
