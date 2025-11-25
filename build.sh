#!/usr/bin/env bash
set -euo pipefail

# Ibex one-click build script
# - Builds Verilator-based Simple System via FuseSoC
# - Uses a feature-rich Ibex configuration (max ISA + features supported)
# - Writes simulator binary to build_result/ibex_sim_rv32

# Use the most extension-rich config present in ibex_configs.yaml:
#   - RV32M SingleCycle
#   - RV32B Full (bitmanip full)
#   - 3-stage pipeline (WritebackStage + BranchTargetALU)
#   - ICache + ECC
#   - PMP with 16 regions
# Note: Ibex does not implement A/F; those instructions will trap if executed.
CONFIG="${CONFIG:-maxperf-pmp-bmfull-icache}"

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT_DIR"

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

echo "Building Verilator simulator (config: ${CONFIG})..."
# Support both CLI entrypoint and module invocation for fusesoc
CFG_OPTS=$(util/ibex_config.py "$CONFIG" fusesoc_opts)
if command -v fusesoc >/dev/null 2>&1; then
  FUSESOC_CMD=(fusesoc)
else
  FUSESOC_CMD=(python3 -m fusesoc)
fi
"${FUSESOC_CMD[@]}" --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system ${CFG_OPTS}

SIM_BIN="build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system"
if [[ ! -x "$SIM_BIN" ]]; then
  echo "ERROR: Simulator binary not found at $SIM_BIN" >&2
  exit 1
fi

echo "Exporting simulator binary..."
OUT_FILE="build_result/ibex_sim_rv32"
mkdir -p "$(dirname "$OUT_FILE")"
if [[ -d "$OUT_FILE" ]]; then
  echo "Removing existing directory '$OUT_FILE' to create file output" >&2
  rm -rf "$OUT_FILE"
fi
cp -f "$SIM_BIN" "$OUT_FILE"
chmod +x "$OUT_FILE"

echo ""
echo "Build complete. Simulator: $OUT_FILE"
echo "Run it with an ELF built for Ibex, e.g.:"
echo "  $OUT_FILE --meminit=ram,examples/sw/simple_system/hello_test/hello_test.elf"
