#!/usr/bin/env python3
"""Replace stale R13 figures in the course report with R16 diagrams."""

from pathlib import Path
from tempfile import NamedTemporaryFile
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
REPORT = next(ROOT.glob("*.docx"))
OUT = ROOT / "artifacts" / "report_figures_r16"
OUT.mkdir(parents=True, exist_ok=True)
FONT = Path(r"C:\Windows\Fonts\msyh.ttc")
FONT_BOLD = Path(r"C:\Windows\Fonts\msyhbd.ttc")


def font(size, bold=False):
    return ImageFont.truetype(str(FONT_BOLD if bold else FONT), size)


def canvas(title, subtitle=""):
    im = Image.new("RGB", (1600, 900), "white")
    d = ImageDraw.Draw(im)
    d.text((80, 55), title, fill="#1f2937", font=font(38, True))
    if subtitle:
        d.text((82, 112), subtitle, fill="#64748b", font=font(22))
    return im, d


def box(d, xy, title, lines, fill, outline="#cbd5e1"):
    d.rounded_rectangle(xy, 14, fill=fill, outline=outline, width=3)
    x1, y1, x2, _ = xy
    d.text(((x1+x2)//2, y1+24), title, anchor="ma", fill="#111827", font=font(26, True))
    y = y1 + 78
    for line in lines:
        d.text(((x1+x2)//2, y), line, anchor="ma", fill="#334155", font=font(20))
        y += 34


def architecture():
    im, d = canvas("图3-1  R16 SoC总体架构（50 MHz单时钟域）",
                   "TEC-PLUS / Spartan-6 XC6SLX9-2FTG256 · 发布版本2.0.0")
    box(d, (570, 220, 1030, 640), "RV32五级流水CPU",
        ["IF · ID · EX · MEM · WB", "前递 + load-use停顿", "16-entry 2-bit BHT",
         "RV32M / Custom Float32", "CSR / 中断 / 性能计数器"], "#dbeafe")
    box(d, (90, 250, 420, 410), "50 MHz输入", ["BUFG直接驱动", "单一sys_clk"], "#fef3c7")
    box(d, (90, 505, 420, 670), "PC端", ["UART 115200 8N1", "仅负责输入与显示"], "#f8fafc")
    box(d, (1160, 170, 1510, 330), "指令侧", ["16 KiB同步ROM", "2-way I-Cache + LRU"], "#dcfce7")
    box(d, (1160, 370, 1510, 530), "数据与MMIO", ["4 KiB片内RAM", "UART / LED / KEY / IRQ"], "#f8fafc")
    box(d, (1160, 570, 1510, 735), "外部存储", ["双HY57V2562", "64 MiB · 32-bit SDRAM"], "#f3e8ff")
    box(d, (480, 710, 1120, 835), "R16板端固件", ["SELFTEST · shell · MLP · calc · Pong · Paint"], "#fee2e2")
    for a, b in [((420,330),(570,330)),((420,585),(570,585)),((1030,270),(1160,250)),
                 ((1030,430),(1160,450)),((1030,590),(1160,650)),((800,640),(800,710))]:
        d.line((a,b), fill="#3b82f6", width=5)
        x,y=b; d.polygon([(x,y),(x-16,y-9),(x-16,y+9)], fill="#3b82f6")
    return im


def cache():
    im, d = canvas("图4-2  I-Cache结构与R16冲突地址流消融",
                   "相同接口、相同12次访问：0, 32, 0, 32, …")
    box(d, (110, 210, 700, 470), "直接映射 · 8行",
        ["index直接选择唯一cache line", "冲突地址反复替换", "hit=0 · miss=12"], "#fee2e2")
    box(d, (900, 210, 1490, 470), "2-way组相联 · LRU",
        ["每组2个way并行比较tag", "LRU选择替换way", "hit=10 · miss=2"], "#dcfce7")
    d.text((110, 550), "命中率", fill="#334155", font=font(26, True))
    for y, label, pct, color in [(630,"直接映射",0,"#ef4444"),(735,"2-way + LRU",83.3,"#10b981")]:
        d.text((110,y),label,fill="#334155",font=font(24))
        d.rounded_rectangle((350,y,1390,y+42),18,fill="#e5e7eb")
        if pct: d.rounded_rectangle((350,y,350+int(1040*pct/100),y+42),18,fill=color)
        d.text((1420,y+21),f"{pct:.1f}%",anchor="lm",fill=color,font=font(24,True))
    return im


def resources():
    im, d = canvas("图6-1  FPGA资源利用率（R16 · ISE 14.7实测）",
                   "XC6SLX9-2FTG256 · 50 MHz · 2.0.0")
    values=[("Occupied Slices",95,"1371 / 1430","#ef4444"),("Slice LUTs",77,"4455 / 5720","#f59e0b"),
            ("Slice Registers",22,"2584 / 11440","#3b82f6"),("RAMB16BWER",25,"8 / 32","#8b5cf6"),
            ("RAMB8BWER",6,"4 / 64","#06b6d4"),("DSP48A1",0,"0 / 16","#10b981")]
    for i,(name,pct,used,color) in enumerate(values):
        y=205+i*100; d.text((100,y),name,fill="#334155",font=font(24,True))
        d.rounded_rectangle((470,y,1320,y+40),16,fill="#e5e7eb")
        if pct: d.rounded_rectangle((470,y,470+int(850*pct/100),y+40),16,fill=color)
        d.text((1360,y+20),f"{pct}%",anchor="lm",fill=color,font=font(26,True))
        d.text((100,y+42),used,fill="#64748b",font=font(18))
    d.text((100,825),"结论：ROM扩容增加4个RAMB16；LUT保持77%，DSP降为0。",fill="#475569",font=font(22))
    return im


def timing():
    im, d = canvas("图6-2  R16静态时序分析：50 MHz约束通过",
                   "top.twr · Timing errors=0 · Score=0")
    box(d,(260,235,1340,390),"系统时钟约束",["20.000 ns  ·  50.000 MHz"],"#dbeafe","#60a5fa")
    box(d,(260,470,1340,655),"布局布线后最坏结果",
        ["Best achievable period = 19.349 ns", "Fmax = 51.682 MHz  ·  setup slack = +0.651 ns"],
        "#dcfce7","#34d399")
    d.line((260,760,1340,760),fill="#94a3b8",width=4)
    for x,label in [(260,"0"),(800,"10 ns"),(1340,"20 ns")]:
        d.line((x,750,x,772),fill="#64748b",width=3); d.text((x,790),label,anchor="ma",fill="#64748b",font=font(18))
    return im


def power():
    im, d = canvas("图6-3  R16功耗估计（XPower Analyzer）",
                   "Total 91.30 mW · Confidence Medium · vector-less")
    center=(560,500); outer=245; inner=135
    dynamic=76.19/91.30*360
    d.pieslice((center[0]-outer,center[1]-outer,center[0]+outer,center[1]+outer),-90,-90+dynamic,fill="#3b82f6")
    d.pieslice((center[0]-outer,center[1]-outer,center[0]+outer,center[1]+outer),-90+dynamic,270,fill="#9ca3af")
    d.ellipse((center[0]-inner,center[1]-inner,center[0]+inner,center[1]+inner),fill="white")
    d.text(center,"91.30 mW\n总功耗",anchor="mm",align="center",fill="#111827",font=font(30,True))
    box(d,(960,285,1450,440),"动态功耗",["76.19 mW  ·  83.4%"],"#dbeafe","#60a5fa")
    box(d,(960,515,1450,670),"静态功耗",["15.11 mW  ·  16.6%"],"#f3f4f6","#9ca3af")
    d.text((230,820),"相对R15总功耗增加0.74 mW（约0.82%）；无VCD/SAIF，仅用于PPA比较。",fill="#64748b",font=font(21))
    return im


figures={"image2.png":architecture(),"image4.png":cache(),"image6.png":resources(),
         "image7.png":timing(),"image8.png":power()}
for name, im in figures.items():
    im.save(OUT/name)

with NamedTemporaryFile(delete=False, suffix=".docx", dir=ROOT) as tmp_file:
    tmp_path=Path(tmp_file.name)
with ZipFile(REPORT,"r") as src, ZipFile(tmp_path,"w",ZIP_DEFLATED) as dst:
    for item in src.infolist():
        replacement=figures.get(Path(item.filename).name) if item.filename.startswith("word/media/") else None
        if replacement is not None:
            payload=(OUT/Path(item.filename).name).read_bytes()
        else:
            payload=src.read(item.filename)
        dst.writestr(item,payload)
tmp_path.replace(REPORT)
print(REPORT)
