import Foundation
import Testing

/// Seam 5: `song2vid make` while it is encoding (SPEC section 14.4 steps 3 to 5).
/// Each test starts a run that takes several seconds, waits until the command has begun writing its temporary file,
/// and then acts. The run is long enough that it can't finish first.
@Suite("song2vid make while encoding")
struct CommandMakeCancelTests {
    /// Waits until the folder holds something that was not there at the start, which is the command's temporary file.
    private func waitForTemporaryFile(in workspace: CommandWorkspace, before: [String], process: CommandProcess.Running) throws {
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if try Set(workspace.listing()).subtracting(before).isEmpty == false { return }
            if !process.isRunning { throw CommandTestFailure("the command ended before it began writing") }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw CommandTestFailure("the command did not begin writing within a minute")
    }

    @Test("Ctrl-C and SIGTERM cancel: status 130, the message, and no file left in the output folder", arguments: [SIGINT, SIGTERM])
    func cancelled(signal: Int32) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.longSong()
        let image = try workspace.picture(width: 600, height: 600)
        let before = try workspace.listing()

        let running = try CommandProcess.Running(["make", song, image, "-o", workspace.path("out.mp4"), "-s", "1:1", "-r", "480p"])
        try waitForTemporaryFile(in: workspace, before: before, process: running)
        Thread.sleep(forTimeInterval: 0.3)
        running.send(signal)
        let result = running.finish()

        #expect(result.status == 130)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == "Cancelled.\n")
        #expect(try workspace.listing() == before)
    }

    @Test("Under --json a cancel is one error line with the code cancelled, and stderr is empty")
    func cancelledJSON() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.longSong()
        let image = try workspace.picture(width: 600, height: 600)
        let before = try workspace.listing()

        let running = try CommandProcess.Running(["make", song, image, "--out=\(workspace.path("out.mp4"))", "-r", "480p", "--json"])
        try waitForTemporaryFile(in: workspace, before: before, process: running)
        running.send(SIGINT)
        let result = running.finish()

        #expect(result.status == 130)
        #expect(result.stderr.isEmpty)
        let line = try JSONOutputLine(result.stdout)
        #expect(line["type"] as? String == "error")
        #expect(line.child("error")?["code"] as? String == "cancelled")
        #expect(line.child("error")?["message"] as? String == "Cancelled.")
        #expect(try workspace.listing() == before)
    }

    @Test("Cancelling a run that would have replaced a file leaves that file as it was")
    func cancelledOverwriteKeepsTheOldFile() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.longSong()
        let image = try workspace.picture(width: 600, height: 600)
        let existing = workspace.url("out.mp4")
        try Data("my earlier video".utf8).write(to: existing)
        let before = try workspace.listing()

        let running = try CommandProcess.Running(["make", song, image, "-o", existing.path, "-r", "480p", "-w"])
        // The old file is there from the start, so wait for the second file.
        let deadline = Date().addingTimeInterval(60)
        while try workspace.listing().count == before.count, Date() < deadline, running.isRunning { Thread.sleep(forTimeInterval: 0.05) }
        running.send(SIGINT)
        let result = running.finish()

        #expect(result.status == 130)
        #expect(try Data(contentsOf: existing) == Data("my earlier video".utf8))
        #expect(try workspace.listing() == before)
    }

    @Test("A file that appears at the output during the run is not replaced without --overwrite: status 4, new video deleted")
    func outputAppearsDuringTheRun() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.longSong()
        let image = try workspace.picture(width: 600, height: 600)
        let before = try workspace.listing()
        let output = workspace.url("out.mp4")

        // It is not there when the command checks, and it is there when the video is finished.
        let running = try CommandProcess.Running(["make", song, image, "-o", output.path, "-s", "1:1", "-r", "480p", "--json"])
        try waitForTemporaryFile(in: workspace, before: before, process: running)
        try Data("made by someone else meanwhile".utf8).write(to: output)
        let result = running.finish()

        #expect(result.status == 4)
        #expect(result.stderr.isEmpty)
        let error = try #require(try JSONOutputLine(result.stdout).child("error"))
        #expect(error["code"] as? String == "output_exists")
        #expect(error["message"] as? String == "The output file already exists. Use --overwrite to replace it.")
        #expect(try Data(contentsOf: output) == Data("made by someone else meanwhile".utf8))
        #expect(try workspace.listing() == (before + ["out.mp4"]).sorted())
    }

    @Test("--overwrite replaces the old file only at the end of the run")
    func overwriteHappensAtTheEnd() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.longSong()
        let image = try workspace.picture(width: 600, height: 600)
        let output = workspace.url("out.mp4")
        let marker = Data("my earlier video".utf8)
        try marker.write(to: output)
        let before = try workspace.listing()

        let running = try CommandProcess.Running(["make", song, image, "-o", output.path, "-s", "1:1", "-r", "480p", "-w"])
        let deadline = Date().addingTimeInterval(60)
        while try workspace.listing().count == before.count, Date() < deadline, running.isRunning { Thread.sleep(forTimeInterval: 0.05) }
        // Encoding is under way, and the old file has not been touched.
        #expect(running.isRunning)
        #expect(try Data(contentsOf: output) == marker)
        let result = running.finish()

        #expect(result.status == 0)
        #expect(try Data(contentsOf: output) != marker)
        #expect(try workspace.listing() == before)
    }
}
