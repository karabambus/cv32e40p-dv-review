#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# run-cve4.sh — run cv32e40p-dv Verilator simulation from an ELF file
#
# The testbench reads the ELF header to extract the entry point (boot_addr)
# and loads the pre-generated <base>.hex via $readmemh internally.
# Run "make gen" before invoking this script to ensure the .hex files exist.
#
# Usage:
#   run-cve4.sh <elf-file>
#
# Environment:
#   CVE4_SIM — path to the built verilator_executable (required)

set -euo pipefail

ELF="${1:?Usage: run-cve4.sh <elf-file>}"
: "${CVE4_SIM:?CVE4_SIM is not set — point it to the built verilator_executable}"

exec "$CVE4_SIM" +elf_file="$ELF"
