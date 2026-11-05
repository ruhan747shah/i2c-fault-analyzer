
#!/usr/bin/env python3

import subprocess
import sys
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parent.parent
SIM = ROOT / "sim"
REPORTS = ROOT / "reports"

SIM.mkdir(exist_ok=True)
REPORTS.mkdir(exist_ok=True)

# Each test includes its required RTL dependencies
TESTS = [
    {
        "name": "START/STOP Detection",
        "top": "tb_i2c_start_stop",
        "files": [
            "rtl/i2c_start_stop.sv",
            "tb/tb_i2c_start_stop.sv",
        ],
        "pass_marker": "PASS: START/STOP detection",
    },
    {
        "name": "Address ACK/NACK",
        "top": "tb_i2c_address_decoder",
        "files": [
            "rtl/i2c_start_stop.sv",
            "rtl/i2c_address_decoder.sv",
            "tb/tb_i2c_address_decoder.sv",
        ],
        "pass_marker": "PASS: Milestone 3",
    },
    {
        "name": "Full Transaction Decoder",
        "top": "tb_i2c_transaction_decoder",
        "files": [
            "rtl/i2c_transaction_decoder.sv",
            "tb/tb_i2c_transaction_decoder.sv",
        ],
        "pass_marker": "PASS: MILESTONE 4",
    },
    {
        "name": "Timestamped Event Logger",
        "top": "tb_i2c_event_logger",
        "files": [
            "rtl/i2c_transaction_decoder.sv",
            "rtl/i2c_event_logger.sv",
            "tb/tb_i2c_event_logger.sv",
        ],
        "pass_marker": "PASS: MILESTONE 5",
    },
    {
        "name": "Circular Fault Capture",
        "top": "tb_i2c_fault_capture",
        "files": [
            "rtl/i2c_transaction_decoder.sv",
            "rtl/i2c_event_logger.sv",
            "rtl/i2c_fault_capture.sv",
            "tb/tb_i2c_fault_capture.sv",
        ],
        "pass_marker": "PASS: MILESTONE 6",
    },
    {
        "name": "Clock Stretching + Reset",
        "top": "tb_i2c_edge_cases",
        "files": [
            "rtl/i2c_transaction_decoder.sv",
            "tb/tb_i2c_edge_cases.sv",
        ],
        "pass_marker": "PASS: MILESTONE 7",
    },
]


def run_command(command):
    return subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def main():
    results = []
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    print("=" * 60)
    print("I2C PROTOCOL ANALYZER — AUTOMATED VERIFICATION")
    print("=" * 60)

    for index, test in enumerate(TESTS, start=1):
        print(f"\n[{index}/{len(TESTS)}] {test['name']}")

        output_file = SIM / f"{test['top']}.vvp"

        compile_command = [
            "iverilog",
            "-g2012",
            "-s",
            test["top"],
            "-o",
            str(output_file),
            *test["files"],
        ]

        try:
            compile_result = run_command(compile_command)
        except FileNotFoundError:
            print("ERROR: Icarus Verilog is not installed.")
            sys.exit(1)

        if compile_result.returncode != 0:
            print("FAIL: Compilation")
            print(compile_result.stdout)
            print(compile_result.stderr)
            results.append((test["name"], False, "Compilation failed"))
            continue

        try:
            sim_result = subprocess.run(
                ["vvp", str(output_file)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
            print(f"FAIL: {exc}")
            results.append((test["name"], False, str(exc)))
            continue

        output = sim_result.stdout + sim_result.stderr

        passed = (
            sim_result.returncode == 0
            and test["pass_marker"] in output
        )

        if passed:
            print("PASS")
            results.append((test["name"], True, "Passed"))
        else:
            print("FAIL")
            print(output)
            results.append((test["name"], False, output.strip()))

    passed_count = sum(result[1] for result in results)

    report = [
        "I2C Protocol Analyzer — Simulation Verification Report",
        f"Generated: {timestamp}",
        "",
    ]

    for name, passed, detail in results:
        status = "PASS" if passed else "FAIL"
        report.append(f"[{status}] {name}")
        if not passed:
            report.append(detail)

    report += [
        "",
        f"Total: {passed_count}/{len(TESTS)} tests passed",
        "Results are from Icarus Verilog simulation.",
    ]

    report_path = REPORTS / "simulation_report.txt"
    report_path.write_text("\n".join(report) + "\n")

    print("\n" + "=" * 60)
    print(f"RESULT: {passed_count}/{len(TESTS)} PASSED")
    print(f"Report: {report_path}")
    print("=" * 60)

    if passed_count != len(TESTS):
        sys.exit(1)


if __name__ == "__main__":
    main()
