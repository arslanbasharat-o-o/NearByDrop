import Foundation
import Darwin

public struct TransferFileIdentity: Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let size: Int64
    public let modificationSeconds: Int64
    public let modificationNanoseconds: Int64
    public let changeSeconds: Int64
    public let changeNanoseconds: Int64
}

public struct TransferFileSelection: Sendable {
    public struct SkippedEntries: Sendable {
        public internal(set) var symbolicLinks = 0
        public internal(set) var unreadable = 0
        public internal(set) var unsupported = 0

        public var total: Int { symbolicLinks + unreadable + unsupported }

        public var message: String? {
            guard total > 0 else { return nil }
            var parts: [String] = []
            if symbolicLinks > 0 {
                parts.append("\(symbolicLinks) symbolic \(symbolicLinks == 1 ? "link was" : "links were") skipped for safety")
            }
            if unreadable > 0 {
                parts.append("\(unreadable) unreadable \(unreadable == 1 ? "item was" : "items were") skipped")
            }
            if unsupported > 0 {
                parts.append("\(unsupported) unsupported \(unsupported == 1 ? "item was" : "items were") skipped")
            }
            return parts.joined(separator: ". ") + "."
        }
    }

    public let urls: [URL]
    public let displayNames: [String]
    public let identities: [TransferFileIdentity]
    public let skipped: SkippedEntries

    public var emptyMessage: String {
        let details = skipped.message.map { " \($0)" } ?? ""
        return "No transferable files remain. Choose regular files or a folder containing readable files.\(details)"
    }
}

public enum TransferFileSafety {
    public static let maximumFileCount = 128

    public static func expandSelection(_ inputURLs: [URL]) -> TransferFileSelection {
        var urls: [URL] = []
        var names: [String] = []
        var identities: [TransferFileIdentity] = []
        var skipped = TransferFileSelection.SkippedEntries()

        for url in inputURLs {
            guard url.isFileURL else {
                skipped.unsupported += 1
                continue
            }

            guard let status = noFollowStatus(at: url) else {
                skipped.unreadable += 1
                continue
            }
            let kind = status.st_mode & mode_t(S_IFMT)
            if kind == mode_t(S_IFLNK) {
                skipped.symbolicLinks += 1
            } else if kind == mode_t(S_IFDIR) {
                let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
                guard descriptor >= 0 else {
                    skipped.unreadable += 1
                    continue
                }
                var openedDirectory = stat()
                guard Darwin.fstat(descriptor, &openedDirectory) == 0,
                      openedDirectory.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                      sameFile(status, openedDirectory) else {
                    Darwin.close(descriptor)
                    skipped.unreadable += 1
                    continue
                }
                scanDirectory(
                    descriptor: descriptor,
                    url: url,
                    relativePath: url.lastPathComponent,
                    urls: &urls,
                    names: &names,
                    identities: &identities,
                    skipped: &skipped
                )
            } else if kind == mode_t(S_IFREG) {
                do {
                    let identity = try readableIdentity(at: url)
                    guard identity == makeIdentity(status) else {
                        skipped.unreadable += 1
                        continue
                    }
                    urls.append(url)
                    names.append(url.lastPathComponent)
                    identities.append(identity)
                } catch {
                    skipped.unreadable += 1
                }
            } else {
                skipped.unsupported += 1
            }
        }

        return TransferFileSelection(urls: urls, displayNames: names, identities: identities, skipped: skipped)
    }

    static func readableIdentity(at url: URL) throws -> TransferFileIdentity {
        guard let status = noFollowStatus(at: url),
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw TransferFileSafetyError.notRegularFile
        }
        let descriptor = try openDescriptor(at: url)
        defer { Darwin.close(descriptor) }
        var opened = stat()
        guard Darwin.fstat(descriptor, &opened) == 0,
              opened.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw TransferFileSafetyError.unreadable
        }
        let identity = makeIdentity(opened)
        guard identity == makeIdentity(status) else { throw TransferFileSafetyError.changed }
        return identity
    }

    static func openReadOnlyFile(at url: URL, expected identity: TransferFileIdentity) throws -> FileHandle {
        let descriptor = try openDescriptor(at: url)
        var opened = stat()
        guard Darwin.fstat(descriptor, &opened) == 0,
              opened.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              makeIdentity(opened) == identity else {
            Darwin.close(descriptor)
            throw TransferFileSafetyError.changed
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    static func verifyUnchanged(_ handle: FileHandle, expected identity: TransferFileIdentity) throws {
        var opened = stat()
        guard Darwin.fstat(handle.fileDescriptor, &opened) == 0,
              opened.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              makeIdentity(opened) == identity else {
            throw TransferFileSafetyError.changed
        }
    }

    static func readVerifiedChunk(
        from handle: FileHandle,
        expected identity: TransferFileIdentity,
        maximumCount: Int
    ) throws -> Data {
        guard maximumCount > 0 else { throw NearbyError.inputOutput }
        try verifyUnchanged(handle, expected: identity)
        guard let data = try handle.read(upToCount: maximumCount), !data.isEmpty else {
            throw NearbyError.inputOutput
        }
        // The descriptor pins the selected inode. Check after the read and before
        // returning bytes so observable in-place changes are rejected before the
        // buffer is framed. This check is not an atomic filesystem snapshot.
        try verifyUnchanged(handle, expected: identity)
        return data
    }

    private static func openDescriptor(at url: URL) throws -> Int32 {
        // O_NONBLOCK prevents a raced replacement with a FIFO from stalling the
        // shared connection queue before fstat can reject the non-regular file.
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC) }
        guard descriptor >= 0 else { throw TransferFileSafetyError.unreadable }
        return descriptor
    }

    private static func noFollowStatus(at url: URL) -> stat? {
        var status = stat()
        guard url.path.withCString({ Darwin.lstat($0, &status) }) == 0 else { return nil }
        return status
    }

    private static func makeIdentity(_ status: stat) -> TransferFileIdentity {
        TransferFileIdentity(
            device: UInt64(truncatingIfNeeded: status.st_dev),
            inode: UInt64(status.st_ino),
            size: Int64(status.st_size),
            modificationSeconds: Int64(status.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(status.st_mtimespec.tv_nsec),
            changeSeconds: Int64(status.st_ctimespec.tv_sec),
            changeNanoseconds: Int64(status.st_ctimespec.tv_nsec)
        )
    }

    private static func sameFile(_ left: stat, _ right: stat) -> Bool {
        left.st_dev == right.st_dev && left.st_ino == right.st_ino
    }

    private static func scanDirectory(
        descriptor: Int32,
        url: URL,
        relativePath: String,
        urls: inout [URL],
        names: inout [String],
        identities: inout [TransferFileIdentity],
        skipped: inout TransferFileSelection.SkippedEntries
    ) {
        guard let directory = Darwin.fdopendir(descriptor) else {
            Darwin.close(descriptor)
            skipped.unreadable += 1
            return
        }
        defer { Darwin.closedir(directory) }

        var childNames: [String] = []
        while let entry = Darwin.readdir(directory) {
            let childName = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(Darwin.MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            guard childName != ".", childName != "..", !childName.hasPrefix(".") else { continue }
            childNames.append(childName)
        }

        let parentDescriptor = Darwin.dirfd(directory)
        for childName in childNames.sorted() {
            var entryStatus = stat()
            let statusResult = childName.withCString {
                Darwin.fstatat(parentDescriptor, $0, &entryStatus, AT_SYMLINK_NOFOLLOW)
            }
            guard statusResult == 0 else {
                skipped.unreadable += 1
                continue
            }

            let childURL = url.appendingPathComponent(childName, isDirectory: false)
            let childRelativePath = "\(relativePath)/\(childName)"
            let kind = entryStatus.st_mode & mode_t(S_IFMT)
            if kind == mode_t(S_IFLNK) {
                skipped.symbolicLinks += 1
                continue
            }
            if kind == mode_t(S_IFDIR) {
                let childDescriptor = childName.withCString {
                    Darwin.openat(parentDescriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard childDescriptor >= 0 else {
                    skipped.unreadable += 1
                    continue
                }
                var openedStatus = stat()
                guard Darwin.fstat(childDescriptor, &openedStatus) == 0,
                      openedStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                      sameFile(entryStatus, openedStatus) else {
                    Darwin.close(childDescriptor)
                    skipped.unreadable += 1
                    continue
                }
                scanDirectory(
                    descriptor: childDescriptor,
                    url: childURL,
                    relativePath: childRelativePath,
                    urls: &urls,
                    names: &names,
                    identities: &identities,
                    skipped: &skipped
                )
                continue
            }
            guard kind == mode_t(S_IFREG) else {
                skipped.unsupported += 1
                continue
            }

            let fileDescriptor = childName.withCString {
                Darwin.openat(parentDescriptor, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            }
            guard fileDescriptor >= 0 else {
                skipped.unreadable += 1
                continue
            }
            var openedStatus = stat()
            let valid = Darwin.fstat(fileDescriptor, &openedStatus) == 0
                && openedStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
                && sameFile(entryStatus, openedStatus)
            Darwin.close(fileDescriptor)
            guard valid else {
                skipped.unreadable += 1
                continue
            }

            urls.append(childURL)
            names.append(childRelativePath)
            identities.append(makeIdentity(openedStatus))
        }
    }
}

private enum TransferFileSafetyError: LocalizedError {
    case notRegularFile
    case unreadable
    case changed

    var errorDescription: String? {
        switch self {
        case .notRegularFile: return "A selected item is no longer a regular file."
        case .unreadable: return "A selected file is no longer readable. Check its permissions and try again."
        case .changed: return "A selected file changed after it was chosen. Select it again and retry."
        }
    }
}
