import SwiftUI

private struct SunburstGeometry {
    let center: CGPoint
    let hole: CGFloat       // radius of the centre disc
    let ring: CGFloat       // thickness of each ring

    init(size: CGSize) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = max(60, min(size.width, size.height) / 2 - 16)
        hole = outer * 0.24
        ring = (outer - hole) / CGFloat(SunburstLayout.maxDepth)
    }

    enum Hit { case center, ring(depth: Int, angle: Double), outside }

    func hit(_ p: CGPoint) -> Hit {
        let dx = Double(p.x - center.x), dy = Double(p.y - center.y)
        let r = CGFloat((dx * dx + dy * dy).squareRoot())
        if r <= hole { return .center }
        let depth = Int((r - hole) / ring) + 1
        guard depth <= SunburstLayout.maxDepth else { return .outside }
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        return .ring(depth: depth, angle: angle)
    }

    func path(for s: Segment) -> Path {
        let inner = hole + ring * CGFloat(s.depth - 1)
        let outer = inner + ring
        let a0 = s.start - .pi / 2
        let a1 = a0 + min(s.end - s.start, 2 * .pi - 0.0005)
        var p = Path()
        p.addArc(center: center, radius: outer, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
        p.addArc(center: center, radius: inner, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
        p.closeSubpath()
        return p
    }
}

struct SunburstView: View {
    @EnvironmentObject var state: AppState
    @State private var overCenter = false

    var body: some View {
        GeometryReader { geo in
            let g = SunburstGeometry(size: geo.size)
            let layout = state.layout
            let hovered = state.hovered

            ZStack {
                Canvas { ctx, _ in
                    for ring in layout.rings {
                        for s in ring {
                            let path = g.path(for: s)
                            ctx.fill(path, with: .color(s.color))
                            ctx.stroke(path, with: .color(Theme.background), lineWidth: 1)
                        }
                    }
                    if let hovered, let s = layout.segment(for: hovered) {
                        let path = g.path(for: s)
                        ctx.fill(path, with: .color(.white.opacity(0.28)))
                        ctx.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
                    }
                    let disc = Path(ellipseIn: CGRect(x: g.center.x - g.hole + 2, y: g.center.y - g.hole + 2,
                                                      width: g.hole * 2 - 4, height: g.hole * 2 - 4))
                    ctx.fill(disc, with: .color(overCenter && state.focus?.parent != nil
                                                ? Color.white.opacity(0.10) : Theme.panel))
                }

                centerLabel
                    .frame(width: g.hole * 1.6, height: g.hole * 1.5)
                    .position(g.center)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    switch g.hit(p) {
                    case .center:
                        overCenter = true
                        state.hover(nil)
                    case .ring(let depth, let angle):
                        overCenter = false
                        state.hover(layout.segment(depth: depth, angle: angle)?.node)
                    case .outside:
                        overCenter = false
                        state.hover(nil)
                    }
                case .ended:
                    overCenter = false
                    state.hover(nil)
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                switch g.hit(value.location) {
                case .center:
                    state.goUp()
                case .ring(let depth, let angle):
                    if let node = layout.segment(depth: depth, angle: angle)?.node { state.open(node) }
                case .outside:
                    break
                }
            })
            .contextMenu {
                if let hovered { NodeMenu(node: hovered) }
            }
        }
    }

    @ViewBuilder private var centerLabel: some View {
        if let focus = state.focus {
            VStack(spacing: 3) {
                if focus.parent != nil {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(overCenter ? .primary : .tertiary)
                }
                Text(state.title(for: focus))
                    .font(.headline)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text(formatBytes(focus.size))
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Text("\(focus.itemCount.formatted()) files")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Context-menu actions shared by the chart and the list.
struct NodeMenu: View {
    @EnvironmentObject var state: AppState
    let node: FileNode

    var body: some View {
        if node.isSynthetic {
            Text(node.name)
        } else {
            if node.isDirectory && !node.children.isEmpty {
                Button("Look Inside") { state.open(node) }
            }
            Button("Reveal in Finder") { state.reveal(node) }
            Button("Copy Path") { state.copyPath(node) }
            Divider()
            if state.isCollected(node) {
                Button("Remove from Collector") { state.uncollect(node) }
            } else {
                Button("Add to Collector") { state.collect(node) }
                    .disabled(!state.canCollect(node))
            }
        }
    }
}
