# readme Specification

## Purpose
TBD - created by archiving change nivis-readme-header. Update Purpose after archive.

## Requirements

### Requirement: The README carries the Nivis project header and footer
`README.md` SHALL open with the Nivis header: the Nivis mark linking to
nivis.tf, the repository name `terraform-provider-hcloudimage` as the only first-level heading, a status
badge reading "early but real", one sentence about the repository, and links to
nivis.tf, the main repository and the docs. It SHALL end with the shared footer
that names the Nivis project and links nivis.tf and the main repository.

#### Scenario: the header
- WHEN `README.md` is read from the top
- THEN it opens with the Nivis mark from `https://nivis.tf/favicon.svg`, then
  `<h1 align="center">terraform-provider-hcloudimage</h1>`, then the "early but real" status badge, and links to
  `https://nivis.tf` and `https://github.com/nivis-project/nivis`.

#### Scenario: the footer
- WHEN `README.md` is read to the end
- THEN its last line is the "Part of the Nivis project" footer, once.

#### Scenario: the check holds it
- WHEN `nix flake check` runs
- THEN the `readme-header` check passes, and it fails if the header, the status
  or the footer is removed or changed.
