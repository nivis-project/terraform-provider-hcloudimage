#!/usr/bin/env bash
set -euo pipefail

readme="${1:?usage: check-readme-header.sh <README.md> <repo-name> <status>}"
name="${2:?repo name}"
status="${3:?status label}"

fail=0
bad() { echo "readme-header: FAIL $*" >&2; fail=1; }

footer='<p align="center"><sub>Part of the <a href="https://nivis.tf">Nivis</a> project: Terraform resources as Nix values. Main repository: <a href="https://github.com/nivis-project/nivis">nivis-project/nivis</a>.</sub></p>'
badge_status="$(printf '%s' "$status" | sed 's/ /%20/g')"

header="$(awk '/^## / { exit } { print }' "$readme" | head -n 40)"
first="$(grep -m1 . "$readme" || true)"

[ "$first" = '<p align="center">' ] || bad "the README does not open with the centred mark"
printf '%s\n' "$header" | grep -qF '<a href="https://nivis.tf"><img src="https://nivis.tf/favicon.svg" alt="Nivis" width="72"></a>' || bad "the header has no Nivis mark linking to nivis.tf"
printf '%s\n' "$header" | grep -qxF "<h1 align=\"center\">$name</h1>" || bad "the header does not name the repository $name"
printf '%s\n' "$header" | grep -qF "https://img.shields.io/badge/status-$badge_status-2d8dd2\" alt=\"Status: $status\"" || bad "the header has no status badge '$status'"
printf '%s\n' "$header" | grep -qF '<a href="https://nivis.tf">nivis.tf</a>' || bad "the header does not link nivis.tf"
printf '%s\n' "$header" | grep -qF '<a href="https://github.com/nivis-project/nivis">nivis</a>' || bad "the header does not link the main repository"
h1s="$(awk '/^```/ { fence = !fence; next } !fence && /^# / { print }' "$readme")"
if [ -n "$h1s" ]; then
  bad "a markdown h1 remains beside the header's h1: $(printf '%s\n' "$h1s" | head -n1)"
fi

last="$(grep . "$readme" | tail -n1)"
[ "$last" = "$footer" ] || bad "the README does not end with the Nivis project footer"
[ "$(grep -cF "$footer" "$readme")" -eq 1 ] || bad "the footer appears more than once"

if grep -qF 'wearetechnative.github.io/nivis' "$readme"; then
  bad "the README links the old address wearetechnative.github.io/nivis"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "readme-header: ok, $name ($status)"
