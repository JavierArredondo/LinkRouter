import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var coordinator: RoutingCoordinator
    var body: some View {
        Text(coordinator.handlerStatus).lineLimit(1)
        Text("Last routed: \(coordinator.lastRouted)").lineLimit(1)
        Divider()
        Button("Refresh destinations") { coordinator.refreshDestinations() }
        Button("Settings…") { coordinator.presentSettings() }
        Divider()
        Button("Quit LinkRouter") { NSApplication.shared.terminate(nil) }
    }
}

struct OnboardingView: View {
    @ObservedObject var coordinator: RoutingCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 42)).foregroundStyle(.tint)
            Text("Route every link to the right browser").font(.title2.bold())
            Text("LinkRouter needs to become the default handler for web links. You can change this later in Settings.")
            Text(coordinator.handlerStatus).foregroundStyle(.secondary)
            HStack {
                Button("Use LinkRouter for web links") { coordinator.becomeDefaultHandler() }.buttonStyle(.borderedProminent)
                Button("Refresh destinations") { coordinator.refreshDestinations() }
            }
        }.padding(28).frame(width: 460)
    }
}
