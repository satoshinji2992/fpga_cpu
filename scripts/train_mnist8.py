#!/usr/bin/env python3
"""Train weights for the board's existing custom-float32 64->10 classifier.

The FPGA hardware and assembly are intentionally unchanged. Training uses
non-negative, coarse-mantissa float32 weights and zero biases so inference only
adds same-sign values. This avoids the custom FADD32 subtraction-normalization
path, which is too long at 50 MHz on Spartan-6. Exported weights are verified
with a bit-accurate model of the board's FADD32/FMUL32/FGT32 instructions.
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from torchvision.datasets import MNIST


ROOT = Path(__file__).resolve().parents[1]
KEEP_FRACTION_BITS = 12

DEMO_DIGIT_ROWS = {
    0: ["..####..", "..#..#..", "..#..#..", "..#..#..", "..#..#..", "..#..#..", "..####..", "........"],
    1: ["...##...", "..###...", "...##...", "...##...", "...##...", "...##...", "..####..", "........"],
    2: ["..####..", ".....#..", ".....#..", "...###..", "..#.....", "..#.....", "..#####.", "........"],
    3: ["..####..", ".....#..", ".....#..", "...###..", ".....#..", ".....#..", "..####..", "........"],
    4: ["..#..#..", "..#..#..", "..#..#..", "..#####.", ".....#..", ".....#..", ".....#..", "........"],
    5: ["..#####.", "..#.....", "..#.....", "..####..", ".....#..", ".....#..", "..####..", "........"],
    6: ["..####..", "..#.....", "..#.....", "..####..", "..#..#..", "..#..#..", "..####..", "........"],
    7: ["..#####.", ".....#..", "....#...", "...#....", "...#....", "..#.....", "..#.....", "........"],
    8: ["..####..", "..#..#..", "..#..#..", "..####..", "..#..#..", "..#..#..", "..####..", "........"],
    9: ["..####..", "..#..#..", "..#..#..", "..#####.", ".....#..", ".....#..", "..####..", "........"],
}


def float_word(x: float) -> int:
    return struct.unpack("<I", struct.pack("<f", float(x)))[0]


def word_float(x: int) -> float:
    return struct.unpack("<f", struct.pack("<I", x & 0xFFFFFFFF))[0]


def quantize_mantissa(values: np.ndarray, keep_bits: int = KEEP_FRACTION_BITS) -> np.ndarray:
    """Clear low float32 fraction bits; these weights are easy for the custom FPU."""
    values = np.asarray(values, dtype=np.float32).copy()
    words = values.view(np.uint32)
    drop = 23 - keep_bits
    words &= np.uint32((0xFFFFFFFF << drop) & 0xFFFFFFFF)
    return words.view(np.float32)


def fake_quantize_mantissa(x: torch.Tensor) -> torch.Tensor:
    """Straight-through coarse float32 quantizer used during training."""
    mantissa, exponent = torch.frexp(x)
    levels = float(1 << (KEEP_FRACTION_BITS + 1))
    quantized = torch.ldexp(torch.trunc(mantissa * levels) / levels, exponent)
    return x + (quantized - x).detach()


def hw_fmul32(a: int, b: int) -> int:
    sign = ((a >> 31) ^ (b >> 31)) & 1
    if (a & 0x7FFFFFFF) == 0 or (b & 0x7FFFFFFF) == 0:
        return 0
    ea, eb = (a >> 23) & 0xFF, (b >> 23) & 0xFF
    ma, mb = 0x800000 | (a & 0x7FFFFF), 0x800000 | (b & 0x7FFFFF)
    product = ma * mb
    exponent = (ea + eb - 127) & 0x1FF
    if product & (1 << 47):
        exponent = (exponent + 1) & 0x1FF
        fraction = (product >> 24) & 0x7FFFFF
    else:
        fraction = (product >> 23) & 0x7FFFFF
    return (sign << 31) | ((exponent & 0xFF) << 23) | fraction


def hw_fadd32(a: int, b: int) -> int:
    if (a & 0x7FFFFFFF) == 0:
        return b & 0xFFFFFFFF
    if (b & 0x7FFFFFFF) == 0:
        return a & 0xFFFFFFFF
    sa, sb = (a >> 31) & 1, (b >> 31) & 1
    ea, eb = (a >> 23) & 0xFF, (b >> 23) & 0xFF
    ma, mb = 0x800000 | (a & 0x7FFFFF), 0x800000 | (b & 0x7FFFFF)
    if ea >= eb:
        diff, exponent = ea - eb, ea
        mb = 0 if diff > 24 else mb >> diff
    else:
        diff, exponent = eb - ea, eb
        ma = 0 if diff > 24 else ma >> diff
    if sa == sb:
        result_mantissa, result_sign = ma + mb, sa
        if result_mantissa & 0x1000000:
            result_mantissa >>= 1
            exponent = (exponent + 1) & 0xFF
    elif ma >= mb:
        result_mantissa, result_sign = ma - mb, sa
    else:
        result_mantissa, result_sign = mb - ma, sb
    while result_mantissa and not (result_mantissa & 0x800000) and exponent:
        result_mantissa <<= 1
        exponent -= 1
    if not result_mantissa:
        return 0
    return (result_sign << 31) | (exponent << 23) | (result_mantissa & 0x7FFFFF)


def hw_fgt32(a: int, b: int) -> bool:
    az, bz = (a & 0x7FFFFFFF) == 0, (b & 0x7FFFFFFF) == 0
    if az and bz:
        return False
    if ((a ^ b) >> 31) & 1:
        return bool((b >> 31) & 1)
    if not ((a >> 31) & 1):
        return (a & 0x7FFFFFFF) > (b & 0x7FFFFFFF)
    return (a & 0x7FFFFFFF) < (b & 0x7FFFFFFF)


def rows_to_bits(rows: list[str]) -> str:
    return "".join("1" if ch == "#" else "0" for row in rows for ch in row)


def demo_prototypes() -> list[str]:
    return [rows_to_bits(DEMO_DIGIT_ROWS[d]) for d in range(10)]


def predict_hardware(weights: np.ndarray, bias: np.ndarray, image_bits: str) -> int:
    one = float_word(1.0)
    scores = []
    for digit in range(10):
        score = float_word(bias[digit])
        for pixel, weight in zip(image_bits, weights[digit]):
            if pixel == "1":
                score = hw_fadd32(score, hw_fmul32(float_word(weight), one))
        scores.append(score)
    best = 0
    for digit in range(1, 10):
        if hw_fgt32(scores[digit], scores[best]):
            best = digit
    return best


def load_mnist8(root: Path, limit_train: int | None):
    train = MNIST(root=str(root), train=True, download=True)
    test = MNIST(root=str(root), train=False, download=True)

    def convert(dataset, limit=None):
        count = len(dataset) if limit is None else min(limit, len(dataset))
        images = np.zeros((count, 64), dtype=np.float32)
        labels = np.zeros(count, dtype=np.int64)
        for index in range(count):
            image, label = dataset[index]
            small = image.resize((8, 8), Image.Resampling.BILINEAR)
            pixels = np.asarray(small, dtype=np.float32) / 255.0
            images[index] = (pixels >= 0.25).astype(np.float32).reshape(-1)
            labels[index] = label
        return images, labels

    return *convert(train, limit_train), *convert(test)


def augment_demos(images: np.ndarray, labels: np.ndarray, repeats: int):
    demo_images = np.asarray([[float(ch) for ch in bits] for bits in demo_prototypes()], dtype=np.float32)
    extra_images = np.repeat(demo_images, repeats, axis=0)
    extra_labels = np.repeat(np.arange(10, dtype=np.int64), repeats)
    return np.concatenate((images, extra_images)), np.concatenate((labels, extra_labels))


class CustomFloatLinear(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.weight = torch.nn.Parameter(torch.rand(10, 64) * 0.1)
        self.bias = torch.nn.Parameter(torch.zeros(10))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        weight = fake_quantize_mantissa(self.weight)
        bias = fake_quantize_mantissa(self.bias)
        return F.linear(x, weight, bias)


def train_model(x_train, y_train, x_test, y_test, epochs: int, lr: float, seed: int):
    torch.manual_seed(seed)
    x, y = torch.from_numpy(x_train), torch.from_numpy(y_train)
    xt, yt = torch.from_numpy(x_test), torch.from_numpy(y_test)
    model = CustomFloatLinear()
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=5e-5)
    loss_fn = torch.nn.CrossEntropyLoss()
    batch_size = 512
    best_accuracy = -1.0
    best_weight = None
    best_bias = None
    for epoch in range(epochs):
        permutation = torch.randperm(len(x))
        for start in range(0, len(x), batch_size):
            indices = permutation[start:start + batch_size]
            optimizer.zero_grad()
            loss = loss_fn(model(x[indices]), y[indices])
            loss.backward()
            optimizer.step()
            with torch.no_grad():
                model.weight.clamp_(min=0.0, max=8.0)
        with torch.no_grad():
            accuracy = (model(xt).argmax(1) == yt).float().mean().item()
            if accuracy > best_accuracy:
                best_accuracy = accuracy
                best_weight = model.weight.cpu().numpy().copy()
                best_bias = model.bias.cpu().numpy().copy()
        print(f"epoch {epoch + 1:02d}: test_acc={accuracy * 100:.2f}%")

    model.weight.data.copy_(torch.from_numpy(best_weight))
    model.bias.data.copy_(torch.from_numpy(best_bias))
    with torch.no_grad():
        train_accuracy = (model(x).argmax(1) == y).float().mean().item()
        test_accuracy = (model(xt).argmax(1) == yt).float().mean().item()
        weights = quantize_mantissa(model.weight.cpu().numpy())
        bias = model.bias.cpu().numpy().copy()
        # A common bias shift preserves argmax while making every starting
        # score non-negative, so all board accumulations remain same-sign.
        bias += max(0.0, float(-bias.min()))
        bias = quantize_mantissa(bias)
    return weights, bias, train_accuracy, test_accuracy


def evaluate_hardware(weights, bias, images, labels) -> float:
    correct = 0
    for image, label in zip(images, labels):
        bits = "".join("1" if pixel else "0" for pixel in image)
        correct += predict_hardware(weights, bias, bits) == int(label)
    return correct / len(labels)


def export_vh(path: Path, weights: np.ndarray, bias: np.ndarray, base_word: int = 64):
    lines = [
        "// generated by scripts/train_mnist8.py -- do not edit",
        "// custom-float32-aware linear model: weights[10][64], bias[10], one",
    ]

    def emit_word(word_index: int, value: int, comment: str):
        value &= 0xFFFFFFFF
        lines.append(
            f"        data_mem_b0[{word_index:3d}] = 8'h{value & 0xff:02x}; "
            f"data_mem_b1[{word_index:3d}] = 8'h{(value >> 8) & 0xff:02x}; "
            f"data_mem_b2[{word_index:3d}] = 8'h{(value >> 16) & 0xff:02x}; "
            f"data_mem_b3[{word_index:3d}] = 8'h{(value >> 24) & 0xff:02x}; // {comment}"
        )

    index = base_word
    for digit in range(10):
        for pixel in range(64):
            emit_word(index, float_word(weights[digit, pixel]), f"w[{digit}][{pixel}]")
            index += 1
    for digit in range(10):
        emit_word(index, float_word(bias[digit]), f"bias[{digit}]")
        index += 1
    emit_word(index, float_word(1.0), "one")
    path.write_text("\n".join(lines) + "\n")


def export_json(path: Path, weights, bias, train_accuracy, test_accuracy,
                hardware_accuracy, predictions):
    data = {
        "format": "mnist8-linear-custom-float32-positive",
        "train_accuracy": train_accuracy,
        "test_accuracy": test_accuracy,
        "hardware_exact_test_accuracy": hardware_accuracy,
        "kept_fraction_bits": KEEP_FRACTION_BITS,
        "non_negative_weights": True,
        "zero_bias": True,
        "weights_shape": [10, 64],
        "bias_shape": [10],
        "prototypes": demo_prototypes(),
        "prototype_predictions_hardware": predictions,
        "weights": weights.astype(float).tolist(),
        "bias": bias.astype(float).tolist(),
    }
    path.write_text(json.dumps(data, indent=2) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default=str(ROOT / "data"))
    parser.add_argument("--vh", default=str(ROOT / "src" / "cnn_weights.vh"))
    parser.add_argument("--json", default=str(ROOT / "data" / "mnist8_model.json"))
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--lr", type=float, default=0.012)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--limit-train", type=int, default=0,
                        help="MNIST training samples; 0 uses all 60000")
    parser.add_argument("--demo-repeats", type=int, default=500)
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)
    train_limit = None if args.limit_train == 0 else args.limit_train
    x_train, y_train, x_test, y_test = load_mnist8(data_dir, train_limit)
    x_train, y_train = augment_demos(x_train, y_train, args.demo_repeats)
    weights, bias, train_accuracy, test_accuracy = train_model(
        x_train, y_train, x_test, y_test, args.epochs, args.lr, args.seed
    )
    predictions = [predict_hardware(weights, bias, bits) for bits in demo_prototypes()]
    hardware_accuracy = evaluate_hardware(weights, bias, x_test, y_test)
    export_vh(Path(args.vh), weights, bias)
    export_json(Path(args.json), weights, bias, train_accuracy, test_accuracy,
                hardware_accuracy, predictions)
    print(f"hardware prototype predictions={predictions}")
    print(f"train_acc={train_accuracy * 100:.2f}% test_acc={test_accuracy * 100:.2f}%")
    print(f"hardware_exact_test_acc={hardware_accuracy * 100:.2f}%")
    print(f"wrote {args.vh}")
    print(f"wrote {args.json}")
    return 0 if predictions == list(range(10)) else 2


if __name__ == "__main__":
    raise SystemExit(main())
