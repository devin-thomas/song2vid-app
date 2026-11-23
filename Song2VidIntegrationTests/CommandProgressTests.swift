import Foundation
import Testing

/// Seam 5 (SPEC section 18): progress from the built command, run as a separate process on a song long enough to take
/// several seconds. Each test measures when output arrives, so these are the timing rules of SPEC section 14.5.
@Suite("song2vid make progress")
struct CommandProgressTests {
    private func makeArguments(_ workspace: CommandWorkspace, extra: [String]) throws -> [String] {
        let song = try workspace.longSong(seconds: 3600)
        let image = try workspace.picture(width: 600, height: 600)
        return ["make", song, image, "-o", workspace.path("out.mp4"), "-s", "1:1", "-r", "480p"] + extra
    }

    @Test("--json: every line parses, the first comes within 0.5 s, no gap over 0.6 s, percent never goes back, one result at the end, stderr empty")
    func jsonLines() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let process = try CommandStreamingProcess(try makeArguments(workspace, extra: ["--json"]))
        let (status, duration) = process.finish()
        #expect(status == 0)
        #expect(duration > 2, "the run was too short to prove anything: \(duration) s")

        let chunks = process.outputSoFar
        #expect(chunks.last?.text.hasSuffix("\n") == true)
        let lines = CommandStreamingProcess.lines(chunks)
        let parsed = try lines.map { line -> [String: Any] in
            let object = try JSONSerialization.jsonObject(with: Data(line.text.utf8)) as? [String: Any]
            return try #require(object, "not a JSON object: \(line.text)")
        }
        #expect(parsed.allSatisfy { $0["api_version"] as? String == "1" })
        #expect(process.errorSoFar.isEmpty)

        // Exactly one result, and it is last.
        let types = parsed.map { $0["type"] as? String }
        #expect(types.last == "result")
        #expect(types.filter { $0 != "progress" } == ["result"])

        // Timing.
        let first = try #require(lines.first)
        #expect(first.time <= 0.5, "first line after \(first.time) s")
        let times = lines.map(\.time)
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        #expect((gaps.max() ?? 0) <= 0.6, "longest gap \(gaps.max() ?? 0) s")

        // Stages come in order, percent only goes up and ends at 100.
        // (Checking files is shown only when it lasts more than a moment, so it may be missing from a fast run.)
        let order = ["checking", "preparing", "encoding", "finishing"]
        let stages = parsed.compactMap { $0["stage"] as? String }
        #expect(Set(stages).isSuperset(of: ["preparing", "encoding", "finishing"]))
        #expect(stages == stages.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! })
        let percents = parsed.compactMap { $0["percent"] as? Double }
        #expect(!percents.isEmpty)
        #expect(percents == percents.sorted())
        #expect(percents.last == 100)
        // No percent and no time left while the stage has none to give; elapsed always present and growing.
        for line in parsed where line["stage"] as? String == "checking" || line["stage"] as? String == "preparing" {
            #expect(line["percent"] is NSNull)
        }
        let elapsed = parsed.compactMap { $0["elapsed_seconds"] as? Double }
        #expect(elapsed == elapsed.sorted())
        // The time left appears only after encoding has run a while, and then it is a number.
        #expect(parsed.contains { ($0["remaining_seconds"] as? Double) != nil })
        let early = parsed.first { $0["stage"] as? String == "encoding" }
        #expect(early?["remaining_seconds"] is NSNull)
    }

    @Test("A run in the background can be read mid-run and shows the latest stage and percent")
    func readMidRun() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let process = try CommandStreamingProcess(try makeArguments(workspace, extra: ["--json"]))
        // Wait until some encoding progress has arrived, with the command still running.
        let deadline = Date().addingTimeInterval(60)
        var latest: [String: Any]?
        while Date() < deadline {
            let lines = CommandStreamingProcess.lines(process.outputSoFar)
            if let last = lines.last, let object = try JSONSerialization.jsonObject(with: Data(last.text.utf8)) as? [String: Any],
               object["stage"] as? String == "encoding", (object["percent"] as? Double ?? 0) > 0 {
                latest = object
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(process.isRunning)
        let line = try #require(latest)
        #expect(line["type"] as? String == "progress")
        #expect((line["percent"] as? Double ?? 0) < 100)
        process.send(SIGINT)
        #expect(process.finish().status == 130)
    }

    @Test("Headless plain: stage lines and a line at least every 2 s, no control characters, the result on stdout")
    func plainLines() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let process = try CommandStreamingProcess(try makeArguments(workspace, extra: []))
        let (status, duration) = process.finish()
        #expect(status == 0)
        #expect(duration > 2, "the run was too short to prove anything: \(duration) s")

        let raw = process.errorSoFar.map(\.text).joined()
        #expect(!raw.contains("\u{1B}"))
        #expect(!raw.contains("\r"))
        #expect(raw.unicodeScalars.allSatisfy { $0 == "\n" || $0.value >= 0x20 })
        let lines = CommandStreamingProcess.lines(process.errorSoFar)
        #expect(lines.first?.text.hasPrefix("Preparing") == true || lines.first?.text.hasPrefix("Checking files") == true)
        #expect(lines.contains { $0.text.hasPrefix("Encoding") && $0.text.contains("%") && $0.text.contains("elapsed") })
        #expect(lines.last?.text.hasPrefix("Finishing") == true)
        #expect(!raw.contains(CommandWorkspace.folderMarker))

        let times = lines.map(\.time) + [duration]
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        #expect((gaps.max() ?? 0) <= 2.1, "longest gap \(gaps.max() ?? 0) s")
        #expect((lines.first?.time ?? 99) <= 2.1)

        let out = process.outputSoFar.map(\.text).joined()
        #expect(out == "Made out.mp4.\n" || out.hasPrefix("Made out.mp4"))
    }

    @Test("--quiet: nothing on stderr, and the result still comes")
    func quiet() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.tone(seconds: 30, sampleRate: 22_050, channels: 1)
        let image = try workspace.picture(width: 600, height: 600)
        let result = try CommandProcess.run(["make", song, image, "-o", workspace.path("q.mp4"), "-r", "480p", "-q"])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("Made q.mp4"))
    }

    @Test("JSON output accepts checking progress and requires exactly one final line")
    func finalJSONLine() throws {
        let progress = #"{"api_version":"1","type":"progress","stage":"checking","elapsed_seconds":0.158}"# + "\n"
        let error = #"{"api_version":"1","type":"error","error":{"code":"output_not_mp4"}}"# + "\n"
        let final = try JSONOutputLine.final(progress + progress + error)
        #expect(final.child("error")?["code"] as? String == "output_not_mp4")

        for invalid in [progress, error + error, error + progress, progress + "not JSON\n" + error] {
            #expect(throws: (any Error).self) { try JSONOutputLine.final(invalid) }
        }
    }

    @Test("Validation failures only show checking progress after the 0.15 s quiet period")
    func validationQuietPeriod() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.tone(seconds: 1)
        let arguments = ["make", song, workspace.path("missing.png")]
        let plain = try CommandProcess.run(arguments)
        #expect(plain.status == 1)
        #expect(plain.stdout.isEmpty)
        let plainLines = plain.stderr.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(plainLines.suffix(2) == ["The image file was not found.", ""])
        #expect(plainLines.dropLast(2).allSatisfy { $0.hasPrefix("Checking files (") })

        let json = try CommandProcess.run(arguments + ["--json"])
        #expect(json.status == 1)
        #expect(json.stderr.isEmpty)
        let final = try JSONOutputLine.final(json.stdout)
        #expect(final["type"] as? String == "error")
        #expect(final.child("error")?["code"] as? String == "image_not_found")
        // The filesystem and scheduler can hold validation past the quiet period, even for a missing file.
        for raw in json.stdout.split(separator: "\n", omittingEmptySubsequences: false).dropLast(2) {
            let progress = try JSONOutputLine(String(raw) + "\n")
            #expect(progress["stage"] as? String == "checking")
            let elapsed = try #require(progress["elapsed_seconds"] as? Double)
            #expect(elapsed >= 0.15)
        }
    }
}

/// The live display, seen through a pseudo-terminal (SPEC section 14.5, "Headed").
@Suite("song2vid make live display")
struct CommandLiveDisplayTests {
    private func run(environment: [String: String]) throws -> (output: String, chunks: [CommandStreamingProcess.Chunk], duration: Double, status: Int32, stdout: String) {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.longSong(seconds: 3600)
        let image = try workspace.picture(width: 600, height: 600)
        var env = ["PATH": "/usr/bin:/bin", "HOME": NSTemporaryDirectory()]
        env.merge(environment) { _, new in new }
        let process = try CommandStreamingProcess(
            ["make", song, image, "-o", workspace.path("out.mp4"), "-s", "1:1", "-r", "480p"], stderr: .terminal, environment: env
        )
        let (status, duration) = process.finish()
        let chunks = process.errorSoFar
        return (chunks.map(\.text).joined(), chunks, duration, status, process.outputSoFar.map(\.text).joined())
    }

    /// The redraws: each starts with a carriage return.
    private func redraws(_ output: String) -> [Substring] {
        output.split(separator: "\r", omittingEmptySubsequences: true)
    }

    @Test("In a terminal the line is redrawn at least ten times a second, with a spinner while preparing and a bar while encoding")
    func redrawn() throws {
        let result = try run(environment: ["TERM": "xterm-256color"])
        #expect(result.status == 0)
        #expect(result.duration > 2, "the run was too short to prove anything: \(result.duration) s")
        let lines = redraws(result.output)
        let rate = Double(lines.count) / result.duration
        #expect(rate >= 10, "\(lines.count) redraws in \(result.duration) s")
        // Spinner (no bar, no percent) in the early stages, with the stage name.
        let early = try #require(lines.first { $0.contains("Preparing") || $0.contains("Checking files") })
        #expect(!early.contains("%"))
        #expect("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏".contains { early.contains($0) })
        let spinners = Set(lines.filter { $0.contains("Preparing") }.compactMap { line in line.first { "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏".contains($0) } })
        #expect(spinners.count > 1, "the spinner did not move")
        // A bar with a percent, elapsed and time left while encoding.
        #expect(lines.contains { $0.contains("Encoding") && $0.contains("█") && $0.contains("%") && $0.contains("elapsed") })
        #expect(lines.contains { $0.contains("estimating") })
        #expect(lines.contains { $0.contains("about") && $0.contains("left") })
        // Colour by default on a normal terminal.
        #expect(result.output.contains("\u{1B}[36m"))
        // The line is wiped at the end, and the result is on stdout.
        #expect(result.output.hasSuffix("\r\u{1B}[K"))
        #expect(result.stdout.hasPrefix("Made out.mp4"))
    }

    @Test("NO_COLOR removes the colour but keeps the live line")
    func noColor() throws {
        let result = try run(environment: ["TERM": "xterm-256color", "NO_COLOR": "1"])
        #expect(result.status == 0)
        #expect(!result.output.contains("\u{1B}[3"))
        #expect(!result.output.contains("\u{1B}[1m"))
        #expect(!result.output.contains("\u{1B}[2m"))
        #expect(redraws(result.output).count > 20)
        #expect(result.output.contains("Encoding"))
    }

    @Test("TERM=dumb has no escape codes at all, and the line is still redrawn")
    func dumbTerminal() throws {
        let result = try run(environment: ["TERM": "dumb"])
        #expect(result.status == 0)
        #expect(!result.output.contains("\u{1B}"))
        #expect(redraws(result.output).count > 20)
        #expect(result.output.contains("Encoding"))
    }
}
