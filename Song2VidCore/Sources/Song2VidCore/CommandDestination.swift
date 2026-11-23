import Foundation

/// A checked destination for `make` or `preview` and the atomic step that publishes it (ADR-014).
struct CommandDestination: Sendable {
    /// The final name. Nothing is written here until the video is complete.
    let url: URL
    /// The file name only: a folder never reaches the output.
    var name: String { url.lastPathComponent }
    var folder: URL { url.deletingLastPathComponent() }

    /// The temporary file sits beside the final name, so the move stays on one volume.
    func temporaryURL() -> URL {
        folder.appendingPathComponent(".song2vid-\(UUID().uuidString).\(url.pathExtension.lowercased()).song2vid-tmp")
    }

    /// Checks the output name and folder. Without `overwrite`, a file already there is an error.
    /// Nothing is created or changed.
    static func plan(
        url: URL, inputs: [URL], overwrite: Bool
    ) throws(CommandError) -> CommandDestination {
        let output = CommandDestination(url: url)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: output.folder.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw .outputFolderNotFound }
        guard FileManager.default.isWritableFile(atPath: output.folder.path) else { throw .outputFolderNotWritable }

        // An entry of any kind at the output (a dangling link counts) is "already there".
        var entry = stat()
        guard lstat(url.path, &entry) == 0 else { return output }
        // Never the person's own song or image, whatever the name and whatever --overwrite says.
        var target = stat()
        if stat(url.path, &target) == 0, inputs.contains(where: { isSameFile($0, as: target) }) {
            throw .outputIsAnInput
        }
        guard overwrite else { throw .outputExists }
        guard entry.st_mode & S_IFMT != S_IFDIR else { throw .outputIsAFolder }
        return output
    }

    private static func isSameFile(_ url: URL, as other: stat) -> Bool {
        var info = stat()
        return stat(url.path, &info) == 0 && info.st_dev == other.st_dev && info.st_ino == other.st_ino
    }

    /// Moves the finished file from `temporary` to the final name, which is touched only here.
    /// The caller cleans up the temporary name, including if a competing writer took the final name.
    func place(_ temporary: URL, overwrite: Bool) throws(CommandError) {
        if overwrite {
            // rename() replaces the old file in one step: there is no moment with neither file.
            guard rename(temporary.path, url.path) == 0 else { throw Self.writeError(for: errno) }
            return
        }
        // Rename only if nothing is there, as one step, so a file that appeared during the run is never replaced.
        if renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL)) == 0 { return }
        var problem = errno
        // A volume that can't do that: a hard link also fails if the name is taken.
        if problem == ENOTSUP || problem == EINVAL {
            if link(temporary.path, url.path) == 0 { return }
            problem = errno
        }
        throw problem == EEXIST ? .outputExists : Self.writeError(for: problem)
    }

    private static func writeError(for code: Int32) -> CommandError {
        switch code {
        case ENOSPC, EDQUOT: CommandError(exportFailure: .diskFull)
        case EISDIR: .outputIsAFolder
        default: .outputFolderNotWritable
        }
    }
}
