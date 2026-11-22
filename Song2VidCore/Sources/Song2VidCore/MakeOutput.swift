import Foundation

/// Where `make` will save, checked before anything is made (SPEC section 14.4 step 1), and the last step that puts
/// the finished video there (ADR-014).
struct MakeOutput: Sendable {
    /// The final name. Nothing is written here until the video is complete.
    let url: URL
    /// The file name only: a folder never reaches the output.
    var name: String { url.lastPathComponent }
    var folder: URL { url.deletingLastPathComponent() }

    /// The video is built under this name in the output's own folder, so the final move stays on one volume.
    func temporaryURL() -> URL {
        folder.appendingPathComponent(".song2vid-\(UUID().uuidString).mp4.song2vid-make")
    }

    /// Checks the output name and folder. Without `overwrite`, a file already there is an error.
    /// Nothing is created or changed.
    static func plan(
        option: String?, audioURL: URL, imageURL: URL, overwrite: Bool
    ) throws(CommandError) -> MakeOutput {
        // The default is the song's own name with .mp4, in the current folder.
        let path = option ?? audioURL.deletingPathExtension().lastPathComponent + ".mp4"
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        guard name.count > 4, name.lowercased().hasSuffix(".mp4") else { throw .outputNotMP4 }

        let output = MakeOutput(url: url)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: output.folder.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw .outputFolderNotFound }
        guard FileManager.default.isWritableFile(atPath: output.folder.path) else { throw .outputFolderNotWritable }

        // An entry of any kind at the output (a dangling link counts) is "already there".
        var entry = stat()
        guard lstat(url.path, &entry) == 0 else { return output }
        // Never the person's own song or image, whatever the name and whatever --overwrite says.
        var target = stat()
        if stat(url.path, &target) == 0, [audioURL, imageURL].contains(where: { isSameFile($0, as: target) }) {
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

    /// Moves the finished video from `temporary` to the final name. This is the only step that touches the final name.
    /// Without `overwrite` it fails, and the new video is deleted, if something has appeared there during the run.
    func place(_ temporary: URL, overwrite: Bool) throws(CommandError) {
        if overwrite {
            // rename() replaces the old file in one step: there is no moment with neither file.
            guard rename(temporary.path, url.path) == 0 else {
                let problem = Self.error(for: errno)
                try? FileManager.default.removeItem(at: temporary)
                throw problem
            }
            return
        }
        // Rename only if nothing is there, as one step, so a file that appeared during the run is never replaced.
        if renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL)) == 0 { return }
        var problem = errno
        // A volume that can't do that: a hard link also fails if the name is taken, and the old name is dropped after.
        if problem == ENOTSUP || problem == EINVAL {
            if link(temporary.path, url.path) == 0 {
                try? FileManager.default.removeItem(at: temporary)
                return
            }
            problem = errno
        }
        try? FileManager.default.removeItem(at: temporary)
        throw problem == EEXIST ? .outputExists : Self.error(for: problem)
    }

    private static func error(for code: Int32) -> CommandError {
        switch code {
        case ENOSPC, EDQUOT: CommandError(exportFailure: .diskFull)
        case EISDIR: .outputIsAFolder
        default: .outputFolderNotWritable
        }
    }
}
