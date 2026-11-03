# MenuBarExtra `.window` 样式下 ScrollView 的高度与滚动约束

- 关联 issue：`shuizhongyueming/port-menu#3`（Part of #1）
- 分支：`research/menubarextra-scroll`（只写文档，不开 PR）
- 代码锚点（本 worktree）：
  - `Porter/PorterApp.swift`：`MenuBarExtra { PortListView(updater:) } label: { ... }` + `.menuBarExtraStyle(.window)`
  - `Porter/Views.swift`：`PortListView` 根视图 `.frame(width: 340)`；`PortMainContentView` = `VStack(spacing: 0) { PortHeaderView; Divider(); 状态分支 / PortEntryListView }`；`PortEntryListView` 是**裸 `ForEach`** 直接 `.padding(.bottom, 6)`（无 `ScrollView`、无 `maxHeight`）；`PortRow` 用 `.onHover` 驱动 hover 按钮、`.contextMenu`、kill 时 `.blur/.offset` 滑出
- 目标平台：macOS 14.0+（`LSMinimumSystemVersion`），工程用 Xcode 27.2 / macOS 26.x SDK 构建

---

## 0. 证据分级与本次研究的限制（先读这段）

本报告把每条结论标成三档：

| 标记 | 含义 |
| --- | --- |
| **[文档]** | Apple 公开文档/发布说明写明的 API 语义 |
| **[社区]** | 开发者实测报告（SO / 论坛 / 第三方库 README），非官方承诺 |
| **[推断]** | 本报告作者基于 API 语义 + 本仓库代码的推理，**未经验证**，需要真机确认 |

**重要限制（必须记录）：** 本次研究运行环境里所有直连 HTTP 出站都被 SSRF/TUN 代理拦截（`developer.apple.com`、`github.com`、`stackoverflow.com` 均解析到 `198.18.x.x` 被拒），因此**没有抓取到任何页面原文**，只有搜索引擎侧返回的摘要。Apple 文档类结论来自对这些 API 的既有认知 + 摘要交叉印证，措辞可能与原文不完全一致；凡是只出现在"摘要里、我无法核对原文"的具体细节（例如某条 release note 的具体句子），一律标为 **[社区]/未核实**，不当作事实使用。第 5 节列出需要在真机/可联网环境补验的条目。

---

## 1. 逐题结论

### Q1. `.window` 样式窗口尺寸是怎么定的？受屏幕高度限制吗？超出会怎样？

**结论：**
- `.window` 对应 `WindowMenuBarExtraStyle`，语义是"以**类 popover 窗口**呈现内容，控件按窗口控件（而非菜单项）的风格布局" **[文档]**（`MenuBarExtraStyle.window`）。也就是说，它是一个真正的 `NSWindow`/`NSPanel`，由系统按状态栏按钮定位，而不是 `NSPopover`。
- 窗口尺寸 = **内容 ideal/intrinsic size**，宽度方向由内容决定（本仓库 `.frame(width: 340)` 固定住了宽度）**[文档 + 推断]**。SwiftUI 每次呈现时对内容做一次 fitting-size 测量，窗口随之调整；**没有任何文档化的 API 让你给这个窗口设置上限**（`.windowResizability(.contentSize)` 是 `Scene` 的 modifier，作用对象是 `WindowGroup`/`Window` 这类常规 Scene，不是 `MenuBarExtra`）**[文档]**。
- **受不受屏幕高度限制**：系统会把窗口放在状态栏按钮下方并限制在屏幕可视区域内（这是 AppKit 放置窗口的常规行为），但**"限制"的表现是裁剪内容，不是自动变滚动、也不是像 `NSPopover` 那样翻转箭头重定位**。`MenuBarExtra` 没有文档化的 `arrowEdge`/`preferredEdge`/自动翻转机制 **[推断：这是本报告最关键、也最需要真机验证的一条]**。
- 对本仓库的直接影响：`PortEntryListView` 是裸 `ForEach`，没有滚动容器，行数越多窗口越高，直到被屏幕边缘裁掉 —— **被裁掉的行既看不到也点不到，这是 issue 描述的"封顶"问题的根因** **[推断（代码事实）+ 文档]**。

**版本适用：** 14 / 15 / 26 行为一致，无文档化的版本差异。

---

### Q2. `.frame(maxHeight: X)` 能否真正产生滚动？需要 `.fixedSize` 或 `ScrollViewReader` 吗？

**结论（分三点，别混为一谈）：**

1. **`ScrollView` + `.frame(maxHeight:)` 在松散约束的父级里通常"能用"**：`maxHeight` 给出一个 flexible frame，`ScrollView` 在滚动轴上是贪婪的（接受父级给的全部空间），所以它会吃满 `maxHeight` 并开始滚动 **[文档：ScrollView 布局语义 + 推断]**。但**这里有一个循环依赖**：窗口高度由内容 fitting size 决定，而内容的 fitting size 又依赖窗口给的建议尺寸。当 `maxHeight` 大于内容高度时，窗口 = 内容高度（不滚动，正常）；当行数很多时，能否真的收到"被限到 X"取决于测量顺序，**在 `MenuBarExtra` 这种"窗口跟内容走"的场景里不可靠** **[推断]**。
2. **用 `.frame(height:)` 显式高度比 `maxHeight` 可靠**：显式高度切断了循环，窗口 fitting size 变确定，滚动区域高度固定 **[推断，工程惯例]**。推荐做法：`height = min(内容估算高度, 上限)`，即"内容少时按内容、内容多时封顶"，这正是 issue 要的语义。
3. **`.fixedSize(horizontal: false, vertical: true)` 不是滚动方案，是"取消滚动上限"的方案**：它让 view 采用内容理想高度，所以**加在 `ScrollView` 上语义上等于让 ScrollView 长到内容那么高 → 反而不滚动**。它之所以出现在社区报告里，是因为它修的是**另一个 bug**（首次打开后高度漂移/塌缩，见 Q6）**[社区]**（SO 77487268 的问答摘要）。⚠️ 这条把两个问题混在一起，是本议题最常见的误区，**不要同时用 `fixedSize` 和"要滚动"的需求**。
4. **`ScrollViewReader` 完全正交**：只用于程序化 `scrollTo(_:anchor:)`（比如 kill 后把视图滚回顶部），与高度约束无关 **[文档]**。是否需要，取决于你要不要在删除行后保持滚动位置。

**版本适用：** 同上；`fixedSize` 的"高度漂移"报告集中在 macOS 13–14 时代 **[社区]**，15 上未见到明确"已修复"的官方说明（见第 4 节 missing evidence）。

---

### Q3. 滚动区域内的现有交互会不会坏？

逐个说（都是本仓库真实代码）：

| 交互 | 是否会坏 | 说明 / 等级 |
| --- | --- | --- |
| `.onHover` 自定义 hover 按钮（`PortRow` 的 `isHovered`、`HoverButton`/`RowButtonStyle` 里的 `@State isHovered`） | **会**（部分坏） | `onHover` 的语义是"指针进入/离开该 view 的 frame 时回调" **[文档]**。但滚动时指针相对窗口不动、行在指针下移动，AppKit 往往**不会补发** enter/exit，导致"已经滚走的那一行仍然保持 `isHovered = true`"（Kill/Open 按钮一直显示、背景高亮卡住）**[社区：`onHover` 在 scroll/recycle 场景下丢 exit 事件是长期痛点；`onContinuousHover` 与 `NSTrackingArea` 常被当作替代]**。`LazyVStack` 复用会让情况更明显。修复：把 hover 状态**上提为单一 `hoveredID`**（谁 hover 谁覆盖），并在**滚动开始时强制清空**。 |
| `.contextMenu`（`PortRow`） | **基本不会坏**，但有边角 | 右键菜单本身在 `ScrollView` 里正常工作；需要 `.contentShape(Rectangle())` 才能整行可右键（本仓库**已有**，OK）**[文档 + 代码事实]**。边角：①菜单弹出期间行仍在滚动/动画，`withAnimation` 的 hover 动画会继续跑；②菜单是独立窗口，会与第 3 项的 tooltip `NSPanel` 抢层级（`.popUpMenu` level 面板可能压在菜单之上或干扰）；③`PortRow` 把 `.blur/.offset` 直接作用在行上，右键命中区域会跟着视觉位移，kill 动画期间右键目标漂移 **[推断]**。 |
| `FloatingTooltipAnchor` + `FloatingTooltipPanel`（独立 `NSPanel`） | **会** | 定位逻辑写在 `updateNSView(_:context:)` 里，只在 `isVisible` 变化时被调用。滚动**不改变任何 SwiftUI state** → `updateNSView` 不重跑 → 面板停在旧屏幕坐标，出现"tooltip 悬在空处"**[推断，基于代码 + `NSViewRepresentable` 更新语义]**。另外三个隐患：①`panel.level = .popUpMenu` 且 `orderFront(nil)`，`MenuBarExtra` 窗口关闭（Esc/点外部）时若该行没被 dismantle，**tooltip 会成为孤儿面板留在屏幕上**（`dismantleNSView` 只在视图被移除时触发）**[推断]**；②`NSHostingView` 每次 `show` 都重建 rootView，滚动中高频重排会有性能/闪烁风险；③header 的 tooltip（`HeaderControlButton`/`PortHeaderView`）不在滚动区，**不受影响，不用改**。修复方向：滚动时 `hide()`，或在滚动坐标系里订阅偏移变化重排，或对行内提示改用原生 `.help()`。 |

**版本适用：** `onHover` 丢事件在 13–26 都有报告；`onScrollPhaseChange`/`onScrollGeometryChange` 是 **macOS 15.0+**，**macOS 14.0 上不可用**，14 需要 `GeometryReader` + `PreferenceKey` 读 `minY` 的做法（骨架里给了双路径）。

---

### Q4. 滚动条在 `.window` 弹窗里可见/可用吗（trackpad + 鼠标滚轮）？

**结论：**
- 只要滚动区域**真的滚动**（Q2 成立），`ScrollView` 的滚动条遵循系统"显示滚动条"设置：默认 *根据鼠标或触控板自动* → overlay 滚动条在滚动时闪现后淡出；设为 *始终* 时是传统占宽滚动条 **[文档：macOS 外观设置语义]**。
- `MenuBarExtra` 窗口没有为滚动条预留 inset，overlay 指示器会**压在行的右边缘**；`PortRow` 右侧正好是 hover 才出现的 Kill/Open 按钮区域 → 滚动时容易视觉打架 **[推断]**。可用 `.scrollIndicators(.automatic)`（默认）/`.hidden` 配合 `.contentMargins(.trailing, 2, for: .scrollIndicators)` 调整，但 `contentMargins(for: .scrollIndicators)` 需要 **macOS 14.0+**（本工程 baseline 刚好满足）**[文档]**
- 触控板双指滚动在 `.window` 弹窗里可用是普遍经验，但**没有官方文档保证**；鼠标滚轮在"内容高度恰好等于可视高度"时无反应是正常现象（无溢出）**[文档语义 + 社区]**。**没有找到**"`.window` 样式下彻底无法滚动"的可复现通用 bug 报告 **[missing evidence]**。

**版本适用：** 26（Liquid Glass）上窗口背景/边缘观感变化可能影响 overlay 滚动条对比度，需实机看。

---

### Q5. 行数从多变少（kill 一台）时窗口高度的行为？

**结论：**
- 窗口会**重新按内容 fitting size 收缩**，且 SwiftUI **不会为窗口 frame 变化做动画**；你在 `PortRow.killWithAnimation()` 里对行做 `.offset/.blur` 的 `withAnimation`，**只动画视图内容，不动画窗口边框** → 观感是"行滑出后窗口啪地一下变矮"（跳变）**[推断，最关键的一条 UX 结论]**。
- 行数在"未封顶"区间内变化才会改窗口高度；一旦列表被 `height = 上限` 固定住（Q2 推荐方案），**kill 行不再改变窗口高度，跳变问题直接消失**（这也是"封顶"方案的附带收益）**[推断]**。
- 另外：收缩发生在指针可能仍位于旧行位置时，会叠加 Q3 的 hover 状态卡住问题 → 更需要在 `entries` 变化时清空 `hoveredID` **[推断]**。

**版本适用：** 全部版本；没有任何文档化 API 让你"平滑动画 MenuBarExtra 窗口高度"，只能靠拿到底层 `NSWindow` 手动 `setFrame(_:display:animate:)`（`MenuBarExtraAccess` 的 `.introspectMenuBarExtraWindow`）**[社区]**。

---

### Q6. 已知 SwiftUI bug 与替代方案代价

**已知问题（社区，均未在官方 release note 中得到确认）：**
1. **首次打开高度 ≠ 之后打开高度 / 高度塌缩**：`.window` + `ScrollView`，第二次打开高度变小；`maxHeight` 未能修好；报告者的 workaround 是 `.fixedSize(horizontal: false, vertical: true)`，代价是动画变差 **[社区：SO 77487268]**
2. **无法用 SwiftUI API 调整 `.window` 弹窗尺寸**；要改尺寸/允许拖拽改变大小，必须拿底层 `NSWindow`（`styleMask.insert(.resizable)` 或 `setFrame`）**[社区：SO 79127814 + `orchetect/MenuBarExtraAccess`]**
3. **打开/关闭状态无法用官方 API 观测**（`scenePhase` 在早期版本对 menu bar extra 不可靠），社区用窗口 introspection 或 event monitor 绕过 **[社区：damian.fyi 2022 文章 + MenuBarExtraAccess]**
4. 检索到的"macOS 15 release notes 修复了 window 样式下 `scenePhase`/`onAppear` 时序"这一说法**只出现在搜索摘要里，我无法核对原文，按未核实处理**（第 4 节）

**替代方案代价（`NSStatusItem` + `NSPopover` + `NSHostingView`）：**
- 换来：`contentSize` 完全自控、`behavior`（`.transient`/`.semitransient`/`.applicationDefined`）可选、箭头边可翻转、可自行决定外观与关闭策略 **[文档：NSPopover]**
- 付出：状态栏图标/高亮/右键菜单要自己搭；外部点击关闭要自己（或 `.transient`）；键盘焦点（输入框、Esc）要自己管；`NSPopover` 仍不适合"常驻面板"；`MenuBarExtra` 的 `@Environment(\.openWindow)`、`commands` 集成、`.environment(store)` 注入、Sparkle 的 `CheckForUpdatesView` 都要重新接线 **[推断：基于本仓库现有 `PorterApp` 结构]**
- `NSStatusItem` + 自建 `NSPanel`：控制力最强（可设 `level`、`canBecomeKey`、resizable、动画），代价是要自己实现定位（贴在状态栏按钮下方、多屏/刘海适配）、Space/全屏行为、可访问性 **[推断]**
- **结论**：对本项目（内容简单、行数有限、无文本输入）**不建议**换 AppKit 方案；`MenuBarExtra(.window)` + 固定高度滚动区 + hover/tooltip 修补足够。只有在"必须可拖拽改大小"或"必须精确动画窗口高度"时才值得付上面这些代价。

---

## 2. 三个具体坑的清单（可当 review checklist）

1. **`.onHover` 自定义 hover 按钮**
   - 坑：滚动后旧行 `isHovered` 残留；`LazyVStack` 复用加剧；`withAnimation` 在滚动中抖动。
   - 解法：状态单一化（`hoveredID`）+ 滚动即清空；需要更细粒度时用 `onContinuousHover`（无需 AppKit）或 `NSTrackingArea`（`NSViewRepresentable`）。
2. **`.contextMenu`**
   - 坑：菜单打开时行还在动画/tooltip 面板抢层级；kill 的 `.offset` 让命中区漂移；右键目标需要整行 `contentShape`（已有）。
   - 解法：菜单打开时禁用 hover 动画与 tooltip（在菜单内容 `onAppear` 里置 state）；kill 期间禁止交互（`.allowsHitTesting(false)`）。
3. **`FloatingTooltipAnchor`（独立 `NSPanel`）**
   - 坑：只由 state 变化驱动重排 → 滚动即错位；窗口关闭可能留下孤儿面板；每次 `show` 重建 `NSHostingView`。
   - 解法：滚动时 `hide()`（最省事）；或订阅滚动偏移重排；`panel.level` 用 `.floating` 而非 `.popUpMenu`（避免压过 context menu）；补 `NSWindow.didResignKeyNotification` / `NSWindow.willCloseNotification` 观察者兜底 `hide()`。

---

## 3. 推荐实现骨架（结构具体，不保证编译）

目标：宽度固定 340，列表区**内容少时按内容高、内容多时封顶滚动**，窗口高度不再随 kill 跳变。

```swift
// MARK: - 度量（集中一处，便于真机调参）
enum PortListMetrics {
    static let width: CGFloat = 340          // 与 PortListView 现有 .frame(width:) 对齐
    static let rowHeight: CGFloat = 58       // 8+8 padding + ~20 body + 6 spacing + ~15 caption + 1 divider
    static let maxListHeight: CGFloat = 520  // 期望上限
    static let minListHeight: CGFloat = 96

    /// 内容高度封顶：min(内容估算, min(绝对上限, 屏幕可用高 * 0.55))
    static func listHeight(rowCount: Int, screen: NSScreen?) -> CGFloat {
        let content = CGFloat(rowCount) * rowHeight + 6
        let screenCap = (screen?.visibleFrame.height ?? 800) * 0.55
        let cap = min(maxListHeight, screenCap)
        return max(minListHeight, min(content, cap))
    }
}

// MARK: - 列表：ScrollView + 显式高度
struct PortEntryListView: View {
    @Environment(PortStore.self) private var store
    @Binding var hoveredID: ActivePort.ID?     // hover 状态上提，避免逐行残留

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                    PortRow(entry: entry,
                            showTopDivider: index > 0,
                            hoveredID: $hoveredID)
                }
            }
            .padding(.bottom, 6)               // 注意：绑在 LazyVStack 上，而不是绑在 ForEach 上
            .background(ScrollOffsetObserver()) // 仅 macOS 14 兜底路径用
        }
        .frame(height: PortListMetrics.listHeight(rowCount: store.entries.count,
                                                  screen: NSScreen.main))
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
        // macOS 15+：滚动一开始就清 hover + 收 tooltip
        .modifier(ClearHoverOnScroll(hoveredID: $hoveredID))
        .onChange(of: store.entries.count) { _, _ in
            hoveredID = nil                     // Q5：行数变化时清状态，避免跳变后残留高亮
        }
    }
}

// MARK: - macOS 15+ / 14 双路径
struct ClearHoverOnScroll: ViewModifier {
    @Binding var hoveredID: ActivePort.ID?

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollPhaseChange { _, phase in
                if phase != .idle {
                    hoveredID = nil
                    FloatingTooltipPanel.shared.hide()
                }
            }
        } else {
            content.onPreferenceChange(ScrollOffsetKey.self) { _ in
                hoveredID = nil
                FloatingTooltipPanel.shared.hide()
            }
        }
    }
}

// MARK: - 行：hover 由父级驱动 + kill 期间禁止交互
struct PortRow: View {
    let entry: ActivePort
    let showTopDivider: Bool
    @Binding var hoveredID: ActivePort.ID?
    @State private var slidOut = false

    private var isHovered: Bool { hoveredID == entry.id && !slidOut }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showTopDivider { Divider().padding(.horizontal, 16) }
            /* ... 原内容不变；HoverButton 的显隐继续用 isHovered ... */
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { hoveredID = entry.id }
            else if hoveredID == entry.id { hoveredID = nil }
        }
        .allowsHitTesting(!slidOut)
        .contextMenu { /* 同现有；可在菜单内容 onAppear 里 hoveredID = nil */ }
    }
}

// MARK: - 骨架补充：让窗口高度确定的三种收口方式
// A) 首选：ScrollView 显式 height（上文）——窗口 fitting size 变确定，kill 不再改动窗口高度
// B) 需要"整个窗口高度可动画"时才引入依赖：
//    MenuBarExtraAccess: .introspectMenuBarExtraWindow { win in
//        var f = win.frame; f.size.height = desired; win.setFrame(f, display: true, animate: true)
//    }
// C) 需要用户可拖拽改大小：win.styleMask.insert(.resizable)（社区方案，非官方 API）
```

**改动面（相对当前代码）：**
1. `PortEntryListView`：裸 `ForEach` → `ScrollView { LazyVStack { ForEach } }`，加 `.frame(height:)`。
2. 顺手修一个现存小 bug：`.padding(.bottom, 6)` 现在挂在 `ForEach` 上，**是给每一行各加 6pt**，不是给整组加 —— 应挂到 `LazyVStack`。
3. `PortRow`：`@State isHovered` → 父级 `@Binding hoveredID`；`PortMainContentView` 持有该 state。
4. `PortRow.killWithAnimation()` 后 `hoveredID = nil`。
5. `FloatingTooltipPanel`：滚动/失焦/关窗时 `hide()`；`level` 从 `.popUpMenu` 降为 `.floating`（避免与 context menu 抢层级）。
6. `PortListView` 的 `.frame(width: 340)` 保留（用 `PortListMetrics.width` 统一常量）。

---

## 4. 必须真机验证的清单（本报告无法替代）

| # | 要验的事 | 怎么算通过 |
| --- | --- | --- |
| V1 | 超过屏幕可用高度的行数（本机 8/15/25 行）时，窗口是**裁剪**还是**滚动** | 能滚到最后一行 = 通过；行被切掉且无法滚动 = Q1 的"裁剪"结论成立 |
| V2 | `.frame(maxHeight:)` vs `.frame(height:)` 两者实测差异 | 哪个能稳定产生滚动条与滚动位移 |
| V3 | macOS 14 上首次打开 vs 第二次打开的高度是否不同（Q6 bug 是否仍在） | 高度一致 = 该 bug 在 14.x 已不复现 |
| V4 | 触控板双指 / 鼠标滚轮 是否能滚动；`onScrollPhaseChange` 是否触发 | 两种输入都能滚 |
| V5 | 系统设置"显示滚动条 = 自动 / 始终"两种情况下指示器可见性与遮挡 | "始终"时行右侧按钮不被压住 |
| V6 | 滚动过程中 hover 按钮是否残留、tooltip 是否错位/残留、关窗后是否留下孤儿面板 | 三者在滚动后都自动清理 |
| V7 | kill 一台后窗口是否跳变（当前实现）/ 封顶后是否不再跳变 | 封顶方案下窗口高度不变 |
| V8 | 小屏（如 800pt 高的显示器）+ 多行时的可用高度系数 0.55 是否合适 | 列表底边不越过 Dock/屏幕下缘 |
| V9 | macOS 26（本机 SDK）上窗口背景/边缘（Liquid Glass）对滚动条与 tooltip 对比度的影响 | 视觉可读 |
| V10 | 若考虑引入 `MenuBarExtraAccess`：SPM 依赖 + Sparkle 签名/公证链路是否受影响 | 构建与发布流程不变 |

---

## 5. 参考来源

- Kept（Apple 文档，作为 API 语义依据；**本次未能抓取原文，仅按 API 语义引用**）
  - `MenuBarExtra` — https://developer.apple.com/documentation/swiftui/menubarextra
  - `MenuBarExtraStyle.window` / `WindowMenuBarExtraStyle` — https://developer.apple.com/documentation/swiftui/menubarextrastyle/window
  - `ScrollView` — https://developer.apple.com/documentation/swiftui/scrollview
  - `onHover(perform:)` / `onContinuousHover` — https://developer.apple.com/documentation/swiftui/view/onhover(perform:)
  - `NSPopover` — https://developer.apple.com/documentation/appkit/nspopover
  - macOS 15 Release Notes — https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes （**未能核对原文，相关说法按未核实处理**）
  - WWDC22 "Meet SwiftUI for macOS"-系列 session（`MenuBarExtra` 引入）— https://developer.apple.com/videos/play/wwdc2022/10061/
- Kept（社区实测，明确标注为非官方）
  - SO 77487268 — "MenuBarExtra with .window style: Layout issue with ScrollView"（首次打开高度漂移 + `fixedSize` workaround）— https://stackoverflow.com/questions/77487268/
  - SO 79127814 — "Resizing a MenuBarExtra Window"（必须拿底层 NSWindow）— https://stackoverflow.com/questions/79127814/
  - `orchetect/MenuBarExtraAccess`（window introspection / 显示隐藏 binding）— https://github.com/orchetect/MenuBarExtraAccess
  - damian.fyi — 检测 `.window` 样式 MenuBarExtra 的打开状态（2022-12-29）— https://damian.fyi/swift/2022/12/29/detecting-when-a-swiftui-menubarextra-with-window-style-is-opened.html
- Rejected/deprioritized
  - techqa.club / m.php.cn / volcengine 等镜像与聚合站：内容为 SO 搬运且带广告，无新增信息
  - 各类 "SwiftUI hover 教程" 聚合页：与 macOS 滚动场景无关
  - 搜索结果中出现的 `developer.apple.com/videos/play/wwdc2026/...` 之类引用：**无法确认存在，已丢弃，不作为依据**

## 6. Missing evidence（明确未解决）

1. Apple 官方对 `.window` 窗口"是否 clamp 到 `NSScreen.visibleFrame`、以及 overflow 时是裁剪还是重定位"**没有任何书面说明** —— 只能实机观测（V1）。
2. `.frame(maxHeight:)` 在 `MenuBarExtra` 测量循环中的确切行为（先测窗口还是先测内容）没有源码/文档依据（V2）。
3. macOS 15 / 26 是否修复了 SO 77487268 的高度漂移：**未找到官方确认**，检索摘要提到 release note 修复了 `scenePhase`/`onAppear` 时序，但**原文未核对**（V3）。
4. overlay 滚动条在 `MenuBarExtra` 窗口里的具体绘制层级与遮挡行为无文档（V5）。
5. `FloatingTooltipPanel` 在窗口关闭时是否真的会变孤儿：需实机（V6）。
6. 本报告所有 Apple 文档结论均**未经原文逐字核对**（见第 0 节），需要联网环境补一次引用校对。
