#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./build.sh [--coverage|--coverage-light|--no-coverage] [--clean] [--help]

Build the Verilator-based Ibex simple system via FuseSoC.
  --coverage           Build full coverage-enabled binary (ibex_rv32_cov)
  --coverage-light     Build light coverage binary with line/user coverage only (ibex_rv32_cov_light)
  --no-coverage        Build the standard binary (default: ibex_rv32)
  --clean              Remove the selected build/output before building
  --help               Show this message
EOF
}

# Ibex one-click build script
# - Builds Verilator-based Simple System via FuseSoC
# - Uses a feature-rich Ibex configuration (max ISA + features supported)
# - Writes simulator binary to build_result/ibex_rv32 (or ..._cov / ..._cov_light)

# Use the most extension-rich config present in ibex_configs.yaml:
#   - RV32M SingleCycle
#   - RV32B Full (bitmanip full)
#   - 3-stage pipeline (WritebackStage + BranchTargetALU)
#   - ICache + ECC
#   - PMP with 16 regions
# Note: Ibex does not implement A/F; those instructions will trap if executed.
CONFIG="${CONFIG:-maxperf-pmp-bmfull-icache}"
COVERAGE_MODE="${COVERAGE_MODE:-none}" # none|full|light
CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --coverage|-c) COVERAGE_MODE="full" ;;
    --coverage-light) COVERAGE_MODE="light" ;;
    --no-coverage|-n) COVERAGE_MODE="none" ;;
    --clean) CLEAN=1 ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

case "$COVERAGE_MODE" in
  full)
    TARGET="sim_cov"
    COV_SUFFIX="_cov"
    ;;
  light)
    TARGET="sim_cov_light"
    COV_SUFFIX="_cov_light"
    ;;
  none)
    TARGET="sim"
    COV_SUFFIX=""
    ;;
  *)
    echo "ERROR: Unknown coverage mode: $COVERAGE_MODE" >&2
    exit 1
    ;;
esac

SIM_SUBDIR="${TARGET}-verilator"
OUT_FILE="build_result/ibex_rv32${COV_SUFFIX}"

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT_DIR"

SIM_BIN="build/lowrisc_ibex_ibex_simple_system_0/${SIM_SUBDIR}/Vibex_simple_system"

VENV=".venv"
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
source "$VENV/bin/activate"

# Install Python deps only if fusesoc/edalize are not importable
if ! python3 - <<'PY'
import sys
try:
    import fusesoc, edalize  # noqa: F401
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
then
  echo "Setting up Python dependencies (this may use network)..."
  if ! python3 -m pip -q install -U -r python-requirements.txt; then
    echo "WARNING: Failed to install python requirements. Will attempt to continue with existing environment." >&2
  fi
else
  echo "Python dependencies already present; skipping pip install."
fi

if (( CLEAN )); then
  rm -rf "build/lowrisc_ibex_ibex_simple_system_0/${SIM_SUBDIR}" "$OUT_FILE"
fi

echo "Building Verilator simulator (config: ${CONFIG}, target: ${TARGET})..."
# Support both CLI entrypoint and module invocation for fusesoc
CFG_OPTS=$(util/ibex_config.py "$CONFIG" fusesoc_opts)
if command -v fusesoc >/dev/null 2>&1; then
  FUSESOC_CMD=(fusesoc)
else
  FUSESOC_CMD=(python3 -m fusesoc)
fi
"${FUSESOC_CMD[@]}" --cores-root=. run --target="${TARGET}" --setup --build \
  lowrisc:ibex:ibex_simple_system ${CFG_OPTS}

if [[ ! -x "$SIM_BIN" ]]; then
  echo "ERROR: Simulator binary not found at $SIM_BIN" >&2
  exit 1
fi

echo "Exporting simulator binary..."
mkdir -p "$(dirname "$OUT_FILE")"
if [[ -d "$OUT_FILE" ]]; then
  echo "Removing existing directory '$OUT_FILE' to create file output" >&2
  rm -rf "$OUT_FILE"
fi
cp -f "$SIM_BIN" "$OUT_FILE"
chmod +x "$OUT_FILE"

echo ""
echo "Build complete. Simulator: $OUT_FILE"
if [[ "$COVERAGE_MODE" == "full" || "$COVERAGE_MODE" == "light" ]]; then
  echo "Pass +covfile=/path/to/coverage.dat to choose the coverage output (default: logs/coverage.dat)."
fi
echo "Run it with an ELF built for Ibex, e.g.:"
echo "  $OUT_FILE --meminit=ram,examples/sw/simple_system/hello_test/hello_test.elf"
