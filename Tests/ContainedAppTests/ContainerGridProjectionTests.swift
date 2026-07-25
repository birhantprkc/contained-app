import Testing
import ContainedCore
import ContainedUI
@testable import ContainedApp

@Suite("Container grid projection")
struct ContainerGridProjectionTests {
    @Test func stableColumnsDependOnlyOnViewportWidth() {
        #expect(UI.Card.Grid.stableColumns(availableWidth: 1_600, spacing: 16).count == 3)
        #expect(UI.Card.Grid.stableColumns(availableWidth: 1_000, spacing: 16).count == 2)
        #expect(UI.Card.Grid.stableColumns(availableWidth: 600, spacing: 16).count == 1)
    }

    @Test func flatProjectionFiltersAndSortsWithStableIdentity() {
        let snapshots = [
            Self.snapshot(id: "worker", image: "example/worker:latest"),
            Self.snapshot(id: "api", image: "example/api:latest"),
        ]
        let input = ContainerGridProjection.Input(snapshots: snapshots,
                                                  networks: [], grouping: .flat, sort: .name,
                                                  runningOnly: false, search: "")

        let first = ContainerGridProjection.build(input)
        let second = ContainerGridProjection.build(input)

        #expect(first == second)
        #expect(first.groups.map { $0.id } == ["flat:all"])
        #expect(first.groups[0].containers.map { $0.id } == ["api", "worker"])
        #expect(first.visibleCount == 2)

        let filtered = ContainerGridProjection.build(.init(snapshots: snapshots,
                                                           networks: [], grouping: .flat, sort: .name,
                                                           runningOnly: false, search: "worker"))
        #expect(filtered.groups[0].containers.map { $0.id } == ["worker"])
        #expect(filtered.visibleCount == 1)
    }

    @Test func imageProjectionUsesStableGroupAndCardIDs() {
        let snapshots = [
            Self.snapshot(id: "api-b", image: "example/api:latest"),
            Self.snapshot(id: "worker", image: "example/worker:latest"),
            Self.snapshot(id: "api-a", image: "example/api:latest"),
        ]
        let projection = ContainerGridProjection.build(.init(snapshots: snapshots,
                                                              networks: [], grouping: .image,
                                                              sort: .name, runningOnly: false,
                                                              search: ""))

        #expect(projection.groups.map { $0.id } == ["image:example/api:latest", "image:example/worker:latest"])
        #expect(projection.groups[0].containers.map { $0.scopedID } == [
            "apple-container::api-a", "apple-container::api-b",
        ])
    }

    @Test func cardPlacementKeepsRepeatedContainerAppearancesDistinct() {
        let apple = Self.snapshot(id: "web", image: "nginx:latest", runtimeKind: .appleContainer)
        let docker = Self.snapshot(id: "web", image: "nginx:latest", runtimeKind: .docker)

        let networkAppearance = ContainerGridCardPlacement(groupID: "network:frontend", snapshot: apple)
        let databaseAppearance = ContainerGridCardPlacement(groupID: "network:database", snapshot: apple)
        let dockerAppearance = ContainerGridCardPlacement(groupID: "network:frontend", snapshot: docker)

        #expect(networkAppearance != databaseAppearance)
        #expect(networkAppearance != dockerAppearance)
        #expect(Set([networkAppearance, databaseAppearance, dockerAppearance]).count == 3)
    }

    @Test @MainActor func unchangedLargeInputDoesNotRebuildProjection() async {
        let snapshots = (0..<500).map { Self.snapshot(id: "container-\($0)", image: "example/app:latest") }
        let input = ContainerGridProjection.Input(snapshots: snapshots,
                                                  networks: [], grouping: .flat, sort: .name,
                                                  runningOnly: false, search: "")
        let state = ContainerGridProjectionState()

        await state.update(input)
        await state.update(input)

        #expect(state.buildCount == 1)
        #expect(state.projection.visibleCount == 500)
    }

    @Test @MainActor func onlyNewestProjectionGenerationPublishes() async {
        let state = ContainerGridProjectionState()
        let first = ContainerGridProjection.Input(
            snapshots: (0..<500).map { Self.snapshot(id: "old-\($0)", image: "example/old:latest") },
            networks: [], grouping: .flat, sort: .name, runningOnly: false, search: ""
        )
        let newest = ContainerGridProjection.Input(
            snapshots: [Self.snapshot(id: "newest", image: "example/new:latest")],
            networks: [], grouping: .flat, sort: .name, runningOnly: false, search: ""
        )

        let obsolete = Task { await state.update(first) }
        await Task.yield()
        await state.update(newest)
        await obsolete.value

        #expect(state.projection.groups.flatMap(\.containers).map(\.id) == ["newest"])
    }

    private static func snapshot(id: String,
                                 image: String,
                                 runtimeKind: Core.Runtime.Kind = .appleContainer) -> Core.Container.Snapshot {
        .placeholder(id: id, image: image, runtimeKind: runtimeKind)
    }
}
