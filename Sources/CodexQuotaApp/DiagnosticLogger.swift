import Foundation

enum DiagnosticSubsystem: String, Sendable {
    case cache
    case reader
    case loginItem = "login_item"
}

enum DiagnosticErrorCode: String, Sendable {
    case cacheLoadFailed = "CACHE_LOAD_FAILED"
    case cacheSaveFailed = "CACHE_SAVE_FAILED"
    case scanFailed = "SCAN_FAILED"
    case loginItemUpdateFailed = "LOGIN_ITEM_UPDATE_FAILED"
}

actor DiagnosticLogger {
    static let maximumBytes: UInt64 = 256 * 1_024

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func log(subsystem: DiagnosticSubsystem, code: DiagnosticErrorCode) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(timestamp) subsystem=\(subsystem.rawValue) code=\(code.rawValue)\n"
            let data = Data(line.utf8)
            try rotateIfNeeded(appendingByteCount: UInt64(data.count))
            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            return
        }
    }

    private func rotateIfNeeded(appendingByteCount: UInt64) throws {
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let (projectedSize, overflowed) = size.addingReportingOverflow(appendingByteCount)
        guard size > 0,
              overflowed || projectedSize > Self.maximumBytes else {
            return
        }

        let rotatedURL = fileURL.appendingPathExtension("1")
        if fileManager.fileExists(atPath: rotatedURL.path) {
            try fileManager.removeItem(at: rotatedURL)
        }
        try fileManager.moveItem(at: fileURL, to: rotatedURL)
    }
}
