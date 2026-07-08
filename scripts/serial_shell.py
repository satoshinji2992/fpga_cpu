#!/usr/bin/env python3
"""Tiny host client for the FPGA UART shell."""

import argparse
import re
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


def transact(ser: serial.Serial, command: bytes, timeout: float = 0.8) -> str:
    ser.reset_input_buffer()
    ser.write(command)
    deadline = time.time() + timeout
    data = bytearray()
    while time.time() < deadline:
        chunk = ser.read(256)
        if chunk:
            data.extend(chunk)
            if b"cpu> " in data:
                break
        else:
            time.sleep(0.02)
    return data.decode("ascii", errors="replace")


def parse_mem(text: str) -> int | None:
    match = re.search(r"mem\d=0x([0-9a-fA-F]{8})", text)
    return int(match.group(1), 16) if match else None


def parse_perf(text: str) -> dict[str, int]:
    match = re.search(
        r"c=([0-9a-fA-F]{8})\s+i=([0-9a-fA-F]{8})\s+b=([0-9a-fA-F]{2})\s+f=([0-9a-fA-F]{2})\s+m=([0-9a-fA-F]{2})",
        text,
    )
    if not match:
        return {}
    return {
        "cycle": int(match.group(1), 16),
        "instret": int(match.group(2), 16),
        "branch": int(match.group(3), 16),
        "flush": int(match.group(4), 16),
        "bp_miss": int(match.group(5), 16),
    }


def show_board_demo(ser: serial.Serial) -> None:
    status = transact(ser, b"s")
    mem = [parse_mem(transact(ser, str(i).encode("ascii"))) for i in range(4)]
    perf = parse_perf(transact(ser, b"p"))

    print("\n=== FPGA CPU 交互演示 ===")
    print(status.replace("cpu> ", "").strip() or "(no status)")
    print("")
    print("内存结果:")
    labels = [
        ("Mem[0]", "MUL 7*6, RV32M 乘法", 42),
        ("Mem[1]", "1+2+...+10, 分支循环/预测", 55),
        ("Mem[2]", "POPCOUNT(0xFF), 自定义指令", 8),
        ("Mem[3]", "RDCYCLE, CSR 周期计数", None),
    ]
    for value, (name, desc, expected) in zip(mem, labels):
        if value is None:
            print(f"  {name}: 未读到")
            continue
        ok = "" if expected is None else (" OK" if value == expected else f" expected {expected}")
        print(f"  {name}: 0x{value:08X} = {value:<5}  {desc}{ok}")

    print("")
    if perf:
        cycle = perf["cycle"]
        instret = perf["instret"]
        cpi = (cycle / instret) if instret else 0.0
        acc = 100.0 * (perf["branch"] - perf["bp_miss"]) / perf["branch"] if perf["branch"] else 0.0
        print("硬件性能计数器:")
        print(f"  cycle   = {cycle}")
        print(f"  instret = {instret}")
        print(f"  CPI     = {cpi:.2f}")
        print(f"  branch  = {perf['branch']}")
        print(f"  flush   = {perf['flush']}")
        print(f"  bp_miss = {perf['bp_miss']}  (branch accuracy {acc:.1f}%)")
    else:
        print("硬件性能计数器: 未读到。可能 FPGA bitstream 还是旧版。")


def demo_mode(args: argparse.Namespace) -> int:
    ser = serial.Serial(args.port, args.baud, timeout=0.05)
    time.sleep(0.2)
    banner = ser.read(512).decode("ascii", errors="replace")
    print(f"Connected to {args.port} at {args.baud} baud.")
    if banner.strip():
        print(banner, end="" if banner.endswith("\n") else "\n")

    print("Demo mode: r refresh, g/a/d/x/n Pong, p perf raw, q quit.")
    try:
        show_board_demo(ser)
        while True:
            choice = input("\n[r]刷新 [g/a/d/x/n]Pong [p]原始计数 [q]退出 > ").strip().lower()
            if choice in ("q", "quit", "exit"):
                break
            if choice in ("", "r"):
                show_board_demo(ser)
            elif choice in ("g", "a", "d", "x", "n"):
                cmd = b"r" if choice == "d" else choice.encode("ascii")
                text = transact(ser, cmd)
                rendered = False
                for line in text.splitlines():
                    if render_pong(line):
                        rendered = True
                    elif line.strip() and line.strip() != "cpu>":
                        print(line)
                if not rendered and not text.strip():
                    print("(no response)")
            elif choice == "p":
                print(transact(ser, b"p").strip())
            else:
                print("未知命令")
    except KeyboardInterrupt:
        pass
    finally:
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
    parser.add_argument("--demo", action="store_true", help="Guided board demo with decoded memory/perf results")
    parser.add_argument("--pong", action="store_true", help="Use keyboard controls for the UART Pong demo")
    parser.add_argument("--snake", action="store_true", help="Alias for --pong kept for old notes")
    args = parser.parse_args()

    if args.list:
        list_serial_ports()
        return 0
    if not args.port:
        parser.error("--port is required unless --list is used")
    if args.demo:
        return demo_mode(args)
    if args.pong or args.snake:
        return pong_mode(args)
    return interactive(args)


if __name__ == "__main__":
    raise SystemExit(main())
