import Foundation
import Testing
import ContainedCore
@testable import ContainedApp

@Suite("Background container history")
@MainActor
struct BackgroundHistorySamplingTests {
    @Test func hiddenContainersUseBatchedSnapshotsAndPersistAfterBaseline() async {
        let database = AppDatabase(isStoredInMemoryOnly: true)
        let app = AppModel(database: database)
        let runner = BackgroundHistoryRunner()
        app.installRuntimeClientForTesting(
            Core.Orchestrator.testing(runner: runner, runtimeKind: .appleContainer)
        )
        app.setContainerStatsVisible(false)
        let first = Date(timeIntervalSinceReferenceDate: 10_000)

        await app.collectBackgroundHistoryIfNeeded(at: first)

        #expect(await runner.runCount(for: "stats") == 1)
        #expect(await runner.streamCallCount() == 0)
        let scopedID = Core.Runtime.Kind.appleContainer.scopedID(for: "fixture-web")
        #expect((await app.historyStore.containerHistory(scopedContainerID: scopedID,
                                                          since: first.addingTimeInterval(-1))).metrics.isEmpty)

        await app.collectBackgroundHistoryIfNeeded(at: first.addingTimeInterval(HistorySamplingCoordinator.interval))

        let history = await app.historyStore.containerHistory(scopedContainerID: scopedID,
                                                              since: first.addingTimeInterval(-1))
        let metric = try! #require(history.metrics.first)
        #expect(await runner.runCount(for: "stats") == 2)
        #expect(metric.cpuFraction == 1.0 / HistorySamplingCoordinator.interval)
        #expect(metric.netRxBytesPerSec == 1_000 / HistorySamplingCoordinator.interval)
    }

    @Test func visibleContainersDoNotRunBackgroundSnapshots() async {
        let app = AppModel(database: AppDatabase(isStoredInMemoryOnly: true))
        let runner = BackgroundHistoryRunner()
        app.installRuntimeClientForTesting(
            Core.Orchestrator.testing(runner: runner, runtimeKind: .appleContainer)
        )

        await app.collectBackgroundHistoryIfNeeded(at: Date())

        #expect(await runner.runCount(for: "list") == 0)
        #expect(await runner.runCount(for: "stats") == 0)
        #expect(await runner.streamCallCount() == 0)
    }
}

private actor BackgroundHistoryRunner: Core.Command.Running {
    private var calls: [[String]] = []
    private var statsRuns = 0
    nonisolated private let streams = StreamCallCounter()

    func run(_ arguments: [String],
             stdin: Data?,
             priority: Core.Command.ExecutionPriority) async throws -> Data {
        calls.append(arguments)
        switch arguments.first {
        case "list": return Self.listJSON
        case "stats":
            statsRuns += 1
            return Self.statsJSON(run: statsRuns)
        default: return Data("[]".utf8)
        }
    }

    nonisolated func stream(_ arguments: [String],
                            priority: Core.Command.ExecutionPriority) -> AsyncThrowingStream<String, Error> {
        streams.record()
        return AsyncThrowingStream { continuation in continuation.finish() }
    }

    func runCount(for firstArgument: String) -> Int {
        calls.filter { $0.first == firstArgument }.count
    }

    func streamCallCount() -> Int { streams.value }

    private static let listJSON = Data("""
    [{
      "configuration": {
        "id": "fixture-web",
        "image": { "reference": "docker.io/library/alpine:latest" },
        "initProcess": {}
      },
      "id": "fixture-web",
      "status": { "state": "running" }
    }]
    """.utf8)

    private static func statsJSON(run: Int) -> Data {
        Data("""
        [{
          "id": "fixture-web",
          "cpuUsageUsec": \(run * 1_000_000),
          "memoryUsageBytes": 2322432,
          "memoryLimitBytes": 1073741824,
          "networkRxBytes": \(run * 1_000),
          "networkTxBytes": \(run * 500),
          "blockReadBytes": \(run * 100),
          "blockWriteBytes": \(run * 200),
          "numProcesses": 1
        }]
        """.utf8)
    }
}

private final class StreamCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
