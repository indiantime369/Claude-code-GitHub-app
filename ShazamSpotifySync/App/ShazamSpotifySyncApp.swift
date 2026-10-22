import SwiftUI
import UserNotifications

@main
struct ShazamSpotifySyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.store)
                .environment(model.auth)
                .environment(model.engine)
                .environment(model.recognizer)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundSync.schedule(enabled: model.store.autoSyncEnabled)
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundSync.register(model: AppModel.shared)
        return true
    }

    // Show sync banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // Tapping a "couldn't be matched" notification opens the Review tab.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.notification.request.content.userInfo["action"] as? String
        Task { @MainActor in
            if action == NotificationManager.reviewAction {
                AppModel.shared.selectedTab = .review
            }
            completionHandler()
        }
    }
}
