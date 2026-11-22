import Foundation

/// The two input files, read with the same readers the app uses (SPEC section 7).
/// Both `check` and `make` start here, so they accept and refuse the same files.
struct CommandInputs: Sendable {
    /// File names only: a folder never reaches the output.
    let audioName: String
    let audio: AudioInfo
    let imageName: String
    let image: ImageInfo

    /// Looks for both files first (status 1), then reads the audio, then the image (status 3).
    static func read(audioPath: String, imagePath: String) throws(CommandError) -> CommandInputs {
        let audioURL = URL(fileURLWithPath: audioPath)
        let imageURL = URL(fileURLWithPath: imagePath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else { throw .audioNotFound }
        guard FileManager.default.fileExists(atPath: imageURL.path) else { throw .imageNotFound }

        // The system readers may log the file's path to the terminal; none of that may reach the output.
        let audio = withSystemOutputSilenced { try? AudioInfo.read(from: audioURL) }
        guard let audio else { throw .audioUnreadable }
        let image = withSystemOutputSilenced { try? ImageInfo.read(from: imageURL) }
        guard let image else { throw .imageUnreadable }
        return CommandInputs(audioName: audioURL.lastPathComponent, audio: audio, imageName: imageURL.lastPathComponent, image: image)
    }
}
