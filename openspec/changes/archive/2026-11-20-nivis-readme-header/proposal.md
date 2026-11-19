## Why

Bean `hcloudimage-unn5`, phase 3.2 of the GitHub polish briefing. nivis.tf, the main
repository and the GitHub organisation now share one house style. A visitor who
lands on this repository from a search cannot tell that it belongs to the Nivis
project, or how far along it is. Every Nivis repository gets the same header and
footer, so each one says what it is, how mature it is, and where the rest lives.

## What Changes

- `README.md` opens with the Nivis header: the Nivis mark (from
  `https://nivis.tf/favicon.svg`) linking to nivis.tf, the repository name, a
  status badge reading "early but real", the sentence "Terraform and OpenTofu provider for uploading raw disk images to Hetzner Cloud as reusable snapshots.", and links to
  nivis.tf, the main repository and the docs.
- `README.md` ends with the shared footer: "Part of the Nivis project:
  Terraform providers as first-class Nix values", linking nivis.tf and the main
  repository.
- The licence badge said MPL-2.0 while `LICENSE` is MIT. It now says MIT.
- `scripts/check-readme-header.sh` and a flake check that runs it, so `nix flake
  check` fails when the header or footer drifts.

## Non-goals

- The body of the README.
