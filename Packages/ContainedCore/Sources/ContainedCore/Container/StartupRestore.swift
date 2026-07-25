import Foundation

/// The outcome of restoring containers after Contained starts a runtime service.
/// Individual failures are retained as runtime detail so one unavailable workload does not block
/// other containers from starting.
public extension Core.Container {
    struct StartupRestoreResult: Sendable, Equatable {
        public struct Failure: Sendable, Equatable, Identifiable {
            public let containerID: String
            public let runtimeKind: Core.Runtime.Kind
            public let runtimeDetail: String

            public var id: String { runtimeKind.scopedID(for: containerID) }

            public init(containerID: String,
                        runtimeKind: Core.Runtime.Kind,
                        runtimeDetail: String) {
                self.containerID = containerID
                self.runtimeKind = runtimeKind
                self.runtimeDetail = runtimeDetail
            }
        }

        public let startedContainerIDs: [String]
        public let failures: [Failure]

        public init(startedContainerIDs: [String], failures: [Failure]) {
            self.startedContainerIDs = startedContainerIDs
            self.failures = failures
        }
    }
}

public extension Core.Orchestrator {
    /// Start each stopped `contained.restart=always` container for one runtime.
    ///
    /// This is intentionally separate from service control: callers must invoke it only after a
    /// successful, Contained-initiated engine start. Containers are started one at a time in a
    /// stable order so a single failure cannot prevent later eligible containers from recovering.
    func restoreAlwaysContainers(runtimeKind: Core.Runtime.Kind) async throws -> Core.Container.StartupRestoreResult {
        let runtime = try requireRuntime(runtimeKind,
                                         capability: .containers,
                                         as: (any RuntimeContainerClient).self)
        let candidates = try await runtime.listContainers(all: true)
            .map { $0.scoped(to: runtimeKind) }
            .filter { snapshot in
                Core.Container.RestartDecision.shouldRestoreAfterEngineStart(
                    policy: Core.Container.RestartPolicy(label: snapshot.restartLabel),
                    state: snapshot.state
                )
            }
            .sorted { $0.id < $1.id }

        var startedContainerIDs: [String] = []
        var failures: [Core.Container.StartupRestoreResult.Failure] = []
        for snapshot in candidates {
            do {
                _ = try await runtime.start([snapshot.id])
                startedContainerIDs.append(snapshot.id)
            } catch {
                failures.append(.init(containerID: snapshot.id,
                                      runtimeKind: runtimeKind,
                                      runtimeDetail: String(describing: error)))
            }
        }
        return .init(startedContainerIDs: startedContainerIDs, failures: failures)
    }
}
