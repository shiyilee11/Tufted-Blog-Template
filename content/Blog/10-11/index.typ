
#import "../index.typ": template, tufted

// 如需生成 RSS feed，必须填写 title、description 和 date 元数据
#show: template.with(
  title: "工具开发｜Tagger：一个极简 CSV/TSV 标注器的设计与实现",
  description: "记录 CSV/TSV 标注工具 Tagger 的完整开发过程：从需求与竞品调研、标签系统与四种标注范围的产品设计、Tauri 与纯浏览器版的技术选型，到 CSV 解析、标签持久化、快捷键的实现细节，以及“故意做小”的产品定位反思。",
  date: datetime(year: 2026, month: 9, day: 13),
  category: "实践与工具",
  lang: "zh",
)

= 图表示 ｜在异构图谱中对Node2Vec等方式的学习
#tufted.post-meta(
  date: datetime(year: 2026, month: 9, day: 13),
  tags: ("Node2Vec")
)
#figure(caption: "论文")[
  #image("imgs/1.png", width: 40%)
]
#tufted.margin-note[
  最近看了论文，关于怎么为症状通过图谱连接得到相关的预测的基因，以及构建一个s-g 的benchmark。这一篇分享论文里面用的图向量表示方式的一些具体细节。好久没更新，打算尝试新的表示方式。食用愉快～😁
]

== 问题：怎么通过间接关系来找想要的实体关联？

在这个论文的场景中：症状一般是缺失直接基因关联的内容的，一般的研究都是聚焦于疾病——基因，或者是症状——基因，或者是基因之间的互作（也就是PPI）

所以我们要怎么找到症状和基因之间的关联，通过这种间接的多跳关系

*答案就是通过异构图谱的向量表示学习，之后再将其匹配相似度 *

== 过程
我们先定义这个问题
#figure[
  #image("imgs/2.png", width: 40%)
]

=== 建立异构图

#figure[
  #image("imgs/3.png", width: 40%)
]

我们怎么看待这个算法：和word2vec对比，word具有上下文，而我们可以利用node来构建序列，此时节点会形成上下文

#figure[
  #image("imgs/4.png", width: 40%)
]

=== 随机游走

这是关键获得序列的方法

#figure[
  #image("imgs/5.png", width: 40%)
]

游走的方式受到多种制约，为了方便理解，我们做出一些简明定义

#figure[
  #image("imgs/6.png", width: 40%)
]

用数学表示这个下一步的概率即为：

#figure[
  #image("imgs/7.png", width: 40%)
]


偏置项有2种类型：

#figure[
  #image("imgs/8.png", width: 40%)
]

当有偏时，存在2种情况

#figure[
  #image("imgs/9.png", width: 40%)
]

#figure[
  #image("imgs/10.png", width: 40%)
]

对应的策略会达到平衡，通过调整参数p，q，可以获取不同类型的序列

== Skip-Gram训练

序列就是我们的训练样本，不过此时我们关注一个中心Node

#figure[
  #image("imgs/11.png", width: 40%)
]

写为机器学习的目标函数即为：

#figure[
  #image("imgs/12.png", width: 40%)
]

此时我们就利用这个训练模型梯度上升：因为为对数目标函数。之后产出对应的Node的Vector表示。


== 概率化和相似度匹配

#figure[
  #image("imgs/13.png", width: 40%)
]

得到一个gene的降序排名，这样我们就可以获得一个s-g的关联候选list了！

== 笔者的话

这是一个比较老的图学习表示算法。现在的算法会考虑关系的偏置，不过先理解这个，后续的原理基本上都是一致的，一通百通了
