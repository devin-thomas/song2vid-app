import Foundation
import Song2VidCore

// The `song2vid` command. It only hands its arguments to Song2VidCore and writes what comes back.
let output = Song2VidCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
FileHandle.standardOutput.write(Data(output.stdout.utf8))
FileHandle.standardError.write(Data(output.stderr.utf8))
exit(output.status)
