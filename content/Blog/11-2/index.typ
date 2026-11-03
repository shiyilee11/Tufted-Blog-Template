
#import "../index.typ": template, tufted

// 如需生成 RSS feed，必须填写 title、description 和 date 元数据
#show: template.with(
  title: "信息论 | 熵与信息论基础",
  description: "Node2Vec",
  date: datetime(year: 2026, month: 11, day: 2),
  category: "机器学习",
  lang: "zh",
)

= 信息论 | 熵与信息论基础
#tufted.post-meta(
  date: datetime(year: 2026, month: 11, day: 2),
  tags: ("信息论","熵")
)
#figure(caption: "引言")[
  #image("imgs/1.png", width: 40%)
]


#line(length: 100%, stroke: 0.6pt)

#tufted.margin-note[信息论学习内容简单记录，关于熵相关，基础又重要。食用愉快～😂（其实不太好食用，权当存放笔记吧）

]

```
一层 · 信息的度量
世界存在不确定性，我们如何量化它？
自信息 → 熵 H → 联合熵 → 条件熵



第二层 · 模型的学习
模型学习的概率分布与真实分布有什么差异？
交叉熵 → KL 散度 → 最大似然估计



第三层 · 信息的关联
知道一个变量，能减少另一个变量多少不确定性？
互信息 I → 条件互信息 → 链式法则



第四层 · 信息的处理(**)
信息经过模型提取、压缩和转换后会发生什么？
数据处理不等式 → 充分统计量 → 信息瓶颈



第五层 · 信息的极限(**)
信息可以压缩到多少？通过噪声后还剩多少？
AEP → 信源编码 → 信道容量 → 率失真 → Fano
```

== 引言：一个例子


如图是个二分类任务。这里可以讨论两种模型的不确定度
#figure[
  #image("imgs/2.png", width: 40%)
]

=== 自信息量

#figure[
  #image("imgs/3.png", width: 40%)
]

=== 熵的概念

#figure[
  #image("imgs/4.png", width: 40%)
]

=== 性质


#figure[
  #image("imgs/5.png", width: 40%)
]

== 其他熵（多分布）

#figure[
  #image("imgs/6.png", width: 40%)
]

=== 互信息

#figure[
  #image("imgs/7.png", width: 40%)
]


=== 证明与对称性

#figure[
  #image("imgs/8.png", width: 40%)
]

=== 一个典型例子

#figure[
  #image("imgs/9.png", width: 40%)
]
=== 链式法则
#figure[
  #image("imgs/10.png", width: 40%)
]


== 其他推导相关

=== Jensen不等式
#figure[
  #image("imgs/11.png", width: 40%)
]

=== DPI与充分统计

#figure[
  #image("imgs/12.png", width: 40%)
]


== 笔者的话

基础的信息论知识，涉及到熵相关。可以有助于理解ai目标函数的交叉熵等内容
