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


def read_key() -> str:
    if sys.platform.startswith("win"):
        import msvcrt

        ch = msvcrt.getch()
        return ch.decode("ascii", errors="ignore")

    import termios
    import tty

    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        return sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def snake_mode(args: argparse.Namespace) -> int:
    ser = serial.Serial(args.port, args.baud, timeout=0.05)
    stop_flag = threading.Event()
    thread = threading.Thread(target=reader_thread, args=(ser, stop_flag), daemon=True)
    thread.start()

    print(f"Connected to {args.port} at {args.baud} baud.")
    print("Snake mode: WASD move, n reset, g redraw, q quit.")
    time.sleep(0.2)
    ser.write(b"g\r")

    keymap = {
        "w": b"u\r",
        "W": b"u\r",
        "s": b"d\r",
        "S": b"d\r",
        "a": b"l\r",
        "A": b"l\r",
        "d": b"r\r",
        "D": b"r\r",
        "n": b"n\r",
        "N": b"n\r",
        "g": b"g\r",
        "G": b"g\r",
    }

    try:
        while True:
            ch = read_key()
            if ch in ("q", "Q", "\x03"):
                break
            if ch in keymap:
                ser.write(keymap[ch])
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
    parser.add_argument("--snake", action="store_true", help="Use WASD controls for the UART snake demo")
    args = parser.parse_args()

    if args.list:
        list_serial_ports()
        return 0
    if not args.port:
        parser.error("--port is required unless --list is used")
    if args.snake:
        return snake_mode(args)
    return interactive(args)


if __name__ == "__main__":
    raise SystemExit(main())
