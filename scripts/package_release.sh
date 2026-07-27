#!/usr/bin/env bash
# Package one release zip per platform core, each containing only that platform's
# Cores/<pkg>/, Platforms/<id>.json and Assets/<id>/. Pupdate maps each core to
# the single-core zip it was found in, so this keeps installs isolated. Subsets
# the tree at packaging time, pkg/ itself is untouched.
#
# Usage: package_release.sh <version> [infix]
#   infix (optional) is inserted before the version, e.g. a branch name for
#   CI artifacts -> openfpga-<shortname>_<infix>_<version>.zip.
# Prints the produced zip names (one per line) on stdout.
set -euo pipefail

VERSION="${1:?usage: package_release.sh <version> [infix]}"
INFIX="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

for core_json in "$PROJECT_DIR"/pkg/Cores/*/core.json; do
  pkgdir="$(basename "$(dirname "$core_json")")"               # author.SHORT
  shortname="$(jq -r '.core.metadata.shortname' "$core_json")" # SHORT
  pid="$(jq -r '.core.metadata.platform_ids[0]' "$core_json")" # platform id

  # zip exits 0 (warning only) when an argument doesn't match, so a drifted or
  # missing shortname/platform mapping would silently ship an incomplete zip.
  # Validate the coupling up front and fail loud instead.
  for field in shortname pid; do
    case "${!field}" in
      '' | null) echo "$pkgdir: core.json .core.metadata.$field is missing" >&2; exit 1 ;;
    esac
  done
  [ -f "$PROJECT_DIR/pkg/Platforms/${pid}.json" ] || {
    echo "$pkgdir: missing pkg/Platforms/${pid}.json for platform '$pid'" >&2; exit 1; }
  [ -d "$PROJECT_DIR/pkg/Assets/${pid}" ] || {
    echo "$pkgdir: missing pkg/Assets/${pid}/ for platform '$pid'" >&2; exit 1; }

    zip_name="openfpga-${shortname}${INFIX:+_$INFIX}_${VERSION}.zip"
  zip_path="$PROJECT_DIR/$zip_name"

  rm -f "$zip_path"
  # Run from pkg/ so the archive's paths are SD-card-root relative.
  # -x '*/.gitkeep' drops the empty-dir marker but keeps Assets/<id>/common/.
  ( cd "$PROJECT_DIR/pkg" && \
    zip -r "$zip_path" \
      "Cores/${pkgdir}" "Platforms/${pid}.json" "Assets/${pid}" \
      -x '*/.gitkeep' ) >&2

  echo "$zip_name"
done
