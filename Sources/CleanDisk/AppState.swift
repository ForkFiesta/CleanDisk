import SwiftUI
import AppKit

struct VolumeInfo: Identifiable {
    let id: String          // mount path
    let name: String
    let total: Int64
    let free: Int64         // what Finder reports (includes purgeable)
    let rawFree: Int64      // actually unallocated right now
    let isInternal: Bool
    var used: Int64 { max(0, total - free) }
}

/// All app state. Only touched on the main thread.
final class AppState: ObservableObject {
    enum Phase { case home, scanning, result }

    @Published var phase: Phase = .home
    @Published var volumes: [VolumeInfo] = []

    // Scanning
    @Published var scanTitle = ""
    @Published var scanFiles = 0
    @Published var scanBytes: Int64 = 0
    @Published var scanPath = ""
    @Published var scanExpectedBytes: Int64?

    // Result
    @Published var root: FileNode?
    @Published var focus: FileNode?
    @Published var hovered: FileNode?
    @Published var layout = SunburstLayout.empty
    @Published var collector: [FileNode] = []
    @Published var message: String?

    private var progress: ScanProgress?
    private var timer: Timer?
    private var lastScan: (path: String, title: String, volume: VolumeInfo?)?

    init() {
        refreshVolumes()
        // `CleanDisk --scan <path>` starts scanning straight away.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--scan"), i + 1 < args.count {
            let url = URL(fileURLWithPath: args[i + 1]).standardizedFileURL
            let volume = volumes.first { $0.id == url.path }
            startScan(path: url.path, title: volume?.name ?? url.lastPathComponent, volume: volume)
        }
    }

    // MARK: Volumes

    func refreshVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let raw = Int64(v.volumeAvailableCapacity ?? 0)
            let important = v.volumeAvailableCapacityForImportantUsage ?? 0
            return VolumeInfo(id: url.path, name: v.volumeName ?? url.lastPathComponent,
                              total: Int64(total), free: important > 0 ? important : raw, rawFree: raw,
                              isInternal: v.volumeIsInternal ?? false)
        }
    }

    // MARK: Scanning

    func scan(volume: VolumeInfo) {
        startScan(path: volume.id, title: volume.name, volume: volume)
    }

    func scanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            startScan(path: url.path, title: url.lastPathComponent, volume: nil)
        }
    }

    func scanHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        startScan(path: home.path, title: home.lastPathComponent, volume: nil)
    }

    func rescan() {
        guard let last = lastScan else { return }
        refreshVolumes()
        startScan(path: last.path, title: last.title,
                  volume: last.volume.flatMap { v in volumes.first { $0.id == v.id } })
    }

    private func startScan(path: String, title: String, volume: VolumeInfo?) {
        lastScan = (path, title, volume)
        root = nil; focus = nil; hovered = nil; collector = []
        layout = .empty
        scanTitle = title
        scanFiles = 0; scanBytes = 0; scanPath = path
        scanExpectedBytes = volume.map { $0.total - $0.rawFree }
        phase = .scanning

        let progress = ScanProgress()
        self.progress = progress
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            let snap = progress.snapshot()
            self?.scanFiles = snap.files
            self?.scanBytes = snap.bytes
            self?.scanPath = snap.path
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Scanner.scan(path: path, progress: progress)
            if let result, let volume {
                // Space the volume reports as used that we could not see: snapshots,
                // swap, other APFS volumes in the container, unreadable folders.
                let hidden = (volume.total - volume.rawFree) - result.size
                if hidden > 100_000_000 {
                    result.add(FileNode(name: "Hidden & inaccessible space", size: hidden, itemCount: 0,
                                        isDirectory: false, isSynthetic: true))
                    result.children.sort { $0.size > $1.size }
                }
            }
            DispatchQueue.main.async {
                guard self.progress === progress else { return } // superseded or cancelled
                self.timer?.invalidate()
                self.progress = nil
                if let result {
                    self.root = result
                    self.setFocus(result)
                    self.phase = .result
                } else {
                    self.phase = .home
                    self.message = "Could not read \(path)."
                }
            }
        }
    }

    func cancelScan() {
        progress?.cancel()
        progress = nil
        timer?.invalidate()
        phase = .home
    }

    func goHome() {
        root = nil; focus = nil; hovered = nil; collector = []
        layout = .empty
        refreshVolumes()
        phase = .home
    }

    // MARK: Navigation

    func title(for node: FileNode) -> String {
        node === root ? scanTitle : node.name
    }

    func setFocus(_ node: FileNode) {
        hovered = nil
        focus = node
        layout = SunburstLayout(focus: node)
    }

    func open(_ node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        setFocus(node)
    }

    func goUp() {
        if let p = focus?.parent { setFocus(p) }
    }

    var breadcrumb: [FileNode] {
        var chain: [FileNode] = []
        var n = focus
        while let cur = n { chain.append(cur); n = cur.parent }
        return chain.reversed()
    }

    func hover(_ node: FileNode?) {
        if hovered !== node { hovered = node }
    }

    // MARK: Actions

    func reveal(_ node: FileNode) {
        guard !node.isSynthetic else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
    }

    func copyPath(_ node: FileNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
    }

    func canCollect(_ node: FileNode) -> Bool {
        !node.isSynthetic && node !== root && !collector.contains { node.isDescendantOrSelf(of: $0) }
    }

    func isCollected(_ node: FileNode) -> Bool {
        collector.contains { $0 === node }
    }

    func collect(_ node: FileNode) {
        guard canCollect(node) else { return }
        collector.removeAll { $0.isDescendantOrSelf(of: node) } // parent subsumes children
        collector.append(node)
    }

    func uncollect(_ node: FileNode) {
        collector.removeAll { $0 === node }
    }

    var collectorSize: Int64 { collector.reduce(0) { $0 + $1.size } }

    /// Move everything in the collector to the Trash and update the tree.
    func trashCollected() {
        var freed: Int64 = 0
        var failures: [String] = []
        var remaining: [FileNode] = []
        for node in collector {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: node.path), resultingItemURL: nil)
                freed += node.size
                if let f = focus, f.isDescendantOrSelf(of: node) { focus = node.parent }
                node.removeFromParent()
            } catch {
                failures.append("\(node.name): \(error.localizedDescription)")
                remaining.append(node)
            }
        }
        collector = remaining
        if let f = focus ?? root { setFocus(f) }
        refreshVolumes()
        if failures.isEmpty {
            message = "Moved \(formatBytes(freed)) to the Trash. Empty the Trash to reclaim the space."
        } else {
            message = "Moved \(formatBytes(freed)) to the Trash.\n\nCould not move:\n"
                + failures.prefix(8).joined(separator: "\n")
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
