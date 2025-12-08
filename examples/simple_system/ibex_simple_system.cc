// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <cassert>
#include <cstring>
#include <fstream>
#include <iostream>

#include "Vibex_simple_system__Syms.h"
#include "ibex_pcounts.h"
#include "ibex_simple_system.h"
#include "verilated_toplevel.h"
#include "verilator_memutil.h"
#include "verilator_sim_ctrl.h"
#if VM_COVERAGE
#include "verilated_cov.h"
#endif

SimpleSystem::SimpleSystem(const char *ram_hier_path, int ram_size_words)
    : _ram(ram_hier_path, ram_size_words, 4) {}

int SimpleSystem::Main(int argc, char **argv) {
  bool exit_app;
  int ret_code = Setup(argc, argv, exit_app);

  if (exit_app) {
    return ret_code;
  }

  Run();

  if (!Finish()) {
    return 1;
  }

  return 0;
}

std::string SimpleSystem::GetIsaString() const {
  const Vibex_simple_system &top = _top;
  assert(top.ibex_simple_system);

  std::string base = top.ibex_simple_system->RV32E ? "rv32e" : "rv32i";

  std::string extensions;
  if (top.ibex_simple_system->RV32M)
    extensions += "m";

  extensions += "c";

  switch (top.ibex_simple_system->RV32B) {
    case 0:  // RV32BNone
      break;

    case 1:  // RV32BBalanced
      extensions += "_Zba_Zbb_Zbs_XZbf_XZbt";
      break;

    case 2:  // RV32BOTEarlGrey
      extensions += "_Zba_Zbb_Zbc_Zbs_XZbf_XZbp_XZbr_XZbt";
      break;

    case 3:  // RV32BFull
      extensions += "_Zba_Zbb_Zbc_Zbs_XZbe_XZbf_XZbp_XZbr_XZbt";
      break;
  }

  return base + extensions;
}

int SimpleSystem::Setup(int argc, char **argv, bool &exit_app) {
  VerilatorSimCtrl &simctrl = VerilatorSimCtrl::GetInstance();

  simctrl.SetTop(&_top, &_top.IO_CLK, &_top.IO_RST_N,
                 VerilatorSimCtrlFlags::ResetPolarityNegative);

  _memutil.RegisterMemoryArea("ram", kRAM_BaseAddr, &_ram);
  simctrl.RegisterExtension(&_memutil);

  exit_app = false;
  int ret = simctrl.ParseCommandArgs(argc, argv, exit_app);

#if VM_COVERAGE
  if (!exit_app && ret) {
    SetupCoverage();
  }
#endif

  return ret;
}

void SimpleSystem::Run() {
  VerilatorSimCtrl &simctrl = VerilatorSimCtrl::GetInstance();

  std::cout << "Simulation of Ibex" << std::endl
            << "==================" << std::endl
            << std::endl;

  simctrl.RunSimulation();
}

bool SimpleSystem::Finish() {
  VerilatorSimCtrl &simctrl = VerilatorSimCtrl::GetInstance();

#if VM_COVERAGE
  Verilated::threadContextp()->coveragep()->write(cov_path_.c_str());
  std::cout << "Coverage: " << cov_path_ << std::endl;
#endif

  if (!simctrl.WasSimulationSuccessful()) {
    return false;
  }

  // Set the scope to the root scope, the ibex_pcount_string function otherwise
  // doesn't know the scope itself. Could be moved to ibex_pcount_string, but
  // would require a way to set the scope name from here, similar to MemUtil.
  svSetScope(svGetScopeFromName("TOP.ibex_simple_system"));

  std::cout << "\nPerformance Counters" << std::endl
            << "====================" << std::endl;
  std::cout << ibex_pcount_string(false);

  std::ofstream pcount_csv("ibex_simple_system_pcount.csv");
  pcount_csv << ibex_pcount_string(true);

  return true;
}

#if VM_COVERAGE
void SimpleSystem::SetupCoverage() {
  if (const char *cov_arg = Verilated::commandArgsPlusMatch("covfile=")) {
    const char *val = cov_arg + std::strlen("+covfile=");
    if (*val) {
      cov_path_ = val;
    }
  }

  const auto slash_pos = cov_path_.find_last_of("/\\");
  if (slash_pos != std::string::npos && slash_pos != 0) {
    Verilated::mkdir(cov_path_.substr(0, slash_pos).c_str());
  } else {
    Verilated::mkdir("logs");
  }

  Verilated::threadContextp()->coveragep()->zero();
}
#endif
