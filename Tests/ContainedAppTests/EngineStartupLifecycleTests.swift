import Foundation
import Testing
import ContainedCore
@testable import ContainedApp

@Suite("Engine startup lifecycle")
@MainActor
struct EngineStartupLifecycleTests {
    @Test func manualStartRestoresAlwaysContainersWhenEnabled() async {
        let runner = EngineStartupRunner()
        let app = makeApp(runner: runner)
        app.settings.autoStartAlwaysContainers = true

        await app.startService()

        #expect(await runner.systemStartCount() == 1)
        #expect(await runner.containerStartCalls() == ["always"])
    }

    @Test func launchStartupStartsAStoppedEngineOnlyOnce() async {
        let runner = EngineStartupRunner()
        let app = makeApp(runner: runner)
        app.settings.autoStartEngineOnLaunch = true

        #expect(await app.startEngineOnLaunchIfNeeded())
        #expect(!(await app.startEngineOnLaunchIfNeeded()))

        #expect(await runner.systemStartCount() == 1)
    }

    @Test func launchStartupLeavesAnAlreadyReadyEngineAlone() async {
        let runner = EngineStartupRunner()
        let app = makeApp(runner: runner, readinessState: .ready)
        app.settings.autoStartEngineOnLaunch = true

        #expect(!(await app.startEngineOnLaunchIfNeeded()))
        #expect(await runner.systemStartCount() == 0)
    }

    @Test func manualStartDoesNotRestoreWhenDisabledOrTriggerCrashWatchdog() async {
        let runner = EngineStartupRunner()
        let app = makeApp(runner: runner)
        app.settings.autoStartAlwaysContainers = false
        app.settings.autoRestartEnabled = true

        await app.startService()
        await app.tick()

        #expect(await runner.systemStartCount() == 1)
        #expect(await runner.containerStartCalls().isEmpty)
    }

    @Test func restartServiceAlsoRestoresAlwaysContainers() async {
        let runner = EngineStartupRunner()
        let app = makeApp(runner: runner)
        app.settings.autoStartAlwaysContainers = true

        await app.restartService()

        #expect(await runner.systemStopCount() == 1)
        #expect(await runner.systemStartCount() == 1)
        #expect(await runner.containerStartCalls() == ["always"])
    }

    private func makeApp(runner: EngineStartupRunner,
                         readinessState: Core.RuntimeReadiness.State = .endpointUnavailable) -> AppModel {
        let app = AppModel(database: AppDatabase(isStoredInMemoryOnly: true))
        let cliURL = URL(fileURLWithPath: "/usr/bin/container")
        app.installRuntimeClientForTesting(
            appTestOrchestrator(runner: runner,
                                cliURL: cliURL,
                                runtimeKind: .appleContainer),
            readiness: [.init(kind: .appleContainer,
                               cliURL: cliURL,
                               state: readinessState)],
            bootstrap: readinessState == .ready ? .ready : .serviceStopped
        )
        return app
    }
}

private actor EngineStartupRunner: Core.Command.Running {
    private var isRunning = false
    private var calls: [[String]] = []

    func run(_ arguments: [String],
             stdin: Data?,
             priority: Core.Command.ExecutionPriority) async throws -> Data {
        calls.append(arguments)
        switch arguments {
        case ["system", "start"]:
            isRunning = true
            return Data()
        case ["system", "stop"]:
            isRunning = false
            return Data()
        case ["system", "status", "--format", "json"]:
            return Data("{\"status\":\"\(isRunning ? "running" : "stopped")\"}".utf8)
        case ["list", "--all", "--format", "json"]:
            return Self.inventory
        default:
            return Data()
        }
    }

    nonisolated func stream(_ arguments: [String],
                            priority: Core.Command.ExecutionPriority) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }

    func systemStartCount() -> Int { calls.filter { $0 == ["system", "start"] }.count }
    func systemStopCount() -> Int { calls.filter { $0 == ["system", "stop"] }.count }
    func containerStartCalls() -> [String] {
        calls.compactMap { call in call.first == "start" ? call.last : nil }
    }

    private static let inventory = Data("""
    [
      {"configuration":{"id":"always","image":{"reference":"example/always"},"initProcess":{},"labels":{"contained.restart":"always"}},"id":"always","status":{"state":"stopped"}},
      {"configuration":{"id":"failure","image":{"reference":"example/failure"},"initProcess":{},"labels":{"contained.restart":"on-failure"}},"id":"failure","status":{"state":"stopped"}},
      {"configuration":{"id":"running","image":{"reference":"example/running"},"initProcess":{},"labels":{"contained.restart":"always"}},"id":"running","status":{"state":"running"}}
    ]
    """.utf8)
}
