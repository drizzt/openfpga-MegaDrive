#!/usr/bin/env bash
# Guard the multi-package invariants: shared binaries must be byte-identical,
# JSONs without intentional per-platform divergences identical, and core.json
# version/date in lockstep. (core/data/video/input.json legitimately differ
# per platform and are not diffed here; interact.json is checked modulo its
# intentional per-platform ids below.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

fail=0

# bitstream.rbf_r is one shared artifact fanned out to every package. It is a
# build product (gitignored), so absence everywhere is fine (fresh checkout);
# present in only some packages is drift.
bin=bitstream.rbf_r
# || true, or a glob matching nothing aborts before the guard below can run
present=$(ls pkg/Cores/*/"$bin" 2>/dev/null | wc -l || true)
total=$(ls -d pkg/Cores/*/ | wc -l)
if [ "$present" -ne 0 ]; then
  if [ "$present" -ne "$total" ]; then
    echo "DRIFT: $bin present in only $present of $total packages"
    fail=1
  elif [ "$(md5sum pkg/Cores/*/"$bin" | awk '{print $1}' | sort -u | wc -l)" -ne 1 ]; then
    echo "DRIFT: $bin differs across packages:"
    md5sum pkg/Cores/*/"$bin"
    fail=1
  fi
fi

# audio.json, variants.json, info.txt and icon.bin have no intentional divergences
for json in audio.json variants.json info.txt icon.bin; do
  if [ "$(md5sum pkg/Cores/*/"$json" | awk '{print $1}' | sort -u | wc -l)" -ne 1 ]; then
    echo "DRIFT: $json differs across packages:"
    md5sum pkg/Cores/*/"$json"
    fail=1
  fi
done

# interact.json must be identical across packages. Ids listed here are dropped
# before comparing, for a menu item only one sibling platform has.
intentional_ids='[]'
interact_hash() {
  jq -S --argjson skip "$intentional_ids" \
    '[.interact.variables[] | select(.id as $i | ($skip | index($i)) == null)]' "$1" \
    | md5sum | awk '{print $1}'
}
if [ "$(for f in pkg/Cores/*/interact.json; do interact_hash "$f"; done | sort -u | wc -l)" -ne 1 ]; then
  echo "DRIFT: interact.json differs across packages beyond the intentional ids ($(jq -rn --argjson s "$intentional_ids" '$s | map(tostring) | join("/")')):"
  for f in pkg/Cores/*/interact.json; do
    echo "  $f: $(interact_hash "$f")"
  done
  fail=1
fi

# AnalogueOS resolves core files by Cores/<author>.<shortname>/ at launch,
# so the package folder name must equal author.shortname exactly
for d in pkg/Cores/*/; do
  name=$(jq -r '.core.metadata.author + "." + .core.metadata.shortname' "$d/core.json")
  if [ "$(basename "$d")" != "$name" ]; then
    echo "DRIFT: folder $(basename "$d") != author.shortname $name"
    fail=1
  fi
done

# core.json metadata diverges per platform, but version/date must move in lockstep
for field in version date_release; do
  if [ "$(jq -r ".core.metadata.$field" pkg/Cores/*/core.json | sort -u | wc -l)" -ne 1 ]; then
    echo "DRIFT: core.json $field differs across packages:"
    jq -r ".core.metadata.$field" pkg/Cores/*/core.json
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "Package consistency check FAILED."
  exit 1
fi
echo "Package consistency check OK."
