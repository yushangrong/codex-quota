import Foundation

public enum QuotaEventReaderError: Error {
    case scanFailed
}

public actor QuotaEventReader {
    typealias ReadOperation = @Sendable (URL, UInt64) throws -> (data: Data, offset: UInt64)

    private struct FileIdentity: Equatable {
        let inode: UInt64?
        let creationDate: Date?
    }

    private struct Cursor {
        var offset: UInt64
        var pending: Data
        var identity: FileIdentity
    }

    private let roots: [URL]
    private let readOperation: ReadOperation
    private var cursors: [URL: Cursor] = [:]
    private var latestSnapshots: [URL: QuotaSnapshot] = [:]

    public init(roots: [URL]) {
        self.roots = roots.map { $0.standardizedFileURL }
        self.readOperation = Self.readFile
    }

    init(roots: [URL], readOperation: @escaping ReadOperation) {
        self.roots = roots.map { $0.standardizedFileURL }
        self.readOperation = readOperation
    }

    public func scan() throws -> QuotaSnapshot? {
        let inventory = jsonlFiles()
        let files = inventory.files
        let discoveredFiles = Set(files.map(\.standardizedFileURL))
        let retainedFiles = Set(cursors.keys).union(latestSnapshots.keys)
        let removedFiles = Self.retainedFilesToRemove(
            retained: retainedFiles,
            discovered: discoveredFiles,
            completelyInventoriedRoots: inventory.completelyInventoriedRoots
        )
        cursors = cursors.filter { !removedFiles.contains($0.key) }
        latestSnapshots = latestSnapshots.filter { !removedFiles.contains($0.key) }
        var hadFailure = inventory.hadFailure
        var decodedValidSnapshot = false

        for fileURL in files {
            let key = fileURL.standardizedFileURL

            do {
                let metadata = try metadata(for: fileURL)
                var cursor = cursors[key] ?? .init(offset: 0, pending: Data(), identity: metadata.identity)

                if cursor.identity != metadata.identity || metadata.size < cursor.offset {
                    cursor = .init(offset: 0, pending: Data(), identity: metadata.identity)
                    latestSnapshots.removeValue(forKey: key)
                }

                let read = try readOperation(fileURL, cursor.offset)
                cursor.offset = read.offset
                cursor.identity = metadata.identity

                let completeLines = append(read.data, to: &cursor.pending)
                let fingerprint = sourceFingerprint(for: fileURL.lastPathComponent)

                for line in completeLines {
                    guard
                        let text = String(data: line, encoding: .utf8),
                        let event = QuotaEventDecoder.decode(line: text),
                        let snapshot = QuotaSelector.snapshot(from: event, sourceFingerprint: fingerprint)
                    else {
                        continue
                    }
                    decodedValidSnapshot = true

                    if latestSnapshots[key].map({ snapshot.observedAt > $0.observedAt }) ?? true {
                        latestSnapshots[key] = snapshot
                    }
                }

                cursors[key] = cursor
            } catch {
                hadFailure = true
            }
        }

        if hadFailure && !decodedValidSnapshot {
            throw QuotaEventReaderError.scanFailed
        }
        return latestSnapshots.values.max { $0.observedAt < $1.observedAt }
    }

    nonisolated static func retainedFilesToRemove(
        retained: Set<URL>,
        discovered: Set<URL>,
        completelyInventoriedRoots: Set<URL>
    ) -> Set<URL> {
        retained.filter { fileURL in
            guard !discovered.contains(fileURL) else { return false }
            return completelyInventoriedRoots.contains { root in
                let rootComponents = root.standardizedFileURL.pathComponents
                let fileComponents = fileURL.standardizedFileURL.pathComponents
                return fileComponents.starts(with: rootComponents)
            }
        }
    }

    private func jsonlFiles() -> (
        files: [URL],
        completelyInventoriedRoots: Set<URL>,
        hadFailure: Bool
    ) {
        var files = [URL]()
        var completelyInventoriedRoots = Set<URL>()
        var hadFailure = false
        var usableRoots = 0
        let manager = FileManager.default

        for root in roots {
            let values: URLResourceValues
            do {
                values = try root.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            } catch let error as CocoaError where
                error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
            {
                completelyInventoriedRoots.insert(root)
                continue
            } catch {
                hadFailure = true
                continue
            }

            if values.isRegularFile == true {
                if root.pathExtension.lowercased() == "jsonl" {
                    usableRoots += 1
                    files.append(root)
                    completelyInventoriedRoots.insert(root)
                } else {
                    hadFailure = true
                }
                continue
            }

            guard values.isDirectory == true else {
                hadFailure = true
                continue
            }
            usableRoots += 1

            var enumerationFailed = false
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in
                    enumerationFailed = true
                    return false
                }
            ) else {
                hadFailure = true
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "jsonl" {
                do {
                    if try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                        files.append(fileURL.standardizedFileURL)
                    }
                } catch {
                    enumerationFailed = true
                }
            }
            hadFailure = hadFailure || enumerationFailed
            if !enumerationFailed {
                completelyInventoriedRoots.insert(root)
            }
        }

        if usableRoots == 0 { hadFailure = true }
        return (
            Array(Set(files)).sorted { $0.path < $1.path },
            completelyInventoriedRoots,
            hadFailure
        )
    }

    private func metadata(for fileURL: URL) throws -> (size: UInt64, identity: FileIdentity) {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard
              let size = (attributes[.size] as? NSNumber)?.uint64Value
        else {
            throw QuotaEventReaderError.scanFailed
        }

        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let creationDate = attributes[.creationDate] as? Date
        return (size, .init(inode: inode, creationDate: creationDate))
    }

    private nonisolated static func readFile(
        _ fileURL: URL,
        from offset: UInt64
    ) throws -> (data: Data, offset: UInt64) {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        return (data, handle.offsetInFile)
    }

    private func append(_ data: Data, to pending: inout Data) -> [Data] {
        pending.append(data)
        let segments = pending.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return [] }

        let lastIndex = segments.index(before: segments.endIndex)
        let completeLines = segments[..<lastIndex].map { Data($0) }

        guard pending.last == 0x0A else {
            pending = Data(segments[lastIndex])
            return completeLines
        }

        pending.removeAll(keepingCapacity: true)
        return completeLines
    }

    private func sourceFingerprint(for filename: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in filename.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
