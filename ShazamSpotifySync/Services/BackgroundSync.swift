import BackgroundTasks
import Foundation

/// Periodic sync while the app is in the background. iOS decides the exact
/// timing (usually a few times a day, based on how often the app is used).
enum BackgroundSync {
    static let taskID = "com.example.shazamspotifysync.refresh"

    @MainActor
    static func register(model: AppModel) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: .main) { task in
            MainActor.assumeIsolated {
                handle(task, model: model)
            }
        }
    }

    @MainActor
    static func schedule(enabled: Bool) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
        guard enabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    private static func handle(_ task: BGTask, model: AppModel) {
        schedule(enabled: model.store.autoSyncEnabled)
        let work = Task { @MainActor in
            await model.engine.sync(trigger: .background)
        }
        task.expirationHandler = { work.cancel() }
        Task { @MainActor in
            let report = await work.value
            task.setTaskCompleted(success: report != nil)
        }
    }
}
