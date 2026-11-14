import Foundation

/// Thread-safe progress, cancellation and hard-link bookkeeping shared between
/// the scanner threads and the UI.
final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var files = 0
    private var bytes: Int64 = 0
    private var path = ""
    private var cancelled = false
    private var hardLinks = Set<UInt64>()

    func add(files: Int, bytes: Int64, path: String) {
        lock.lock(); defer { lock.unlock() }
        self.files += files; self.bytes += bytes; self.path = path
    }

    func snapshot() -> (files: Int, bytes: Int64, path: String) {
        lock.lock(); defer { lock.unlock() }
        return (files, bytes, path)
    }

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// True the first time an inode is seen, so hard-linked content is counted once.
    func firstSighting(inode: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return hardLinks.insert(inode).inserted
    }
}

enum Scanner {
    private static let datalessFlag: UInt32 = 0x4000_0000 // SF_DATALESS: cloud-only placeholder
    /// Directories at this depth are handed out to worker threads.
    private static let splitLevel = 3

    private struct Deferred {
        let parent: FileNode
        let path: String
        let name: String
    }

    /// Walk `path` and build a size tree. Returns nil if cancelled or unreadable.
    static func scan(path: String, progress: ScanProgress) -> FileNode? {
        var rootStat = stat()
        guard stat(path, &rootStat) == 0 else { return nil }

        // Stay on the volume being scanned. The boot volume is really two volumes
        // (sealed system + Data) stitched together with firmlinks, so allow both
        // and skip the raw mount points that would double-count.
        var allowedDevs: Set<dev_t> = [rootStat.st_dev]
        var skipPaths: Set<String> = []
        if path == "/" {
            var s = stat()
            if stat("/System/Volumes/Data", &s) == 0 { allowedDevs.insert(s.st_dev) }
            skipPaths = ["/System/Volumes", "/Volumes", "/dev"]
        }

        // Phase 1: walk the top few levels on this thread, deferring deeper folders.
        var deferred: [Deferred] = []
        guard let root = walk(path: path, rootName: path, allowedDevs: allowedDevs, skipPaths: skipPaths,
                              splitLevel: splitLevel, deferred: &deferred, progress: progress)
        else { return nil }

        // Phase 2: scan the deferred subtrees in parallel.
        let results = UnsafeMutablePointer<FileNode?>.allocate(capacity: deferred.count)
        results.initialize(repeating: nil, count: deferred.count)
        defer { results.deinitialize(count: deferred.count); results.deallocate() }
        let jobs = deferred
        DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
            var none: [Deferred] = []
            results[i] = walk(path: jobs[i].path, rootName: jobs[i].name, allowedDevs: allowedDevs,
                              skipPaths: [], splitLevel: nil, deferred: &none, progress: progress)
        }
        if progress.isCancelled { return nil }

        // Phase 3: graft the subtrees in and fix sizes/order of the shallow levels.
        var touched: [ObjectIdentifier: FileNode] = [:]
        for (i, job) in jobs.enumerated() {
            guard let sub = results[i] else { continue }
            sub.parent = job.parent
            job.parent.children.append(sub)
            var anc: FileNode? = job.parent
            while let a = anc {
                a.size += sub.size
                a.itemCount += sub.itemCount
                touched[ObjectIdentifier(a)] = a
                anc = a.parent
            }
        }
        for node in touched.values { node.children.sort { $0.size > $1.size } }
        return root
    }

    /// Single-threaded fts walk. When `splitLevel` is set, directories at that depth
    /// are not entered but appended to `deferred`.
    private static func walk(path: String, rootName: String, allowedDevs: Set<dev_t>, skipPaths: Set<String>,
                             splitLevel: Int?, deferred: inout [Deferred], progress: ScanProgress) -> FileNode? {
        guard let cpath = strdup(path) else { return nil }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return nil }
        defer { fts_close(fts) }

        var stack: [(node: FileNode, level: Int)] = []
        var root: FileNode?
        var pendingFiles = 0
        var pendingBytes: Int64 = 0
        var tick = 0

        while let ent = fts_read(fts) {
            tick &+= 1
            if tick & 0x3FF == 0 {
                if progress.isCancelled { return nil }
                progress.add(files: pendingFiles, bytes: pendingBytes,
                             path: String(cString: ent.pointee.fts_path))
                pendingFiles = 0; pendingBytes = 0
            }

            let level = Int(ent.pointee.fts_level)
            switch Int32(ent.pointee.fts_info) {
            case FTS_D:
                guard let st = ent.pointee.fts_statp else {
                    fts_set(fts, ent, FTS_SKIP)
                    continue
                }
                if level > 0 {
                    let foreign = !allowedDevs.contains(st.pointee.st_dev)
                    let dataless = st.pointee.st_flags & datalessFlag != 0
                    let skipped = level <= 2 && !skipPaths.isEmpty
                        && skipPaths.contains(String(cString: ent.pointee.fts_path))
                    if foreign || dataless || skipped {
                        fts_set(fts, ent, FTS_SKIP)
                        continue
                    }
                    if level == splitLevel, let parent = stack.last?.node {
                        deferred.append(Deferred(parent: parent, path: String(cString: ent.pointee.fts_path),
                                                 name: entryName(ent)))
                        fts_set(fts, ent, FTS_SKIP)
                        continue
                    }
                }
                let own = Int64(st.pointee.st_blocks) * 512
                pendingBytes += own
                let node = FileNode(name: level == 0 ? rootName : entryName(ent), size: own,
                                    itemCount: 0, isDirectory: true)
                stack.append((node, level))

            case FTS_DP, FTS_DNR:
                // Skipped directories were never pushed, so match on level.
                guard let top = stack.last, top.level == level else { continue }
                stack.removeLast()
                top.node.finalizeChildren()
                if let parent = stack.last?.node {
                    parent.add(top.node)
                } else {
                    root = top.node
                }

            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let st = ent.pointee.fts_statp, let parent = stack.last?.node else { continue }
                var size = Int64(st.pointee.st_blocks) * 512
                if st.pointee.st_nlink > 1, !progress.firstSighting(inode: UInt64(st.pointee.st_ino)) {
                    size = 0
                }
                pendingFiles += 1
                pendingBytes += size
                parent.add(FileNode(name: entryName(ent), size: size, itemCount: 1, isDirectory: false))

            default:
                break
            }
        }

        progress.add(files: pendingFiles, bytes: pendingBytes, path: path)
        return progress.isCancelled ? nil : root
    }

    private static func entryName(_ ent: UnsafeMutablePointer<FTSENT>) -> String {
        let offset = Int(ent.pointee.fts_pathlen) - Int(ent.pointee.fts_namelen)
        return String(cString: ent.pointee.fts_path + offset)
    }
}
