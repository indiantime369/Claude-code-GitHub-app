import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            SyncView()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .tag(AppTab.sync)
            ReviewView()
                .tabItem { Label("Review", systemImage: "questionmark.circle") }
                .badge(store.unmatched.count)
                .tag(AppTab.review)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(.green)
    }
}
