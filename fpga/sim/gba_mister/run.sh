#!/usr/bin/env bash
set -euo pipefail

fpga_root=$(cd "$(dirname "$0")/../.." && pwd)
rtl="$fpga_root/verilog/gba_mister"
build_dir=$(mktemp -d)
trap 'rm -r -- "$build_dir"' EXIT
cd "$build_dir"
ghdl -i --std=08 --work=mem "$rtl"/mem/*.vhd
ghdl -i --std=08 "$rtl"/rtl/*.vhd "$rtl/gba_gamebub.vhd" "$fpga_root/sim/gba_mister/"*_tb.vhd
ghdl -m --std=08 gba_sound_dma_tb
ghdl -r --std=08 gba_sound_dma_tb --ieee-asserts=disable
ghdl -m --std=08 gba_serial_tb
ghdl -r --std=08 gba_serial_tb --ieee-asserts=disable
ghdl -m --std=08 gba_savestates_tb
ghdl -r --std=08 gba_savestates_tb --ieee-asserts=disable
ghdl -m --std=08 gba_gamebub_tb
ghdl -r --std=08 gba_gamebub_tb --ieee-asserts=disable "$@"
