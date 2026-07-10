#!/usr/bin/env python3
"""Host UART client for the CPU-driven shell, CNN and Pong demos.

The FPGA top now exposes UART as memory-mapped I/O to the RISC-V CPU. The
program running on the CPU parses a tiny shell, receives an 8x8 digit image,
runs fixed-weight inference, and owns a small Pong state machine. This script
is only a UART terminal/client; command logic lives in asm/soc_firmware.s.
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
    # y=6 is the CPU's out-of-bounds marker after the paddle misses.
    match = re.search(r"P ([0-7]) ([0-6]) ([0-5]) ([01]) ([0-9a-fA-F])$", line.strip())
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


def render_paint_packet(payload: bytes) -> None:
    if len(payload) != 131:
        return
    cursor_x = payload[0] | (payload[1] << 8)
    cursor_y = payload[2]
    pixels = "".join({0: ".", 1: "#", 2: "@"}.get(value, "?") for value in payload[3:])
    if sys.stdout.isatty():
        print("\033[2J\033[H", end="")
    print("+----------------+")
    for row in range(8):
        print("|" + pixels[row * 16:(row + 1) * 16] + "|")
    print("+----------------+")
    print(f"SDRAM canvas 512x256 (128 KiB)  cursor=({cursor_x},{cursor_y})", flush=True)


def render_perf_values(values: list[int]) -> None:
    cycle, instret, branch, flush, stall, bp_miss, mdu, hit, miss = values
    cpi = cycle / instret if instret else 0.0
    throughput_mips = 12.5 / cpi if cpi else 0.0
    bp_accuracy = 100.0 * (branch - bp_miss) / branch if branch else 100.0
    accesses = hit + miss
    hit_rate = 100.0 * hit / accesses if accesses else 0.0
    print("\n[CPU performance counters @ 12.5 MHz]")
    print(f"cycle={cycle} (elapsed clocks)  instret={instret} (retired instructions)")
    print(f"CPI={cpi:.3f}  throughput={throughput_mips:.3f} MIPS")
    print(f"branch={branch}  flush={flush}  bp_miss={bp_miss}  BP accuracy={bp_accuracy:.2f}%")
    print(f"stall={stall} (load/memory wait cycles)  mdu={mdu} (mul/div/rem instructions)")
    print(f"ic_hit={hit}  ic_miss={miss}  I-cache hit rate={hit_rate:.2f}%", flush=True)


def render_perf_state(line: str) -> bool:
    """Backward-compatible parser for pre-R9 text firmware."""
    match = re.fullmatch(r"perf ([0-9a-fA-F]{8}(?: [0-9a-fA-F]{8}){8})", line.strip())
    if not match:
        return False
    render_perf_values([int(word, 16) for word in match.group(1).split()])
    return True


def reader_thread(ser: serial.Serial, stop_flag: threading.Event) -> None:
    line_buffer = ""
    packet_stage = "text"
    packet_kind = 0
    packet_length = 0
    packet_payload = bytearray()
    while not stop_flag.is_set():
        data = ser.read(256)
        if data:
            for byte in data:
                if packet_stage == "text" and byte == 0xA5:
                    packet_stage = "kind"
                    continue
                if packet_stage == "kind":
                    if byte not in (ord("P"), ord("D")):
                        print("\n[host] discarded malformed binary packet\n", end="")
                        packet_stage = "text"
                    else:
                        packet_kind = byte
                        packet_stage = "length"
                    continue
                if packet_stage == "length":
                    expected = 36 if packet_kind == ord("P") else 131
                    if byte != expected:
                        print(f"\n[host] bad binary packet length {byte}, expected {expected}\n", end="")
                        packet_stage = "text"
                    else:
                        packet_length = byte
                        packet_payload.clear()
                        packet_stage = "payload"
                    continue
                if packet_stage == "payload":
                    packet_payload.append(byte)
                    if len(packet_payload) == packet_length:
                        if packet_kind == ord("P"):
                            values = [int.from_bytes(packet_payload[i:i + 4], "little")
                                      for i in range(0, 36, 4)]
                            render_perf_values(values)
                        else:
                            render_paint_packet(bytes(packet_payload))
                        packet_stage = "text"
                    continue

                char = chr(byte) if byte < 128 else "�"
                print(char, end="")
                if char == "\n":
                    line = line_buffer.rstrip("\r")
                    render_pong_state(line)
                    render_perf_state(line)
                    line_buffer = ""
                else:
                    line_buffer += char
            sys.stdout.flush()


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
    print("[host] CPU Pong runs automatically. Controls: a/d move, n new, q back to CPU shell; s steps once.")
    while True:
        ch = read_key().lower()
        if ch in ("\x03", "\x04"):
            raise KeyboardInterrupt
        if ch == " ":
            ch = "s"
        if ch not in ("a", "d", "s", "n", "q"):
            continue
        print(ch, flush=True)
        # Pong UART input is interrupt-driven and consumes one byte at a time.
        # Do not append a newline: after q it would leak into the CPU shell as
        # an empty command, and during play it is needless IRQ traffic.
        ser.write(ch.encode("ascii"))
        if ch == "q":
            time.sleep(0.2)
            return


def paint_control_loop(ser: serial.Serial) -> None:
    print("[host] SDRAM Paint controls: W/A/S/D move, X or Space toggle, C clear, Q back to CPU shell.")
    while True:
        ch = read_key().lower()
        if ch in ("\x03", "\x04"):
            raise KeyboardInterrupt
        if ch not in ("w", "a", "s", "d", "x", " ", "c", "q"):
            continue
        print("x" if ch == " " else ch, flush=True)
        ser.write(ch.encode("ascii"))
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
    print("Useful commands: help, status/s, self-test m0..m9, irq, sdram, perf/p, ledX, cnn, pong, paint.")
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
            elif cmd == "paint":
                paint_control_loop(ser)
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
