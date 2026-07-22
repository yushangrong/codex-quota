import Foundation

public struct QuotaCache: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> QuotaSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(QuotaSnapshot.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ value: QuotaSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
    }
}
