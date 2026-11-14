import Foundation

/// One file or folder in the scanned tree. Kept deliberately small: a full-disk
/// scan creates millions of these.
final class FileNode: @unchecked Sendable {
    /// Path component. For the scan root this is the full path.
    let name: String
    /// Allocated size on disk, in bytes (includes all descendants).
    var size: Int64
    /// Number of files represented (1 for a plain file).
    var itemCount: Int
    let isDirectory: Bool
    /// Synthetic nodes are aggregates ("smaller files", "hidden space") with no real path.
    let isSynthetic: Bool
    unowned(unsafe) var parent: FileNode?
    var children: [FileNode] = []

    /// Per folder, only this many individual files are kept; the rest are folded
    /// into one synthetic node to bound memory.
    static let maxFilesPerFolder = 200

    init(name: String, size: Int64, itemCount: Int, isDirectory: Bool, isSynthetic: Bool = false) {
        self.name = name
        self.size = size
        self.itemCount = itemCount
        self.isDirectory = isDirectory
        self.isSynthetic = isSynthetic
    }

    func add(_ child: FileNode) {
        child.parent = self
        children.append(child)
        size += child.size
        itemCount += child.itemCount
    }

    /// Sort children largest-first and fold the long tail of small files.
    func finalizeChildren() {
        guard !children.isEmpty else { return }
        children.sort { $0.size > $1.size }
        guard children.count > FileNode.maxFilesPerFolder else { return }

        var kept: [FileNode] = []
        var files = 0
        var foldedSize: Int64 = 0
        var foldedCount = 0
        for c in children {
            if c.isDirectory {
                kept.append(c)
            } else if files < FileNode.maxFilesPerFolder {
                files += 1
                kept.append(c)
            } else {
                foldedSize += c.size
                foldedCount += c.itemCount
            }
        }
        if foldedCount > 0 {
            let folded = FileNode(name: "\(foldedCount.formatted()) smaller \(foldedCount == 1 ? "file" : "files")", size: foldedSize,
                                  itemCount: foldedCount, isDirectory: false, isSynthetic: true)
            folded.parent = self
            let idx = kept.firstIndex { $0.size < foldedSize } ?? kept.count
            kept.insert(folded, at: idx)
        }
        children = kept
    }

    var path: String {
        var parts: [String] = []
        var n = self
        while let p = n.parent {
            parts.append(n.name)
            n = p
        }
        var s = n.name
        for part in parts.reversed() {
            if !s.hasSuffix("/") { s += "/" }
            s += part
        }
        return s
    }

    func isDescendantOrSelf(of other: FileNode) -> Bool {
        var n: FileNode? = self
        while let cur = n {
            if cur === other { return true }
            n = cur.parent
        }
        return false
    }

    /// Detach from the tree, fixing up sizes and ordering in every ancestor.
    func removeFromParent() {
        guard let p = parent else { return }
        p.children.removeAll { $0 === self }
        var anc: FileNode? = p
        while let a = anc {
            a.size = max(0, a.size - size)
            a.itemCount = max(0, a.itemCount - itemCount)
            a.parent?.children.sort { $0.size > $1.size }
            anc = a.parent
        }
        parent = nil
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func formatFileCount(_ count: Int) -> String {
    "\(count.formatted()) \(count == 1 ? "file" : "files")"
}
