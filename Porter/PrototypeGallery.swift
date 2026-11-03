// PROTOTYPE — 丢弃用，不要合并。
//
// 回答两个视觉问题（issue #5）：
//   1. 列表封顶几行、`›` 之外还有没有更好的分隔符；
//   2. `仓库 › 包路径` 在 340pt + `.tail` 截断下的观感。
//
// 刻意不做：真 monorepo 解析（那是 issue #4 的事）。这里只有假数据，
// 目的就是把字符串形态和高度摆到眼前。
//
// 触发方式（不进正式 UI）：
//   PORTER_PROTOTYPE=export  → 渲染若干变体到 /tmp/porter-proto/*.png 后退出
//   PORTER_PROTOTYPE=1       → 打开一个可交互的窗口，自己滚、自己切变体

import AppKit
import SwiftUI

enum PrototypeFixtures {
    /// 覆盖三种形态：单包仓库、monorepo 包、超长包名（用来触发截断）。
    static func entries(separator: String = "›", repoFirst: Bool = true, count: Int = 12) -> [ActivePort] {
        let specs: [(repo: String, path: String, branch: String, port: UInt16)] = [
            ("shuizhongyueming.github.io", "", "main", 4321),
            ("my-repo", "apps/web", "feat/monorepo-naming-and-scroll", 3000),
            ("my-repo", "apps/api", "feat/monorepo-naming-and-scroll", 4000),
            ("my-repo", "packages/ui", "main", 6006),
            ("my-repo", "packages/shared-types", "main", 6007),
            ("acme-console", "apps/dashboard-with-a-very-long-package-name", "release/2026-11", 5173),
            ("acme-console", "services/billing", "release/2026-11", 8080),
            ("game-recon-runs", "", "main", 9000),
            ("threejs-rocket-fling", "", "main", 5174),
            ("xyx-vm", "packages/runtime", "fix/native-intl", 9229),
            ("xyx-vm", "packages/cli", "fix/native-intl", 9230),
            ("gc-2026-10", "packages/c2-utils", "main", 3001),
        ]

        return specs.prefix(count).enumerated().map { index, spec in
            let name: String
            if spec.path.isEmpty {
                name = spec.repo
            } else if repoFirst {
                name = "\(spec.repo) \(separator) \(spec.path)"
            } else {
                name = "\(spec.path) \(separator) \(spec.repo)"
            }
            return ActivePort(
                port: spec.port,
                pid: Int32(90000 + index),
                projectName: name,
                branch: spec.branch,
                startTime: Date().addingTimeInterval(-Double(index + 1) * 412)
            )
        }
    }
}

// MARK: - 封顶滚动容器（原型版）

/// `limit` = 最多显示几行；行高用实测值，避免猜。
struct PrototypeCappedList: View {
    let entries: [ActivePort]
    let maxRows: Int
    let rowHeight: CGFloat

    // +6 = 列表底部的 .padding(.bottom, 6)，否则最后一行会被切掉半截。
    private var contentHeight: CGFloat { CGFloat(entries.count) * rowHeight + 6 }
    private var capHeight: CGFloat { CGFloat(maxRows) * rowHeight + 6 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    PortRow(entry: entry, showTopDivider: index > 0)
                }
            }
            .padding(.bottom, 6)
        }
        .frame(height: min(contentHeight, capHeight))
        .environment(PortStore.shared)
    }
}

// MARK: - 画廊

struct PrototypeVariant: Identifiable {
    let id: String
    let title: String
    let separator: String
    let repoFirst: Bool
    let maxRows: Int
    let count: Int
    let scheme: ColorScheme

    var fileName: String { "\(id)-\(scheme == .dark ? "dark" : "light").png" }
}

enum PrototypeVariants {
    static let colorSchemes: [ColorScheme] = [.light, .dark]

    static func make(schemes: [ColorScheme]) -> [PrototypeVariant] {
        var result: [PrototypeVariant] = []
        func add(_ id: String, _ title: String, _ sep: String, _ repoFirst: Bool,
                 _ rows: Int, _ count: Int) {
            for scheme in schemes {
                result.append(PrototypeVariant(
                    id: id, title: title, separator: sep, repoFirst: repoFirst,
                    maxRows: rows, count: count, scheme: scheme
                ))
            }
        }

        // 分隔符 × 顺序
        add("A", "`›` 8 行", "›", true, 8, 12)
        add("B", "`·` 8 行", "·", true, 8, 12)
        add("C", "`/` 8 行", "/", true, 8, 12)
        add("D", "路径在前 `apps/web › my-repo`", "›", false, 8, 12)
        // 上限行数
        add("E", "`›` 6 行", "›", true, 6, 12)
        add("F", "`›` 10 行", "›", true, 10, 12)
        // 不满一屏（高度自适应）
        add("G", "`›` 8 行上限 · 只有 3 条", "›", true, 8, 3)
        return result
    }
}

struct PrototypeGallery: View {
    let rowHeight: CGFloat
    @State private var selected = "A"

    private var variants: [PrototypeVariant] { PrototypeVariants.make(schemes: [.light]) }

    private var current: PrototypeVariant {
        variants.first { $0.id == selected } ?? variants[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $selected) {
                    ForEach(variants) { variant in
                        Text(variant.title).tag(variant.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Spacer()
                Text("\(current.count) 条 · 上限 \(current.maxRows) 行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)

            Divider()

            PrototypeCappedList(
                entries: PrototypeFixtures.entries(
                    separator: current.separator, repoFirst: current.repoFirst
                ),
                maxRows: current.maxRows,
                rowHeight: rowHeight
            )
            .frame(width: 340)
            .background(current.scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 340)
    }
}

// MARK: - 渲染与导出

@MainActor
enum PrototypeRenderer {
    /// 用一个真实 PortRow 量出行高，避免拿一个猜出来的数字去算封顶高度。
    static func measureRowHeight() -> CGFloat {
        snapshot(
            PortRow(entry: PrototypeFixtures.entries(count: 1).first!, showTopDivider: false)
                .frame(width: 340)
                .environment(PortStore.shared),
            width: 340,
            scheme: .light
        )?.size.height ?? 56
    }

    /// ImageRenderer 渲染不出 ScrollView 的内容（得到空白图），所以走 NSHostingView
    /// 的离屏 display 缓存：它是真实 AppKit 布局，滚动容器和文本都在。
    static func snapshot<V: View>(_ view: V, width: CGFloat, scheme: ColorScheme,
                                  scale: CGFloat = 2) -> NSImage? {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 20)

        // 挂到一个不 orderFront 的窗口里，让布局与外观解析走真实路径。
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 20),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.contentView = hosting
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)

        hosting.layoutSubtreeIfNeeded()
        let height = hosting.fittingSize.height
        guard height > 0 else { return nil }

        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.setContentSize(NSSize(width: width, height: height))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale),
            pixelsHigh: Int(height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: width, height: height)

        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    static func exportAll(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rowHeight = measureRowHeight()
        print("[prototype] measured row height = \(rowHeight)")

        for variant in PrototypeVariants.make(schemes: PrototypeVariants.colorSchemes) {
            let content = VStack(spacing: 0) {
                Divider()
                PrototypeCappedList(
                    entries: PrototypeFixtures.entries(
                        separator: variant.separator,
                        repoFirst: variant.repoFirst,
                        count: variant.count
                    ),
                    maxRows: variant.maxRows,
                    rowHeight: rowHeight
                )
            }
            .frame(width: 340)
            .background(Color(nsColor: .windowBackgroundColor))

            guard let image = snapshot(content, width: 340, scheme: variant.scheme),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                print("[prototype] failed to render \(variant.fileName)")
                continue
            }
            let url = directory.appending(path: variant.fileName)
            try png.write(to: url)
            print("[prototype] wrote \(url.path()) (\(Int(image.size.width))x\(Int(image.size.height))pt)")
        }
    }
}

@MainActor
enum PrototypeWindow {
    private static var window: NSWindow?

    static func show(rowHeight: CGFloat) {
        let hosting = NSHostingController(rootView: PrototypeGallery(rowHeight: rowHeight))
        let window = NSWindow(contentViewController: hosting)
        window.title = "PROTOTYPE · Port Menu 封顶滚动与主行命名"
        window.setContentSize(NSSize(width: 340, height: 640))
        window.styleMask = [.titled, .closable]
        window.setFrameOrigin(NSPoint(x: 200, y: 200))
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    static func runExportAndQuit(directory: URL) {
        do {
            try PrototypeRenderer.exportAll(to: directory)
        } catch {
            print("[prototype] export failed: \(error)")
        }
        NSApp.terminate(nil)
    }
}
