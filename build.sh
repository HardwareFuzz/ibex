#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./build.sh [options]

Build the Verilator-based Ibex simple system via FuseSoC.

Options:
  --isa <rv32...>          ISA label for output naming (default: rv32imc)
                           Note: Ibex is RV32-only; rv64* is rejected.
  --cores <N>              Number of cores (default: 1)
                           Note: this branch wires a single core.
  --coverage [mode]        Coverage mode: none|full|light (default: none)
                           If mode is omitted, it defaults to full.
  --clean                  Remove selected build/output before building
  --help                   Show this message

Outputs:
  build_result/ibex_<isa>_<N>c[_cov|_cov_light]
EOF
}

CONFIG="${CONFIG:-maxperf-pmp-bmfull-icache}"
ISA="rv32imc"
CORES="1"
COVERAGE_MODE="none" # none|full|light
CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --isa)
      [[ $# -ge 2 ]] || { echo "ERROR: --isa requires a value" >&2; usage; exit 1; }
      ISA="$2"; shift 2; continue ;;
    --isa=*)
      ISA="${1#*=}" ;;
    --cores)
      [[ $# -ge 2 ]] || { echo "ERROR: --cores requires a value" >&2; usage; exit 1; }
      CORES="$2"; shift 2; continue ;;
    --cores=*)
      CORES="${1#*=}" ;;
    --coverage)
      if [[ $# -ge 2 ]] && [[ ! "$2" =~ ^- ]]; then
        COVERAGE_MODE="$2"; shift 2; continue
      fi
      COVERAGE_MODE="full" ;;
    --coverage=*)
      COVERAGE_MODE="${1#*=}" ;;
    --coverage-light) # legacy alias
      COVERAGE_MODE="light" ;;
    --no-coverage) # legacy alias
      COVERAGE_MODE="none" ;;
    --clean)
      CLEAN=1 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "$ISA" != rv32* ]]; then
  echo "ERROR: Ibex is RV32-only; got --isa '$ISA'" >&2
  exit 1
fi
if [[ ! "$ISA" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "ERROR: --isa must match ^[A-Za-z0-9_]+$ (got '$ISA')" >&2
  exit 1
fi
if [[ ! "$CORES" =~ ^[0-9]+$ ]] || (( CORES < 1 )); then
  echo "ERROR: --cores must be a positive integer (got '$CORES')" >&2
  exit 1
fi
if (( CORES != 1 )); then
  echo "ERROR: This branch supports --cores 1 only (requested: $CORES)." >&2
  echo "       Use the 2hart branch for multi-core simple_system wiring." >&2
  exit 1
fi

case "$COVERAGE_MODE" in
  none)
    TARGET="sim"
    COV_SUFFIX=""
    ;;
  full)
    TARGET="sim_cov"
    COV_SUFFIX="_cov"
    ;;
  light)
    TARGET="sim_cov_light"
    COV_SUFFIX="_cov_light"
    ;;
  *)
    echo "ERROR: Unknown --coverage mode '$COVERAGE_MODE' (use none|full|light)" >&2
    exit 1
    ;;
esac

SIM_SUBDIR="${TARGET}-verilator"
OUT_FILE="build_result/ibex_${ISA}_${CORES}c${COV_SUFFIX}"
SIM_BIN="build/lowrisc_ibex_ibex_simple_system_0/${SIM_SUBDIR}/Vibex_simple_system"

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT_DIR"

VENV=.venv
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
source "$VENV/bin/activate"

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
fi

if (( CLEAN )); then
  rm -rf "build/lowrisc_ibex_ibex_simple_system_0/${SIM_SUBDIR}" "$OUT_FILE"
fi

echo "Building Verilator simulator (config: ${CONFIG}, target: ${TARGET})..."
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
