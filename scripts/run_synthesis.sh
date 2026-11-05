#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p reports

echo "Running Yosys synthesis..."

yosys -Q -T -l reports/yosys_synthesis.log -p '
    read_verilog -sv rtl/i2c_transaction_decoder.sv
    read_verilog -sv rtl/i2c_event_logger.sv
    read_verilog -sv rtl/i2c_fault_capture.sv
    read_verilog -sv rtl/i2c_analyzer_top.sv
    hierarchy -check -top i2c_analyzer_top
    synth -top i2c_analyzer_top
    stat -width
'

echo "PASS: Yosys synthesis completed"
