# CleanDisk

A free, open-source disk space visualizer for macOS. Scan a volume or folder, see
what is taking up space as an interactive sunburst map, and move what you don't
need to the Trash.

Native SwiftUI, no dependencies.

## Features

- **Fast scanning** – multi-threaded `fts` walk; a ~2 million file boot disk scans in well under a minute on Apple silicon.
- **Sunburst map** – six levels of folders at a glance. Click a wedge to look inside, click the centre to go back up.
- **Sorted list** – the current folder's contents, largest first, colour-matched to the map.
- **Collector** – right-click items to collect them, review the total, then move them all to the Trash in one step. Nothing is ever deleted permanently.
- **Accurate sizes** – reports allocated size on disk, counts hard links once, skips cloud-only placeholders, and shows space it could not see as "Hidden & inaccessible space".

## Requirements

- macOS 14 or later
- Xcode 15+ or the Swift 5.9+ toolchain (to build)

## Build and run

```sh
git clone https://github.com/ForkFiesta/CleanDisk.git
cd CleanDisk
./build.sh --run
```

This produces `build/CleanDisk.app` (ad-hoc signed). Copy it to `/Applications` if you want to keep it.

To start scanning a path straight away:

```sh
open build/CleanDisk.app --args --scan ~/Downloads
```

## Full Disk Access

macOS hides some folders (Mail, Safari data, other apps' containers, …) from apps
by default. For complete results, add CleanDisk under **System Settings → Privacy &
Security → Full Disk Access**. Because the build is ad-hoc signed, you may need to
grant it again after rebuilding.

## How it works

| File | Purpose |
| --- | --- |
| `Scanner.swift` | Walks the top levels on one thread, then scans deeper subtrees in parallel and grafts them together. |
| `FileNode.swift` | Compact tree node. Each folder keeps its 200 largest files and folds the rest into one entry to bound memory. |
| `SunburstLayout.swift` | Turns a folder into wedges (angles, depth, colour) and handles hit-testing. |
| `SunburstView.swift` | Draws the map with `Canvas`; hover, click and context menu. |
| `ResultView.swift` | Breadcrumb, item list, status bar and collector. |
| `AppState.swift` | Volumes, scan lifecycle, navigation, Trash. |

## Known limitations

- APFS clones are counted once per copy, so totals can exceed real usage for cloned files.
- Local snapshots, swap and other volumes in the same APFS container appear only as hidden space.
- Files folded into "N smaller files" cannot be collected individually.

## Contributing

Issues and pull requests are welcome. Please keep the project dependency-free and
make sure `swift build` passes.

## License

[MIT](LICENSE)
