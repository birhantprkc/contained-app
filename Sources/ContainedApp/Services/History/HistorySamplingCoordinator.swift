import Foundation

/// Schedules infrequent persistent-history snapshots while the app is running but the live
/// container-stat stream is not needed by the visible UI. The coordinator intentionally does not
/// ask macOS to keep the process awake: App Nap may defer a low-priority sample.
@MainActor
final class HistorySamplingCoordinator {
    static let interval: TimeInterval = 5 * 60

    private weak var app: AppModel?
    private var loop: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?

    func start(app: AppModel) {
        self.app = app
        guard loop == nil else { return }
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        sleeper?.cancel()
        sleeper = nil
    }

    /// Run a new eligibility check promptly after a mode or runtime change.
    func wake() {
        sleeper?.cancel()
    }

    private func run() async {
        while !Task.isCancelled {
            if let app {
                await app.collectBackgroundHistoryIfNeeded()
            }
            sleeper = Task { try? await Task.sleep(for: .seconds(Self.interval)) }
            await sleeper?.value
        }
    }

    deinit {
        loop?.cancel()
        sleeper?.cancel()
    }
}
