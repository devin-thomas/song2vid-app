import Dispatch
import Foundation

// Progress that is always visible (SPEC section 14.5, ADR-018, ADR-019).
//
// `ProgressSnapshot` is the pure part: what the run looks like at one moment, and how that is written in each of
// the three forms. `ProgressDisplay` is the part with a clock: it keeps the latest state and writes it on a timer,
// so the output keeps moving even while the exporter has nothing new to say (Checking files, Preparing).

/// Where progress events go. The relay delivers them one at a time and calls `finish` once, before the channel closes.
protocol ProgressSink: Sendable {
    func event(_ event: CommandProgress, channel: CommandChannel)
    func finish(channel: CommandChannel)
}

/// A `CommandProgressHandler` as a sink, for callers that draw progress themselves.
struct HandlerSink: ProgressSink {
    let handler: CommandProgressHandler
    func event(_ event: CommandProgress, channel: CommandChannel) { handler(event, channel) }
    func finish(channel: CommandChannel) {}
}

/// How the command shows progress for one run.
enum ProgressMode: Sendable {
    /// No progress output (`--quiet`).
    case none
    /// The caller's own handler.
    case handler(CommandProgressHandler)
    /// The command's own display, drawn according to the environment it was started in.
    case display(environment: [String: String])
}

/// How a run looks at one moment.
struct ProgressSnapshot: Equatable {
    var stage: CommandProgress.Stage
    /// 0 to 1, or nil while it is not known.
    var fraction: Double?
    var elapsed: Double
    /// Seconds left, or nil while it is not known (before encoding has run for a second).
    var remaining: Double?
    /// Which frame of the spinner to draw.
    var tick: Int
    var encoder: String? = nil

    static let stageNames: [CommandProgress.Stage: String] = [
        .checking: "Checking files", .preparing: "Preparing", .encoding: "Encoding", .finishing: "Finishing",
    ]
    var stageName: String { Self.stageNames[stage] ?? "Working" }
    var percent: Int { Int(((fraction ?? 0) * 100).rounded(.down)) }

    static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private var timing: String {
        let spent = "\(Self.clock(elapsed)) elapsed"
        guard fraction != nil else { return spent }
        if let remaining { return spent + " · about \(Self.clock(remaining.rounded(.up))) left" }
        return spent + " · estimating"
    }

    // MARK: Live, for a terminal

    private static let spinnerFrames = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    private static let barWidth = 16

    /// The one-line display. `columns` limits its length so the line never wraps (a wrapped line can't be redrawn);
    /// a line too long for the terminal is cut and drawn without colour.
    func liveText(columns: Int, color: Bool) -> String {
        let limit = max(10, columns - 1)
        let plain = line(color: false)
        if plain.count > limit { return String(plain.prefix(limit)) }
        return color ? line(color: true) : plain
    }

    private func line(color: Bool) -> String {
        func paint(_ text: String, _ code: String) -> String { color ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text }
        let name = paint(stageName.padding(toLength: 14, withPad: " ", startingAt: 0), "1")
        let middle: String
        if let fraction {
            let filled = Int((fraction * Double(Self.barWidth)).rounded(.down))
            let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: Self.barWidth - filled)
            middle = paint(bar, "36") + String(format: "  %3d%%", percent)
        } else {
            middle = paint(String(Self.spinnerFrames[tick % Self.spinnerFrames.count]), "36")
        }
        return "\(name)  \(middle)  \(paint(timing, "2"))"
    }

    // MARK: Headless, plain

    /// A line for a log: no control characters.
    var plainText: String {
        let head = fraction == nil ? stageName : "\(stageName) \(percent)%"
        let detail: String
        if fraction == nil {
            detail = "\(Self.clock(elapsed)) elapsed"
        } else if let remaining {
            detail = "\(Self.clock(elapsed)) elapsed, about \(Self.clock(remaining.rounded(.up))) left"
        } else {
            detail = "\(Self.clock(elapsed)) elapsed, estimating time left"
        }
        return "\(head) (\(detail))"
    }

    // MARK: Headless, JSON

    var jsonValue: JSONValue {
        var fields: [(JSONKey, JSONValue)] = [
            (.stage, .string(stage.rawValue)),
            (.percent, fraction.map { .seconds(($0 * 1000).rounded(.down) / 10) } ?? .null),
            (.elapsedSeconds, .seconds(elapsed)),
            (.remainingSeconds, remaining.map { .seconds($0) } ?? .null),
        ]
        if let encoder { fields.append((.encoder, .string(encoder))) }
        return .line(type: "progress", fields)
    }
}

/// Writes progress as the run goes (SPEC section 14.5).
///
/// - **Live**: stderr is a terminal. One line, redrawn at least ten times a second, replaced by the result at the end.
/// - **Plain**: stderr is not a terminal. A line at each stage change and every second.
/// - **JSON**: `--json`. JSON Lines on stdout at each stage change and four times a second; stderr stays empty.
///
/// Checking files is shown only if it lasts past a short quiet period, so a run that fails at once (a missing file)
/// shows only its error. Every later stage is shown as it begins, and after that the output never goes quiet: a
/// timer writes the latest state even when the exporter has nothing new to say.
final class ProgressDisplay: ProgressSink, @unchecked Sendable {
    enum Style: Equatable {
        case live(color: Bool, clearsLine: Bool)
        case plain
        case json
    }

    /// How long Checking files is kept quiet.
    static let quietPeriod = 0.15

    private let style: Style
    private let clock: @Sendable () -> Double
    private let columns: @Sendable () -> Int
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "song2vid.progress", qos: .userInitiated)
    private let timer: DispatchSourceTimer
    private let startedAt: Double
    private let startDelay: Double

    private var stage: CommandProgress.Stage = .checking
    private var fraction: Double?
    private var encoder: String?
    private var encodingStartedAt: Double?
    private var ticks = 0
    private var visible = false
    private var started = false
    private var finished = false
    private var liveWidth = 0
    private var channel: CommandChannel?

    init(
        style: Style, startDelay: Double = ProgressDisplay.quietPeriod,
        clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
        columns: @escaping @Sendable () -> Int = { 80 }
    ) {
        self.style = style
        self.clock = clock
        self.columns = columns
        self.startDelay = startDelay
        startedAt = clock()
        timer = DispatchSource.makeTimerSource(queue: queue)
    }

    /// The display for this run, chosen from where the command's output is going and the environment.
    static func make(channel: CommandChannel, json: Bool, environment: [String: String]) -> ProgressDisplay {
        if json { return ProgressDisplay(style: .json) }
        guard channel.errorDescriptor >= 0, isatty(channel.errorDescriptor) == 1 else { return ProgressDisplay(style: .plain) }
        let dumb = environment["TERM"] == "dumb"
        let noColor = !(environment["NO_COLOR"] ?? "").isEmpty
        let descriptor = channel.errorDescriptor
        return ProgressDisplay(
            style: .live(color: !dumb && !noColor, clearsLine: !dumb),
            columns: {
                var size = winsize()
                return ioctl(descriptor, TIOCGWINSZ, &size) == 0 && size.ws_col > 0 ? Int(size.ws_col) : 80
            }
        )
    }

    private var isLive: Bool {
        if case .live = style { return true }
        return false
    }

    /// How often the latest state is written.
    private var interval: Double {
        switch style {
        case .live: 0.08
        case .json: 0.25
        case .plain: 1.0
        }
    }

    func event(_ event: CommandProgress, channel: CommandChannel) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        if !started { start(channel) }
        let changed = event.stage != stage
        stage = event.stage
        encoder = event.encoder
        if let value = event.fraction {
            fraction = max(fraction ?? 0, value)
            if encodingStartedAt == nil { encodingStartedAt = clock() }
        }
        if changed, stage != .checking { visible = true }
        // A new stage is shown at once, except in the live display, which redraws on its own beat anyway.
        if changed, visible, !isLive { write() }
    }

    func finish(channel: CommandChannel) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        timer.setEventHandler {}
        timer.cancel()
        // A timer that was never started must be resumed before it is released, or libdispatch stops the process.
        if !started { timer.resume() }
        // The live line is wiped so the result takes its place. The other forms have nothing to take back.
        if visible, isLive, let channel = self.channel { channel.writeError(wipe()) }
        liveWidth = 0
    }

    /// Starts the timer on the first event. Called with the lock held.
    private func start(_ channel: CommandChannel) {
        started = true
        self.channel = channel
        let wait = max(0, startedAt + startDelay - clock())
        timer.schedule(deadline: .now() + wait, repeating: interval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.beat() }
        timer.resume()
    }

    private func beat() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        visible = true
        ticks += 1
        write()
    }

    /// Writes the current state. Called with the lock held.
    private func write() {
        guard let channel else { return }
        let now = clock()
        var remaining: Double?
        if let fraction, let began = encodingStartedAt, fraction > 0 {
            let encoding = now - began
            if fraction >= 1 { remaining = 0 } else if encoding >= 1 { remaining = encoding * (1 - fraction) / fraction }
        }
        let snapshot = ProgressSnapshot(stage: stage, fraction: fraction, elapsed: now - startedAt, remaining: remaining, tick: ticks, encoder: encoder)
        switch style {
        case .json:
            channel.writeOutput(snapshot.jsonValue.line)
        case .plain:
            channel.writeError(snapshot.plainText + "\n")
        case .live(let color, let clearsLine):
            let text = snapshot.liveText(columns: columns(), color: color)
            let shown = Self.visibleLength(text)
            // Without the clear-line code (a dumb terminal), blanks cover whatever a longer earlier line left.
            let cover = clearsLine ? "\u{1B}[K" : String(repeating: " ", count: max(0, liveWidth - shown))
            channel.writeError("\r" + text + cover)
            liveWidth = shown
        }
    }

    private func wipe() -> String {
        guard case .live(_, let clearsLine) = style else { return "" }
        return clearsLine ? "\r\u{1B}[K" : "\r" + String(repeating: " ", count: liveWidth) + "\r"
    }

    /// The length of a line without its colour codes.
    private static func visibleLength(_ text: String) -> Int {
        var count = 0
        var inCode = false
        for character in text {
            if character == "\u{1B}" { inCode = true } else if inCode { if character == "m" { inCode = false } } else { count += 1 }
        }
        return count
    }
}
