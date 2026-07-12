#!/usr/bin/env python3
"""
rvasm.py — a small two-pass assembler for the RV32I/M subset + CSR + custom
instructions implemented by src/riscv_pipeline_core.v in this project.

There is no RISC-V toolchain in this repo; the existing instr_mem programs are
hand-assembled. This assembler makes real software (e.g. asm/soc_firmware.s) writable
in assembly and emits a Verilog initial-block fragment (src/soc_firmware.vh) that
top.v `include`s to initialize instr_mem.

Supported:
  RV32I   add/sub/and/or/xor/sll/srl/sra/slt/sltu + i-forms, slli/srli/srai,
          lb/lh/lw/lbu/lhu, sb/sh/sw, beq/bne/blt/bge/bltu/bgeu, jal/jalr,
          lui/auipc, ecall/ebreak, csrrs/csrrw (csr read form)
  RV32M   mul/mulh/mulhsu/mulhu/div/divu/rem/remu
  CSR     rdcycle rd, rdinstret rd   (= csrrs rd, 0xC00/0xC02, x0)
  Custom  popcount rd, rs1 ; bitrev rd, rs1 ; fadd32/fmul32/fgt32 rd, rs1, rs2
          (opcode 0x0B, custom-0; fadd32/fmul32 are lightweight float32 ops)
  Pseudo  li, mv, nop, j, jr, ret, jal, call, beqz/bnez/bltz/bgez/blez/bgtz,
          not, neg, seqz/snez
  Macros  .word w,...  .putc 'c'  .puts "str"  .align n  .org addr
  Output  --hex FILE  |  --vh FILE (default: prints a .vh initial block)

Encoding reference (confirmed against riscv_pipeline_core.v decode):
  R-type  : funct7[31:25] rs2[24:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
  RV32M   : opcode 0110011, funct7 0000001, funct3 000..111 = mul..remu
  custom  : opcode 0001011, funct7 0000000, funct3 001=popcount 010=bitrev
            011=fadd32 100=fmul32 101=fgt32
  CSR rd  : opcode 1110011, funct3 010 (csrrs), csr=0xC00 cycle / 0xC02 instret

Usage:
  python3 scripts/rvasm.py asm/soc_firmware.s --vh src/soc_firmware.vh --base 0
  python3 scripts/rvasm.py asm/soc_firmware.s --hex /tmp/firmware.hex
"""

import sys
import re
import argparse

# ----------------------------------------------------------------------------
# Register names
# ----------------------------------------------------------------------------
REGS = {}
_ABI = [
    ("zero", 0), ("ra", 1), ("sp", 2), ("gp", 3), ("tp", 4),
    ("t0", 5), ("t1", 6), ("t2", 7),
    ("s0", 8), ("fp", 8), ("s1", 9),
    ("a0", 10), ("a1", 11), ("a2", 12), ("a3", 13), ("a4", 14), ("a5", 15),
    ("a6", 16), ("a7", 17),
    ("s2", 18), ("s3", 19), ("s4", 20), ("s5", 21), ("s6", 22), ("s7", 23),
    ("s8", 24), ("s9", 25), ("s10", 26), ("s11", 27),
    ("t3", 28), ("t4", 29), ("t5", 30), ("t6", 31),
]
for _n, _v in _ABI:
    REGS[_n] = _v
for _i in range(32):
    REGS["x%d" % _i] = _i


def parse_reg(tok):
    t = tok.strip().rstrip(",")
    if t not in REGS:
        raise AsmError("unknown register %r" % tok)
    return REGS[t]


class AsmError(Exception):
    pass


def parse_imm(tok, symbols=None):
    """Parse an immediate: decimal, 0x hex, 0b bin, negative, or 'c' char, or a
    symbol name (resolved via symbols dict). Returns an int."""
    t = tok.strip().rstrip(",")
    if t == "":
        raise AsmError("empty immediate")
    # char literal 'c' or '\n'
    if len(t) >= 3 and t[0] == "'" and t[-1] == "'":
        inner = t[1:-1]
        if inner == "\\n":
            return 0x0A
        if inner == "\\r":
            return 0x0D
        if inner == "\\t":
            return 0x09
        if inner == "\\0":
            return 0x00
        if len(inner) == 1:
            return ord(inner)
        raise AsmError("bad char literal %r" % tok)
    # symbol?
    if symbols is not None and t in symbols:
        return symbols[t]
    if re.fullmatch(r"-?\d+", t):
        return int(t)
    if re.fullmatch(r"-?0[xX][0-9a-fA-F]+", t):
        return int(t, 16)
    if re.fullmatch(r"-?0[bB][01]+", t):
        return int(t, 2)
    # last resort: maybe it's an unresolved symbol in pass 2
    if re.fullmatch(r"[A-Za-z_.][A-Za-z0-9_.]*", t):
        raise AsmError("undefined symbol %r" % t)
    raise AsmError("bad immediate %r" % tok)


# ----------------------------------------------------------------------------
# Encoding helpers
# ----------------------------------------------------------------------------
def u(x, n):
    x &= (1 << n) - 1
    return x


def enc_r(opcode, rd, funct3, rs1, rs2, funct7):
    return (u(funct7, 7) << 25) | (u(rs2, 5) << 20) | (u(rs1, 5) << 15) | \
           (u(funct3, 3) << 12) | (u(rd, 5) << 7) | u(opcode, 7)


def enc_i(opcode, rd, funct3, rs1, imm):
    return (u(imm, 12) << 20) | (u(rs1, 5) << 15) | (u(funct3, 3) << 12) | \
           (u(rd, 5) << 7) | u(opcode, 7)


def enc_s(opcode, funct3, rs1, rs2, imm):
    imm = u(imm, 12)
    hi = (imm >> 5) & 0x7F
    lo = imm & 0x1F
    return (hi << 25) | (u(rs2, 5) << 20) | (u(rs1, 5) << 15) | \
           (u(funct3, 3) << 12) | (lo << 7) | u(opcode, 7)


def enc_b(opcode, funct3, rs1, rs2, imm):
    # imm is a byte offset; branch targets are 2-byte aligned, bit 0 unused.
    if imm & 1:
        raise AsmError("branch target not 2-aligned: %d" % imm)
    if imm < -4096 or imm > 4094:
        raise AsmError("branch target out of range: %d (expected -4096..4094)" % imm)
    imm = u(imm, 13)
    b12 = (imm >> 12) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    b11 = (imm >> 11) & 1
    return (b12 << 31) | (b10_5 << 25) | (u(rs2, 5) << 20) | (u(rs1, 5) << 15) | \
           (u(funct3, 3) << 12) | (b4_1 << 8) | (b11 << 7) | u(opcode, 7)


def enc_u(opcode, rd, imm):
    return (u(imm, 20) << 12) | (u(rd, 5) << 7) | u(opcode, 7)


def enc_j(opcode, rd, imm):
    if imm & 1:
        raise AsmError("jump target not 2-aligned: %d" % imm)
    if imm < -1048576 or imm > 1048574:
        raise AsmError("jump target out of range: %d" % imm)
    imm = u(imm, 21)
    b20 = (imm >> 20) & 1
    b10_1 = (imm >> 1) & 0x3FF
    b11 = (imm >> 11) & 1
    b19_12 = (imm >> 12) & 0xFF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | \
           (u(rd, 5) << 7) | u(opcode, 7)


# ----------------------------------------------------------------------------
# Instruction table. Each entry: (kind, opcode, funct3, funct7_or_None)
#   kind in: R, I, Ishift, S, B, U, J, Jr, CSR, Custom, Sys
# ----------------------------------------------------------------------------
OPC_R = 0b0110011
OPC_RI = 0b0010011
OPC_LD = 0b0000011
OPC_ST = 0b0100011
OPC_BR = 0b1100011
OPC_JAL = 0b1101111
OPC_JALR = 0b1100111
OPC_LUI = 0b0110111
OPC_AUIPC = 0b0010111
OPC_SYS = 0b1110011
OPC_CUSTOM0 = 0b0001011

# funct3 for various groups
R_TAB = {  # RV32I R-type: funct3 -> (name, funct7_0, funct7_alt)
    "add": (0b000, 0b0000000, None), "sub": (0b000, 0b0100000, None),
    "sll": (0b001, 0b0000000, None), "slt": (0b010, 0b0000000, None),
    "sltu": (0b011, 0b0000000, None), "xor": (0b100, 0b0000000, None),
    "srl": (0b101, 0b0000000, None), "sra": (0b101, 0b0100000, None),
    "or": (0b110, 0b0000000, None), "and": (0b111, 0b0000000, None),
}
M_TAB = {  # RV32M (funct7=0000001): funct3
    "mul": 0b000, "mulh": 0b001, "mulhsu": 0b010, "mulhu": 0b011,
    "div": 0b100, "divu": 0b101, "rem": 0b110, "remu": 0b111,
}
RI_TAB = {  # I-type ALU: funct3
    "addi": 0b000, "slti": 0b010, "sltiu": 0b011, "xori": 0b100,
    "ori": 0b110, "andi": 0b111,
}
RISH_TAB = {  # I-type shifts: name -> (funct3, funct7)
    "slli": (0b001, 0b0000000), "srli": (0b101, 0b0000000), "srai": (0b101, 0b0100000),
}
LD_TAB = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
ST_TAB = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
BR_TAB = {"beq": 0b000, "bne": 0b001, "blt": 0b100, "bge": 0b101,
          "bltu": 0b110, "bgeu": 0b111}
CSR_NAMES = {
    "mstatus": 0x300, "mie": 0x304, "mtvec": 0x305,
    "mepc": 0x341, "mcause": 0x342, "mip": 0x344,
    "cycle": 0xC00, "time": 0xC01, "instret": 0xC02,
}

# ----------------------------------------------------------------------------
# Operand splitting
# ----------------------------------------------------------------------------
def split_operands(s):
    # split on commas, but keep "imm(rs1)" forms together by handling in caller
    return [p.strip() for p in s.split(",") if p.strip() != ""]


def parse_mem_operand(tok, symbols):
    """Parse 'imm(rs1)' or 'sym' or 'sym(rs1)'. Returns (imm, rs1)."""
    tok = tok.strip()
    m = re.fullmatch(r"\s*(.*?)\s*\(\s*([A-Za-z0-9]+)\s*\)\s*", tok)
    if m:
        imm = parse_imm(m.group(1), symbols)
        rs1 = parse_reg(m.group(2))
        return imm, rs1
    # bare symbol/imm -> offset from x0
    return parse_imm(tok, symbols), 0


# ----------------------------------------------------------------------------
# Macro expansion (happens before pass-1 addressing so item count is known)
# ----------------------------------------------------------------------------
def expand_line(mnemonic, ops, putc_label):
    """Expand pseudo-instructions and macros into a list of real (mnemonic, ops)
    tuples. Returns None if it's a real instruction (caller handles). Raises
    AsmError on bad input. 'ops' is the raw operand substring (may be empty)."""
    m = mnemonic

    if m == "nop":
        return [("addi", "x0, x0, 0")]
    if m == "mv":
        return [("addi", ops + ", 0")]
    if m == "not":
        return [("xori", ops + ", -1")]
    if m == "neg":
        rd, rs = split_operands(ops)
        return [("sub", "%s, x0, %s" % (rd, rs))]
    if m == "seqz":
        return [("sltiu", ops + ", 1")]
    if m == "snez":
        return [("sltu", "%s, x0, %s" % tuple(split_operands(ops)))]
    # j / jr / ret / call
    if m == "j":
        return [("jal", "x0, " + ops)]
    if m == "jr":
        return [("jalr", "x0, 0, " + ops)]
    if m == "ret":
        return [("jalr", "x0, 0, ra")]
    if m == "call":
        return [("jal", "ra, " + ops)]
    if m == "csrw":
        csr, rs = split_operands(ops)
        return [("csrrw", "x0, %s, %s" % (csr, rs))]
    # branch-if-zero forms
    if m in ("beqz", "bnez", "bltz", "bgez", "blez", "bgtz"):
        rd, off = split_operands(ops)
        mp = {"beqz": "beq", "bnez": "bne", "bltz": "blt", "bgez": "bge"}
        if m in ("beqz", "bnez", "bltz", "bgez"):
            return [(mp[m], "%s, x0, %s" % (rd, off))]
        # blez rd, off -> bge x0, rd, off ; bgtz rd, off -> blt x0, rd, off
        if m == "blez":
            return [("bge", "x0, %s, %s" % (rd, off))]
        return [("blt", "x0, %s, %s" % (rd, off))]
    # li (expand to addi if fits, else lui+addi)
    if m == "li":
        rd, imm = split_operands(ops)
        return _expand_li(rd.strip(), imm)
    # la (load address): data lives in low RAM here, so addi suffices for <2048
    if m == "la":
        rd, imm = split_operands(ops)
        return [("addi", "%s, x0, %s" % (rd.strip(), imm))]
    if m == ".putc":
        # li a0, 'c' ; jal ra, putc
        return [("li", "a0, %s" % ops), ("call", putc_label)]
    if m == ".puts":
        # emit li a0,<ch>; call putc for each char in the string
        s = _parse_string_literal(ops)
        out = []
        for ch in s:
            out.append(("li", "a0, %d" % ord(ch)))
            out.append(("call", putc_label))
        return out
    return None  # not a macro


def _expand_li(rd, imm_tok):
    # imm_tok may be a symbol; we can't fully resolve in expansion, but we can
    # decide addi vs lui+addi only for numeric literals. For symbols, assume
    # they're small data offsets and use addi. Large constants should be written
    # numerically or with explicit lui/addi.
    try:
        val = int(imm_tok, 0)
    except (ValueError, TypeError):
        return [("addi", "%s, x0, %s" % (rd, imm_tok))]
    if -2048 <= val <= 2047:
        return [("addi", "%s, x0, %d" % (rd, val))]
    # lui rd, hi ; addi rd, rd, lo
    val32 = val & 0xFFFFFFFF
    lo = val32 & 0xFFF
    hi = (val32 >> 12) & 0xFFFFF
    if lo & 0x800:  # sign-extend correction
        hi = (hi + 1) & 0xFFFFF
    return [("lui", "%s, 0x%x" % (rd, hi)),
            ("addi", "%s, %s, %d" % (rd, rd, (lo - 0x1000 if lo & 0x800 else lo)))]


def _parse_string_literal(s):
    s = s.strip()
    if len(s) >= 2 and s[0] in '"\'' and s[-1] == s[0] and s[0] == '"':
        inner = s[1:-1]
    else:
        raise AsmError(".puts expects a \"string\", got %r" % s)
    out = []
    i = 0
    while i < len(inner):
        c = inner[i]
        if c == "\\" and i + 1 < len(inner):
            n = inner[i + 1]
            out.append({"n": "\n", "r": "\r", "t": "\t", "0": "\0",
                        "\\": "\\", '"': '"'}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return out


def fully_expand(mn, ops, putc_label):
    """Recursively expand macros/pseudos until only real instructions remain.
    Handles nested cases like .puts -> li -> addi and .puts -> call -> jal."""
    seq = expand_line(mn, ops, putc_label)
    if seq is None:
        return [(mn, ops)]          # base case: a real instruction
    out = []
    for rmn, rop in seq:
        out.extend(fully_expand(rmn, rop, putc_label))
    return out


# ----------------------------------------------------------------------------
# Assembler
# ----------------------------------------------------------------------------
class Assembler:
    def __init__(self, base_addr=0, putc_label="putc"):
        self.base = base_addr
        self.putc_label = putc_label
        self.symbols = {}
        self.items = []          # list of (addr, mnemonic, ops, srcline)
        self.words = []          # list of (addr, value, srcline) from .word/.org

    # ---- pass 1: layout + symbols, with macro expansion ----
    def pass1(self, lines):
        addr = self.base
        for lineno, raw in enumerate(lines, 1):
            raw = raw.split("#", 1)[0]      # strip comments
            # ';' separates multiple statements on one line
            for stmt in raw.split(";"):
                line = stmt.strip()
                if not line:
                    continue
                # peel any leading "label:" prefixes
                while ":" in line:
                    idx = line.index(":")
                    head = line[:idx].strip()
                    if re.fullmatch(r"[A-Za-z_.][A-Za-z0-9_.]*", head) and "(" not in head:
                        if head in self.symbols:
                            raise AsmError("line %d: duplicate label %r" % (lineno, head))
                        self.symbols[head] = addr
                        line = line[idx + 1:].strip()
                        if not line:
                            break
                    else:
                        break
                if not line:
                    continue

                first = line.split(None, 1)[0]
                rest = line[len(first):].strip()
                if first in (".equ", ".set"):
                    name, val = [t.strip() for t in rest.split(",", 1)]
                    self.symbols[name] = parse_imm(val, self.symbols)
                    continue
                if first == ".word":
                    for tok in rest.split(","):
                        tok = tok.strip()
                        if tok:
                            self.words.append((addr, lineno, tok))
                            addr += 4
                    continue
                if first == ".align":
                    n = int(rest, 0)
                    if n > 0:
                        mask = (1 << n) - 1
                        if addr & mask:
                            addr = (addr + mask) & ~mask
                    continue
                if first == ".org":
                    addr = int(rest, 0)
                    continue
                if first in (".text", ".data", ".globl", ".global", ".section"):
                    continue   # layout directives ignored (single address space)

                # Resolve known .equ constants before pseudo expansion. A
                # symbolic `li` may need LUI+ADDI (for example MMIO 0x1018),
                # while unresolved symbols are otherwise assumed to be small.
                if first == "li":
                    li_ops = split_operands(rest)
                    if len(li_ops) == 2 and li_ops[1] in self.symbols:
                        rest = "%s, %d" % (li_ops[0], self.symbols[li_ops[1]])

                for rmn, rop in fully_expand(first, rest, self.putc_label):
                    self.items.append((addr, rmn, rop, lineno))
                    addr += 4
        self.end_addr = addr

    # ---- pass 2: encode ----
    def pass2(self):
        out = []  # (addr, word, comment)
        # .word entries
        word_addrs = {}
        for addr, lineno, tok in self.words:
            val = parse_imm(tok, self.symbols)
            word_addrs[addr] = (val, lineno)
        # encode instructions
        for addr, mn, ops, lineno in self.items:
            try:
                w = self.encode(mn, ops, addr)
            except AsmError as e:
                raise AsmError("line %d: %s (mnemonic %s, ops %r)" %
                               (lineno, e, mn, ops))
            out.append((addr, w, ("%-6s %s" % (mn, ops)).rstrip()))
        return out, word_addrs

    # ---- encode one instruction ----
    def encode(self, mn, ops, addr):
        sym = self.symbols

        # RV32M R-type
        if mn in M_TAB:
            rd, rs1, rs2 = (parse_reg(t) for t in split_operands(ops))
            return enc_r(OPC_R, rd, M_TAB[mn], rs1, rs2, 0b0000001)
        # RV32I R-type
        if mn in R_TAB:
            rd, rs1, rs2 = (parse_reg(t) for t in split_operands(ops))
            f3, f7, _ = R_TAB[mn]
            return enc_r(OPC_R, rd, f3, rs1, rs2, f7)
        # custom
        if mn in ("popcount", "bitrev"):
            rd, rs1 = (parse_reg(t) for t in split_operands(ops))
            f3 = 0b001 if mn == "popcount" else 0b010
            return enc_r(OPC_CUSTOM0, rd, f3, rs1, 0, 0b0000000)
        if mn in ("fadd32", "fmul32", "fgt32"):
            rd, rs1, rs2 = (parse_reg(t) for t in split_operands(ops))
            f3 = {"fadd32": 0b011, "fmul32": 0b100, "fgt32": 0b101}[mn]
            return enc_r(OPC_CUSTOM0, rd, f3, rs1, rs2, 0b0000000)
        # I-type ALU
        if mn in RI_TAB:
            rd, rs1, imm = split_operands(ops)
            return enc_i(OPC_RI, parse_reg(rd), RI_TAB[mn], parse_reg(rs1),
                         parse_imm(imm, sym))
        # I-type shifts: imm[11:5]=funct7, imm[4:0]=shamt
        if mn in RISH_TAB:
            rd, rs1, sh = split_operands(ops)
            f3, f7 = RISH_TAB[mn]
            shamt = u(parse_imm(sh, sym), 5)
            imm = (u(f7, 7) << 5) | shamt
            return enc_i(OPC_RI, parse_reg(rd), f3, parse_reg(rs1), imm)
        # loads
        if mn in LD_TAB:
            rd, mem = split_operands(ops)
            imm, rs1 = parse_mem_operand(mem, sym)
            return enc_i(OPC_LD, parse_reg(rd), LD_TAB[mn], rs1, imm)
        # stores
        if mn in ST_TAB:
            rs2, mem = split_operands(ops)
            imm, rs1 = parse_mem_operand(mem, sym)
            return enc_s(OPC_ST, ST_TAB[mn], rs1, parse_reg(rs2), imm)
        # branches: label -> PC-relative offset; numeric -> direct offset
        if mn in BR_TAB:
            rs1, rs2, off = split_operands(ops)
            off = off.strip()
            if off in sym:
                offval = sym[off] - addr
            else:
                offval = parse_imm(off, sym)
            return enc_b(OPC_BR, BR_TAB[mn], parse_reg(rs1), parse_reg(rs2), offval)
        # jal
        if mn == "jal":
            rd, off = split_operands(ops)
            if off.strip() in sym:
                offval = sym[off.strip()] - addr
            else:
                offval = parse_imm(off, sym)
            return enc_j(OPC_JAL, parse_reg(rd), offval)
        # jalr  (jalr rd, imm, rs1  or  jalr rd, imm(rs1))
        if mn == "jalr":
            toks = split_operands(ops)
            if len(toks) == 3:
                rd, imm, rs1 = toks
                return enc_i(OPC_JALR, parse_reg(rd), 0, parse_reg(rs1),
                             parse_imm(imm, sym))
            rd, mem = toks
            imm, rs1 = parse_mem_operand(mem, sym)
            return enc_i(OPC_JALR, parse_reg(rd), 0, rs1, imm)
        # lui / auipc
        if mn == "lui":
            rd, imm = split_operands(ops)
            return enc_u(OPC_LUI, parse_reg(rd), parse_imm(imm, sym))
        if mn == "auipc":
            rd, imm = split_operands(ops)
            return enc_u(OPC_AUIPC, parse_reg(rd), parse_imm(imm, sym))
        # csr reads: rdcycle / rdinstret
        if mn in ("rdcycle", "rdinstret"):
            csr = 0xC00 if mn == "rdcycle" else 0xC02
            rd = parse_reg(ops)
            # csrrs rd, csr, x0
            return enc_i(OPC_SYS, rd, 0b010, 0, csr)
        # raw CSR register operations
        if mn in ("csrrs", "csrrw"):
            rd, csr, rs1 = split_operands(ops)
            csrnum = CSR_NAMES.get(csr.strip(), None)
            if csrnum is None:
                csrnum = parse_imm(csr, sym)
            funct3 = 0b010 if mn == "csrrs" else 0b001
            return enc_i(OPC_SYS, parse_reg(rd), funct3, parse_reg(rs1), csrnum)
        # system
        if mn == "ecall":
            return 0x00000073
        if mn == "ebreak":
            return 0x00100073
        if mn == "mret":
            return 0x30200073
        raise AsmError("unknown mnemonic %r" % mn)

    # ---- output formatters ----
    def build(self):
        instrs, word_addrs = self.pass2()
        # merge words + instructions by address
        merged = {}
        for addr, w, cmt in instrs:
            merged[addr] = (w, cmt)
        for addr, (val, lineno) in word_addrs.items():
            merged[addr] = (val, ".word")
        return merged, self.end_addr

    def emit_vh(self, var="instr_mem", base=None, total=None):
        merged, end = self.build()
        if base is None:
            base = self.base
        lines = []
        for addr in sorted(merged):
            idx = (addr - base) // 4
            w, cmt = merged[addr]
            lines.append("        %s[%3d] = 32'h%08X;  // 0x%03X: %s" %
                         (var, idx, w & 0xFFFFFFFF, addr, cmt))
        return "\n".join(lines) + "\n"

    def emit_hex(self):
        merged, end = self.build()
        lines = []
        addr = self.base
        while addr < end:
            w = merged.get(addr, (0x00000013, "nop"))[0]  # fill gaps with NOP
            lines.append("%08x" % (w & 0xFFFFFFFF))
            addr += 4
        return "\n".join(lines) + "\n"


def assemble_file(path, base=0, putc_label="putc"):
    with open(path) as f:
        lines = f.readlines()
    asm = Assembler(base_addr=base, putc_label=putc_label)
    asm.pass1(lines)
    return asm


def main(argv):
    ap = argparse.ArgumentParser(description="RV32I/M+CSR+custom assembler")
    ap.add_argument("source")
    ap.add_argument("--vh", metavar="FILE", help="write a Verilog initial-block fragment")
    ap.add_argument("--hex", metavar="FILE", help="write $readmemh hex (one word/line)")
    ap.add_argument("--var", default="instr_mem", help="Verilog array name (vh)")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0, help="start address")
    ap.add_argument("--putc", default="putc", help="label used by .putc/.puts macros")
    args = ap.parse_args(argv)

    asm = assemble_file(args.source, base=args.base, putc_label=args.putc)
    try:
        vh = asm.emit_vh(var=args.var)
        hx = asm.emit_hex()
    except AsmError as e:
        sys.stderr.write("error: %s\n" % e)
        return 1

    if args.vh:
        with open(args.vh, "w") as f:
            f.write("// generated by scripts/rvasm.py from %s — do not edit\n" % args.source)
            f.write(vh)
        sys.stderr.write("wrote %s\n" % args.vh)
    if args.hex:
        with open(args.hex, "w") as f:
            f.write(hx)
        sys.stderr.write("wrote %s\n" % args.hex)
    if not args.vh and not args.hex:
        sys.stdout.write(vh)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
