#!/usr/bin/env python3
"""Host UART client for the CPU-driven shell and 8x8 digit inference demo.

The FPGA top now exposes UART as memory-mapped I/O to the RISC-V CPU. The
program running on the CPU parses a tiny shell, receives an 8x8 digit image,
and runs fixed-weight inference. This script is only a UART terminal/client;
inference and shell logic live in asm/cnn_digit.s.
"""

import argparse
import json
import sys
import threading
import time
from pathlib import Path

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("pyserial is required. Install with: python -m pip install pyserial", file=sys.stderr)
    raise


def list_serial_ports() -> None:
    ports = list(list_ports.comports())
    if not ports:
        print("No serial ports found.")
        return
    for port in ports:
        print(f"{port.device}\t{port.description}")


def reader_thread(ser: serial.Serial, stop_flag: threading.Event) -> None:
    while not stop_flag.is_set():
        data = ser.read(256)
        if data:
            print(data.decode("ascii", errors="replace"), end="", flush=True)


def read_key() -> str:
    if sys.platform.startswith("win"):
        import msvcrt

        return msvcrt.getch().decode("ascii", errors="ignore")

    import termios
    import tty

    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        return sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def open_serial(args: argparse.Namespace) -> serial.Serial:
    return serial.Serial(args.port, args.baud, timeout=0.05)


def digit_pixels(digit: int) -> str:
    model_path = Path(__file__).resolve().parents[1] / "data" / "mnist8_model.json"
    with model_path.open() as f:
        model = json.load(f)
    return model["prototypes"][digit]


def print_digit_preview(pixels: str) -> None:
    for y in range(8):
        row = pixels[y * 8:(y + 1) * 8]
        print("".join("#" if ch == "1" else "." for ch in row))


def send_cnn_digit(ser: serial.Serial, digit: int) -> None:
    pixels = digit_pixels(digit)
    print(f"\n[host] sending 8x8 digit {digit}:")
    print_digit_preview(pixels)
    ser.write(pixels.encode("ascii") + b"\n")


def shell_mode(args: argparse.Namespace) -> int:
    ser = open_serial(args)
    stop_flag = threading.Event()
    thread = threading.Thread(target=reader_thread, args=(ser, stop_flag), daemon=True)
    thread.start()

    print(f"Connected to {args.port} at {args.baud} baud.")
    print("Host shell: type cnn, then choose 0-9; q quits host.")
    time.sleep(0.2)

    try:
        while True:
            line = input()
            cmd = line.strip().lower()
            if cmd in ("q", "quit", "exit"):
                break
            if not cmd:
                ser.write(b"\n")
                continue
            ser.write((line + "\n").encode("ascii", errors="ignore"))
            if cmd in ("c", "cnn"):
                digit_text = input("[host] digit 0-9 > ").strip()
                if digit_text.isdigit() and 0 <= int(digit_text) <= 9:
                    send_cnn_digit(ser, int(digit_text))
                else:
                    print("[host] skipped: not a digit 0-9")
    except KeyboardInterrupt:
        pass
    finally:
        stop_flag.set()
        thread.join(timeout=0.2)
        ser.close()
    return 0


def cnn_mode(args: argparse.Namespace) -> int:
    ser = open_serial(args)
    stop_flag = threading.Event()
    thread = threading.Thread(target=reader_thread, args=(ser, stop_flag), daemon=True)
    thread.start()

    print(f"Connected to {args.port} at {args.baud} baud.")
    print(f"Starting CPU CNN inference for digit {args.cnn}.")
    time.sleep(0.2)
    ser.write(b"cnn\n")
    time.sleep(0.1)
    send_cnn_digit(ser, args.cnn)
    time.sleep(1.0)

    stop_flag.set()
    thread.join(timeout=0.2)
    ser.close()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Connect to the FPGA CPU UART shell.")
    parser.add_argument("-p", "--port", help="Serial port, for example COM5 or /dev/cu.usbserial-130")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Baud rate, default 115200")
    parser.add_argument("--list", action="store_true", help="List serial ports and exit")
    parser.add_argument("--cnn", type=int, choices=range(10), metavar="DIGIT",
                        help="Start CNN inference immediately with a template digit 0-9")
    args = parser.parse_args()

    if args.list:
        list_serial_ports()
        return 0
    if not args.port:
        parser.error("--port is required unless --list is used")
    if args.cnn is not None:
        return cnn_mode(args)
    return shell_mode(args)


if __name__ == "__main__":
    raise SystemExit(main())
