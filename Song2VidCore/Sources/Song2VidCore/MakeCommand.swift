import Foundation

/// `song2vid make <audio> <image> [options]` (SPEC section 14.4): checks everything, then makes the video with the
/// same export code as the app (`VideoExporting`, `ExportRequest`, `OutputFrame`) and no logic of its own about frames.
enum MakeCommand {
    /// Runs the command. `exporter` is the app's own; it is a parameter so the export path is the one place a test
    /// or a future caller could swap.
    static func run(
        _ options: MakeOptions, environment: [String: String],
        exporter: any VideoExporting = SystemVideoExporter(), progress: ProgressMode = .none
    ) -> CommandOutput {
        let signals = CancelSignals(watchStdin: options.cancelOnEOF)
        defer { signals.stop() }
        // Every call into a system framework happens inside this: its log lines go to /dev/null, and the command's
        // own progress goes through the channel, to the real streams. The result is returned and written by the caller.
        return withSystemOutputSilenced(json: options.json) { channel in
            let sink: (any ProgressSink)?
            switch options.quiet || options.dryRun ? .none : progress {
            case .none: sink = nil
            case .handler(let handler): sink = HandlerSink(handler: handler)
            case .display(let environment): sink = ProgressDisplay.make(channel: channel, json: options.json, environment: environment)
            }
            let relay = ProgressRelay(sink: sink, channel: channel)
            defer { relay.close() }
            do throws(CommandError) {
                return try execute(options, environment: environment, exporter: exporter, signals: signals, relay: relay)
            } catch {
                return .failure(signals.isRequested ? CommandError.cancelled : error, json: options.json)
            }
        }
    }

    private static func execute(
        _ options: MakeOptions, environment: [String: String], exporter: any VideoExporting,
        signals: CancelSignals, relay: ProgressRelay
    ) throws(CommandError) -> CommandOutput {
        if signals.isRequested { throw .cancelled }
        relay.stage(.checking)

        // 1. Validate everything first: the files, the size for Original, the output. Nothing is written until all pass.
        let inputs = try CommandInputs.read(
            audioPath: options.audioPath, imagePath: options.imagePath, isCancelled: { signals.isRequested }
        )
        let frame: OutputFrame
        do {
            frame = try OutputFrame(
                imageSize: inputs.image.size, frameShape: options.shape, resolution: options.resolution, cropPosition: options.crop
            )
        } catch {
            throw .imageTooSmall
        }
        let audioURL = URL(fileURLWithPath: options.audioPath)
        let imageURL = URL(fileURLWithPath: options.imagePath)
        let path = options.output ?? audioURL.deletingPathExtension().lastPathComponent + ".mp4"
        let outputURL = URL(fileURLWithPath: path)
        let name = outputURL.lastPathComponent
        guard name.count > 4, name.lowercased().hasSuffix(".mp4") else { throw .outputNotMP4 }
        let output = try CommandDestination.plan(url: outputURL, inputs: [audioURL, imageURL], overwrite: options.overwrite)
        if signals.isRequested { throw .cancelled }
        guard AppleEncoder.isAvailable(options.codec, environment: environment) else {
            throw CommandError(code: .codecUnavailable, message: "This computer can't make \(options.codec.title) videos.")
        }
        if signals.isRequested { throw .cancelled }

        var report = MakeReport(
            inputs: inputs, frame: frame, shape: options.shape, codec: options.codec,
            outputName: output.name, bytes: nil, dryRun: options.dryRun
        )
        // 2. A dry run says what would be made and stops.
        if options.dryRun { return CommandOutput(stdout: options.json ? report.jsonValue.line : report.text, status: 0) }

        // 3. Make it in a temporary file beside the output.
        let temporary = output.temporaryURL()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let request = ExportRequest(
            audioURL: audioURL, imageURL: imageURL, frame: frame, destinationURL: temporary, codec: options.codec
        )
        relay.stage(.preparing)
        switch export(request, with: exporter, signals: signals, relay: relay) {
        case .completed:
            break
        case .cancelled:
            throw .cancelled
        case .failed(let failure):
            throw CommandError(exportFailure: failure)
        }

        // 4. Only now is the final name touched: --overwrite replaces an old file here, and without it a file that
        // appeared during the run is an error and the new video is deleted.
        relay.stage(.finishing)
        if signals.isRequested { throw .cancelled }
        try output.place(temporary, overwrite: options.overwrite)
        let size = (try? FileManager.default.attributesOfItem(atPath: output.url.path)[.size] as? Int) ?? 0
        report.bytes = size
        return CommandOutput(stdout: options.json ? report.jsonValue.line : report.text, status: 0)
    }

    /// Runs the export to the end on the cooperative pool and waits for it on this thread, so the signal handlers
    /// (which run on their own queue) can cancel it. Cancelling waits for the exporter to clean up its files.
    private static func export(
        _ request: ExportRequest, with exporter: any VideoExporting, signals: CancelSignals, relay: ProgressRelay
    ) -> ExportOutcome {
        let finished = DispatchSemaphore(value: 0)
        let result = OutcomeBox()
        let task = Task.detached {
            let outcome = await exporter.export(request) { fraction in relay.encoding(fraction) }
            result.set(outcome)
            finished.signal()
        }
        signals.onCancel { task.cancel() }
        finished.wait()
        signals.clearAction()
        return result.value ?? .failed(.encodingFailed)
    }
}

/// Carries the export's outcome from the task that ran it back to the command's own thread.
private final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: ExportOutcome?

    var value: ExportOutcome? {
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }

    func set(_ newValue: ExportOutcome) {
        lock.lock()
        outcome = newValue
        lock.unlock()
    }
}

/// Turns what the command and the exporter report into `CommandProgress` events for the handler, one at a time and
/// only when the stage or the percent moves on. After `close()` nothing more is delivered.
final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private let sink: (any ProgressSink)?
    private let channel: CommandChannel
    private var current: CommandProgress.Stage?
    private var isClosed = false

    init(sink: (any ProgressSink)?, channel: CommandChannel) {
        self.sink = sink
        self.channel = channel
    }

    /// A stage with no percent yet.
    func stage(_ stage: CommandProgress.Stage) {
        send(CommandProgress(stage: stage, fraction: nil, encoder: stage == .finishing ? AppleEncoder.name : nil), onlyIfNewStage: true)
    }

    /// The exporter's fraction (0 to 1). The last 1% is the writer closing the file and moving it, so it is Finishing.
    func encoding(_ fraction: Double) {
        let stage: CommandProgress.Stage = fraction >= 0.99 ? .finishing : .encoding
        send(CommandProgress(stage: stage, fraction: min(1, max(0, fraction)), encoder: AppleEncoder.name), onlyIfNewStage: false)
    }

    /// Ends progress: the sink is told once, and nothing more is delivered after it.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        sink?.finish(channel: channel)
    }

    private func send(_ event: CommandProgress, onlyIfNewStage: Bool) {
        guard let sink else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed, !(onlyIfNewStage && current == event.stage) else { return }
        current = event.stage
        sink.event(event, channel: channel)
    }
}
