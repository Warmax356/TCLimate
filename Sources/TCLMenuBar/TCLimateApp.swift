import SwiftUI
import AppKit

@main
struct TCLimateApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            AirPanel(store: store)
                .task { await store.restore() }
        } label: {
            Image(nsImage: MenuBarIcon.image).accessibilityLabel("TCLimate")
        }
        .menuBarExtraStyle(.window)
    }
}
