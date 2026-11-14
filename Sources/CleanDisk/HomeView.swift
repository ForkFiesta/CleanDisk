import SwiftUI

struct HomeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("CleanDisk").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("See what is filling your disks, then clear it out.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(state.volumes) { VolumeCard(volume: $0) }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: 640)

            HStack(spacing: 12) {
                Button { state.scanHome() } label: { Label("Scan Home Folder", systemImage: "house") }
                Button { state.scanFolder() } label: { Label("Scan Folder…", systemImage: "folder") }
                Button { state.refreshVolumes() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            .controlSize(.large)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("For complete results, grant CleanDisk Full Disk Access.")
                Button("Open Settings") { state.openFullDiskAccessSettings() }
                    .buttonStyle(.link)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
    }
}

private struct VolumeCard: View {
    @EnvironmentObject var state: AppState
    let volume: VolumeInfo

    private var fraction: Double { Double(volume.used) / Double(max(volume.total, 1)) }
    private var barColor: Color { fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .blue }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(volume.name).font(.headline)
                    Spacer()
                    Text("\(formatBytes(volume.free)) free of \(formatBytes(volume.total))")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule().fill(barColor).frame(width: max(6, geo.size.width * fraction))
                    }
                }
                .frame(height: 8)
            }

            Button("Scan") { state.scan(volume: volume) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
    }
}

struct ScanningView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 18) {
            Text("Scanning \(state.scanTitle)…").font(.title2.weight(.semibold))

            if let expected = state.scanExpectedBytes, expected > 0 {
                ProgressView(value: min(1, Double(state.scanBytes) / Double(expected)))
                    .frame(width: 420)
            } else {
                ProgressView().progressViewStyle(.linear).frame(width: 420)
            }

            Text("\(formatBytes(state.scanBytes))  ·  \(state.scanFiles.formatted()) files")
                .font(.title3).monospacedDigit()

            Text(state.scanPath)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .frame(width: 520)

            Button("Cancel") { state.cancelScan() }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
        }
    }
}
