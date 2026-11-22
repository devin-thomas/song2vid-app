import Testing
@testable import Song2VidCore

/// How a run looks at one moment, in each of the three forms (SPEC section 14.5). Expected text is written out by hand.
@Suite("Progress text")
struct ProgressSnapshotTests {
    private func snapshot(
        _ stage: CommandProgress.Stage, _ fraction: Double?, elapsed: Double = 4.2, remaining: Double? = 3.1, tick: Int = 0
    ) -> ProgressSnapshot {
        ProgressSnapshot(stage: stage, fraction: fraction, elapsed: elapsed, remaining: remaining, tick: tick)
    }

    @Test("Clock times are m:ss")
    func clock() {
        #expect(ProgressSnapshot.clock(0) == "0:00")
        #expect(ProgressSnapshot.clock(4.9) == "0:04")
        #expect(ProgressSnapshot.clock(75) == "1:15")
        #expect(ProgressSnapshot.clock(3_725) == "62:05")
    }

    @Test("Live: the encoding line has a bar, the percent, elapsed and time left")
    func liveEncoding() {
        let text = snapshot(.encoding, 0.52).liveText(columns: 120, color: false)
        #expect(text == "Encoding        ████████░░░░░░░░   52%  0:04 elapsed · about 0:04 left")
    }

    @Test("Live: before a time left is known it says estimating")
    func liveEstimating() {
        let text = snapshot(.encoding, 0.02, remaining: nil).liveText(columns: 120, color: false)
        #expect(text == "Encoding        ░░░░░░░░░░░░░░░░    2%  0:04 elapsed · estimating")
    }

    @Test("Live: with no percent a spinner moves instead of a bar, one step per tick")
    func liveSpinner() {
        let frames = (0..<10).map { snapshot(.preparing, nil, remaining: nil, tick: $0).liveText(columns: 120, color: false) }
        #expect(Set(frames).count == 10)
        #expect(frames[0] == "Preparing       ⠋  0:04 elapsed")
        #expect(snapshot(.checking, nil, remaining: nil, tick: 10).liveText(columns: 120, color: false)
            == "Checking files  ⠋  0:04 elapsed")
    }

    @Test("Live: colour only when asked, and a narrow terminal gets a cut line without colour")
    func liveColourAndWidth() {
        let coloured = snapshot(.encoding, 0.5).liveText(columns: 120, color: true)
        #expect(coloured.contains("\u{1B}[36m"))
        let plain = snapshot(.encoding, 0.5).liveText(columns: 120, color: false)
        #expect(!plain.contains("\u{1B}"))
        let narrow = snapshot(.encoding, 0.5).liveText(columns: 30, color: true)
        #expect(narrow.count == 29)
        #expect(!narrow.contains("\u{1B}"))
    }

    @Test("Plain: one line with no control characters")
    func plain() {
        #expect(snapshot(.encoding, 0.52).plainText == "Encoding 52% (0:04 elapsed, about 0:04 left)")
        #expect(snapshot(.encoding, 0.03, remaining: nil).plainText == "Encoding 3% (0:04 elapsed, estimating time left)")
        #expect(snapshot(.preparing, nil, remaining: nil).plainText == "Preparing (0:04 elapsed)")
        #expect(snapshot(.checking, nil, remaining: nil).plainText == "Checking files (0:04 elapsed)")
        #expect(snapshot(.finishing, 1, remaining: 0).plainText == "Finishing 100% (0:04 elapsed, about 0:00 left)")
    }

    @Test("JSON: the keys and nulls of SPEC section 14.5")
    func json() {
        #expect(snapshot(.encoding, 0.52).jsonValue.line
            == #"{"api_version":"1","type":"progress","stage":"encoding","percent":52.0,"elapsed_seconds":4.2,"remaining_seconds":3.1}"# + "\n")
        #expect(snapshot(.preparing, nil, remaining: nil).jsonValue.line
            == #"{"api_version":"1","type":"progress","stage":"preparing","percent":null,"elapsed_seconds":4.2,"remaining_seconds":null}"# + "\n")
    }
}
