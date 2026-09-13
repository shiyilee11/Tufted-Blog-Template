#import "../index.typ": template, tufted

// 如需生成 RSS feed，必须填写 title、description 和 date 元数据
#show: template.with(
  title: "工具开发｜Tagger：一个极简 CSV/TSV 标注器的设计与实现",
  description: "记录 CSV/TSV 标注工具 Tagger 的完整开发过程：从需求与竞品调研、标签系统与四种标注范围的产品设计、Tauri 与纯浏览器版的技术选型，到 CSV 解析、标签持久化、快捷键的实现细节，以及“故意做小”的产品定位反思。",
  date: datetime(year: 2026, month: 9, day: 13),
  category: "实践与工具",
  lang: "zh",
)

= 工具开发｜Tagger：极简 CSV/TSV 标注器的设计与实现

#tufted.post-meta(
  date: datetime(year: 2026, month: 9, day: 13),
  tags: ("工具开发", "Tagger", "产品设计"),
)
#figure(caption: "Tagger的彩虹橘子🌈好看吗？！")[
  #image("imgs/1.png", width: 40%)
]
#tufted.margin-note[
  *阅读提示*：在标注csv数据的时候感觉wps等等工具为什么没有快捷标记的方式，而且这些标记又没法给LLM读取，之后我咋处理，哎～所以自己按照想法搓了一个工具，至于为什么图标是个橙子，还是一个五彩斑斓的橙子，因为我喜欢吃，而且我突然想到了珍妮文斯特的“橘子不是唯一的水果”，就想要一个彩虹一样的🌈，打开Adobe搓了下，效果不错，嗯。祝食用愉快～🍊
]

#line(length: 100%, stroke: 0.6pt)

== *导言：为什么要做 Tagger*

事情的起因很简单：笔者经常拿到一个 CSV 或 TSV 文件，需要快速标注哪些数据重要、哪些需要复查、哪些可以直接丢掉。

市面上的 CSV 工具已经很多了——Excel、Numbers、各种在线表格。但它们都是为*编辑和计算*设计的。我想要的只是“快速给这一行打个标签”，而且要快，还要可以被LLM读取。

笔者需要的是：

```text
打开文件 → 选中数据 → 按个键 → 标签打上 → 导出给 AI
```

就这么简单，但没有一个工具是为这件事而生的。于是决定自己做一个。

#quote[
  橘子不是唯一的水果，但 Tagger 可以是五彩斑斓的 😊
]

#line(length: 100%, stroke: 0.6pt)

== *一：现有工具调研*

动手之前，我先看了 GitHub 上几个已有项目。

=== *1.1 Ceesvee*

这是一个功能非常完整的 CSV 编辑器，用 Tauri + Rust + React 构建。它已经把 CSV 编辑、筛选、快捷键、行书签、标签、备注、sidecar annotation 做得非常完整，还有数据清洗、验证、PII 检测等高级功能。功能路线大致是：

```text
CSV → 查看 → 编辑 → 筛选 → 清洗 → 验证 → Tag → Note → Export
```

越来越像一个完整的数据工作台。

=== *1.2 Rowly*

一个轻量的 macOS CSV 编辑器，强调快速打开和编辑，用 Electron 构建。

=== *1.3 Columnar*

一个纯粹的 CSV 查看器，明确说自己 `no editing`，专注于巨大 CSV/TSV 的浏览，用 Tauri 构建。

=== *1.4 结论：故意做小*

这些工具都很优秀，但没有一个是专门为“人工标注”设计的。Ceesvee 虽然有标签功能，但定位是数据工作台。

所以笔者决定定位为：

#quote[
  *一个为“快速人工标注表格数据”而生的极简 CSV/TSV Editor。*
]

核心流程就是：

```text
打开 → 看 → 选 → 快捷键 → 打标签 → 保存 → 给 AI
```

#line(length: 100%, stroke: 0.6pt)

== *二：设计*

=== *2.1 标签系统*

每个标签包含四个字段：

```json
{
  "name": "important",
  "definition": "High-confidence candidate that should be retained for downstream analysis.",
  "color": "#4A90E2",
  "shortcut": "cmd+1"
}
```

其中 `definition` 不是备注，而是*标签的语义定义*。这一点很重要：当标签数据导出给 LLM 时，模型需要知道 `important` 到底是什么意思。

=== *2.2 四种标注范围*

这是 Tagger 和普通 CSV 工具拉开差距的地方：

#table(
  columns: (1fr, 1.2fr, 1.4fr),
  align: (left, left, left),
  table.header([*范围*], [*触发方式*], [*示例*]),
  [Cell Tag], [选中一个单元格], [给 `BRCA1` 打上 `important`],
  [Row Tag], [选中一整行], [整行标记为 `review`],
  [Column Tag], [选中一列], [标记 `phenotype` 列的语义],
  [Dataset Tag], [不选任何内容], [标记整个数据集],
)

*用户不需要告诉软件“我要给什么打标签”*，软件根据当前选择自动判断：

- 选了一个 cell → Cell Tag；
- 选了一整行 → Row Tag；
- 选了一列 → Column Tag；
- 什么都没选 → Dataset Tag。

=== *2.3 快捷键优先*

快捷键是整个软件最重要的交互：

```text
T        → 进入标签模式
1        → 添加第 1 个标签
2        → 添加第 2 个标签
Shift+1  → 移除第 1 个标签
Esc      → 退出标签模式
```

用户可以连续操作：选行 → 按 1 → 选下一行 → 按 2 → 选下一行 → 按 3……这就是真正的“快速标注”。

=== *2.4 数据文件与标签文件分离*

这是一个关键设计决策。标签不写进 CSV 本身，而是保存在独立的 JSON 文件中：

```text
data.tsv
data.tsv.tags.json
```

这样做的好处：

+ CSV 保持干净，用任何工具打开都不会看到奇怪的标注；
+ 标签文件可以单独导入导出；
+ 大模型可以直接读取 JSON 理解标注含义。

=== *2.5 AI 导出格式*

专门设计了一个给 LLM 的导出格式：

```json
{
  "dataset": {
    "file": "data.tsv",
    "description": "Human phenotype-gene associations"
  },
  "tag_definitions": {
    "important": {
      "definition": "High-confidence candidate."
    }
  },
  "annotations": [
    {
      "row_id": "001",
      "tags": ["important"]
    }
  ]
}
```

这一步的本质：*把人的隐性判断，转换成机器可理解的显式知识。*



#line(length: 100%, stroke: 0.6pt)

== *三：技术选型*

=== *3.1 第一方案：Tauri + Rust + React*

参考 Ceesvee 和 Columnar 的技术栈，最初选择：

- *前端*：React 18 + TypeScript + Vite；
- *后端*：Rust + Tauri v2；
- *表格*：Glide Data Grid（虚拟化）；
- *状态管理*：Zustand。

理由：

+ Tauri 已经验证可以处理百万行 CSV；
+ 跨平台：macOS、Windows、Linux；
+ 比 Electron 轻量得多。

=== *3.2 架构设计*

```text
┌─────────────────────────────────┐
│ React / TypeScript (UI层)       │
│ - 表格虚拟化                    │
│ - 标签面板                      │
│ - 快捷键处理                    │
└───────────────┬─────────────────┘
                │
┌───────────────▼─────────────────┐
│ Tauri Commands (通信层)         │
│ - 文件读写                      │
│ - CSV/TSV解析                   │
│ - 标签持久化                    │
└───────────────┬─────────────────┘
                │
┌───────────────▼─────────────────┐
│ Rust Core (业务逻辑层)          │
│ - CSV/TSV解析器                 │
│ - 行身份管理                    │
│ - 标签数据结构                  │
└───────────────┬─────────────────┘
                │
          本地文件系统
```

=== *3.3 行身份管理*

不能用行号作为行的标识——用户排序后行号会变。参考 Ceesvee 的方案：

+ 优先使用用户指定的 ID 列；
+ 没有 ID 列时，使用 `SHA256(row content)` 作为行 ID。


=== *3.4 两版并行*

最终项目同时包含两个版本：

```text
tagger/
├── tagger.html              ← 浏览器独立版（零安装）
├── src/                     ← React 前端（桌面版 + 开发版）
├── src-tauri/               ← Rust 后端（桌面版）
└── package.json             ← Node.js 项目配置
```

浏览器版和桌面版共用同一套设计理念和 UI 风格，差别主要在运行环境和适用的文件大小。

#line(length: 100%, stroke: 0.6pt)

== *四：实现细节*

=== *4.1 CSV 解析*

手写了一个支持引号和换行的 CSV 解析器：

```javascript
function parseCSV(text, delimiter) {
  const lines = [];
  let current = '';
  let inQuotes = false;
  let row = [];

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"' && text[i+1] === '"') { current += '"'; i++; }
      else if (ch === '"') { inQuotes = false; }
      else { current += ch; }
    } else {
      if (ch === '"') { inQuotes = true; }
      else if (ch === delimiter) { row.push(current); current = ''; }
      else if (ch === '\n' || ch === '\r') {
        // 处理换行...
      }
      else { current += ch; }
    }
  }
  // ...
}
```

关键点：

- 自动检测分隔符（CSV 用逗号，TSV 用 Tab）；
- 支持字段内换行和双引号转义；
- 首行作为表头。

=== *4.2 标签持久化*

浏览器版使用 localStorage，以文件名为 key：

```javascript
function saveKey() { return 'tagger_' + filePath; }

function saveState() {
  localStorage.setItem(saveKey(), JSON.stringify({ tags, annotations }));
}
```

桌面版（Tauri）使用独立的 JSON 文件，由 Rust 端读写。

=== *4.3 标注逻辑*

核心逻辑很简单——根据当前选择判断标注范围：

```javascript
function applyTag(tagName) {
  if (selectedCell) {
    // 单元格标注
    annotateCell(selectedCell.row, selectedCell.col, tagName);
  } else if (selectedRows.size > 0) {
    // 行标注
    for (const ri of selectedRows) {
      annotateRow(ri, tagName);
    }
  } else {
    // 数据集标注
    annotateDataset(tagName);
  }
}
```

=== *4.4 快捷键处理*

用全局 keydown 事件监听，区分模式和上下文：

```javascript
document.addEventListener('keydown', (e) => {
  // T → 切换标签模式
  if (e.key === 't' && !e.metaKey && !e.ctrlKey) {
    toggleMode();
    return;
  }

  // 标签模式下的数字键
  if (mode === 'tag') {
    const num = parseInt(e.key);
    if (num >= 1 && num <= 9) {
      const tag = tagList[num - 1];
      if (e.shiftKey) removeTag(tag.name);
      else applyTag(tag.name);
    }
  }
});
```

=== *4.5 UI 设计*

UI 遵循“克制”原则：

```text
┌─────────────────────────────────────────────────────────┐
│  data.tsv                         🔍    🏷    Export     │
├─────────────────────────────────────────────────────────┤
│  #   Gene       Disease       Score       Tags          │
├─────────────────────────────────────────────────────────┤
│  1   BRCA1      Breast        0.92        🔵 important  │
│  2   TP53       Cancer        0.87        🟡 review     │
│  3   EGFR       Lung          0.76                     │
│  4   PTEN       Cancer        0.72        🔴 reject     │
├─────────────────────────────────────────────────────────┤
│  1,248 rows    3 selected    ⌘1 Important  ⌘2 Review   │
└─────────────────────────────────────────────────────────┘
```

右侧标签栏默认收起，点击展开。默认界面不要出现一大堆按钮。

#line(length: 100%, stroke: 0.6pt)




== *五：反思与收获*

=== *5.1 定位*


市场上已经有太多 CSV 编辑器。Tagger 的优势恰恰是“不做其他，只做标签”。这个定位让它和所有现有产品形成明确差异。

=== *5.2 技术选型*

最初选择 Tauri + Rust 是因为参考了 Ceesvee 的成功案例；当环境装不了 Rust 时，果断切换到纯浏览器方案。


=== *5.3 设计先行*

在写第一行代码之前，产品设计文档已经非常详细：

- 标签系统的设计；
- 四种标注范围；
- 快捷键映射；
- JSON 格式定义；
- UI 布局。

这些设计在实现过程中几乎没有大的修改

=== *5.4 做小*

砍掉功能比添加功能更需要判断力：

- ❌ 数据清洗
- ❌ 数据库
- ❌ SQL
- ❌ 多人协作
- ❌ 云端账户
- ❌ AI 集成
- ❌ 公式、排序、冻结窗格



=== *6.5 隐性判断变显式知识*

“把人的隐性判断变成机器可理解的显式知识”，可能是 Tagger 最有价值的设计理念。

用户给一行数据打上 `important` 标签，这个判断是隐性的；当标签有明确定义、导出格式结构化时，这个判断就变成了显式的、可传递的知识。这比“AI 自动打标签”更有意义——人的判断是有语境的，AI 需要先理解这个语境。

#line(length: 100%, stroke: 0.6pt)

== *七：下一步*

Tagger 目前是原型阶段，我思考了一下未来的方向（如果有时间继续做的话.jpg）：

+ *AI 辅助标注*：人工标一部分，AI 预测剩余部分；
+ *协作功能*：多人标注同一文件；
+ *高级导出*：更多格式、自定义模板；
+ *性能优化*：Web Worker 解析、虚拟化渲染；
+ *更多文件格式*：Excel、JSON、Parquet。



#line(length: 100%, stroke: 0.6pt)


== *笔者的话*

  橘子不是唯一的水果，但 Tagger 可以是五彩斑斓的 😊 这个项目从想法到能用的原型花的时间很短  

项目地址：#link("https://github.com/your-username/tagger")[github.com/your-username/tagger]
反馈邮箱：#link("mailto:1747819157@qq.com")[1747819157\@qq.com]



#line(length: 100%, stroke: 0.6pt)