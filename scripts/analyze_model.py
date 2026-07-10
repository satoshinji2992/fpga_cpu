
#!/usr/bin/env python3
import numpy as np
import json
from pathlib import Path

def load_model(json_path):
    with open(json_path) as f:
        data = json.load(f)
    return data

def analyze_model(data):
    print("=" * 80)
    print("Model Analysis")
    print("=" * 80)
    print(f"Train Accuracy: {data['train_accuracy'] * 100:.2f}%")
    print(f"Test Accuracy: {data['test_accuracy'] * 100:.2f}%")
    print()
    
    weights = np.array(data['weights'])  # shape (10, 64)
    bias = np.array(data['bias'])  # shape (10,)
    
    print("=" * 80)
    print("Weight Statistics")
    print("=" * 80)
    print(f"Weights shape: {weights.shape}")
    print(f"Bias shape: {bias.shape}")
    print(f"Min weight: {weights.min():.4f}, Max weight: {weights.max():.4f}")
    print(f"Mean weight: {weights.mean():.4f}, Std weight: {weights.std():.4f}")
    print()
    
    print("=" * 80)
    print("Per-class weight statistics")
    print("=" * 80)
    for i in range(10):
        print(f"Class {i}:")
        print(f"  Mean: {weights[i].mean():.4f}, Std: {weights[i].std():.4f}")
        print(f"  Min: {weights[i].min():.4f}, Max: {weights[i].max():.4f}")
        print(f"  L2 norm: {np.linalg.norm(weights[i]):.4f}")
    print()
    
    print("=" * 80)
    print("Bias values")
    print("=" * 80)
    for i in range(10):
        print(f"Class {i}: {bias[i]:.4f}")
    print()
    
    print("=" * 80)
    print("Summary")
    print("=" * 80)
    print("Current model uses a linear classifier with float32 weights.")
    print()
    
    print("Suggestions for improvement:")
    print("1. Try different binarization threshold (current: 0.25)")
    print("2. Experiment with different training epochs (current: 12)")
    print("3. Try different learning rate (current: 0.5)")
    print("4. Add L2 regularization (current: weight_decay=1e-4)")
    print("5. Try different optimizers (current: SGD with momentum=0.9)")
    print("6. Data augmentation: even for 8x8 images, small shifts/rotations can help")
    print("7. Try batch normalization if extending to deeper models")
    print("8. Consider using fixed-point quantization for better FPGA performance")
    print()
    
    return weights, bias

if __name__ == "__main__":
    data = load_model(Path(__file__).parent.parent / "data" / "mnist8_model.json")
    analyze_model(data)
