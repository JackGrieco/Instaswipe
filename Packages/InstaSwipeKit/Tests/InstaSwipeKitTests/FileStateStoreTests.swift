import Foundation
import Testing
@testable import InstaSwipeKit

private func withTempDirs(_ body: (URL, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root.appendingPathComponent("local"), root.appendingPathComponent("cloud"))
}

private func state(savedAt seconds: TimeInterval, users: [String] = ["a"]) -> AppState {
    var result = Fixtures.state(users.map { Fixtures.account($0, since: nil) })
    result.savedAt = Date(timeIntervalSince1970: seconds)
    return result
}

private func names(_ directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
}

private func corrupt(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: directory.appendingPathComponent("state.json"))
}

@Test func saveThenLoadReturnsSameState() throws {
    try withTempDirs { local, cloud in
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        let saved = state(savedAt: 1_000.5)
        try store.save(saved)
        #expect(try store.load() == saved)
    }
}

@Test func saveIsAtomicLeavesNoTempFiles() throws {
    try withTempDirs { local, cloud in
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        try store.save(state(savedAt: 1))
        try store.save(state(savedAt: 2))
        try store.mirrorToCloud(state(savedAt: 2))
        #expect(names(local) == ["state.json"])
        #expect(names(cloud) == ["state.json"])
    }
}

@Test func loadPrefersNewestOfLocalAndCloud() throws {
    try withTempDirs { local, cloud in
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        try store.save(state(savedAt: 100, users: ["old"]))
        try store.mirrorToCloud(state(savedAt: 200, users: ["new"]))
        #expect(try store.load()?.accounts.map(\.username) == ["new"])
        let localOnly = FileStateStore(localDirectory: local, cloudDirectory: nil)
        #expect(try localOnly.load()?.savedAt == Date(timeIntervalSince1970: 200))
    }
}

@Test func loadKeepsLocalWhenLocalIsNewer() throws {
    try withTempDirs { local, cloud in
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        try store.save(state(savedAt: 300, users: ["local"]))
        try store.mirrorToCloud(state(savedAt: 200, users: ["cloud"]))
        #expect(try store.load()?.accounts.map(\.username) == ["local"])
    }
}

@Test func loadRestoresFromCloudWhenLocalMissing() throws {
    try withTempDirs { local, cloud in
        try FileStateStore(localDirectory: local, cloudDirectory: cloud)
            .mirrorToCloud(state(savedAt: 50))
        let reinstalled = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        #expect(try reinstalled.load() == state(savedAt: 50))
        #expect(names(local) == ["state.json"])
    }
}

@Test func loadQuarantinesCorruptLocalAndUsesCloud() throws {
    try withTempDirs { local, cloud in
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        try store.mirrorToCloud(state(savedAt: 70))
        try corrupt(local)
        #expect(try store.load() == state(savedAt: 70))
        let files = names(local)
        #expect(files.count == 2)
        #expect(files.contains("state.json"))
        #expect(files.contains { $0.hasPrefix("state.corrupt-") && $0.hasSuffix(".json") })
        let quarantined = try #require(files.first { $0.hasPrefix("state.corrupt-") })
        #expect(try Data(contentsOf: local.appendingPathComponent(quarantined)) == Data("{ not json".utf8))
    }
}

@Test func loadThrowsWhenBothCorrupt() throws {
    try withTempDirs { local, cloud in
        try corrupt(local)
        try corrupt(cloud)
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        do {
            _ = try store.load()
            Issue.record("expected StateStoreError.corrupted")
        } catch let StateStoreError.corrupted(quarantined) {
            #expect(quarantined.count == 2)
            #expect(quarantined.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        }
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("state.json").path))
        #expect(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("state.json").path))
    }
}

@Test func quarantineNeverOverwritesExistingFile() throws {
    try withTempDirs { local, _ in
        let store = FileStateStore(localDirectory: local, cloudDirectory: nil)
        for _ in 0..<3 {
            try corrupt(local)
            #expect(throws: StateStoreError.self) { try store.load() }
        }
        #expect(names(local).filter { $0.hasPrefix("state.corrupt-") }.count == 3)
    }
}

@Test func loadReturnsNilWhenNothingSaved() throws {
    try withTempDirs { local, cloud in
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        let loaded = try store.load()
        #expect(loaded == nil)
        #expect(!FileManager.default.fileExists(atPath: local.path))
    }
}

@Test func storeWorksWithoutCloudDirectory() throws {
    try withTempDirs { local, _ in
        let store = FileStateStore(localDirectory: local, cloudDirectory: nil)
        try store.save(state(savedAt: 9))
        try store.mirrorToCloud(state(savedAt: 9))
        #expect(try store.load() == state(savedAt: 9))
    }
}

private func placeholder(_ cloud: URL) throws -> URL {
    try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
    let url = cloud.appendingPathComponent(".state.json.icloud")
    try Data("placeholder".utf8).write(to: url)
    return url
}

@Test func cloudPlaceholderWithoutLocalThrowsNotDownloaded() throws {
    try withTempDirs { local, cloud in
        let marker = try placeholder(cloud)
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        #expect(throws: StateStoreError.cloudNotDownloaded) { try store.load() }
        #expect(try Data(contentsOf: marker) == Data("placeholder".utf8))
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("state.json").path))
    }
}

@Test func cloudPlaceholderWithCorruptLocalThrowsNotDownloaded() throws {
    try withTempDirs { local, cloud in
        _ = try placeholder(cloud)
        try corrupt(local)
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        #expect(throws: StateStoreError.cloudNotDownloaded) { try store.load() }
    }
}

@Test func cloudPlaceholderWithValidLocalReturnsLocal() throws {
    try withTempDirs { local, cloud in
        let marker = try placeholder(cloud)
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        try store.save(state(savedAt: 5))
        #expect(try store.load() == state(savedAt: 5))
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }
}

@Test func loadKeepsThrowingCorruptedAfterQuarantine() throws {
    try withTempDirs { local, _ in
        let store = FileStateStore(localDirectory: local, cloudDirectory: nil)
        try corrupt(local)
        var first: [URL] = []
        do { _ = try store.load() } catch let StateStoreError.corrupted(urls) { first = urls }
        #expect(first.count == 1)
        do {
            _ = try store.load()
            Issue.record("expected StateStoreError.corrupted")
        } catch let StateStoreError.corrupted(urls) {
            #expect(urls == first)
        }
        #expect(names(local).count == 1)
    }
}
