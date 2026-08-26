#import "../index.typ": template, tufted

// 如需生成 RSS feed，必须填写 title、description 和 date 元数据
#show: template.with(
  title: "Transformer 手写实现｜Encoder 组件实现笔记：形状思维与 PyTorch 语法共性",
  description: "记录一次从零手写 Transformer Encoder 的完整练习：按数据流依次实现文本编码、Embedding、位置编码、Mask、Scaled Dot-Product Attention、Multi-Head Attention、FFN、残差、LayerNorm 与 Adam 优化器，并把踩过的坑按共性归类，总结成 PyTorch 形状操作与语法的速查参考。",
  date: datetime(year: 2026, month: 8, day: 26),
  category: "数学与算法",
  lang: "zh",
)

= Transformer 手写实现｜Encoder 组件实现笔记：形状思维与 PyTorch 语法共性

#tufted.post-meta(
  date: datetime(year: 2026, month: 8, day: 26),
  tags: ("Transformer", "PyTorch", "学习笔记"),
)

#tufted.margin-note[
  *阅读提示*：这一篇记录把 Encoder 从文本编码手写到 Adam 优化器的完整练习。前八节按数据流推进，每节先说明这一步解决什么问题，再给实现与形状推导；第九节是全链路形状总表；第十节把踩过的坑按语法共性归类，可以单独作为速查参考。祝食用愉快～✍️
]

#line(length: 100%, stroke: 0.6pt)

== *导言：从“看懂公式”到“写对代码”*

在#link("/Blog/5-18/")["Transformer 反向传播"系列]里，笔者从数学上把 Transformer 的梯度推导走了一遍。这次换一个方向：不借助 `nn.TransformerEncoder` 这样的现成模块，把 Encoder 的每个组件从零手写一遍。结果是“看得懂”和“写得对”之间还有一段距离，而且这段距离不在数学上，在工程上。

练习的粒度拆得很细：整个 Encoder 变成大约四十个小函数——文本编码、词表、Embedding、位置编码、Padding Mask、Causal Mask、Scaled Dot-Product Attention、Multi-Head 的拆分与合并、FFN、Dropout、残差、LayerNorm、Encoder Layer 的组装与堆叠，最后再手写一个 Adam 优化器。每个函数独立实现、独立测试，错了就修正、记笔记。

把笔记整理成文章时做了重新组织。原始笔记按“踩坑的先后顺序”记录：同一个语法点（比如广播、比如 `unsqueeze`）散落在四五个组件里各出现一次，结构很松散。这篇文章改用两条线索：

+ *一条数据流*：一个句子如何一步步变成 `(B, L)` 的整数张量、如何获得语义与位置信息、如何穿过 Attention 与 FFN、最后如何驱动参数更新——第一到八节按这个顺序推进；
+ *一个方法论*：始终追问“形状三问”——每个维度表示什么？当前操作是否改变元素顺序？两个 Tensor 为什么能进行矩阵乘法或广播？

#quote[
  练习中最直接的体会：*论文层面的困难在数学，代码层面的困难在形状。大部分报错来自形状不匹配；其余主要是把 Python 的直觉用在了 Tensor 上。*
]

#line(length: 100%, stroke: 0.6pt)

== *一：形状思维*

如果先罗列“PyTorch 常用语法清单”，同一个语法点会在不同组件里重复出现，笔记只会越记越散。所以先建立判断框架，后面各节的语法点都归入这个框架。

=== *1.1 记号约定：(B, L, D)*

全文统一用三个字母描述前三个维度：

- `B`：batch size，一个批次里的样本数量；
- `L`：sequence length，序列长度（token 数）；
- `D`：feature dimension，每个 token 的特征维度。

因此 `x.shape == (B, L, D)` 读作：“一个批次里有 B 个句子，每个句子 L 个 token，每个 token 是一个 D 维向量”。维度可以从左往右编号，也可以从右往左：

```text
正数编号：  0   1   2
形状：      B   L   D
负数编号： -3  -2  -1
```

于是：

```python
x.shape[0]   # B
x.shape[1]   # L
x.shape[-1]  # D
```

练习里最先遇到的一个混淆，是 `x.shape[-1]` 与 `x[-1]` 的区别：

- `x.shape[-1]`：*最后一个维度的大小*，一个整数；
- `x[-1]`：*沿第 0 轴取最后一个元素*，一个 Tensor。

例如 `x.shape == (2, 5, 8)` 时：

```python
x.shape[-1]  # 8
x[-1].shape  # (5, 8)，取出最后一个 batch
```

所以在 Attention 里取 `d_k`，正确写法是：

```python
d_k = query.shape[-1]
```

而不是 `d_k = len(query[-1])`——后者取到的是“最后一个元素”的长度，在四维张量里可能得到 head 数或序列长度，唯独不是特征维度。

=== *1.2 形状三问*

后面所有章节的推导，反复使用同三个问题：

+ *每个轴表示什么？*——写任何一行代码之前，先能用一句话说清输入输出每个维度的语义（“B 个样本、H 个头、每个 Query 对每个 Key 的分数”）。
+ *当前操作是否改变元素顺序？*——`reshape`、`transpose`、`unsqueeze` 都不增删元素，但只有 `transpose` 交换轴的位置，只有 `reshape` 重新解释元素的排布（第六节会看到“顺序错了”的代价）。
+ *两个 Tensor 为什么能运算？*——矩阵乘法要求 `(..., a, b) @ (..., b, c)`；广播要求从右向左对齐后，每对维度相等或其中一个为 `1`。

这三问覆盖了练习中几乎所有的报错：`RuntimeError` 的形状不匹配对应第三问；结果“形状对了、数值错了”对应第二问；`d_k` 取错这类不报错的静默 bug 对应第一问。

#line(length: 100%, stroke: 0.6pt)

== *二：从字符串到 (B, L)*

数据流的第一步：模型不认识字符串，只认识整数。这一节解决“句子如何变成一个规则的、可以喂给模型的长方形整数张量”。

=== *2.1 流程总览*

```text
句子字符串
→ 按空白切分 token
→ token_to_id 词表
→ token ID 序列
→ 加 BOS/EOS（如需要）
→ Padding
→ 堆叠为 (B, L) LongTensor
```

下面按顺序拆开每一步。

=== *2.2 建词表：token_to_id*

词表就是“token → 整数”的字典。练习里的约定是：特殊 token 先编号，普通 token 按第一次出现的顺序接着编：

```python
def build_token_to_id_vocab(
    sentences,
    specials=('<pad>', '<bos>', '<eos>', '<unk>')
):
    # 特殊 token 先编号
    token_to_id = {
        token: token_id
        for token_id, token in enumerate(specials)
    }

    # 普通 token 按第一次出现顺序加入
    for sentence in sentences:
        for token in sentence.split():
            if token not in token_to_id:
                token_to_id[token] = len(token_to_id)

    return token_to_id
```

两个值得留意的 Python 细节：

- `enumerate(specials)` 返回 `(索引, 元素)` 对，所以推导式里写成 `(token_id, token)`，编号才能作为键；
- `if token not in token_to_id` 保证每个 token 只在第一次出现时分配编号，此时 `len(token_to_id)` 恰好是“下一个可用编号”。

*踩坑记录：*

- 字典不是列表，不能想当然地用 `0、1、2…` 当索引；
- 普通 dict 不能用 `res.key` 写入——属性语法和下标语法是两回事，必须用 `res[key]`。

=== *2.3 反向词表：id_to_token*

解码时需要“整数 → token”的反查。朴素做法是每次循环搜索，更好的做法是预先建一张反向字典：

```python
def build_id_to_token_vocab(token_to_id):
    id_to_token = {}

    for token, token_id in token_to_id.items():
        id_to_token[token_id] = token

    return id_to_token
```

也可以写成一行字典推导式：

```python
id_to_token = {
    token_id: token
    for token, token_id in token_to_id.items()
}
```

这里的原则后面还会用到：*需要频繁“按值反查”时，预先建立反向映射，而不是每次线性搜索。*

=== *2.4 编码与解码：`.get()` 的默认值*

编码遇到词表外的 token 时，回落到 `<unk>`：

```python
def encode_sentence_to_ids(sentence, token_to_id):
    unk_id = token_to_id['<unk>']

    return [
        token_to_id.get(token, unk_id)
        for token in sentence.split()
    ]
```

解码是纯查表：

```python
def decode_ids_to_tokens(token_ids, id_to_token):
    return [id_to_token[token_id] for token_id in token_ids]
```

关键是 `.get(key, default)`：key 不存在时返回默认值而不抛 `KeyError`，正好用来实现“未知 token 回落到 `<unk>`”。

=== *2.5 Padding 与堆叠：得到 (B, L)*

不同句子长度不同，但张量必须是规则的矩形，所以短句要用 `<pad>` 补齐，再堆叠成二维整数张量。假设补齐后是：

```python
padded_sequences = [
    [1, 2, 0],
    [3, 4, 5],
]
```

转换只需要：

```python
def stack_padded_sequences_to_batch(padded_sequences):
    return torch.tensor(
        padded_sequences,
        dtype=torch.long
    )
```

输出 `shape == (2, 3)`、`dtype == torch.int64`（即 `torch.long`）——token ID 是类别编号，用整数类型是惯例。

*踩坑记录：*函数忘了写 `return` 时，Python 默认返回 `None`，测试再调用 `.tolist()` 就会报：

```text
'NoneType' object has no attribute 'tolist'
```

这种错误特别隐蔽：出错的位置在函数体里，报错的位置却在调用方。看到 `'NoneType'`，第一反应应该是“是不是忘 return 了”。

#line(length: 100%, stroke: 0.6pt)

== *三：Embedding 与位置编码*

`(B, L)` 的 ID 张量拿到了，但它有两个问题：其一，ID 只是类别编号，数值大小没有语义——编号 5 的词并不比编号 4 的词“大一点”；其二，Attention 是对称的两两打分，本身不感知顺序。这一节分别用 Embedding 和位置编码解决这两个问题。

=== *3.1 Embedding：一次查表*

Embedding 的本质是查表：维护一张“词表大小 × d_model”的浮点向量表，把每个 ID 换成表中对应的行向量：

```text
(B, L) → (B, L, d_model)
```

原始 Transformer 还会在查表后做一次缩放：

```python
import math


def scale_embeddings_by_sqrt_d_model(embeddings, d_model):
    return embeddings * math.sqrt(d_model)
```

注意全文两处缩放的方向相反，非常容易记混：

#table(
  columns: (1fr, 1fr, 1.6fr),
  align: (left, left, left),
  table.header([*位置*], [*操作*], [*目的*]),
  [Embedding 之后], [乘 $sqrt(d_"model")$], [放大输入，与位置编码的量级匹配],
  [Attention score], [除 $sqrt(d_k)$], [缩小点积，防止 softmax 饱和（第五节）],
)

=== *3.2 Sinusoidal 位置编码*

位置编码的设计目标：给每个位置生成一个确定性向量，且不同位置的向量易于区分。Sinusoidal 方案用一组从高到低的频率：

$ "PE"_("pos", 2i) = sin("pos" / 10000^(2i / d_"model")) $

$ "PE"_("pos", 2i+1) = cos("pos" / 10000^(2i / d_"model")) $

偶数列填 `sin`、奇数列填 `cos`。实现时先把“频率因子”算出来（以偶数特征下标 $j = 0, 2, 4, ...$ 记）：

$ "div\_term"_j = 10000^(-j / d_"model") $

```python
def compute_positional_div_term(d_model):
    even_indices = torch.arange(
        0, d_model, 2, dtype=torch.float32
    )

    return torch.pow(
        10000.0,
        -even_indices / d_model
    )
```

*踩坑记录：*笔者最初把频率因子写成 `10 ** (-j / 2)`。在 $d_"model" = 8$ 的示例里，$10000^(-j/8) = 10^(-j/2)$，两者完全一致；一旦换成别的维度就会算错，而且数值错、形状对，小例子测不出来。教训是：*不能把特定示例里凑出来的规律当成通用公式。*

接着构造 position 列向量：

```python
position = torch.arange(
    max_len, dtype=torch.float32
).unsqueeze(1)
```

形状是 `(max_len, 1)`。它与 `div_term` 的 `(d_model / 2,)` 相乘：

```text
(max_len, 1) × (d_model/2,)
→ (max_len, d_model/2)
```

这个乘法本身就是一次广播：列向量沿列方向复制、行向量沿行方向复制，得到“每个位置 × 每个频率”的角度矩阵——正好是后面 `sin`/`cos` 的输入。

偶奇列填充靠切片：

```python
def fill_even_indices_with_sin(pe, position, div_term):
    pe[:, 0::2] = torch.sin(position * div_term)
    return pe


def fill_odd_indices_with_cos(pe, position, div_term):
    pe[:, 1::2] = torch.cos(position * div_term)
    return pe
```

`pe[:, 0::2]` 表示“所有行、列 0、2、4、…”，`pe[:, 1::2]` 表示“所有行、列 1、3、5、…”。组装：

```python
def build_sinusoidal_positional_encoding(max_len, d_model):
    pe = torch.zeros(max_len, d_model, dtype=torch.float32)

    position = torch.arange(
        max_len, dtype=torch.float32
    ).unsqueeze(1)
    div_term = compute_positional_div_term(d_model)

    pe = fill_even_indices_with_sin(pe, position, div_term)
    pe = fill_odd_indices_with_cos(pe, position, div_term)

    return pe
```

可以拿 `pos = 0` 做个 sanity check：$sin(0) = 0$、$cos(0) = 1$，所以第一行一定是 `[0, 1, 0, 1, ...]`。打印出来不是这个模式，就说明偶奇列或频率因子算错了。

*踩坑记录：*为了“方便循环”把 Tensor 转成 `.tolist()` 再逐格填表，是这一节最典型的错误思路——转成 Python 列表会同时丢掉广播、设备搬运和自动求导能力，而且更慢。位置编码全程都应该用向量化切片完成。

=== *3.3 相加：一次广播*

```python
def add_positional_encoding_to_embeddings(
    embedded_batch,
    positional_encoding
):
    seq_len = embedded_batch.shape[1]
    return embedded_batch + positional_encoding[:seq_len]
```

形状：

```text
embedded_batch:                (B, L, d_model)
positional_encoding[:seq_len]:    (L, d_model)
```

`(L, d_model)` 自动广播到 `(B, L, d_model)`：每个样本加上的是同一份位置编码。这个自动广播成立的原因是缺失的前导维度按 `1` 处理，第十节会把它归入广播的统一规则。

#line(length: 100%, stroke: 0.6pt)

== *四：Padding Mask 与 Causal Mask*

Attention 的机制是“所有 Query 对所有 Key 打分”，但有两类位置从原理上就不该被打分：padding 补出来的位置不是内容；自回归任务训练时不允许看到未来。Mask 的作用是把这两类位置从 softmax 中排除，两种 mask 的实现重点都在形状上。

=== *4.1 Padding Mask：unsqueeze 的真正用途*

```python
def build_padding_mask(token_ids, pad_id):
    mask = token_ids != pad_id
    return mask.unsqueeze(1).unsqueeze(1)
```

形状变化：

```text
(B, L) → (B, 1, 1, L)
```

`token_ids != pad_id` 逐元素比较得到布尔张量，约定 *True = 可以关注，False = 需要屏蔽*。重点是两次 `unsqueeze`：将来这个 mask 要与 `(B, H, Lq, Lk)` 的注意力分数按位对齐，head 维和 Query 维上的 `1` 会在广播中被“复制”，等价于“所有 head、所有 Query 共用同一份 padding 屏蔽”。

*踩坑记录：*曾想当然地写 `if token_ids != pad_id:`——比较结果是多元素布尔 Tensor，Python 的 `if` 无法对它求值，直接抛 `Boolean value of Tensor with more than one value is ambiguous`。逐元素比较的结果就该作为 mask 使用，而不是进控制流。

=== *4.2 Causal Mask：tril 与下三角*

```python
def build_causal_mask(seq_len):
    mask = torch.ones(
        seq_len, seq_len, dtype=torch.bool
    )

    mask = torch.tril(mask)

    return mask.unsqueeze(0).unsqueeze(0)
```

形状变化：

```text
(L, L) → (1, 1, L, L)
```

`torch.tril()` 保留主对角线及以下的部分：

```text
[True,  False, False]
[True,  True,  False]
[True,  True,  True ]
```

读法：第 `q` 行是 Query `q` 的视野，`True` 的列 `k` 满足 `k <= q`——每个位置只能看自己和过去，不能看未来。两次 `unsqueeze` 的目的与 Padding Mask 相同：构造能对齐到 `(B, H, Lq, Lk)` 的形状。

=== *4.3 合并：`&` 与广播对齐*

```python
def combine_padding_and_causal_masks(
    padding_mask,
    causal_mask
):
    return padding_mask & causal_mask
```

两个 mask 形状不同，但可以广播：

```text
Padding: (B, 1, 1, L)
Causal:  (1, 1, L, L)
Result:  (B, 1, L, L)
```

合并后的语义：*只有两个 mask 都为 True 的位置才保留*——既不是 padding，也没有越过因果边界。

*踩坑记录：*合并 mask 要用 `&`（Tensor 的逐元素逻辑与），不能用 `and`——`and` 是 Python 对“两个对象整体真假”的判断，而多元素 Tensor 恰恰没有整体真假，报错信息与 4.1 相同。这一对错误的共性，第十节统一总结。

#line(length: 100%, stroke: 0.6pt)

== *五：Scaled Dot-Product Attention 的实现*

mask 就位后进入 Attention。这一节是全文形状推导最密集的部分。

=== *5.1 公式与“打分表”直觉*

输入约定：

```text
Q: (B, H, Lq, d_k)
K: (B, H, Lk, d_k)
V: (B, H, Lk, d_v)
```

公式：

$ "Attention"(Q, K, V) = "softmax"(Q K^T / sqrt(d_k)) V $

先回答第一问——`QK^T` 的形状为什么是 `(Lq, Lk)`？它可以看成一张打分表：每一行是一个 Query，每一列是一个 Key，格子 `(q, k)` 是两者的点积：

```text
             Key 0  Key 1  ... Key Lk-1
Query 0        .       .           .
Query 1        .       .           .
...
Query Lq-1     .       .           .
```

每个 head 拿到一张 `(Lq, Lk)` 的表，所以带上 batch 与 head 维度后就是 `(B, H, Lq, Lk)`。

=== *5.2 Q @ Kᵀ：`@` 与 `*` 的区别*

```python
def compute_raw_attention_scores(query, key):
    return query @ key.transpose(-2, -1)
```

形状推导：

```text
Q:  (B, H, Lq, d_k)
Kᵀ: (B, H, d_k, Lk)
→   (B, H, Lq, Lk)
```

`transpose(-2, -1)` 只交换最后两条轴（`-1` 是最后一维、`-2` 是倒数第二维），把 K 从 `(B, H, Lk, d_k)` 变成 `(B, H, d_k, Lk)`。矩阵乘法的规则是：

```text
(..., a, b) @ (..., b, c) → (..., a, c)
```

中间的 `b` 维做内积后消失——这正是“每个 Query 与每个 Key 算一次点积”的形状表达。

结果的语义也需要明确：`scores[b, h, q, k]` 是第 `b` 个样本、第 `h` 个 head 里，Query `q` 与 Key `k` 的匹配分数。

*踩坑记录：*曾写成 `query * key_t`。`*` 是逐元素乘法，不会沿 `d_k` 求和——形状根本对不上；就算形状碰巧能广播，语义也完全不是点积。“要不要沿某条轴求和”是区分 `*` 与 `@` 的唯一标准（第十节）。

=== *5.3 除以 √d_k：为什么需要缩放*

```python
import math


def scale_attention_scores(scores, d_k):
    return scores / math.sqrt(d_k)
```

假设 `q`、`k` 的分量是均值 0、方差 1 的独立随机变量，那么点积 $q dot k = sum_i q_i k_i$ 的方差是 $d_k$：维度越高，点积幅值越大，softmax 会越来越接近 one-hot，梯度几乎消失。除以 $sqrt(d_k)$ 恰好把方差拉回 1。

这里用 `math.sqrt` 是安全的，因为 `d_k` 是 Python 整数——`math` 与 `torch` 的分工在第十节统一说明。

=== *5.4 masked_fill 与 −inf*

```python
def mask_attention_scores_with_neg_inf(scores, mask):
    return scores.masked_fill(
        ~mask,
        float('-inf')
    )
```

`masked_fill(condition, value)` 在 condition 为 True 的位置替换数值。由于约定 True = 保留，要填的恰好是 False 的位置——先取反 `~mask`。填 `-inf` 的原因很直接：

$ "exp"(-oo) = 0 $

被屏蔽位置的分数经过 softmax 后权重恰好为 0，等价于“这个位置从未参与打分”。

=== *5.5 softmax(dim=-1) 与全 −inf 行的 NaN*

softmax 沿 Key 维度归一化：

```python
torch.softmax(scores, dim=-1)
```

注意一次 softmax 只沿一个维度归一化，不存在“同时沿 `-1` 和 `-2`”。另一个隐患：如果某一行全是 `-inf`（例如某个 Query 的所有 Key 都被 padding 屏蔽），softmax 会算出 0/0：

```text
[-inf, -inf, -inf] → softmax → [NaN, NaN, NaN]
```

稳妥的实现是先找出全屏蔽行、临时填 0 计算、再把结果置 0：

```python
def softmax_attention_weights(masked_scores):
    # 找出整行都被屏蔽的位置
    # (B, H, Lq, Lk) → (B, H, Lq, 1)
    all_masked = torch.isneginf(masked_scores).all(
        dim=-1,
        keepdim=True
    )

    # 临时将全屏蔽行改成 0，避免 0/0
    safe_scores = masked_scores.masked_fill(
        all_masked,
        0.0
    )

    weights = torch.softmax(safe_scores, dim=-1)

    # 全屏蔽行最终应返回全 0 权重
    return weights.masked_fill(all_masked, 0.0)
```

这里的关键是 `keepdim=True`：`.all(dim=-1)` 本会把最后一维塌缩成 `(B, H, Lq)`，无法直接广播回 `(B, H, Lq, Lk)`；保留成大小为 1 的维度后，恰好满足广播规则。

=== *5.6 权重混合 Value：加权求和*

```python
def apply_attention_weights_to_values(
    attention_weights,
    value
):
    return attention_weights @ value
```

形状：

```text
Weights: (B, H, Lq, Lk)
V:       (B, H, Lk, d_v)
Result:  (B, H, Lq, d_v)
```

这一步同样是矩阵乘法：`Lk` 维在乘法中做内积后消失——每个 Query 的输出是所有 Value 的加权和，权重是对应打分表里的那一行。

=== *5.7 完整拼装*

```python
def scaled_dot_product_attention(
    query,
    key,
    value,
    mask=None
):
    d_k = query.shape[-1]

    scores = compute_raw_attention_scores(query, key)
    scores = scale_attention_scores(scores, d_k)

    if mask is not None:
        scores = mask_attention_scores_with_neg_inf(
            scores,
            mask
        )

    attention_weights = softmax_attention_weights(scores)

    context = apply_attention_weights_to_values(
        attention_weights,
        value
    )

    return context, attention_weights
```

*踩坑记录：*完整拼装时暴露的错误，几乎每条都能对应到“三问”之一：

- `d_k` 误取成 `len(query[-1])`——第一问（每个轴是什么）；
- `mask` 是可选参数，判断必须写 `if mask is not None`——写成 `if mask` 会把多元素 Tensor 放进 Python 布尔上下文（第十节统一说明）；
- 变量名前后不一致：`masker_scores` 与 `masked_scores` 是两个变量，拼装时要么 NameError、要么用错；`context` 定义了却返回 `ctx` 同理。

#line(length: 100%, stroke: 0.6pt)

== *六：Multi-Head Attention 的拆分与合并*

单头 Attention 一次只在一个表示子空间里打分。Multi-Head 的做法是：把 `d_model` 均分成 `H` 份，每个 head 在自己的 `d_k = d_model \/ H` 子空间里独立做 Attention，最后拼回来。实现上的难点集中在形状的拆分与合并。

=== *6.1 线性投影：weight 为什么是 (out, in)*

PyTorch 的 Linear 层把权重存成 `(out_features, in_features)`，所以手写投影要先转置：

```python
def apply_linear_projection(x, weight, bias):
    output = x @ weight.T

    if bias is not None:
        output = output + bias

    return output
```

形状：

```text
x:        (..., in_features)
weight.T: (in_features, out_features)
output:   (..., out_features)
```

`bias` 的形状是 `(out_features,)`，靠广播加到所有前置维度上。注意前置维度 `...` 完全不被矩阵乘法触碰——这正是“每个 token 独立过同一个线性层”的形状表达。

*踩坑记录：*

- `bias` 可能为 `None`，`Tensor + None` 直接报错，必须先判断；
- 不要在模型内部对中间结果 `round()`——会破坏精度与梯度；想控制打印精度，用 `torch.set_printoptions()`。

=== *6.2 拆分 heads：reshape → transpose*

第一步，把最后一维拆开：

```python
def split_last_dim_into_heads(tensor, num_heads):
    B, L, d_model = tensor.shape
    d_k = d_model // num_heads
    return tensor.reshape(B, L, num_heads, d_k)
```

```text
(B, L, d_model) → (B, L, H, d_k)
```

`reshape` 只要求前后元素总数相同（`d_model = H × d_k`）。第二步，把 head 维换到前面：

```python
x = x.transpose(1, 2)    # (B, H, L, d_k)
```

Q、K、V 一起处理：

```python
def split_qkv_into_heads(q, k, v, num_heads):
    q_h = split_last_dim_into_heads(q, num_heads).transpose(1, 2)
    k_h = split_last_dim_into_heads(k, num_heads).transpose(1, 2)
    v_h = split_last_dim_into_heads(v, num_heads).transpose(1, 2)

    return q_h, k_h, v_h
```

*踩坑记录：*只做第一步是不够的——在 `(B, L, H, d_k)` 布局下，后续 `Q @ Kᵀ` 会把 `L` 当成矩阵维度。Attention 需要的正确布局是 `(B, H, L, d_k)`：`B、H` 作为批量维度待在前面。

=== *6.3 无须 Python 循环：批量矩阵乘*

```python
def multi_head_scaled_dot_product_attention(
    q_h,
    k_h,
    v_h,
    mask=None
):
    return scaled_dot_product_attention(
        q_h,
        k_h,
        v_h,
        mask=mask
    )
```

没有 for 循环、没有对 head 的遍历——第五节写的单头函数原封不动地服务多头。原因是 `@` 的规则：`(..., a, b) @ (..., b, c)` 的前置维度只要求相等或可广播，`B、H` 都作为批量维度被保留，所有 head 的矩阵乘法一次并行完成。

*踩坑记录：*这个函数最初被写成 `scaled_dot_product_attention(q_h, k_h, v_h, mask=None)`——参数默认值 `mask=None` 会强制丢弃外部传入的 mask，正确写法是 `mask=mask`（把当前函数收到的变量原样传下去）。这是静默错误：训练照常跑，但 mask 实际没有生效。

=== *6.4 合并 heads：transpose → reshape*

拆分是 reshape → transpose，合并就是镜像的 transpose → reshape：

```python
def merge_heads_back_to_model_dim(multi_head_tensor):
    B, H, L, d_k = multi_head_tensor.shape

    tensor = multi_head_tensor.transpose(1, 2)
    return tensor.reshape(B, L, H * d_k)
```

```text
(B, H, L, d_k) → transpose → (B, L, H, d_k) → reshape → (B, L, d_model)
```

为什么必须先 transpose？这里直接对应第二问（操作是否改变元素顺序）：`reshape` 按行优先的顺序重新解释元素，在 `(B, H, L, d_k)` 布局下直接 reshape 成 `(B, L, H * d_k)`，同一个 token 的 `H` 段向量并不相邻——拼出来的是“head 交错”的错误组合，*形状正确、数值全错*。先 transpose 把同一个 token 的各 head 移到相邻位置，reshape 的语义才是“同一个 token 的多个 head 拼接”。

拆与合可以对照着记：

#table(
  columns: (1fr, 1.2fr, 1.8fr),
  align: (left, left, left),
  table.header([*方向*], [*顺序*], [*形状*]),
  [拆分 heads], [reshape → transpose], [`(B, L, d_model) → (B, L, H, d_k) → (B, H, L, d_k)`],
  [合并 heads], [transpose → reshape], [`(B, H, L, d_k) → (B, L, H, d_k) → (B, L, d_model)`],
)

=== *6.5 完整前向*

```python
def assemble_multi_head_attention_forward(
    query,
    key,
    value,
    w_q,
    w_k,
    w_v,
    w_o,
    num_heads,
    mask=None
):
    # 1. Q/K/V 使用不同权重进行投影
    q = apply_linear_projection(query, w_q, None)
    k = apply_linear_projection(key, w_k, None)
    v = apply_linear_projection(value, w_v, None)

    # 2. 拆分 heads
    q_h, k_h, v_h = split_qkv_into_heads(
        q, k, v, num_heads
    )

    # 3. 所有 head 并行执行 Attention
    context_h, attention_weights = (
        multi_head_scaled_dot_product_attention(
            q_h, k_h, v_h, mask=mask
        )
    )

    # 4. 合并 heads 并输出投影
    merged = merge_heads_back_to_model_dim(context_h)
    output = apply_linear_projection(merged, w_o, None)

    return output, attention_weights
```

一个容易被忽略的点：即使是 Self-Attention（`query = key = value = x`），三者仍然要经过*不同的* `W_q`、`W_k`、`W_v` 投影——同一份输入，三种不同的投影。

#line(length: 100%, stroke: 0.6pt)

== *七：FFN、Dropout、残差与 LayerNorm*

Attention 之后，张量依然是 `(B, L, d_model)`，但一个完整的 Encoder Layer 还需要几个组件：FFN 提供逐位置的非线性变换，Dropout 用于正则化，残差与 LayerNorm 用于训练稳定性。这一节依次实现它们，再组装成完整的 Encoder Layer。

=== *7.1 FFN：对每个 token 独立的同款两层网络*

$ "FFN"(x) = "Linear"_2("ReLU"("Linear"_1(x))) $

```python
def apply_ffn_first_linear_and_relu(x, w1, b1):
    hidden = x @ w1.T + b1
    return torch.relu(hidden)


def apply_ffn_second_linear(hidden, w2, b2):
    return hidden @ w2.T + b2
```

形状：

```text
x:      (B, L, d_model)
w1:     (d_ff, d_model)
hidden: (B, L, d_ff)
w2:     (d_model, d_ff)
output: (B, L, d_model)
```

“对每个 token 独立”的形状表达：`B、L` 全程作为批量维度待在前面，矩阵乘法只碰最后一维。第一层升维（`d_model → d_ff`），第二层投影回 `d_model`。

*踩坑记录：*ReLU 不能写成 `x if x >= 0 else 0`——Python 三元表达式要对整个 Tensor 判断真假，与 `if` 是同一种错误。

=== *7.2 Inverted Dropout：为什么除以 keep_prob*

```python
def apply_dropout_with_keep_mask(x, keep_mask, keep_prob):
    keep_mask = keep_mask.to(
        dtype=x.dtype,
        device=x.device
    )

    return x * keep_mask / keep_prob
```

原理（以保留概率 $p$ 记）：

```text
保留时输出 = x / p
丢弃时输出 = 0
```

期望不变：

$ "E"[y] = p dot (x / p) + (1 - p) dot 0 = x $

这样推理时就不需要补偿缩放。注意参数语义：这里除以的是 *keep_prob*（保留概率）；如果接口给的是 drop probability，才应该按 `1 / (1 - p)` 缩放。练习里最容易犯的错，就是没看清接口约定就用错了分母。

代码里的 `.to(dtype=..., device=...)` 同样值得留意：布尔 mask 与浮点 Tensor 相乘之前，先对齐类型与设备。

=== *7.3 残差连接：一切子层都必须回到 d_model*

```python
residual_output = x + sublayer_output
```

残差就是逐元素相加，硬性要求 `x.shape == sublayer_output.shape`。这一条要求解释了前面的两处设计：Multi-Head 合并后要投影回 `d_model`（`W_o` 的作用），FFN 第二层也要落回 `d_model`——都是为了满足残差相加的形状要求。

两种常见排布：

```text
Post-Norm:  output = LayerNorm(x + Dropout(Sublayer(x)))
Pre-Norm:   output = x + Dropout(Sublayer(LayerNorm(x)))
```

练习的辅助函数固定了其中一种顺序，组装时严格按接口调用即可；但要知道两种都存在，现代实现多采用 Pre-Norm（深层训练更稳定）。

=== *7.4 LayerNorm：keepdim、unbiased 与 torch.sqrt*

$ hat(x) = (x - mu) / sqrt(sigma^2 + epsilon), quad y = gamma dot hat(x) + beta $

```python
def compute_layer_norm_mean_and_variance(x):
    mean = x.mean(dim=-1, keepdim=True)

    variance = x.var(
        dim=-1,
        keepdim=True,
        unbiased=False
    )

    return mean, variance


def normalize_and_scale_with_gamma_beta(
    x,
    gamma,
    beta,
    eps=1e-5
):
    mean, variance = compute_layer_norm_mean_and_variance(x)

    normalized = (
        (x - mean) /
        torch.sqrt(variance + eps)
    )

    return normalized * gamma + beta
```

四个细节：

+ *沿最后一维归一化*：每个 token 自己算均值与方差——这是 LayerNorm 与 BatchNorm 的本质区别；
+ *`keepdim=True`*：`(B, L, D) → (B, L, 1)`，保留的大小为 1 的维恰好能广播回 `(B, L, D)`，与 5.5 的 `all(dim=-1, keepdim=True)` 是同一个技巧；
+ *`unbiased=False`*：LayerNorm 用总体方差 $sum((x - mu)^2) \/ D$，而不是除以 $D - 1$ 的样本无偏方差；
+ *`torch.sqrt` 而不是 `math.sqrt`*：`variance` 是 Tensor；`gamma`、`beta` 形状通常为 `(d_model,)`，靠广播作用于每个 token。

*踩坑记录：*

- 方差已经是平方偏差的均值，再写 `variance ** 2` 就成了四次方；
- 用 `math.sqrt(variance + eps)` 会对 Tensor 报错——`math` 模块只吃标量。

=== *7.5 组装一个 Encoder Layer*

一个 Encoder Layer 的结构：

```text
Self-Attention 子层
→ Residual + LayerNorm
→ FFN 子层
→ Residual + LayerNorm
```

组装代码：

```python
def assemble_encoder_layer(
    x,
    layer_params,
    num_heads,
    src_mask
):
    attn_output = encoder_layer_self_attention_sublayer(
        x,
        layer_params['w_q'],
        layer_params['w_k'],
        layer_params['w_v'],
        layer_params['w_o'],
        layer_params['gamma1'],
        layer_params['beta1'],
        num_heads,
        src_mask
    )

    output = encoder_layer_feed_forward_sublayer(
        attn_output,
        layer_params['w1'],
        layer_params['b1'],
        layer_params['w2'],
        layer_params['b2'],
        layer_params['gamma2'],
        layer_params['beta2']
    )

    return output
```

要点：

- 参数全部从 `layer_params` 字典读取——`w_q`、`w1` 这些名字不在局部作用域里，直接裸用就是 NameError；
- Attention 子层与 FFN 子层使用*两套独立的* LayerNorm 参数（`gamma1/beta1` 与 `gamma2/beta2`）；
- 第二个子层接收的是*第一个子层的输出*，不是原始 `x`。

=== *7.6 堆叠：hidden 必须接力*

```python
def stack_encoder_layers(
    x,
    encoder_layer_params_list,
    num_heads,
    src_mask
):
    hidden = x

    for layer_params in encoder_layer_params_list:
        hidden = assemble_encoder_layer(
            hidden,
            layer_params,
            num_heads,
            src_mask
        )

    return hidden
```

重点：每一层接收上一层的输出。错误写法对比：

```python
for params in params_list:
    hidden = layer(x, params)   # 每层都从原始 x 出发，堆叠失效
```

多层结构的作用是逐层变换表示。这个 bug 形状完全合法，小规模测试输出看起来也“正常”，特别容易漏。

#line(length: 100%, stroke: 0.6pt)

== *八：Adam 优化器*

前向传播完成后，反向传播交给自动求导，剩下的是优化器。SGD 对学习率敏感；Adam 为每个参数维护梯度的一阶矩与二阶矩移动平均，自适应地调整步长，代价是优化器成为一个*有状态*的对象。

=== *8.1 状态：m、v、t*

#table(
  columns: (auto, 1fr),
  align: (left, left),
  table.header([*状态*], [*含义*]),
  [`m`], [梯度的一阶矩移动平均（趋势/方向）],
  [`v`], [梯度平方的二阶矩移动平均（幅度）],
  [`t`], [全局优化步数（标量）],
)

```python
def initialize_adam_optimizer_state(parameter_list):
    parameters = list(parameter_list)

    m = [torch.zeros_like(p) for p in parameters]
    v = [torch.zeros_like(p) for p in parameters]
    t = 0

    return m, v, t
```

`torch.zeros_like(p)` 自动继承形状、dtype 与 device。

*踩坑记录：*不能写 `v = m`——Python 赋值是引用共享，之后对 `m` 的原地更新会同步污染 `v`，两个状态会变成同一个。

=== *8.2 四条公式与偏差修正*

$ m_t = beta_1 m_(t-1) + (1 - beta_1) g_t $

$ v_t = beta_2 v_(t-1) + (1 - beta_2) g_t^2 $

$ hat(m)_t = m_t / (1 - beta_1^t), quad hat(v)_t = v_t / (1 - beta_2^t) $

$ theta_t <- theta_(t-1) - (eta dot hat(m)_t) / (sqrt(hat(v)_t) + epsilon) $

偏差修正（后两行）的存在原因：`m`、`v` 从 0 初始化，训练初期被历史“拖”向 0，直接使用会步长偏小；除以 $1 - beta^t$（前期远小于 1）把估计放大回合理量级，$t$ 增大后修正自动趋近于 1。

=== *8.3 完整 step：原地操作与 no_grad*

```python
def apply_adam_step_to_all_parameters(
    parameter_list,
    optimizer_state,
    learning_rate,
    beta1=0.9,
    beta2=0.98,
    epsilon=1e-9
):
    # 延续上一轮状态，不能重新初始化
    m, v, t = optimizer_state
    t += 1

    with torch.no_grad():
        for i, parameter in enumerate(parameter_list):
            if parameter.grad is None:
                continue

            grad = parameter.grad

            # m = beta1 * m + (1 - beta1) * grad
            m[i].mul_(beta1).add_(
                grad,
                alpha=1.0 - beta1
            )

            # v = beta2 * v + (1 - beta2) * grad^2
            v[i].mul_(beta2).addcmul_(
                grad,
                grad,
                value=1.0 - beta2
            )

            m_hat = m[i] / (1.0 - beta1 ** t)
            v_hat = v[i] / (1.0 - beta2 ** t)

            # parameter -= lr * m_hat / (sqrt(v_hat) + eps)
            parameter.addcdiv_(
                m_hat,
                torch.sqrt(v_hat) + epsilon,
                value=-learning_rate
            )

    return m, v, t
```

这段代码的要点：

- *`m, v, t = optimizer_state` 在函数开头*：Adam 是有状态的优化器，每一步必须延续上一步的 `m、v、t`——每步重新初始化等于把历史清零；
- *`t += 1` 在循环外*：`t` 是全局步数，每个训练 step 只加一次，不能对每个参数各加一次；
- *`with torch.no_grad()`*：参数更新是“用手搬参数”，不是计算图的一部分，必须在 no_grad 里做，否则会被自动求导记录；
- *`mul_`、`add_`、`addcmul_`、`addcdiv_`*：下划线后缀的原地操作，直接修改状态与参数，不产生新 Tensor；
- *`if parameter.grad is None: continue`*：没参与损失计算的参数没有梯度，跳过而不是报错。

*踩坑记录：*`(m, v, t)` 是元组，不能调用 `.item()`——`.item()` 只对单元素 Tensor 有意义。想确认参数是否更新，打印 `t` 或参数的范数就够了。

#line(length: 100%, stroke: 0.6pt)

== *九：端到端流程与形状总表*

组件全部实现后，把整条执行链路串起来，并汇总所有中间形状。

=== *9.1 端到端流程*

```text
1. 文本处理
   句子 → token → token ID → padding → batch: (B, L)

2. 输入表示
   Embedding lookup → (B, L, d_model)
   → 乘 sqrt(d_model)
   → 加 Positional Encoding

3. Encoder Self-Attention
   Q/K/V 线性投影 → (B, L, d_model)
   → reshape 拆 heads → (B, L, H, d_k)
   → transpose → (B, H, L, d_k)

4. Scaled Dot-Product Attention
   Q @ Kᵀ → (B, H, L, L)
   → 除 sqrt(d_k)
   → mask 填 -inf
   → softmax(dim=-1)
   → weights @ V → (B, H, L, d_k)

5. 合并 Heads
   transpose → (B, L, H, d_k)
   reshape → (B, L, d_model)
   输出投影 Wo → (B, L, d_model)

6. Attention 子层收尾
   Dropout → Residual Add → LayerNorm

7. FFN
   Linear(d_model → d_ff) → ReLU → Linear(d_ff → d_model)
   → Dropout → Residual Add → LayerNorm

8. 堆叠多层 Encoder
   hidden = layer_1(hidden) → layer_2(hidden) → ...

9. 训练
   loss.backward() → 参数得到 grad
   → Adam 更新 m、v、t，原地更新参数
   → 清空 grad
```

每个步骤都标注了对应的形状。

=== *9.2 形状总表*

#table(
  columns: (1fr, 1fr),
  align: (left, left),
  table.header([*Tensor*], [*形状*]),
  table.cell(colspan: 2)[*输入表示*],
  [Token IDs], [`(B, L)`],
  [Embedding], [`(B, L, d_model)`],
  [Positional Encoding], [`(max_len, d_model)`],
  [Embedding + PE], [`(B, L, d_model)`],
  table.cell(colspan: 2)[*Multi-Head Attention*],
  [Q/K/V 投影后], [`(B, L, d_model)`],
  [拆分但未转置], [`(B, L, H, d_k)`],
  [转置后], [`(B, H, L, d_k)`],
  [Q], [`(B, H, Lq, d_k)`],
  [K], [`(B, H, Lk, d_k)`],
  [Kᵀ], [`(B, H, d_k, Lk)`],
  [Attention Scores], [`(B, H, Lq, Lk)`],
  [Padding Mask], [`(B, 1, 1, Lk)`],
  [Causal Mask], [`(1, 1, Lq, Lk)`],
  [Combined Mask], [`(B, 1, Lq, Lk)`],
  [Attention Weights], [`(B, H, Lq, Lk)`],
  [V], [`(B, H, Lk, d_v)`],
  [Context per head], [`(B, H, Lq, d_v)`],
  [Merged context], [`(B, Lq, H * d_v)`],
  [MHA output], [`(B, Lq, d_model)`],
  table.cell(colspan: 2)[*Encoder Layer*],
  [FFN hidden], [`(B, L, d_ff)`],
  [FFN output], [`(B, L, d_model)`],
  [LayerNorm mean/variance], [`(B, L, 1)`],
  [Encoder layer output], [`(B, L, d_model)`],
)

#line(length: 100%, stroke: 0.6pt)

== *十：语法共性总结*

前八节的踩坑按出现位置记录；这一节按共性重新归类。同一条规律往往在不同组件里各出现一次，集中对照更便于记忆。

=== *10.1 形状变换：都是对轴的操作*

`unsqueeze`、`reshape`、`transpose` 与切片都不增删元素，只改变“元素的逻辑排布”。区分它们的标准只有一个——你想对哪条轴做什么：

#table(
  columns: (1fr, auto, 1.5fr),
  align: (left, left, left),
  table.header([*目的*], [*工具*], [*本文中的例子*]),
  [新增一条长度为 1 的轴], [`unsqueeze`], [Padding Mask `(B, L) → (B, 1, 1, L)`；position 列向量 `(max_len, 1)`],
  [把一个维度拆成两个], [`reshape`], [多头拆分 `(B, L, d_model) → (B, L, H, d_k)`],
  [把两个维度合成一个], [`reshape`], [多头合并 `(B, L, H, d_k) → (B, L, d_model)`],
  [交换两条已有轴的位置], [`transpose`], [`Kᵀ`：`transpose(-2, -1)`；head 维：`transpose(1, 2)`],
  [沿某条轴按步长取样], [切片], [位置编码的 `[:, 0::2]` 与 `[:, 1::2]`],
)

两条附带的经验：

- `reshape` 唯一的合法性检查是*元素总数不变*（`12 = 3 × 4`），它不检查语义——语义要靠自己保证，6.4 的“head 交错”就是形状合法、语义全错的例子；
- 需要“把 12 拆成 3 × 4”时不要用 `unsqueeze`——它只能新增长度为 1 的轴，不能改变已有维度的大小。

=== *10.2 广播：大小为 1 的轴可以被复制*

广播规则：两个形状*从右向左*逐对比较，每一对满足以下之一即可运算：

+ 两者大小相同；
+ 其中一个为 `1`；
+ 某个 Tensor 缺少该维度（缺失按 `1` 处理）。

回看全文，至少有四个完全不同的场景，底层都是这一条规则：

#table(
  columns: (1.2fr, 1.2fr, 1.4fr),
  align: (left, left, left),
  table.header([*场景*], [*对齐的形状*], [*“1”被复制后的效果*]),
  [Padding Mask 对齐打分表], [`(B, 1, 1, Lk)` 与 `(B, H, Lq, Lk)`], [所有 head、所有 Query 共用一份屏蔽],
  [LayerNorm 的均值方差], [`(B, L, 1)` 与 `(B, L, D)`], [每个 token 用自己的一对 $mu$、$sigma^2$],
  [位置编码相加], [`(L, d_model)` 与 `(B, L, d_model)`], [每个样本加同一份位置编码],
  [Linear 的偏置], [`(out,)` 与 `(..., out)`], [每个位置加同一个偏置],
)

以 Padding Mask 为例，广播后的下标关系是：

$ "mask"_"expanded"[b, h, q, k] = "mask"[b, 0, 0, k] $

长度为 1 的维度只有下标 `0`，扩展后所有 head 和所有 Query 读取的都是这一份数据——这就是“共享”的原因。两个要点：

- *大小为 1 本身不等于共享*——是它在广播运算中被反复读取，才表现为共享。设计 mask 形状的过程，本质上就是“主动构造大小为 1 的轴”；
- `keepdim=True` 的统一意义在这里可以直接看出：归约后保留大小为 1 的轴，让结果恰好满足广播规则、直接参与后续运算。5.5 的 `all(dim=-1, keepdim=True)` 与 7.4 的 `mean(dim=-1, keepdim=True)` 是同一个技巧的两次应用。

=== *10.3 乘法与归约：是否沿轴求和*

把 `*`、`@` 与各种归约操作放在一起，区分标准只有一个——是否沿某条轴做求和：

#table(
  columns: (auto, 1.4fr, 1.4fr),
  align: (left, left, left),
  table.header([*运算*], [*规则*], [*本文中的例子*]),
  [`A * B`], [逐元素乘（可广播），不聚合任何轴], [Dropout 的 `x * keep_mask`；Embedding 缩放],
  [`A @ B`], [最后两轴做矩阵乘，前置轴要求相等或可广播], [`Q @ Kᵀ`；`weights @ V`；线性投影],
  [`mean` / `var` / `sum` / `all(dim)`], [沿指定轴塌缩，其余轴保留], [LayerNorm 统计量；全屏蔽行检测],
)

`@` 的前置轴规则同时解释了两件事：为什么多头不需要 for 循环（`B、H` 是被保留的批量轴），以及为什么 `(B, L, H, d_k)` 布局下 Attention 会算错（`L` 被当成了矩阵维）。

=== *10.4 Python 逻辑与 Tensor 逻辑*

练习里数量最多的一类错误，是把 Python 的标量直觉用在多元素 Tensor 上。把成对的写法整理如下：

#table(
  columns: (1fr, 1.1fr, 1.3fr),
  align: (left, left, left),
  table.header([*想做的事*], [*Python 直觉（错误）*], [*Tensor 正确写法*]),
  [多元素条件判断], [`if x != 0:`], [`mask = x != 0`；归纳用 `.any()` / `.all()`],
  [逻辑与], [`a and b`], [`a & b`（逐元素）],
  [按条件取值 / ReLU], [`x if x >= 0 else 0`], [`torch.relu(x)`、`torch.where(...)`],
  [开平方等数学函数], [`math.sqrt(tensor)`], [`torch.sqrt(tensor)`],
  [逐元素循环计算], [`for` + `.tolist()`], [广播 / 向量化切片],
)

共同的规则是：*Python 的控制流作用在“一个对象”上，Tensor 的控制流作用在“每个元素”上。*凡是一个表达式会返回多个布尔值，它就不能进 `if`、`and` 或三元表达式。`math` 与 `torch` 的分工同理：`math` 吃标量返回标量；`torch` 吃 Tensor 返回 Tensor，并且保留梯度与设备信息（唯一的例外场景：`d_k` 这类 Python 整数用 `math.sqrt` 完全没问题）。

=== *10.5 原地操作、no_grad 与 dtype/device*

最后一组共性，关于训练循环里“不进计算图”的操作：

+ *下划线后缀 = 原地修改*：`add_`、`mul_`、`sub_`、`masked_fill_` 直接修改原 Tensor；不带下划线的版本返回新 Tensor。优化器更新参数用的全是原地版本；
+ *`torch.no_grad()` 包住参数更新*：手动搬参数不是模型计算，不该被自动求导记录；
+ *`zeros_like` 与 `.to(dtype=..., device=...)`*：新建或转换 Tensor 时，主动对齐“形状 + dtype + device”三件套——类型不匹配的报错往往发生在广播之前；
+ *状态要跨步延续*：Adam 的 `m、v、t`、Encoder 堆叠的 `hidden`，本质都是“上一步的输出是下一步的输入”，初始化只能发生一次——`v = m` 这种引用共享的写法，会让两个状态实际指向同一个对象。

=== *10.6 检查表*

把全部踩坑整理成一份清单：

*Python 基础*

- 函数写完 `return` 了吗？看到 `'NoneType'` 先查这个；
- 字典用 `dict[key]` 读写，`dict.key` 是另一回事；
- 变量名前后一致：`context` / `ctx`、`b_o` / `b_0`、`masked_scores` / `masker_scores`；
- 传参写 `mask=mask`，别把默认值 `mask=None` 抄进调用处。

*形状操作*

- `shape[-1]` 是最后一维的大小，`x[-1]` 是取最后一个元素；
- 选 `unsqueeze`（加长度 1 的轴）、`reshape`（拆/合维度）、`transpose`（换轴位置）之前，先说出目的；
- `reshape` 前后元素总数相同吗？
- 合并 heads 前先 `transpose` 回 `(B, L, H, d_k)` 了吗？

*运算*

- 这里需要逐元素 `*`，还是矩阵乘 `@`？
- Tensor 条件进 `if` / `and` / 三元表达式了吗？
- 对 Tensor 用的是 `torch.sqrt` 而不是 `math.sqrt` 吗？

*Attention*

- Key 做了 `transpose(-2, -1)` 吗？
- Softmax 沿 `dim=-1` 吗？
- mask 约定是 True = 保留？`masked_fill` 用的是 `~mask` 吗？
- 全 `-inf` 行的 NaN 处理了吗？
- 可选 mask 判断的是 `if mask is not None` 吗？

*LayerNorm / FFN*

- 方差用了 `unbiased=False` 吗？
- 需要广播回去的归约加 `keepdim=True` 了吗？
- 分母是 `sqrt(variance + eps)`（没有对 variance 再平方）吗？

*优化器*

- Adam 状态只初始化一次、每步延续 `m、v、t` 吗？
- `t` 每个 step 只加一次吗？
- 参数更新包在 `torch.no_grad()` 里吗？
- `grad is None` 的参数跳过了吗？

#line(length: 100%, stroke: 0.6pt)

== *小结*

这篇笔记覆盖从零手写 Transformer Encoder 的完整链路，主线有两条：

- *一条数据流*：句子 → `(B, L)` 的 ID → Embedding 与位置编码 → Mask → Scaled Dot-Product Attention → Multi-Head 拆与合 → FFN、残差、LayerNorm → Encoder 堆叠 → Adam 更新；
- *一个方法论*：形状三问——每个轴是什么、操作是否改变元素顺序、两个 Tensor 为什么能运算。

第十节把全部踩坑按共性归为五类：形状变换都是对“轴”的操作；一条广播规则统一了 mask、归一化与偏置；“是否沿轴求和”区分 `*` 与 `@`；Python 与 Tensor 的控制流规则不同；原地操作、no_grad 与类型对齐约束着训练循环中的副作用。

#quote[
  如果每个维度的语义都能解释清楚，Transformer 的代码就不是零散的语法堆砌，而是可以从线性代数结构推导出来的结果。
]

#line(length: 100%, stroke: 0.6pt)

== *笔者的话*

#quote[
  这篇笔记整理自练习记录：原始记录按踩坑的先后顺序写成，整理时改为按数据流与语法共性两条线索组织。文中列出的错误都在练习中实际出现过，可以作为实现同类组件时的自查参考。祝食用愉快～🤖
]

#line(length: 100%, stroke: 0.6pt)

== *参考资料*

- Attention Is All You Need：#link("https://arxiv.org/abs/1706.03762")[arXiv:1706.03762]
- Adam: A Method for Stochastic Optimization：#link("https://arxiv.org/abs/1412.6980")[arXiv:1412.6980]
- The Annotated Transformer：#link("http://nlp.seas.harvard.edu/annotated-transformer/")[nlp.seas.harvard.edu/annotated-transformer]
- PyTorch Broadcasting Semantics：#link("https://docs.pytorch.org/docs/stable/notes/broadcasting.html")[docs.pytorch.org/notes/broadcasting]
- PyTorch `torch.matmul` 文档：#link("https://docs.pytorch.org/docs/stable/generated/torch.matmul.html")[docs.pytorch.org/generated/torch.matmul]
- PyTorch `torch.nn.LayerNorm` 文档：#link("https://docs.pytorch.org/docs/stable/generated/torch.nn.LayerNorm.html")[docs.pytorch.org/generated/torch.nn.LayerNorm]

#line(length: 100%, stroke: 0.6pt)