import SwiftUI

struct ResultView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider().overlay(Theme.hairline)
            HStack(spacing: 0) {
                SunburstView()
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().overlay(Theme.hairline)
                ItemList()
                    .frame(width: 340)
                    .background(Theme.panel)
            }
            Divider().overlay(Theme.hairline)
            StatusBar()
            if !state.collector.isEmpty {
                Divider().overlay(Theme.hairline)
                CollectorBar()
            }
        }
    }
}

private struct TopBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Button { state.goHome() } label: { Label("Disks", systemImage: "chevron.left") }
            Button { state.goUp() } label: { Image(systemName: "arrow.up") }
                .disabled(state.focus?.parent == nil)
                .help("Go to enclosing folder")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let chain = state.breadcrumb
                    ForEach(Array(chain.enumerated()), id: \.offset) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Button(state.title(for: node)) { state.setFocus(node) }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(index == chain.count - 1 ? Color.white.opacity(0.10) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }

            Button { state.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ItemList: View {
    @EnvironmentObject var state: AppState
    private static let rowLimit = 300

    var body: some View {
        if let focus = state.focus {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title(for: focus)).font(.title3.weight(.semibold)).lineLimit(1)
                    Text("\(formatBytes(focus.size))  ·  \(focus.itemCount.formatted()) files")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(12)
                Divider().overlay(Theme.hairline)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        let rows = focus.children.prefix(ItemList.rowLimit)
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, node in
                            ItemRow(node: node, parentSize: focus.size)
                        }
                        if focus.children.count > ItemList.rowLimit {
                            Text("\((focus.children.count - ItemList.rowLimit).formatted()) more small items")
                                .font(.caption).foregroundStyle(.secondary).padding(10)
                        }
                        if focus.children.isEmpty {
                            Text("Empty folder").foregroundStyle(.secondary).padding(20)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct ItemRow: View {
    @EnvironmentObject var state: AppState
    let node: FileNode
    let parentSize: Int64

    var body: some View {
        let isHovered = state.hovered === node
        let color = state.layout.topColors[ObjectIdentifier(node)] ?? Color(white: 0.32)
        let canOpen = node.isDirectory && !node.children.isEmpty

        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Image(systemName: node.isSynthetic ? "ellipsis.circle" : node.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(node.name).lineLimit(1).truncationMode(.middle)
            if state.isCollected(node) {
                Image(systemName: "tray.and.arrow.down.fill").font(.caption).foregroundStyle(.orange)
            }
            Spacer(minLength: 6)
            Text(formatBytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption2)
                .foregroundStyle(.tertiary).opacity(canOpen ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isHovered ? Color.white.opacity(0.09) : .clear)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { state.hover(node) } else if state.hovered === node { state.hover(nil) }
        }
        .onTapGesture { state.open(node) }
        .contextMenu { NodeMenu(node: node) }
    }
}

private struct StatusBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            if let node = state.hovered ?? state.focus {
                Text(node.isSynthetic ? node.name : node.path)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(formatBytes(node.size)).monospacedDigit()
            } else {
                Spacer()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
    }
}

private struct CollectorBar: View {
    @EnvironmentObject var state: AppState
    @State private var showList = false
    @State private var confirm = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill").foregroundStyle(.orange)
            Text("Collector: \(state.collector.count) item\(state.collector.count == 1 ? "" : "s")  ·  \(formatBytes(state.collectorSize))")
                .monospacedDigit()
            Button("Show") { showList = true }
                .popover(isPresented: $showList, arrowEdge: .top) { collectorList }
            Spacer()
            Button("Clear") { state.collector = [] }
            Button("Move to Trash…") { confirm = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.panel)
        .confirmationDialog("Move \(state.collector.count) item\(state.collector.count == 1 ? "" : "s") (\(formatBytes(state.collectorSize))) to the Trash?",
                            isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { state.trashCollected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can restore them from the Trash until you empty it.")
        }
    }

    private var collectorList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(state.collector.enumerated()), id: \.offset) { _, node in
                    HStack(spacing: 8) {
                        Image(systemName: node.isDirectory ? "folder.fill" : "doc").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(node.name).lineLimit(1)
                            Text(node.path).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                        Spacer(minLength: 12)
                        Text(formatBytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
                        Button { state.uncollect(node) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 460)
        .frame(maxHeight: 320)
    }
}
