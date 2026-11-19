## 1. README

- [x] 1.1 The Nivis header and footer in `README.md` (test: the `readme-header`
  flake check).
- [x] 1.2 The licence badge says MIT, as `LICENSE` does (test: read the rendered README).

## 2. Check

- [x] 2.1 `scripts/check-readme-header.sh` and the `readme-header` flake check.
- [x] 2.2 Probes: the check fails without the mark, the status, the footer, and
  with a second first-level heading.
- [x] 2.3 `nix flake check`.
