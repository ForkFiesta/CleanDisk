import SwiftUI

@main
struct CleanDiskApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("CleanDisk", id: "main") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 940, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1180, height: 760)
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch state.phase {
            case .home: HomeView()
            case .scanning: ScanningView()
            case .result: ResultView()
            }
        }
        .alert("CleanDisk", isPresented: Binding(get: { state.message != nil },
                                                 set: { if !$0 { state.message = nil } })) {
            Button("OK") { state.message = nil }
        } message: {
            Text(state.message ?? "")
        }
    }
}

enum Theme {
    static let background = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let panel = Color(red: 0.13, green: 0.14, blue: 0.17)
    static let hairline = Color.white.opacity(0.08)
}
