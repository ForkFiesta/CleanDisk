import SwiftUI

struct Segment {
    /// nil for the grey "everything too small to draw" remainder wedge.
    let node: FileNode?
    let depth: Int        // 1 = innermost ring
    let start: Double     // radians, 0 = 12 o'clock, clockwise
    let end: Double
    let color: Color
}

/// Precomputed wedges for the sunburst rooted at one folder.
final class SunburstLayout {
    static let maxDepth = 6
    static let minAngle = 0.006

    let rings: [[Segment]]                    // rings[depth-1], sorted by start angle
    let topColors: [ObjectIdentifier: Color]  // colors of the first ring, for the list
    let segmentCount: Int

    static let empty = SunburstLayout(focus: nil)

    init(focus: FileNode?) {
        var rings = [[Segment]](repeating: [], count: SunburstLayout.maxDepth)
        var colors: [ObjectIdentifier: Color] = [:]

        func place(_ node: FileNode, depth: Int, start: Double, end: Double) {
            guard depth <= SunburstLayout.maxDepth, node.size > 0, !node.children.isEmpty else { return }
            let span = end - start
            var a = start
            for child in node.children {
                let w = span * Double(child.size) / Double(node.size)
                if w < SunburstLayout.minAngle {
                    if end - a > 0.002 {
                        rings[depth - 1].append(Segment(node: nil, depth: depth, start: a, end: end,
                                                        color: Color(white: 0.32)))
                    }
                    return
                }
                let color = SunburstLayout.color(for: child, mid: a + w / 2, depth: depth)
                rings[depth - 1].append(Segment(node: child, depth: depth, start: a, end: a + w, color: color))
                if depth == 1 { colors[ObjectIdentifier(child)] = color }
                place(child, depth: depth + 1, start: a, end: a + w)
                a += w
            }
        }

        if let focus { place(focus, depth: 1, start: 0, end: 2 * .pi) }
        self.rings = rings
        self.topColors = colors
        self.segmentCount = rings.reduce(0) { $0 + $1.count }
    }

    private static func color(for node: FileNode, mid: Double, depth: Int) -> Color {
        if node.isSynthetic { return Color(white: 0.38) }
        let hue = mid / (2 * .pi)
        let d = Double(depth - 1)
        if node.isDirectory {
            return Color(hue: hue, saturation: 0.68 - 0.05 * d, brightness: 0.95 - 0.06 * d)
        }
        return Color(hue: hue, saturation: 0.22, brightness: 0.74 - 0.05 * d)
    }

    func segment(depth: Int, angle: Double) -> Segment? {
        guard depth >= 1, depth <= rings.count else { return nil }
        let ring = rings[depth - 1]
        var lo = 0, hi = ring.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let s = ring[mid]
            if angle < s.start { hi = mid - 1 }
            else if angle >= s.end { lo = mid + 1 }
            else { return s }
        }
        return nil
    }

    func segment(for node: FileNode) -> Segment? {
        for ring in rings {
            if let s = ring.first(where: { $0.node === node }) { return s }
        }
        return nil
    }
}
