#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 21.1 ships the core: it is all CI has, and timing_baseline.txt is a 21.1
# measurement, so numbers from another version cannot be compared against it.
# Build with QUARTUS_DIR=/opt/intelFPGA/25.1/quartus for low-level debugging,
# where JTAG is needed: it does not work on 21.1 here.
LOCAL_QUARTUS="${QUARTUS_DIR:-/opt/intelFPGA_lite/21.1/quartus}"

# The toolchain pin, used here and by CI (.github/actions/build-core runs this
# script), so there is one image to bump.
QUARTUS_IMAGE="${QUARTUS_IMAGE:-docker.io/raetro/quartus:21.1}"

if [ -x "$LOCAL_QUARTUS/bin/quartus_sh" ]; then
  echo "=== Starting Quartus build (local: $LOCAL_QUARTUS) ==="
  cd "$PROJECT_DIR"
  PATH="$LOCAL_QUARTUS/bin:$PATH" quartus_sh -t generate.tcl
else
  echo "=== Starting Quartus build via container ==="
  # podman works too
  "${CONTAINER_RUNTIME:-docker}" run --rm \
    -v "$PROJECT_DIR":/build:Z \
    -w /build \
    "$QUARTUS_IMAGE" \
    quartus_sh -t generate.tcl
fi

echo ""
echo "=== Build complete, reversing bitstream ==="
"$SCRIPT_DIR/deploy_bitstream.sh"

echo ""
"$SCRIPT_DIR/print_timing.sh" \
  "$PROJECT_DIR/projects/output_files/ap_core.sta.summary" \
  "$PROJECT_DIR/build_output/reports/ap_core.sta.clock_summary.rpt"

echo "Done"
echo "Bitstream copied to: pkg/Cores/*/bitstream.rbf_r"
