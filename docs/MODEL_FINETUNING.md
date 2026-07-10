
# 模型微调建议

## 当前模型情况
- 模型类型：线性分类器（单层全连接）
- 输入：8x8 二值化图像（64维特征）
- 输出：10个类别的分数
- 当前训练准确率：81.69%
- 当前测试准确率：82.45%

## 参数微调方案

### 1. 学习率调整
**当前值：0.5**

建议尝试以下学习率：
```bash
# 保守方案
python scripts/train_mnist8.py --lr 0.1 --epochs 20

# 激进方案
python scripts/train_mnist8.py --lr 0.8 --epochs 10

# 自适应调整（需要修改代码）
# 可以在 train_mnist8.py 中添加学习率调度
```

### 2. 训练轮数调整
**当前值：12**

建议尝试：
```bash
# 更多轮数（可能过拟合，配合正则化）
python scripts/train_mnist8.py --epochs 30 --lr 0.2

# 更少轮数（快速收敛）
python scripts/train_mnist8.py --epochs 8 --lr 0.8
```

### 3. 二值化阈值调整
**当前值：0.25**

修改 train_mnist8.py 第45行：
```python
# 更严格的阈值
x[i] = (arr >= 0.3).astype(np.float32).reshape(-1)

# 更宽松的阈值
x[i] = (arr >= 0.2).astype(np.float32).reshape(-1)

# 自适应阈值（如使用Otsu方法）
```

### 4. 正则化调整
**当前值：weight_decay=1e-4**

修改 train_mnist8.py 第62行：
```python
# 更强的正则化
opt = torch.optim.SGD(model.parameters(), lr=lr, momentum=0.9, weight_decay=5e-4)

# 更弱的正则化
opt = torch.optim.SGD(model.parameters(), lr=lr, momentum=0.9, weight_decay=0)
```

### 5. 数据预处理改进
当前只做了简单的双线性插值缩放和二值化，可以尝试：

1. **直方图均衡化**：增强对比度
2. **降噪**：使用高斯滤波去除噪声
3. **数据增强**：对于 8x8 图像，可以：
   - 小范围平移（±1像素）
   - 轻微旋转（±5度）
   - 增加少量椒盐噪声

### 6. 优化器改进
当前使用 SGD+momentum，可以尝试：

1. **Adam**：自适应学习率
2. **RMSprop**：适合小批量
3. **AdamW**：带权重衰减的Adam

### 7. 模型架构改进（推荐）
当前是简单的线性模型，可以考虑：

1. **增加隐藏层**：例如 64 → 32 → 10
2. **添加激活函数**：ReLU, Sigmoid, Tanh
3. **添加批量归一化**：提高训练稳定性
4. **Dropout**：防止过拟合

### 8. 实验网格搜索建议
创建一个脚本执行以下参数组合：

| 学习率 | epochs | weight_decay | 预期效果 |
|--------|--------|--------------|----------|
| 0.1    | 20     | 1e-4         | 保守训练 |
| 0.3    | 15     | 5e-5         | 平衡方案 |
| 0.5    | 12     | 1e-4         | 当前方案 |
| 0.8    | 10     | 2e-4         | 快速收敛 |

## 快速实验命令

```bash
# 实验1：增加训练轮数，降低学习率
python scripts/train_mnist8.py --lr 0.2 --epochs 25 --seed 42

# 实验2：更强的正则化
python scripts/train_mnist8.py --lr 0.3 --epochs 20 --seed 123  # 需要修改代码中的weight_decay

# 实验3：更小的学习率，更多轮数
python scripts/train_mnist8.py --lr 0.1 --epochs 40 --seed 7
```

## 注意事项
1. 每次训练后要重新汇编程序并重新综合FPGA
2. 最好使用相同的随机种子进行公平比较
3. 不要只看训练准确率，要重点关注测试准确率
4. 注意模型大小和FPGA资源使用的平衡
