#!/usr/bin/env python3
"""Host UART client for the CPU-driven shell and dungeon demo.

The FPGA top now exposes UART as memory-mapped I/O to the RISC-V CPU. The
program running on the CPU parses a tiny shell, starts the dungeon command,
prints the map, and waits for WASD bytes. This script is only a terminal/client;
game and shell logic live in asm/dungeon.s.
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
        tty.setcbreak(fd)
        return sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def open_serial(args: argparse.Namespace) -> serial.Serial:
    return serial.Serial(args.port, args.baud, timeout=0.05)


def raw_dungeon_controls(ser: serial.Serial) -> None:
    keymap = {
        "w": b"w", "W": b"w",
        "a": b"a", "A": b"a",
        "s": b"s", "S": b"s",
        "d": b"d", "D": b"d",
    }

    print("\n[host] dungeon controls: W/A/S/D move, Q returns to CPU shell.")
    try:
        while True:
            ch = read_key()
            if ch in ("q", "Q", "\x03"):
                ser.write(b"q")
                break
            if ch in keymap:
                ser.write(keymap[ch])
    except KeyboardInterrupt:
        ser.write(b"q")


def shell_mode(args: argparse.Namespace) -> int:
    ser = open_serial(args)
    stop_flag = threading.Event()
    thread = threading.Thread(target=reader_thread, args=(ser, stop_flag), daemon=True)
    thread.start()

    print(f"Connected to {args.port} at {args.baud} baud.")
    print("Host shell: type dungeon to enter raw controls, q to quit host.")
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
            if cmd in ("d", "dungeon"):
                raw_dungeon_controls(ser)
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
    print("Starting CPU dungeon. Press Q in game to return to shell, Ctrl-C exits host.")
    time.sleep(0.2)
    ser.write(b"dungeon\n")

    try:
        raw_dungeon_controls(ser)
        while True:
            line = input()
            cmd = line.strip().lower()
            if cmd in ("q", "quit", "exit"):
                break
            ser.write((line + "\n").encode("ascii", errors="ignore"))
            if cmd in ("d", "dungeon"):
                raw_dungeon_controls(ser)
    except KeyboardInterrupt:
        pass
    finally:
        stop_flag.set()
        thread.join(timeout=0.2)
        ser.close()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Connect to the FPGA CPU UART shell.")
    parser.add_argument("-p", "--port", help="Serial port, for example COM5 or /dev/cu.usbserial-130")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Baud rate, default 115200")
    parser.add_argument("--list", action="store_true", help="List serial ports and exit")
    parser.add_argument("--dungeon", action="store_true", help="Start dungeon immediately")
    parser.add_argument("--demo", action="store_true", help="Alias for --dungeon")
    parser.add_argument("--pong", action="store_true", help="Deprecated alias for --dungeon")
    parser.add_argument("--snake", action="store_true", help="Deprecated alias for --dungeon")
    args = parser.parse_args()

    if args.list:
        list_serial_ports()
        return 0
    if not args.port:
        parser.error("--port is required unless --list is used")
    if args.dungeon or args.demo or args.pong or args.snake:
        return dungeon_mode(args)
    return shell_mode(args)


if __name__ == "__main__":
    raise SystemExit(main())
