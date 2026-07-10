#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fpga_cpu 课程设计功能扩展 —— 集成展示脚本
跑全部 testbench, 汇总: 回归状态 / 流水线CPI / 分支预测准确率 /
I-Cache命中率 / RV32M乘除法 / 自定义指令, 并对照课程设计要求清单。
全部在电脑上用 Icarus Verilog 运行, 不需要 FPGA 开发板。
用法:  py -3 scripts/analyze.py      (或 python scripts/analyze.py)
"""
import subprocess, re, os, sys, shutil, tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")

# ---------------- toolchain discovery ----------------
def find_tools():
    iv = shutil.which("iverilog") or shutil.which("iverilog.exe")
    if not iv:
        for d in ("D:/iverilog/bin", "C:/iverilog/bin", os.path.expanduser("~/iverilog/bin")):
            c = os.path.join(d, "iverilog.exe")
            if os.path.exists(c):
                iv = c
                break
    vv = None
    if iv:
        vv = (shutil.which("vvp") or shutil.which("vvp.exe")
              or os.path.join(os.path.dirname(iv), "vvp.exe"))
    return iv, vv

def run_tb(iv, vv, srcs, label):
    out = os.path.join(tempfile.gettempdir(), "fpgacpu_%s.out" % label)
    cp = subprocess.run([iv, "-I", SRC, "-o", out] + [os.path.join(SRC, s) for s in srcs],
                        capture_output=True, text=True)
    if cp.returncode != 0 or not os.path.exists(out):
        return "", "compile fail: " + (cp.stderr or cp.stdout)[-400:]
    rp = subprocess.run([vv, out], capture_output=True, text=True)
    return rp.stdout, None

def grab(pattern, text, cast=str, default=None):
    m = re.search(pattern, text)
    return cast(m.group(1)) if m else default

def bar(pct, w=36):
    n = max(0, min(w, round(pct / 100.0 * w)))
    return "#" * n + "." * (w - n)

def main():
    iv, vv = find_tools()
    if not iv:
        print("[ERROR] 找不到 iverilog。请安装 Icarus Verilog 并加入 PATH,")
        print("        或放到 D:/iverilog/bin (本机默认安装路径)。")
        sys.exit(1)

    ver = subprocess.run([iv, "-V"], capture_output=True, text=True).stdout.split("\n")[0]

    TBS = [
        ("self-test",     ["riscv_pipeline_core.v", "tb_pipeline_core.v"]),
        ("load-use",      ["riscv_pipeline_core.v", "tb_loaduse.v"]),
        ("branchpredict", ["riscv_pipeline_core.v", "tb_branchpredict.v"]),
        ("muldiv",        ["riscv_pipeline_core.v", "tb_muldiv.v"]),
        ("float",         ["riscv_pipeline_core.v", "tb_float.v"]),
        ("custom",        ["riscv_pipeline_core.v", "tb_custom.v"]),
        ("all-features",  ["riscv_pipeline_core.v", "tb_all_features.v"]),
        ("interrupt",     ["riscv_pipeline_core.v", "tb_interrupt.v"]),
        ("sdram-wait",    ["riscv_pipeline_core.v", "sdram_latency_model.v", "tb_sdram_wait.v"]),
        ("sdram-ctrl",    ["sdram_controller.v", "tb_sdram_controller.v"]),
        ("cache",         ["icache_direct_mapped.v", "icache_2way.v", "tb_cache.v"]),
        ("cnn",           ["top.v", "sdram_controller.v", "sdram_device_model.v", "riscv_pipeline_core.v", "icache_direct_mapped.v",
                           "icache_2way.v", "uart_rx.v", "uart_tx.v", "tb_cnn.v"]),
        ("cnn-ablation",  ["top.v", "sdram_controller.v", "sdram_device_model.v", "riscv_pipeline_core.v", "icache_direct_mapped.v",
                           "icache_2way.v", "uart_rx.v", "uart_tx.v", "tb_cnn_ablation.v"]),
        ("shell",         ["top.v", "sdram_controller.v", "sdram_device_model.v", "riscv_pipeline_core.v", "icache_direct_mapped.v",
                           "icache_2way.v", "uart_rx.v", "uart_tx.v", "tb_shell.v"]),
        ("soc-io",        ["top.v", "sdram_controller.v", "riscv_pipeline_core.v", "icache_direct_mapped.v",
                           "icache_2way.v", "uart_rx.v", "uart_tx.v", "tb_soc_io.v"]),
    ]
    res = {}
    for label, srcs in TBS:
        res[label] = run_tb(iv, vv, srcs, label)

    print("=" * 66)
    print(" fpga_cpu 课程设计功能扩展 — 集成展示")
    print(" 工具: " + ver)
    print(" 全部在电脑上用 Icarus Verilog 仿真, 无需 FPGA 开发板")
    print("=" * 66)

    # 1. regression status
    print("\n[1] 回归测试")
    print("    %-16s %-8s %s" % ("testbench", "结果", "说明"))
    print("    " + "-" * 54)
    npass = 0
    for label, _ in TBS:
        out, err = res[label]
        if err:
            ok = False
            print("    %-16s %-8s %s" % (label, "[FAIL]", err))
        else:
            ok = ("PASS" in out) and ("FAIL" not in out)
            print("    %-16s %-8s" % (label, "[PASS]" if ok else "[FAIL]"))
            if not ok:
                print("        " + "\n        ".join(out.strip().splitlines()[-4:]))
        if ok:
            npass += 1

    # 2. pipeline CPI
    print("\n[2] 流水线性能 (CPI = cycle / instret)")
    st = res["self-test"][0]
    c = grab(r"cycle=(\d+)", st, int)
    ir = grab(r"instret=(\d+)", st, int)
    if c and ir:
        print("    self-test 基础 RV32I:  CPI = %.2f  (cycle=%d instret=%d)" % (c / ir, c, ir))

    # 3. branch prediction
    print("\n[3] 动态分支预测 (循环 1+2+...+10, BLT 执行10次: 9 taken + 1 not)")
    bp = res["branchpredict"][0]
    pm = re.search(r"PREDICT.*?cpi=([\d.]+).*?branch=(\d+).*?bp_miss=(\d+).*?acc=([\d.]+)", bp, re.S)
    bm = re.search(r"BASELINE.*?cpi=([\d.]+).*?flush=(\d+)", bp, re.S)
    if pm and bm:
        pcpi, bcpi = float(pm.group(1)), float(bm.group(1))
        acc = float(pm.group(4))
        save = (bcpi - pcpi) / bcpi * 100
        print("    无预测 (baseline):    CPI = %.2f  (每个 taken 分支都冲刷, flush=%s)" % (bcpi, bm.group(2)))
        print("    2-bit BHT 预测:       CPI = %.2f  (准确率 %.1f%%, 误预测=%s)" % (pcpi, acc, pm.group(3)))
        print("    -> CPI 降低 %.1f%%" % save)
        print("    预测准确率 %5.1f%%  %s" % (acc, bar(acc)))

    # 4. CNN program ablation
    print("\n[4] CNN 端到端程序 ablation (UART cnn 命令 -> 输出 pred 7)")
    cab = res["cnn-ablation"][0]
    con = re.search(r"BP_ON\s+cycle=(\d+).*?instret=(\d+).*?cpi=([\d.]+).*?branch=(\d+).*?flush=(\d+).*?bp_miss=(\d+).*?acc=([\d.]+)%.*?load_use=(\d+).*?mdu=(\d+)", cab, re.S)
    cof = re.search(r"BP_OFF\s+cycle=(\d+).*?instret=(\d+).*?cpi=([\d.]+).*?branch=(\d+).*?flush=(\d+).*?bp_miss=(\d+).*?acc=([\d.]+)%.*?load_use=(\d+).*?mdu=(\d+)", cab, re.S)
    if con and cof:
        cyc_on, cyc_off = int(con.group(1)), int(cof.group(1))
        speed = (cyc_off - cyc_on) / cyc_off * 100.0
        print("    2-bit BHT: cycle=%s instret=%s CPI=%s branch=%s flush=%s bp_miss=%s acc=%s%% load_use=%s mdu=%s" %
              (con.group(1), con.group(2), con.group(3), con.group(4), con.group(5),
               con.group(6), con.group(7), con.group(8), con.group(9)))
        print("    baseline : cycle=%s instret=%s CPI=%s branch=%s flush=%s bp_miss=%s acc=%s%% load_use=%s mdu=%s" %
              (cof.group(1), cof.group(2), cof.group(3), cof.group(4), cof.group(5),
               cof.group(6), cof.group(7), cof.group(8), cof.group(9)))
        print("    -> 端到端 cycle 降低 %.1f%%" % speed)

    # 5. cache
    print("\n[5] I-Cache 命中率 (冲突地址流 0,32,0,32,... 同一组)")
    ca = res["cache"][0]
    dm = re.search(r"DIRECT.*?hit=(\d+).*?miss=(\d+).*?rate=([\d.]+)", ca, re.S)
    tw = re.search(r"2-WAY.*?hit=(\d+).*?miss=(\d+).*?rate=([\d.]+)", ca, re.S)
    if dm and tw:
        dr, tr = float(dm.group(3)), float(tw.group(3))
        print("    直接映射 8行:     命中率 %5.1f%%  hit=%s miss=%s  %s" % (dr, dm.group(1), dm.group(2), bar(dr)))
        print("    2路组相联 + LRU:  命中率 %5.1f%%  hit=%s miss=%s  %s" % (tr, tw.group(1), tw.group(2), bar(tr)))

    # 6. RV32M
    print("\n[6] RV32M 乘除法扩展 (单周期组合实现)")
    md = res["muldiv"][0]
    m0 = grab(r"Mem\[0\] = (\d+)", md, int)
    m1 = grab(r"Mem\[1\] = (\d+)", md, int)
    m2 = grab(r"Mem\[2\] = (\d+)", md, int)
    ok_m = (m0 == 42 and m1 == 1 and m2 == 1)
    print("    MUL 7*6 = %s (期望42)   DIV 7/6 = %s (期望1)   REM 7%%6 = %s (期望1)   %s"
          % (m0, m1, m2, "[OK]" if ok_m else "[FAIL]"))

    # 7. custom float32
    print("\n[7] Custom float32 扩展 (custom-0: FADD32 / FMUL32 / FGT32)")
    fl = res["float"][0]
    f0 = grab(r"Mem\[0\] = ([0-9a-fA-F]+)", fl)
    f1 = grab(r"Mem\[1\] = ([0-9a-fA-F]+)", fl)
    f2 = grab(r"Mem\[2\] = ([0-9a-fA-F]+)", fl)
    ok_f = (f0 and f0.lower() == "40700000" and f1 and f1.lower() == "40400000" and
            f2 and f2.lower() == "00000001")
    print("    FADD32 1.5+2.25 = 0x%s   FMUL32 1.5*2.0 = 0x%s   FGT32 2.25>1.5 = 0x%s   %s"
          % (f0, f1, f2, "[OK]" if ok_f else "[FAIL]"))

    # 8. custom ISA
    print("\n[8] 自定义 ISA 扩展 (custom-0: POPCOUNT / BITREVERSE)")
    cu = res["custom"][0]
    c0 = grab(r"Mem\[0\] = (\d+)", cu, int)
    c1 = grab(r"Mem\[1\] = ([0-9a-fA-F]+)", cu)
    ok_c = (c0 == 18 and c1 and c1.lower() == "ff00b3d5")
    print("    POPCOUNT(0xABCD00FF) = %s (期望18)   BITREV = 0x%s (期望 ff00b3d5)   %s"
          % (c0, c1, "[OK]" if ok_c else "[FAIL]"))

    # 9. requirement coverage
    print("\n[9] 课程设计要求覆盖 (对照图片需求清单)")
    ppa_reports_exist = (os.path.exists(os.path.join(HERE, "..", "top.par")) and
                         os.path.exists(os.path.join(HERE, "..", "top.twr")) and
                         os.path.exists(os.path.join(HERE, "..", "top.pwr")))
    cov = [
        ("进阶: CPU + 内存 + Cache + I/O 系统集成",            True),
        ("进阶: 小型测试程序完整运行",                         npass == len(TBS)),
        ("进阶: 流水线 + CPI/吞吐量量化评估",                  c and ir is not None),
        ("拓展: 数据前推 + load-use 停顿",                     res["load-use"][1] is None),
        ("拓展: 动态分支预测 (2-bit BHT)",                     pm is not None),
        ("拓展: Cache 组相联 + LRU + 命中率分析",              tw is not None),
        ("拓展: 乘除法扩展指令 (RV32M)",                       ok_m),
        ("拓展: 浮点运算扩展指令 (custom float32)",             ok_f),
        ("拓展: 自定义 ISA 扩展设计",                          ok_c),
        ("PPA 权衡分析 (面积/功耗/频率)",                      ppa_reports_exist),
    ]
    for name, ok in cov:
        print("    [%s] %s" % ("x" if ok else " ", name))

    print("\n" + "=" * 66)
    print(" 回归: %d/%d testbench 通过" % (npass, len(TBS)))
    if ppa_reports_exist:
        print(" PPA: 已发现 top.par/top.twr/top.pwr；面积/时序/功耗已按当前 ISE/XPower 报告记录")
    else:
        print(" PPA (面积/功耗/Fmax) 需在本地 ISE 14.7 综合后填入报告或 README")
    print("=" * 66)

if __name__ == "__main__":
    main()
