#import "../index.typ": template, tufted

// 如需生成 RSS feed，必须填写 title、description 和 date 元数据
#show: template.with(
  title: "评估系统｜关于 Benchmark 的构建以及评估标准的建立",
  description: "总结构建 Agent 系统 Benchmark 与设计评估标准的实践经验：明确系统目标、拆解任务类别、设计可靠的标准答案与标注一致性、区分能力问题，以及评估准则、LLM-as-a-Judge 评估器与偏差控制的三层评估框架。",
  date: datetime(year: 2026, month: 10, day: 25),
  category: "实践与工具",
  lang: "zh",
)

= 评估系统｜关于 Benchmark 的构建以及评估标准的建立

#tufted.post-meta(
  date: datetime(year: 2026, month: 10, day: 25),
  tags: ("评估系统", "Benchmark", "Agent"),
)

#tufted.margin-note[
  *阅读提示*：最近做项目的时候负责了对我们的 Agent 系统的 Benchmark 的构建任务，以及后续的基于 benchmark 的评估器的评估标准的设计和迭代修正。这里打算系统性地总结一些经验。祝食用愉快～🎂

  （PS：一星期前是我的生日，在这里悄悄祝自己生日快乐，如果有读者读到这里，也可以悄悄给我默念一句生日快乐，嘿嘿）
]

#line(length: 100%, stroke: 0.6pt)

== *引言*

#quote[
  Benchmark 是什么？
]

我总结一下就是：评估某个系统的某方面能力的标准数据基准，围绕着特定领域而专门构建的多样化标准数据集，一般以问题-答案的 pairs 形式展示。可以理解成一份出给测试系统的试卷，附上标准答案。

有了这个 benchmark 之后，一个系统就可以根据 Benchmark 的数据得到一个结果，那这个结果是好是坏呢？

所以这个时候，我们需要一个针对这个 benchmark 结果的评分方式，怎么合理的给基于特定 benchmark 的系统答案给出恰当的分数？说实话，这是另一方面的事情。

因此：我认为完整的 benchmark 的任务分为 2 大块——

+ 怎么构建 benchmark？
+ 怎么根据系统的答案基于 benchmark 来给出一个合理的评分准则？

这构成了我们接下来需要讨论的关键。以下是我个人在做这些内容时候的经验，涉及到一些论文参考时，我会明确指出。

#line(length: 100%, stroke: 0.6pt)

== *Benchmark 的构建*

首先要构建 benchmark，我们需要明确自己的任务系统的目标是什么 🎯

思考一下当我们用很多的开源的现成的 benchmark 的时候，会怎么去寻找相应的 benchmark。

对的，当然是从这个任务涉及到的领域去寻找，这是人之常情。而且如果已经有了现场的 Expert 做出来的标准集之后呢，一般就不大想去费力自己构建一个了。

毕竟现成的大型开源集会带来以下的 advantages：

+ 很可能存在其他的系统使用过该集进行评估，这是一个横向比较的机会，来突出这个新的系统的优势，展现自己的创新点在哪里
+ 现成的标准集进行测试用途通常可以帮助发现一些自己原先系统存在的问题，在进一步投入更多的测评沉没成本之前就及时刹车，避免更大的时间 token 资源的浪费。
+ 对现成标准集的测试有助于了解这个领域的 benchmark 的构建的形式和方法，不管是之后在这个基础上做 fine-tuning 类似的改进或者是重头自己手搓一个出来，都有经验执行上的优势

但是实际上，面对论文的多样性的要求，一般来说 benchmark 在特化的任务上很难完全使用一个原封不动的标准去跑，所以这个时候就需要有一些 benchmark 构建改造的经验。

为什么说这非常需要 HITL 类似的参与？以往很多的 benchmark 都是需要专家去构建的，现在就算有了 ai，它难以代替我们对于一个 benchmark 客观的好或者不好的评价，这是很微妙的。

所以学习怎么去合理构建一个 benchmark 同时评估它的好坏是很重要的。

那么闲话少说，我们现在正式开始分享：

以下我会拿构建一个医学 Agent 系统作为例子。

=== *一、明确系统目标*

在开始收集题目之前，先写出一句可以验证的目标。

例如：

#quote[
  本 benchmark 用于评估大模型 Agent 在生物医学数据库及知识图谱环境中，完成实体标准化、多源信息检索、多跳关系推理、证据溯源和数据分析任务的能力，并考察其正确性、鲁棒性、效率与结果可重复性。
]

这个目标应该能够指导后续所有设计，我们将围绕着这个目标来搜集数据与制定内容。

=== *二、定义任务类别*

我听过一个故事，跑步冠军分享自己为什么能够坚持跑完整个马拉松，它说它将目标分成了一个一个小目标，这样终点就不是那么遥不可及的了。

每一个小目标不难完成，但最终很清晰地指向了终点。

评价一个系统和这个有异曲同工之妙：你不能指望一个任务一个标准就全面衡量出一个系统的特点，发现它的优势和劣势，就像不能指望见一两面就概括了一个完整的人的特点。

所以，为了做一个客观公正的评论家，我们需要把上面的目标拆解成合理的几个小任务来设计与实施。

比如：

- 任务 A：实体识别、规范化与链接：给出实体名称、别名、缩写或存在歧义的术语，要求 Agent 找到标准实体 ID，并说明匹配依据。主要测量：实体链接正确率、标准 ID 准确率、歧义处理能力。
- 任务 B：数据库导航与查询执行：要求 Agent 查找特定记录、阅读元数据、理解查询接口，必要时编写 SQL、SPARQL 或 Python 代码，取得目标结果。主要测量：查询执行成功率、返回记录正确率、工具调用恰当性。
- 任务 C：多跳关系推理与多源整合：例如，需要从疾病出发，经由表型、基因或其他实体，找到满足条件的关联路径，并整合不同数据源的证据。主要测量：关系精确率和召回率、路径正确率、跨数据源整合准确率。
- 任务 D：数据分析与质量控制：要求 Agent 识别重复记录、命名不一致、缺失关系、类型错误，或者针对图谱回答统计问题并给出可以复现的分析脚本。主要测量：问题检测的 Precision/Recall、分析结果与标准输出的一致性、脚本执行成功率。
- 任务 E：证据核验与溯源要求：Agent 为每个关系提供来源、记录 ID、版本信息或原始文献证据，区分直接证据、间接证据和没有证据支持的推断。主要测量：证据正确率、来源覆盖率、无依据关系的比例。

说实话上面已经设计的有些过分复杂了，针对像 Agent 这样的系统，我提出的评估的大方向就是：

+ 答案的准确性：智能体是否可以准确的得出我们 benchmark 的答案，以及这个答案的质量如何，覆盖度怎么样？
+ 执行的稳定性：是否最终得到的答案在统计学可以解释的合理范围内，是否多次运行无代码报错，程序失败，流程组件是否完整通畅运行。还有一个点就是工具的成功调用，是否在合适的 point 触发检索功能，这是 Agent 的一个独有的点。以及 API 的模型调用应答的持续性。
+ 证据链真实性以及推理链路可见性：得到的答案的 source 时有真实来源 support 的，推理的链路 CoT 是可信的，有逻辑的，不存在 skip 跳步的情况。

我认为这是任务设计的主要大方向，其他的多是可以归纳至下方的小 parts。

=== *三、设计可靠的标准答案*

我们需要为后续评估准备好一个可以作为参考的正确答案

这里答案的设计涉及几个问题：

+ 很多任务不一定只有一个正确答案。如果同一目标存在多个合法路径、不同但等价的标准术语，必须明确允许哪些结果，否则会错误惩罚正确但表达不同的模型。
+ 标准答案不等于绝对科学真理。当你的 benchmark 基于特定知识图谱或某个公开数据库构建时，首先测量的是 Agent 在指定知识源和版本下的任务表现。换句话说，要明确导致差异的源头到底是谁，不要出现莫须有的冤案。

==== *其他问题：答案标注*

怎样保证标注可靠？

一般的流程如下：

+ 第一位标注者独立确定答案与证据
+ 第二位标注者独立核验，不直接照抄第一位的结论
+ 计算一致性，对不一致条目进行专家仲裁
+ 将仲裁结果写回标准答案，并保存修改记录

（典型的三人仲裁打分，有点像高考改卷对吧 😂）

对不同类型的标签，评价标注的一致性可以选择不同的统计量。

- 名义分类标签可以考虑 Cohen's kappa；多标注者或存在缺失评分时可考虑 Krippendorff's alpha。
- 有序评分可考虑加权 kappa。
- 连续分值的一致性可考虑 ICC。

即便最终使用自动评价器，也要对一部分输出建立独立的人类评分集，并检查评价器与人工标准的一致性。这是一个很重要的校准。

==== *区分能力的问题*

怎样避免 Benchmark 失去区分能力？

这是大模型评价的普遍问题。

如果所有模型都接近 100\%，说明测试可能过于简单，或者容易通过记忆命中；如果所有模型都接近 0\%，则可能是任务过难、工具环境不合理或标准答案存在问题。

benchmark 增加区分程度可以采用类似的思路：任务在过程上具有挑战性，验收标准更加清楚。

或者是等到后面讲的，评估标准的提高以及特别处理。

==== *总结一下大致的评估维度*

第一，目标能力是否明确？\
第二，答案是否可信？\
第三，结果是否有区分度？\
第四，评价是否稳定？\
第五，失败是否可以诊断？

#line(length: 100%, stroke: 0.6pt)

== *评估器与评估准则*

论文参考：

+ Benchmarking large language models for end-to-end clinical support in traditional Chinese medicine，Expert Systems With Applications，2026
+ TCM-BEST4SDT：A benchmark dataset for evaluating Syndrome Differentiation and Treatment in large language models，Scientific Data，2025

这里的原则其实还是一样的，评估一个系统在 benchmark 上面表现的好坏，其实需要我们围绕它在特定领域上的任务的表现来展开。从而设计出一套合乎标准的打分方式。

一个合理的顺序是：先定义什么叫完成得好，再设计如何验证，最后检验验证方法本身是否可靠。

- 第 1 层：评估准则（Evaluation Criteria）用于定义任务质量：哪些结果正确、哪些错误、什么情况可以部分得分、哪些错误不能被其他优点抵消。
- 第 2 层：评估器（Evaluator / Judge）按准则检查 Agent 的最终答案、实际执行结果、工具调用记录和证据来源，并输出分数及失败原因。
- 第 3 层：评估器验证（Meta-evaluation）检查评估器是否与专家判断一致，是否存在系统性偏差，以及在合理的输入变化下是否稳定。

这里的评估流程非常清晰，只是许多论文其实更加啊注重的是前面 2 层内容，第 3 层总是不那么被重视，也许确实是因为大模型现在太过于强大了 hhhhh。于是只做多次波动性测试就当作真实值的答案了。

=== *评估准则*

这几乎是最重要的部分，也是可以对分数操作性最大的部分，所以这一部分的设计就显得至关重要。

每项准则至少需要具备四个部分：

- 判断对象：具体检查什么。
- 正确标准：什么结果算正确。
- 错误定义：哪些情况算错误或部分正确。
- 判定方法：怎样从原始输出中判断它是否满足标准。

例如：

#table(
  columns: (1fr, 1.3fr, 1.3fr, 1fr),
  align: (left, left, left, left),
  table.header([*评价维度*], [*核心问题*], [*推荐指标*], [*主要评价方法*]),
  [任务结果正确性], [最终结果对不对？], [Accuracy、Precision、Recall、F1], [程序校验],
  [结果完整性], [是否遗漏必要实体、关系或分析步骤？], [Coverage、Recall], [程序校验],
  [证据可靠性], [引用的证据是否真实，是否支持结论？], [Evidence Precision、支持率、无依据断言率], [规则 + 专家或 LLM],
  [工具使用质量], [是否正确选择工具、传递参数并处理结果？], [工具执行成功率、调用错误率], [日志与环境检查],
  [过程正确性], [关键步骤是否完成，步骤间的输入输出是否匹配？], [关键步骤通过率、路径合法率], [程序 + 轨迹核验],
  [鲁棒性], [合理改变输入后是否仍能完成任务？], [配对任务成功率变化], [程序化压力测试],
  [效率], [是否花费过多时间、调用或计算资源？], [延迟、Token、工具调用次数、成本], [自动统计],
  [可重复性], [同样条件下能否再次得到合格结果？], [重复成功率、分数方差], [多次执行],
)

一个评价维度就会对应一些分数指标，同时需要相应的评分器依照一定的评价方法来评分。

=== *评估器*

评估器典型的就是专家评估以及大模型评估。

鉴于大家现在基本都是用大模型做评估，我这里就只对大模型评估做一些阐述。

LLM-as-a-Judge 的评估方式要根据 LLM 具体的特点来设计评估指标：

==== *1. 不要让裁判只给一个整体分数*

更合理的做法是将任务拆分成多个独立维度，每个维度都定义明确的评分锚点：

```text
示例：解释质量评分表

维度 A：事实正确性

0 分：核心结论错误或出现关键事实错误。

1 分：只有部分事实正确，存在影响结论的错误。

2 分：核心事实正确，存在少量非关键问题。

维度 B：证据支持

0 分：缺少有效证据，或证据不能支持结论。

1 分：有部分相关证据，但论证不完整。

2 分：关键结论均有可核查证据支持。

维度 C：任务要求覆盖

0 分：遗漏大部分必需输出。

1 分：完成部分要求，但缺少关键项。

2 分：覆盖所有必需输出。
```

==== *2. LLM 裁判提示词——prompt*

这个至关重要。明确规定 LLM 的 role，input，output，rule，fomat，使得这个流程程序化规范化，给到一个独特的的 persona。

如：

```text
# Role

You are an independent evaluator for a biomedical database and knowledge-graph agent benchmark.

# Inputs

- Task specification: {{task_specification}}
- Gold-standard answer and accepted alternatives: {{gold_standard}}
- Authoritative evidence records: {{gold_evidence}}
- Agent final output: {{agent_output}}
- Observable execution trace and tool results: {{execution_trace}}
- Scoring rubric: {{scoring_rubric}}

# Evaluation Rules

1. Evaluate each criterion independently according to the supplied rubric.
2. Treat the task specification and the authoritative benchmark records as the reference standard. Do not invent missing facts or evidence.
3. Distinguish a scientifically plausible statement from a statement actually supported by the specified evidence.
4. Verify cited record identifiers against the supplied records. Do not assume that a citation supports a claim merely because it exists.
5. Evaluate only observable outputs, tool calls, execution records, and submitted explanations. Do not infer the agent's hidden internal reasoning.
6. Award partial credit only when explicitly permitted by the rubric.
7. Do not reward verbosity, confident wording, or formatting unless explicitly required by the criteria.
8. If the reference answer is ambiguous or the supplied evidence is insufficient to determine correctness, flag the issue rather than inventing a verdict.

# Output

Return valid JSON containing:

- task_id
- criterion_scores
- evidence_for_each_judgment
- identified_errors
- hard_failure_flags
- uncertainty_flag
- final_score
- scoring_rationale

Every score must be justified by observable evidence and the predefined rubric.
```

==== *3. Bias*

LLM 裁判有时会偏袒某些答案，怎么防止呢？

这种 bias 有时是相当隐蔽的，让我们看看几种和相应的解决办法：

- 长度偏差：保持事实与证据相同，将同一答案改写为长版和短版
- 位置偏差：对两个待比较的答案交换展示顺序
- 名称偏差：隐去模型名称，避免裁判知道答案来自哪个系统
- 证据偏差：给出措辞流畅但缺少证据的答案，与简洁但证据充分的答案进行比较

对于争议较大的开放式任务，可以采用两个独立裁判交叉评分，并对分歧样本交由专家复核。但交叉评分本身也不是可靠性的证明：两个裁判可能存在相同的偏差。那是一种很糟糕的情况。

最终的分数应该综合多维度的分数来给出一个综合的结果，作为对该系统的能力的判断。

#line(length: 100%, stroke: 0.6pt)

== *总结*

总之，以上只是一些小小的经验，算是自我总结之后的一些参考。只有一些非常基础的内容。

#line(length: 100%, stroke: 0.6pt)