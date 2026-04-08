###############################################################################
#
# Copyright 2020,2022 Eclipse Foundation
#
# Licensed under the Solderpad Hardware Licence, Version 2.1 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://solderpad.org/licenses/
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
###############################################################################
#
# Makefile for the CV32E40P UVM testbench.
#
###############################################################################

# "Constants"
MAKE                  = make
MAKE_PATH            := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
export CV32E40P_DV     = $(abspath $(MAKE_PATH)/../..)
export CORE_V_VERIF   = $(CV32E40P_DV)/vendor_lib/openhwgroup_core-v-verif
export CV_CORE       ?= cv32e40p

DPI_DASM_SPIKE_REPO  ?= https://github.com/riscv/riscv-isa-sim.git

export CV_SW_MARCH   = rv32imc_zicsr_zifencei
CV_SW_TOOLCHAIN      ?= /opt/riscv
CV_SW_PREFIX         ?= " "

CORE_DEFINES         = +define+CV32E40P_RVFI+RVFI

UVM_VERBOSITY        ?= UVM_LOW

USER_RUN_FLAGS       ?= +scoreboard_enable=1 +UVM_VERBOSITY=$(UVM_VERBOSITY) +report_file=$(TEST).yaml

ISS ?= SPIKE

include ../ExternalRepos.mk
include $(CV32E40P_DV)/mk/uvmt/uvmt.mk
