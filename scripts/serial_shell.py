#!/usr/bin/env python3
"""Host UART client for the CPU-driven shell, CNN and Pong demos.

The FPGA top now exposes UART as memory-mapped I/O to the RISC-V CPU. The
program running on the CPU parses a tiny shell, receives an 8x8 digit image,
runs fixed-weight inference, and owns a small Pong state machine. This script
is only a UART terminal/client; command logic lives in asm/cnn_digit.s.
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


def pong_control_loop(ser: serial.Serial) -> None:
    print("[host] Pong controls: a/d move, s or Space step, n new, q back to host shell.")
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
                digit_text = input("[host] digit 0-9 or image path > ").strip()
                if digit_text.isdigit() and 0 <= int(digit_text) <= 9:
                    send_cnn_digit(ser, int(digit_text))
                else:
                    try:
                        send_cnn_image_file(ser, Path(digit_text))
                    except Exception as exc:
                        print(f"[host] skipped: {exc}")
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

    stop_flag.set()
    thread.join(timeout=0.2)
    ser.close()
    return 0


def pong_mode(args: argparse.Namespace) -> int:
    ser = open_serial(args)
    stop_flag = threading.Event()
    thread = threading.Thread(target=reader_thread, args=(ser, stop_flag), daemon=True)
    thread.start()

    print(f"Connected to {args.port} at {args.baud} baud.")
    print("Starting CPU Pong demo.")
    time.sleep(0.2)
    ser.write(b"pong\n")
    time.sleep(0.2)
    try:
        pong_control_loop(ser)
    except KeyboardInterrupt:
        pass

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
    parser.add_argument("--pong", action="store_true",
                        help="Start CPU Pong immediately and use keyboard controls")
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
    if args.pong:
        return pong_mode(args)
    return shell_mode(args)


if __name__ == "__main__":
    raise SystemExit(main())
