import Foundation
import XCTest
@testable import CodexQuotaCore

final class QuotaEventReaderTests: XCTestCase {
    func testLaterReadFailureDoesNotDowngradeToOlderRetainedSnapshot() async throws {
        try await withTemporaryDirectory { directory in
            let newerURL = directory.appendingPathComponent("newer.jsonl")
            let olderURL = directory.appendingPathComponent("older.jsonl")
            try Data(makeEvent(usedPercent: 60, timestamp: "2026-07-21T08:00:00.000Z").utf8).write(to: newerURL)
            try Data(makeEvent(usedPercent: 40, timestamp: "2026-07-21T07:00:00.000Z").utf8).write(to: olderURL)
            let gate = ReadFailureGate()
            let reader = QuotaEventReader(roots: [directory]) { url, offset in
                if gate.shouldFail(url) {
                    throw CocoaError(.fileReadNoPermission)
                }
                return try Self.readFile(url, from: offset)
            }

            XCTAssertEqual(try await reader.scan()?.usedPercent, 60)
            gate.fail(fileNamed: newerURL.lastPathComponent)

            do {
                _ = try await reader.scan()
                XCTFail("A failed newer source must not be downgraded to an older retained snapshot")
            } catch {
                XCTAssertTrue(error is QuotaEventReaderError)
            }
        }
    }

    func testPartialInventoryDoesNotPruneRetainedFilesFromFailedRoot() {
        let root = URL(fileURLWithPath: "/tmp/sessions", isDirectory: true)
        let retained = Set([
            root.appendingPathComponent("kept.jsonl"),
            root.appendingPathComponent("also-kept.jsonl"),
        ])

        let removed = QuotaEventReader.retainedFilesToRemove(
            retained: retained,
            discovered: [root.appendingPathComponent("kept.jsonl")],
            completelyInventoriedRoots: []
        )

        XCTAssertTrue(removed.isEmpty)
    }

    func testAllConfiguredRootsMissingThrows() async throws {
        try await withTemporaryDirectory { directory in
            let firstMissingRoot = directory.appendingPathComponent("missing-sessions", isDirectory: true)
            let secondMissingRoot = directory.appendingPathComponent("missing-archive", isDirectory: true)
            let reader = QuotaEventReader(roots: [firstMissingRoot, secondMissingRoot])

            do {
                _ = try await reader.scan()
                XCTFail("Expected a scan failure when every configured root is missing")
            } catch {
                // Expected: callers must be able to activate diagnostics and backoff.
            }
        }
    }

    func testExistingEmptyRootIsSuccessfulEmptyScan() async throws {
        try await withTemporaryDirectory { directory in
            let reader = QuotaEventReader(roots: [directory])

            let result = try await reader.scan()

            XCTAssertNil(result)
        }
    }

    func testMissingOptionalRootDoesNotFailWhenAnotherRootIsUsable() async throws {
        try await withTemporaryDirectory { directory in
            let reader = QuotaEventReader(roots: [
                directory,
                directory.appendingPathComponent("missing-archive", isDirectory: true),
            ])

            XCTAssertNil(try await reader.scan())
        }
    }

    func testReadFailureWithoutValidSnapshotThrows() async throws {
        try await withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("unreadable.jsonl")
            try Data(makeIgnoredEvent(timestamp: "2026-07-21T07:00:00.000Z").utf8).write(to: fileURL)
            let reader = QuotaEventReader(roots: [directory]) { _, _ in
                throw CocoaError(.fileReadNoPermission)
            }

            do {
                _ = try await reader.scan()
                XCTFail("Expected the injected read failure to propagate")
            } catch {
                XCTAssertTrue(error is QuotaEventReaderError)
            }
        }
    }

    func testBadFileDoesNotHideValidSnapshotFromAnotherRoot() async throws {
        try await withTemporaryDirectory { directory in
            let badRoot = directory.appendingPathComponent("bad", isDirectory: true)
            let goodRoot = directory.appendingPathComponent("good", isDirectory: true)
            try FileManager.default.createDirectory(at: badRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: goodRoot, withIntermediateDirectories: true)
            let badURL = badRoot.appendingPathComponent("bad.jsonl")
            let goodURL = goodRoot.appendingPathComponent("good.jsonl")
            try Data(makeIgnoredEvent(timestamp: "2026-07-21T07:00:00.000Z").utf8).write(to: badURL)
            try Data(makeEvent(usedPercent: 37, timestamp: "2026-07-21T08:00:00.000Z").utf8).write(to: goodURL)
            let reader = QuotaEventReader(roots: [badRoot, goodRoot]) { url, offset in
                if url.lastPathComponent == "bad.jsonl" {
                    throw CocoaError(.fileReadNoPermission)
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: offset)
                let data = try handle.readToEnd() ?? Data()
                return (data, handle.offsetInFile)
            }

            XCTAssertEqual(try await reader.scan()?.usedPercent, 37)
        }
    }

    func testPartialLineIsRetainedUntilItIsCompleted() async throws {
        try await withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("rollout.jsonl")
            let reader = QuotaEventReader(roots: [directory])
            let event = makeEvent(usedPercent: 40, timestamp: "2026-07-21T07:30:27.974Z")

            try Data(event.dropLast(2).utf8).write(to: fileURL)
            let partialResult = await reader.scan()
            XCTAssertNil(partialResult)

            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(event.suffix(2).utf8))
            try handle.close()

            let completedResult = await reader.scan()
            XCTAssertEqual(completedResult?.usedPercent, 40)
        }
    }

    func testAppendedNewerEventWins() async throws {
        try await withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("rollout.jsonl")
            let reader = QuotaEventReader(roots: [directory])
            try Data(makeEvent(usedPercent: 40, timestamp: "2026-07-21T07:30:27.974Z").utf8).write(to: fileURL)
            let initialResult = await reader.scan()
            XCTAssertEqual(initialResult?.usedPercent, 40)

            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(makeEvent(usedPercent: 41, timestamp: "2026-07-21T07:31:27.974Z").utf8))
            try handle.close()

            let appendedResult = await reader.scan()
            XCTAssertEqual(appendedResult?.usedPercent, 41)
        }
    }

    func testOlderAppendedEventDoesNotReplaceLatestInSameFile() async throws {
        try await withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("rollout.jsonl")
            let reader = QuotaEventReader(roots: [directory])
            try Data(makeEvent(usedPercent: 60, timestamp: "2026-07-21T08:00:00.000Z").utf8).write(to: fileURL)
            let initialResult = await reader.scan()
            XCTAssertEqual(initialResult?.usedPercent, 60)

            try append(makeEvent(usedPercent: 50, timestamp: "2026-07-21T07:30:00.000Z"), to: fileURL)

            let nextResult = await reader.scan()
            XCTAssertEqual(nextResult?.usedPercent, 60)
        }
    }

    func testTruncationResetsCursor() async throws {
        try await withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("rollout.jsonl")
            let reader = QuotaEventReader(roots: [directory])
            let initial = makeEvent(usedPercent: 40, timestamp: "2026-07-21T07:30:27.974Z")
                + makeIgnoredEvent(timestamp: "2026-07-21T07:30:28.974Z")
            try Data(initial.utf8).write(to: fileURL)
            let initialResult = await reader.scan()
            XCTAssertEqual(initialResult?.usedPercent, 40)

            try Data(makeIgnoredEvent(timestamp: "2026-07-21T07:31:27.974Z").utf8).write(to: fileURL)

            let clearedResult = await reader.scan()
            XCTAssertNil(clearedResult)

            try append(makeEvent(usedPercent: 41, timestamp: "2026-07-21T07:32:27.974Z"), to: fileURL)

            let truncatedResult = await reader.scan()
            XCTAssertEqual(truncatedResult?.usedPercent, 41)
        }
    }

    func testAtomicReplacementResetsCursorEvenWhenReplacementIsNotSmaller() async throws {
        try await withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("rollout.jsonl")
            let replacementURL = directory.appendingPathComponent("replacement.jsonl")
            let reader = QuotaEventReader(roots: [directory])
            try Data(makeEvent(usedPercent: 40, timestamp: "2026-07-21T07:30:27.974Z").utf8).write(to: fileURL)
            let initialResult = await reader.scan()
            XCTAssertEqual(initialResult?.usedPercent, 40)

            let replacement = makeEvent(usedPercent: 42, timestamp: "2026-07-21T07:32:27.974Z")
                + makeIgnoredEvent(timestamp: "2026-07-21T07:32:28.974Z")
            try Data(replacement.utf8).write(to: replacementURL)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: replacementURL)

            let replacementResult = await reader.scan()
            XCTAssertEqual(replacementResult?.usedPercent, 42)
        }
    }

    func testNewestEventAcrossFilesWins() async throws {
        try await withTemporaryDirectory { directory in
            let olderURL = directory.appendingPathComponent("older.jsonl")
            let newerDirectory = directory.appendingPathComponent("nested")
            try FileManager.default.createDirectory(at: newerDirectory, withIntermediateDirectories: true)
            let newerURL = newerDirectory.appendingPathComponent("newer.jsonl")
            let reader = QuotaEventReader(roots: [directory])

            try Data(makeEvent(usedPercent: 40, timestamp: "2026-07-21T07:30:27.974Z").utf8).write(to: olderURL)
            try Data(makeEvent(usedPercent: 41, timestamp: "2026-07-21T07:31:27.974Z").utf8).write(to: newerURL)

            let newestResult = await reader.scan()
            XCTAssertEqual(newestResult?.usedPercent, 41)
        }
    }

    func testNewestEventAcrossFilesIsRetainedAcrossScans() async throws {
        try await withTemporaryDirectory { directory in
            let newerURL = directory.appendingPathComponent("newer.jsonl")
            let olderURL = directory.appendingPathComponent("older.jsonl")
            let reader = QuotaEventReader(roots: [directory])
            try Data(makeEvent(usedPercent: 60, timestamp: "2026-07-21T08:00:00.000Z").utf8).write(to: newerURL)
            try Data(makeEvent(usedPercent: 40, timestamp: "2026-07-21T07:00:00.000Z").utf8).write(to: olderURL)
            let initialResult = await reader.scan()
            XCTAssertEqual(initialResult?.usedPercent, 60)

            try append(makeEvent(usedPercent: 50, timestamp: "2026-07-21T07:30:00.000Z"), to: olderURL)

            let nextResult = await reader.scan()
            XCTAssertEqual(nextResult?.usedPercent, 60)
        }
    }

    func testRemovedFileNoLongerContributesRetainedSnapshot() async throws {
        try await withTemporaryDirectory { directory in
            let newerURL = directory.appendingPathComponent("newer.jsonl")
            let olderURL = directory.appendingPathComponent("older.jsonl")
            let reader = QuotaEventReader(roots: [directory])
            try Data(makeEvent(usedPercent: 60, timestamp: "2026-07-21T08:00:00.000Z").utf8).write(to: newerURL)
            try Data(makeEvent(usedPercent: 40, timestamp: "2026-07-21T07:00:00.000Z").utf8).write(to: olderURL)
            let initialResult = await reader.scan()
            XCTAssertEqual(initialResult?.usedPercent, 60)

            try FileManager.default.removeItem(at: newerURL)

            let remainingResult = await reader.scan()
            XCTAssertEqual(remainingResult?.usedPercent, 40)
        }
    }

    func testReaderToCacheExcludesPrivateTextPathsAndNonJSONLFiles() async throws {
        try await withTemporaryDirectory { directory in
            let privateDirectoryName = "PRIVATE_PATH_\(UUID().uuidString)"
            let privateDirectory = directory.appendingPathComponent(privateDirectoryName, isDirectory: true)
            try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
            let jsonlURL = privateDirectory.appendingPathComponent("private-rollout.jsonl")
            let ignoredURL = privateDirectory.appendingPathComponent("ignored.txt")
            let cacheURL = directory.appendingPathComponent("cache/quota.json")
            let reader = QuotaEventReader(roots: [directory])
            try Data(makeEvent(usedPercent: 40, timestamp: "2026-07-21T08:00:00.000Z").utf8).write(to: jsonlURL)
            try Data(makeEvent(usedPercent: 99, timestamp: "2026-07-21T09:00:00.000Z").utf8).write(to: ignoredURL)

            let scannedSnapshot = await reader.scan()
            let snapshot = try XCTUnwrap(scannedSnapshot)
            XCTAssertEqual(snapshot.usedPercent, 40)
            XCTAssertFalse(snapshot.sourceFingerprint.contains(privateDirectoryName))
            XCTAssertFalse(snapshot.sourceFingerprint.contains(jsonlURL.lastPathComponent))

            let cache = QuotaCache(fileURL: cacheURL)
            try cache.save(snapshot)
            let cacheText = try String(contentsOf: cacheURL, encoding: .utf8)
            XCTAssertFalse(cacheText.contains("PRIVATE_TEXT_MUST_NOT_SURVIVE"))
            XCTAssertFalse(cacheText.contains(privateDirectoryName))
            XCTAssertFalse(cacheText.contains(jsonlURL.lastPathComponent))
        }
    }

    func testCacheSerializesOnlySnapshotFields() async throws {
        try await withTemporaryDirectory { directory in
            let cacheURL = directory.appendingPathComponent("cache/quota.json")
            let snapshot = QuotaSnapshot(
                usedPercent: 40,
                windowMinutes: 10_080,
                resetsAt: Date(timeIntervalSince1970: 1_800_259_200),
                observedAt: Date(timeIntervalSince1970: 1_800_000_000),
                sourceFingerprint: "fixture"
            )
            let cache = QuotaCache(fileURL: cacheURL)

            try cache.save(snapshot)

            XCTAssertEqual(try cache.load(), snapshot)
            XCTAssertFalse(try String(contentsOf: cacheURL, encoding: .utf8).contains("PRIVATE_TEXT_MUST_NOT_SURVIVE"))
        }
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async rethrows {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func append(_ text: String, to fileURL: URL) throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private static func readFile(_ fileURL: URL, from offset: UInt64) throws -> (data: Data, offset: UInt64) {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        return (data, handle.offsetInFile)
    }

    private func makeEvent(usedPercent: Double, timestamp: String) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"message\":\"PRIVATE_TEXT_MUST_NOT_SURVIVE\",\"rate_limits\":{\"limit_id\":\"codex\",\"primary\":{\"used_percent\":\(usedPercent),\"window_minutes\":10080,\"resets_at\":1800259200},\"secondary\":null}}}\n"
    }

    private func makeIgnoredEvent(timestamp: String) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"message\":\"PRIVATE_TEXT_MUST_NOT_SURVIVE\",\"rate_limits\":{\"limit_id\":\"other\",\"primary\":{\"used_percent\":43,\"window_minutes\":10080,\"resets_at\":1800259200},\"secondary\":null}}}\n"
    }
}

private final class ReadFailureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var failedFilename: String?

    func fail(fileNamed filename: String) {
        lock.withLock { failedFilename = filename }
    }

    func shouldFail(_ url: URL) -> Bool {
        lock.withLock { failedFilename == url.lastPathComponent }
    }
}
