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
    print("Commands: h help, s status, 0/1/2/3 read memory, p perf, q quit.")
    time.sleep(0.2)

    try:
        while True:
            line = input()
            if line.strip().lower() in ("q", "quit", "exit"):
                break
            if line:
                ser.write(line[0].encode("ascii", errors="ignore"))
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


def render_pong(line: str) -> bool:
    parts = line.strip().split()
    if len(parts) < 4 or parts[0] != "P":
        return False
    try:
        bx = int(parts[1][1])
        by = int(parts[1][2])
        px = int(parts[2][1])
        over = parts[3][1] == "1"
    except (IndexError, ValueError):
        return False

    board = [["." for _ in range(8)] for _ in range(6)]
    if 0 <= bx < 8 and 0 <= by < 6:
        board[by][bx] = "O"
    for x in range(px, min(px + 3, 8)):
        board[5][x] = "="
    print("\n".join("".join(row) for row in board))
    if over:
        print("GAME OVER")
    return True


def pong_mode(args: argparse.Namespace) -> int:
    ser = serial.Serial(args.port, args.baud, timeout=0.05)
    print(f"Connected to {args.port} at {args.baud} baud.")
    print("Pong mode: A/D move, Space step, n reset, g redraw, p metrics, q quit.")
    time.sleep(0.2)
    ser.write(b"g")

    keymap = {
        "a": b"a",
        "A": b"a",
        "d": b"r",
        "D": b"r",
        " ": b"x",
        "n": b"n",
        "N": b"n",
        "g": b"g",
        "G": b"g",
        "p": b"p",
        "P": b"p",
    }

    try:
        while True:
            while ser.in_waiting:
                line = ser.readline().decode("ascii", errors="replace")
                if line:
                    if not render_pong(line):
                        print(line, end="")
            ch = read_key()
            if ch in ("q", "Q", "\x03"):
                break
            if ch in keymap:
                ser.write(keymap[ch])
                time.sleep(0.05)
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Connect to the FPGA UART shell.")
    parser.add_argument("-p", "--port", help="Serial port, for example COM5 or /dev/tty.usbserial-0001")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Baud rate, default 115200")
    parser.add_argument("--list", action="store_true", help="List serial ports and exit")
    parser.add_argument("--pong", action="store_true", help="Use keyboard controls for the UART Pong demo")
    parser.add_argument("--snake", action="store_true", help="Alias for --pong kept for old notes")
    args = parser.parse_args()

    if args.list:
        list_serial_ports()
        return 0
    if not args.port:
        parser.error("--port is required unless --list is used")
    if args.pong or args.snake:
        return pong_mode(args)
    return interactive(args)


if __name__ == "__main__":
    raise SystemExit(main())
