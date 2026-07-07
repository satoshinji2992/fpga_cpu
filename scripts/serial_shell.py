#!/usr/bin/env python3
"""Tiny host client for the FPGA UART shell."""

import argparse
import sys
import threading
import time

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
            text = data.decode("ascii", errors="replace")
            print(text, end="", flush=True)


def interactive(args: argparse.Namespace) -> int:
    ser = serial.Serial(args.port, args.baud, timeout=0.05)
    stop_flag = threading.Event()
    thread = threading.Thread(target=reader_thread, args=(ser, stop_flag), daemon=True)
    thread.start()

    print(f"Connected to {args.port} at {args.baud} baud.")
    print("Commands: h help, s status, 0/1/2 read memory, q quit.")
    time.sleep(0.2)

    try:
        while True:
            line = input()
            if line.strip().lower() in ("q", "quit", "exit"):
                break
            if not line:
                ser.write(b"\r")
            else:
                ser.write(line[0].encode("ascii", errors="ignore") + b"\r")
    except KeyboardInterrupt:
        pass
    finally:
        stop_flag.set()
        thread.join(timeout=0.2)
        ser.close()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Connect to the FPGA UART shell.")
    parser.add_argument("-p", "--port", help="Serial port, for example COM5 or /dev/tty.usbserial-0001")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Baud rate, default 115200")
    parser.add_argument("--list", action="store_true", help="List serial ports and exit")
    args = parser.parse_args()

    if args.list:
        list_serial_ports()
        return 0
    if not args.port:
        parser.error("--port is required unless --list is used")
    return interactive(args)


if __name__ == "__main__":
    raise SystemExit(main())
