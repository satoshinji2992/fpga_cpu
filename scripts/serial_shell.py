#!/usr/bin/env python3
"""Host UART client for the CPU-driven dungeon demo.

The FPGA top now exposes UART as memory-mapped I/O to the RISC-V CPU. The
dungeon program running on the CPU prints the map and waits for WASD bytes.
This script is only a terminal/client; game logic lives in asm/dungeon.s.
"""

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
        tty.setraw(fd)
        return sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def open_serial(args: argparse.Namespace) -> serial.Serial:
    return serial.Serial(args.port, args.baud, timeout=0.05)


def terminal_mode(args: argparse.Namespace) -> int:
    ser = open_serial(args)
    stop_flag = threading.Event()
    thread = threading.Thread(target=reader_thread, args=(ser, stop_flag), daemon=True)
    thread.start()

    print(f"Connected to {args.port} at {args.baud} baud.")
    print("CPU dungeon terminal. Type w/a/s/d then Enter, q to quit.")
    time.sleep(0.2)

    try:
        while True:
            line = input()
            cmd = line.strip().lower()
            if cmd in ("q", "quit", "exit"):
                break
            if cmd:
                ser.write(cmd[0].encode("ascii", errors="ignore"))
    except KeyboardInterrupt:
        pass
    finally:
        stop_flag.set()
        thread.join(timeout=0.2)
        ser.close()
    return 0


def dungeon_mode(args: argparse.Namespace) -> int:
    ser = open_serial(args)
    stop_flag = threading.Event()
    thread = threading.Thread(target=reader_thread, args=(ser, stop_flag), daemon=True)
    thread.start()

    print(f"Connected to {args.port} at {args.baud} baud.")
    print("Dungeon mode: W/A/S/D move, Q quit. Game runs on the CPU via MMIO UART.")
    time.sleep(0.2)

    keymap = {
        "w": b"w", "W": b"w",
        "a": b"a", "A": b"a",
        "s": b"s", "S": b"s",
        "d": b"d", "D": b"d",
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
    parser = argparse.ArgumentParser(description="Connect to the FPGA CPU dungeon UART.")
    parser.add_argument("-p", "--port", help="Serial port, for example COM5 or /dev/cu.usbserial-130")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Baud rate, default 115200")
    parser.add_argument("--list", action="store_true", help="List serial ports and exit")
    parser.add_argument("--line", action="store_true", help="Line-input mode: type w/a/s/d then Enter")
    parser.add_argument("--dungeon", action="store_true", help="Single-key WASD dungeon controls (default)")
    parser.add_argument("--demo", action="store_true", help="Alias for --dungeon")
    parser.add_argument("--pong", action="store_true", help="Deprecated alias for --dungeon")
    parser.add_argument("--snake", action="store_true", help="Deprecated alias for --dungeon")
    args = parser.parse_args()

    if args.list:
        list_serial_ports()
        return 0
    if not args.port:
        parser.error("--port is required unless --list is used")
    if args.line:
        return terminal_mode(args)
    return dungeon_mode(args)


if __name__ == "__main__":
    raise SystemExit(main())
