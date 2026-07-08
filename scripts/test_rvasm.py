#!/usr/bin/env python3
"""
Unit tests for scripts/rvasm.py.

Authoritative ground truth = the hand-assembled machine code of top.v's demo
program, which already PASSES on the board and in tb_all_features. If the
assembler reproduces those exact 32-bit words, the enc_i/enc_r/enc_s/enc_b
encoders + custom-0/CSR dispatch are correct. The remaining vectors cover the
table-driven funct fields (shifts, M-ext, U/J-type), computed systematically
from the bit layout.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from rvasm import Assembler

PASS = 0
FAIL = 0

def asm_one(text, base=0):
    a = Assembler(base_addr=base)
    a.pass1([text + "\n"])
    merged, _ = a.build()
    return list(merged.values())[0][0]

def check(name, got, want):
    global PASS, FAIL
    if (got & 0xFFFFFFFF) == (want & 0xFFFFFFFF):
        PASS += 1
    else:
        FAIL += 1
        print("FAIL %-26s got 0x%08X  want 0x%08X" % (name, got & 0xFFFFFFFF, want & 0xFFFFFFFF))

# ===================== ground truth from top.v (board-proven) =====================
check("addi x1,x0,7",    asm_one("addi x1, x0, 7"),    0x00700093)
check("addi x2,x0,6",    asm_one("addi x2, x0, 6"),    0x00600113)
check("mul  x3,x1,x2",   asm_one("mul x3, x1, x2"),    0x022081B3)
check("sw   x3,0(x0)",   asm_one("sw x3, 0(x0)"),      0x00302023)
check("add  x4,x4,x5",   asm_one("add x4, x4, x5"),    0x00520233)
check("addi x5,x5,1",    asm_one("addi x5, x5, 1"),    0x00128293)
check("blt  x5,x6,-8",   asm_one("blt x5, x6, -8"),    0xFE62CCE3)
check("sw   x4,4(x0)",   asm_one("sw x4, 4(x0)"),      0x00402223)
check("addi x7,x0,0xFF", asm_one("addi x7, x0, 0xFF"), 0x0FF00393)
check("popcount x8,x7",  asm_one("popcount x8, x7"),   0x0003940B)
check("rdcycle x9",      asm_one("rdcycle x9"),        0xC00024F3)
check("sw   x9,12(x0)",  asm_one("sw x9, 12(x0)"),     0x00902623)
check("ecall",           asm_one("ecall"),             0x00000073)

# ===================== table-driven coverage (systematic) =====================
# R-type RV32I: base = (rs2<<20)|(rs1<<15)|(rd<<7)|0x33 ; + funct3<<12 ; + funct7<<25
check("sub x1,x2,x3",    asm_one("sub x1, x2, x3"),    0x403100B3)  # funct7=0x20
check("and x1,x2,x3",    asm_one("and x1, x2, x3"),    0x003170B3)  # funct3=7
# I-type shifts: imm[11:5]=funct7, imm[4:0]=shamt
check("slli x5,x6,3",    asm_one("slli x5, x6, 3"),    0x00331293)  # f3=1
check("srli x5,x6,3",    asm_one("srli x5, x6, 3"),    0x00335293)  # f3=5
check("srai x5,x6,3",    asm_one("srai x5, x6, 3"),    0x40335293)  # f3=5, f7=0x20
# M-ext: funct7=0000001, opcode 0x33. base=0x022082B3 for (rs1=1,rs2=2,rd=5); +f3<<12
check("mulhu x5,x1,x2",  asm_one("mulhu x5, x1, x2"),  0x0220B2B3)  # f3=3
check("div x5,x1,x2",    asm_one("div x5, x1, x2"),    0x0220C2B3)  # f3=4
check("divu x5,x1,x2",   asm_one("divu x5, x1, x2"),   0x0220D2B3)  # f3=5
check("rem x5,x1,x2",    asm_one("rem x5, x1, x2"),    0x0220E2B3)  # f3=6
check("remu x5,x1,x2",   asm_one("remu x5, x1, x2"),   0x0220F2B3)  # f3=7
# Loads/stores
check("lw x1, 8(x2)",    asm_one("lw x1, 8(x2)"),      0x00812083)
check("lbu x1, 1(x0)",   asm_one("lbu x1, 1(x0)"),     0x00104083)
check("sb x5, 2(x0)",    asm_one("sb x5, 2(x0)"),      0x00500123)
check("sh x10, 4(x0)",   asm_one("sh x10, 4(x0)"),     0x00A01223)
# Branches
check("beq x13,x14,8",   asm_one("beq x13, x14, 8"),   0x00E68463)
check("bne x1,x2,-4",    asm_one("bne x1, x2, -4"),    0xFE209EE3)
# U-type / J-type
check("lui x1, 0x12345", asm_one("lui x1, 0x12345"),   0x123450B7)
check("auipc x1, 0x10",  asm_one("auipc x1, 0x10"),    0x00010097)
check("jalr x1, 0(x2)",  asm_one("jalr x1, 0(x2)"),    0x000100E7)
# CSR / system / custom
check("csrrs x1,cycle,x0", asm_one("csrrs x1, cycle, x0"), 0xC00020F3)
check("ebreak",          asm_one("ebreak"),            0x00100073)
check("bitrev x1, x2",   asm_one("bitrev x1, x2"),     0x0001208B)  # custom0 f3=2
check("popcount x1, x2", asm_one("popcount x1, x2"),   0x0001108B)  # custom0 f3=1
check("fadd32 x4,x1,x2", asm_one("fadd32 x4, x1, x2"), 0x0020B20B)  # custom0 f3=3
check("fmul32 x5,x1,x3", asm_one("fmul32 x5, x1, x3"), 0x0030C28B)  # custom0 f3=4
check("fgt32 x6,x1,x2",  asm_one("fgt32 x6, x1, x2"),  0x0020D30B)  # custom0 f3=5

# ===================== pseudo / macros =====================
check("nop",             asm_one("nop"),               0x00000013)
check("mv x1,x2",        asm_one("mv x1, x2"),         0x00010093)
check("li x1,5",         asm_one("li x1, 5"),          0x00500093)
check("li x1,-1",        asm_one("li x1, -1"),         0xFFF00093)
check("ret",             asm_one("ret"),               0x00008067)
check("not x1,x2",       asm_one("not x1, x2"),        0xFFF14093)
check("j label (offset 0 handled as jal x0)", asm_one("j 0"), 0x0000006F)

# li with big immediate -> lui + addi (2 instructions, 8 bytes)
a_li = Assembler(); a_li.pass1(["li a0, 0x12345678\n"])
m_li, _ = a_li.build()
check("li a0,0x12345678 @0 (lui)", m_li[0][0], 0x12345537)  # lui a0,0x12345
check("li a0,0x12345678 @4 (addi)",m_li[4][0], 0x67850513)  # addi a0,a0,0x678

# ===================== program: labels + backward branch =====================
prog = """
start:
    addi x1, x0, 0
loop:
    addi x1, x1, 1
    addi x2, x0, 3
    blt x1, x2, loop
    sw  x1, 0(x0)
"""
a = Assembler(base_addr=0)
a.pass1(prog.splitlines())
merged, end = a.build()
check("prog start addr", a.symbols["start"], 0)
check("prog loop addr",  a.symbols["loop"], 4)
check("prog blt@12 word", merged[12][0], 0xFE20CCE3)  # blt x1,x2,-8
check("prog sw@16 word",  merged[16][0], 0x00102023)  # sw x1,0(x0)
check("prog end addr",    end, 20)

# ===================== .puts macro expansion =====================
# .puts "AB" fully expands to: li a0,'A'; call putc; li a0,'B'; call putc
# i.e. addi, jal, addi, jal (li/call are themselves pseudos)
a2 = Assembler(putc_label="putc")
a2.pass1(['.puts "AB"\n'])
if len(a2.items) == 4 and a2.items[0][1] == "addi" and a2.items[1][1] == "jal":
    PASS += 1
else:
    FAIL += 1
    print("FAIL .puts expansion -> %r" % [(m, o) for _, m, o, _ in a2.items])

print("RVASM %s (%d ok, %d fail)" % ("PASS" if FAIL == 0 else "FAIL", PASS, FAIL))
sys.exit(1 if FAIL else 0)
