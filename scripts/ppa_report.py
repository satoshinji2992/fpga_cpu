#!/usr/bin/env python3
"""Extract a compact PPA summary from Xilinx ISE report files.

The script reads the reports produced by the existing ISE flow and prints a
Markdown table suitable for experiment.md or a course report.
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(name):
    path = ROOT / name
    if not path.exists():
        return ""
    return path.read_text(errors="ignore")


def find(pattern, text, default="NA", flags=0):
    m = re.search(pattern, text, flags)
    return m.group(1) if m else default


def resource_line(label, text):
    pattern = rf"{re.escape(label)}:\s+([0-9,]+) out of\s+([0-9,]+)\s+([0-9]+)%"
    m = re.search(pattern, text)
    if not m:
        return ("NA", "NA", "NA")
    return m.group(1), m.group(2), m.group(3) + "%"


def main():
    par = read("top.par")
    twr = read("top.twr")
    pwr = read("top.pwr")

    regs = resource_line("Number of Slice Registers", par)
    luts = resource_line("Number of Slice LUTs", par)
    slices = resource_line("Number of occupied Slices", par)
    iobs = resource_line("Number of bonded IOBs", par)
    ramb16 = resource_line("Number of RAMB16BWERs", par)
    ramb8 = resource_line("Number of RAMB8BWERs", par)
    bufg = resource_line("Number of BUFG/BUFGMUXs", par)
    dsp = resource_line("Number of DSP48A1s", par)

    min_period = find(r"Minimum period:\s+([0-9.]+ns)", twr)
    fmax = find(r"Maximum frequency:\s+([0-9.]+MHz)", twr)
    slack = find(r"Worst Case\s+\|\s+Best Case.*?\n\*.*?SETUP\s+\|\s+(-?[0-9.]+ns)", par, flags=re.S)
    timing_errors = find(r"\*\s+TS_clk.*?SETUP\s+\|\s+-?[0-9.]+ns\|\s+[0-9.]+ns\|\s+([0-9]+)\|", par, flags=re.S)

    total_power = find(r"Supply Power \(mW\)\s+\|\s+([0-9.]+)", pwr)
    dynamic_power = find(r"Supply Power \(mW\)\s+\|\s+[0-9.]+\s+\|\s+([0-9.]+)", pwr)
    static_power = find(r"Supply Power \(mW\)\s+\|\s+[0-9.]+\s+\|\s+[0-9.]+\s+\|\s+([0-9.]+)", pwr)
    confidence = find(r"Overall confidence level\s+\|\s+([A-Za-z]+)", pwr)

    rows = [
        ("Slice Registers", *regs),
        ("Slice LUTs", *luts),
        ("Occupied Slices", *slices),
        ("Bonded IOBs", *iobs),
        ("RAMB16BWER", *ramb16),
        ("RAMB8BWER", *ramb8),
        ("BUFG/BUFGMUX", *bufg),
        ("DSP48A1", *dsp),
    ]

    print("# PPA Summary\n")
    print("| Resource | Used | Available | Utilization |")
    print("|---|---:|---:|---:|")
    for name, used, avail, util in rows:
        print(f"| {name} | {used} | {avail} | {util} |")

    print("\n| Timing | Value |")
    print("|---|---:|")
    print("| Target period | 20 ns |")
    print(f"| Best achievable period | {min_period} |")
    print(f"| Maximum frequency | {fmax} |")
    print(f"| Worst setup slack | {slack} |")
    print(f"| Timing errors | {timing_errors} |")

    print("\n| Power | Value |")
    print("|---|---:|")
    print(f"| Total supply power | {total_power} mW |")
    print(f"| Dynamic power | {dynamic_power} mW |")
    print(f"| Static power | {static_power} mW |")
    print(f"| XPower confidence | {confidence} |")
    if confidence != "NA":
        print("\nNote: power is estimated without a simulation activity file, so use it as a coarse estimate.")


if __name__ == "__main__":
    main()
