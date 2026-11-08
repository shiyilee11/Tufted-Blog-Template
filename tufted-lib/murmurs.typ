// 作者碎碎念：显示在 Blog 首页右上角的挂件。
//
// 使用方法：只编辑下面的 murmurs 列表，最新的一条放在最上面。
// - date 填 datetime(...)；
// - body 里可以写 Typst 内容（加粗、链接、emoji 都可以）；
// - 页面收起时只显示第一条，点开后按列表顺序显示全部历史。
//
// 在其他页面（比如文章页）也想显示的话，加两行即可：
//   #import "../../tufted-lib/murmurs.typ": murmur-widget
//   #murmur-widget()

#let murmurs = (
  (
    date: datetime(year: 2026, month: 11, day: 8),
    body: [信息论第二章已更新！！今天是卫戍协议回归的日子～😋],
  ),
  (
    date: datetime(year: 2026, month: 11, day: 5),
    body: [新增了日语学习板块，来督促我吧],
  ),
)

/// 渲染右上角的碎碎念挂件（不需要参数）。
/// 依赖 assets/custom.css 中的 .murmur-widget 样式。
#let murmur-widget() = {
  if murmurs.len() == 0 {
    return
  }

  let latest = murmurs.first()

  html.elem(
    "details",
    attrs: (class: "murmur-widget",),
    {
      // 收起状态：标签 + 最新一条
      html.elem(
        "summary",
        attrs: (class: "murmur-summary",),
        {
          html.span(class: "murmur-title", [💬 碎碎念])
          html.span(class: "murmur-latest", latest.body)
        },
      )

      // 展开状态：全部碎碎念
      html.div(
        class: "murmur-panel",
        {
          for m in murmurs {
            html.div(
              class: "murmur-item",
              {
                html.elem(
                  "time",
                  attrs: (class: "murmur-date", datetime: m.date.display()),
                  m.date.display(),
                )
                html.div(class: "murmur-body", m.body)
              },
            )
          }
        },
      )
    },
  )
}