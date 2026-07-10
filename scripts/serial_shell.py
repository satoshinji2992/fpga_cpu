#!/usr/bin/env python3
"""Host UART client for the CPU-driven shell, CNN and Pong demos.

The FPGA top now exposes UART as memory-mapped I/O to the RISC-V CPU. The
program running on the CPU parses a tiny shell, receives an 8x8 digit image,
runs fixed-weight inference, and owns a small Pong state machine. This script
is only a UART terminal/client; command logic lives in asm/cnn_digit.s.
"""

import argparse
import json
import re
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


def render_pong_state(line: str) -> bool:
    match = re.search(r"P ([0-7]) ([0-5]) ([0-5]) ([01]) ([0-9a-fA-F])$", line.strip())
    if not match:
        return False

    ball_x, ball_y, paddle, game_over = (int(value) for value in match.groups()[:4])
    score = int(match.group(5), 16)
    rows = []
    for y in range(6):
        row = []
        for x in range(8):
            ball_here = x == ball_x and y == ball_y
            paddle_here = y == 5 and paddle <= x <= paddle + 2
            row.append("O" if ball_here else "=" if paddle_here else " ")
        rows.append("|" + "".join(row) + "|")

    if sys.stdout.isatty():
        print("\033[2J\033[H", end="")
    print("+--------+")
    print("\n".join(rows))
    print("+--------+")
    print(f"score {score}" + ("  GAME OVER (n: new, q: exit)" if game_over else ""), flush=True)
    return True


def reader_thread(ser: serial.Serial, stop_flag: threading.Event) -> None:
    line_buffer = ""
    while not stop_flag.is_set():
        data = ser.read(256)
        if data:
            text = data.decode("ascii", errors="replace")
            print(text, end="", flush=True)
            for char in text:
                if char == "\n":
                    render_pong_state(line_buffer.rstrip("\r"))
                    line_buffer = ""
                else:
                    line_buffer += char


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


def image_file_pixels(path: Path) -> str:
    """Read an 8x8 text image.

    Accepted foreground chars: 1 # @ X x
    Accepted background chars: 0 . _ -
    Spaces are ignored, so rows can be written as ". . # #".
    """
    rows = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line
        if not line.strip():
            continue
        bits = []
        for ch in line:
            if ch in "1#@Xx":
                bits.append("1")
            elif ch in "0._-":
                bits.append("0")
            elif ch.isspace():
                continue
            else:
                raise ValueError(f"bad image char {ch!r}; use #/. or 1/0")
        if bits:
            rows.append("".join(bits))

    if len(rows) != 8 or any(len(row) != 8 for row in rows):
        shape = "x".join(str(len(row)) for row in rows) or "empty"
        raise ValueError(f"image must be exactly 8 rows x 8 cols, got {len(rows)} rows ({shape})")
    return "".join(rows)


def print_digit_preview(pixels: str) -> None:
    for y in range(8):
        row = pixels[y * 8:(y + 1) * 8]
        print("".join("#" if ch == "1" else "." for ch in row))


def send_pixels(ser: serial.Serial, pixels: str, label: str) -> None:
    print(f"\n[host] sending 8x8 {label}:")
    print("+--------+")
    for y in range(8):
        row = pixels[y * 8:(y + 1) * 8]
        print("|" + "".join("#" if ch == "1" else "." for ch in row) + "|")
    print("+--------+")
    ser.write(pixels.encode("ascii") + b"\n")


def send_cnn_digit(ser: serial.Serial, digit: int) -> None:
    pixels = digit_pixels(digit)
    send_pixels(ser, pixels, f"MNIST prototype digit {digit}")


def send_cnn_image_file(ser: serial.Serial, path: Path) -> None:
    pixels = image_file_pixels(path)
    send_pixels(ser, pixels, str(path))


def cnn_control_loop(ser: serial.Serial) -> None:
    print("[host] CNN mode: enter digit 0-9 or an 8x8 image path; q returns to CPU shell.")
    time.sleep(0.1)
    while True:
        value = input("cnn> ").strip()
        if value.lower() == "q":
            ser.write(b"q\n")
            time.sleep(0.2)
            return
        if value.isdigit() and 0 <= int(value) <= 9:
            send_cnn_digit(ser, int(value))
        else:
            try:
                send_cnn_image_file(ser, Path(value))
            except Exception as exc:
                print(f"[host] skipped: {exc}")


def pong_control_loop(ser: serial.Serial) -> None:
    print("[host] Pong controls: a/d move, s or Space step, n new, q back to CPU shell.")
    while True:
        ch = read_key().lower()
        if ch in ("\x03", "\x04"):
            raise KeyboardInterrupt
        if ch == " ":
            ch = "s"
        if ch not in ("a", "d", "s", "n", "q"):
            continue
        print(ch, flush=True)
        ser.write(ch.encode("ascii") + b"\n")
        if ch == "q":
            time.sleep(0.2)
            return


def shell_mode(args: argparse.Namespace) -> int:
    ser = open_serial(args)
    stop_flag = threading.Event()
    thread = threading.Thread(target=reader_thread, args=(ser, stop_flag), daemon=True)
    thread.start()

    print(f"Connected to {args.port} at {args.baud} baud.")
    print("Host shell commands are sent to the CPU.")
    print("Useful commands: help, status/s, mem N/mN/0..3, perf/p, ledX, cnn, pong.")
    print("Host-only: quit/exit closes this Python client.")
    time.sleep(0.2)

    try:
        while True:
            line = input()
            cmd = line.strip().lower()
            if cmd in ("quit", "exit"):
                break
            if not cmd:
                ser.write(b"\n")
                continue
            ser.write((line + "\n").encode("ascii", errors="ignore"))
            if cmd in ("c", "cnn"):
                cnn_control_loop(ser)
            elif cmd == "pong":
                pong_control_loop(ser)
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
    if args.image:
        send_cnn_image_file(ser, args.image)
    else:
        send_cnn_digit(ser, args.cnn)
    time.sleep(1.0)
    ser.write(b"q\n")
    time.sleep(0.2)

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
    parser.add_argument("--image", type=Path, metavar="FILE",
                        help="With --cnn, send an 8x8 #/. or 1/0 text image instead of a prototype")
    args = parser.parse_args()

    if args.list:
        list_serial_ports()
        return 0
    if not args.port:
        parser.error("--port is required unless --list is used")
    if args.image and args.cnn is None:
        parser.error("--image must be used together with --cnn DIGIT; DIGIT is only a label/start trigger")
    if args.cnn is not None:
        return cnn_mode(args)
    return shell_mode(args)


if __name__ == "__main__":
    raise SystemExit(main())
