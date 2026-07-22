import Foundation
import XCTest
@testable import CodexQuotaApp

final class DiagnosticLoggerTests: XCTestCase {
    func testAppendCrossingBoundaryRotatesBeforeWriting() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("app.log")
        let original = Data(repeating: 0x61, count: Int(DiagnosticLogger.maximumBytes - 1))
        try original.write(to: logURL)

        await DiagnosticLogger(fileURL: logURL).log(subsystem: .reader, code: .scanFailed)

        XCTAssertEqual(try Data(contentsOf: logURL.appendingPathExtension("1")), original)
        XCTAssertLessThan(try fileSize(at: logURL), DiagnosticLogger.maximumBytes)
    }

    func testFileAtBoundaryRotatesBeforeWriting() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("app.log")
        let original = Data(repeating: 0x62, count: Int(DiagnosticLogger.maximumBytes))
        try original.write(to: logURL)

        await DiagnosticLogger(fileURL: logURL).log(subsystem: .cache, code: .cacheSaveFailed)

        XCTAssertEqual(try Data(contentsOf: logURL.appendingPathExtension("1")), original)
        XCTAssertLessThan(try fileSize(at: logURL), DiagnosticLogger.maximumBytes)
    }

    func testRotationReplacesExistingRotatedFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("app.log")
        let rotatedURL = logURL.appendingPathExtension("1")
        let original = Data(repeating: 0x63, count: Int(DiagnosticLogger.maximumBytes - 1))
        try original.write(to: logURL)
        try Data("previous rotation".utf8).write(to: rotatedURL)

        await DiagnosticLogger(fileURL: logURL).log(
            subsystem: .loginItem,
            code: .loginItemUpdateFailed
        )

        XCTAssertEqual(try Data(contentsOf: rotatedURL), original)
        XCTAssertLessThan(try fileSize(at: logURL), DiagnosticLogger.maximumBytes)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticLoggerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap((attributes[.size] as? NSNumber)?.uint64Value)
    }
}
