import Foundation
import Song2VidCore
import Testing

/// The hook S2V-013 draws its live progress through: `Song2VidCommand.run(arguments:progress:)` reports each stage and
/// the exporter's fraction, and hands over a channel that writes to the real streams while everything else the system
/// prints is sent to /dev/null. This runs the command in this process, so the suite runs one test at a time (the
/// streams are redirected for the whole process while a run is going).
@Suite("song2vid make progress hook", .serialized)
struct CommandMakeProgressTests {
    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [CommandProgress] = []
        func add(_ event: CommandProgress) { lock.lock(); stored.append(event); lock.unlock() }
        var all: [CommandProgress] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    /// Runs the command with standard error replaced by a pipe, and returns what the command returned, the events,
    /// and everything that reached standard error.
    private func run(_ arguments: [String]) throws -> (output: CommandOutput, events: [CommandProgress], stderr: String) {
        var fds: [Int32] = [0, 0]
        try #require(pipe(&fds) == 0)
        let saved = dup(STDERR_FILENO)
        dup2(fds[1], STDERR_FILENO)
        let events = Events()
        let output = Song2VidCommand.run(arguments: arguments) { event, channel in
            events.add(event)
            // What the handler writes through the channel must arrive. What anything else writes to standard error
            // while the command runs (here, a line like the system's own log lines) must not.
            channel.writeError("progress-line\n")
            write(STDERR_FILENO, "system-noise-line\n", 18)
        }
        dup2(saved, STDERR_FILENO)
        close(saved)
        close(fds[1])
        let data = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true).readDataToEndOfFile()
        return (output, events.all, String(decoding: data, as: UTF8.self))
    }

    @Test("make reports checking, preparing, encoding and finishing, and the channel reaches the real standard error")
    func stagesAndChannel() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        // 120 s of mono audio is 3,600 video frames, so the exporter reports many times.
        let audio = try workspace.tone(seconds: 120, sampleRate: 22_050, channels: 1)
        let image = try workspace.picture(width: 400, height: 300)

        let (output, events, stderr) = try run(["make", audio, image, "-o", workspace.path("out.mp4"), "-s", "1:1", "-r", "480p", "--json"])
        #expect(output.status == 0)
        #expect(try JSONOutputLine(output.stdout)["type"] as? String == "result")

        // Stages come in order and never go back.
        let order: [CommandProgress.Stage] = [.checking, .preparing, .encoding, .finishing]
        let stages = events.map(\.stage)
        #expect(stages.first == .checking)
        #expect(Set(stages) == Set(order))
        #expect(stages == stages.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! })
        // No percent while checking and preparing; after that, from 0 to 1, never going back, and ending at 1.
        for event in events where event.stage == .checking || event.stage == .preparing { #expect(event.fraction == nil) }
        let fractions = events.compactMap(\.fraction)
        #expect(!fractions.isEmpty)
        #expect(fractions.allSatisfy { (0...1).contains($0) })
        #expect(fractions == fractions.sorted())
        #expect(fractions.last == 1)
        #expect(events.last?.stage == .finishing)

        // One line per event, from the channel, and none of the other writes.
        #expect(stderr == String(repeating: "progress-line\n", count: events.count))
        #expect(!stderr.contains("system-noise-line"))
    }

    @Test("--quiet makes no progress calls, and the result still comes back")
    func quiet() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone(seconds: 20, sampleRate: 22_050, channels: 1)
        let image = try workspace.picture(width: 400, height: 300)

        let (output, events, stderr) = try run(["make", audio, image, "-o", workspace.path("out.mp4"), "-r", "480p", "-q"])
        #expect(output.status == 0)
        #expect(output.stdout.hasPrefix("Made out.mp4 (H.264, Apple encoder)."))
        #expect(events.isEmpty)
        #expect(stderr.isEmpty)
    }

    @Test("A run that fails while checking reports only the checking stage")
    func failedRun() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone(seconds: 1)
        let (output, events, _) = try run(["make", audio, workspace.path("missing.png")])
        #expect(output.status == 1)
        #expect(events.map(\.stage) == [.checking])
    }
}
