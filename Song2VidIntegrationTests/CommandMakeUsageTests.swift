import Foundation
import Testing

/// Seam 5: every way `song2vid make` can be used wrongly (SPEC section 14.2).
/// A usage error is exit status 2 and one line on stderr (or one JSON error line), it never echoes what was typed,
/// and it is found before any file is looked at or written.
@Suite("song2vid make usage errors")
struct CommandMakeUsageTests {
    static let help = "Run 'song2vid make --help'."

    /// Names that don't exist, so a usage error that wrongly went on to look at files would show as status 1.
    private let missing = ["no-such-song.wav", "no-such-picture.png"]

    private func expectUsage(_ arguments: [String], _ message: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let result = try CommandProcess.run(arguments)
        #expect(result.status == 2, "\(arguments)", sourceLocation: sourceLocation)
        #expect(result.stdout.isEmpty, sourceLocation: sourceLocation)
        #expect(result.stderr == "\(message) \(Self.help)\n", "\(arguments)", sourceLocation: sourceLocation)

        // The same error under --json is one error line on stdout, and stderr is empty.
        let json = try CommandProcess.run(arguments + ["--json"])
        #expect(json.status == 2, sourceLocation: sourceLocation)
        #expect(json.stderr.isEmpty, sourceLocation: sourceLocation)
        let line = try JSONOutputLine(json.stdout)
        #expect(line["type"] as? String == "error", sourceLocation: sourceLocation)
        #expect(line.child("error")?["code"] as? String == "usage", sourceLocation: sourceLocation)
        #expect(line.child("error")?["message"] as? String == "\(message) \(Self.help)", sourceLocation: sourceLocation)
    }

    // MARK: The files

    @Test("make needs exactly one audio file and one image file", arguments: [
        [], ["only-one"], ["one", "two", "three"],
    ] as [[String]])
    func wrongNumberOfFiles(files: [String]) throws {
        try expectUsage(["make"] + files, "make needs one audio file and one image file.")
    }

    // MARK: Option values

    @Test("--shape takes one of the five shape names", arguments: ["5:4", "16-9", "square", "", "ORIGINAL"])
    func badShape(shape: String) throws {
        for spelling in [["-s", shape], ["--shape", shape], ["--shape=\(shape)"]] {
            try expectUsage(["make"] + missing + spelling, "Shape must be 16:9, 9:16, 1:1, 4:3 or original.")
        }
    }

    @Test("--resolution takes 480p, 1080p or 2160p", arguments: ["720p", "1080", "4k", "", "480P"])
    func badResolution(resolution: String) throws {
        for spelling in [["-r", resolution], ["--resolution", resolution], ["--resolution=\(resolution)"]] {
            try expectUsage(["make"] + missing + spelling, "Resolution must be 480p, 1080p or 2160p.")
        }
    }

    @Test("--resolution is a usage error with the original shape", arguments: [
        ["-s", "original", "-r", "480p"], ["-r", "2160p", "--shape", "original"], ["--shape=original", "--resolution=1080p"],
    ] as [[String]])
    func resolutionWithOriginal(options: [String]) throws {
        try expectUsage(["make"] + missing + options, "Resolution does not apply to the original shape.")
    }

    @Test("--crop is a usage error unless the shape is 1:1 or 4:3", arguments: [
        [], ["-s", "16:9"], ["-s", "9:16"], ["-s", "original"],
    ] as [[String]])
    func cropOnlyForCroppedShapes(shape: [String]) throws {
        try expectUsage(["make"] + missing + shape + ["-c", "0.2,0.8"], "Crop applies only to the 1:1 and 4:3 shapes.")
    }

    @Test("--crop is two numbers from 0 to 1 with a comma between them, and is not clamped", arguments: [
        "0.5", "a,b", "0.5,", ",0.5", "0.5,0.5,0.5", "1.5,0.5", "0.5,1.0001", "nan,0.5", "inf,0.5", "0x1,0.5", "", " 0.5,0.5", "0.5;0.5",
    ])
    func badCrop(crop: String) throws {
        try expectUsage(
            ["make"] + missing + ["-s", "1:1", "--crop=\(crop)"],
            "Crop must be two numbers from 0 to 1, like 0.5,0.5."
        )
    }

    @Test("A negative crop value is out of range, not clamped")
    func negativeCrop() throws {
        try expectUsage(
            ["make"] + missing + ["-s", "4:3", "--crop=-0.1,0.5"], "Crop must be two numbers from 0 to 1, like 0.5,0.5."
        )
    }

    // MARK: Option grammar

    @Test("Short options can't be clustered", arguments: ["-wn", "-nw", "-wq", "-sr", "-wj", "-jq"])
    func clusteredShortOptions(cluster: String) throws {
        try expectUsage(["make"] + missing + [cluster], "Unknown option.")
    }

    @Test("An option that needs a value says so when it has none", arguments: [
        ["-o"], ["-s"], ["--resolution"], ["--crop"], ["--out"],
        // Another option is not a value.
        ["-o", "-w"], ["-s", "-n"],
    ] as [[String]])
    func missingValue(options: [String]) throws {
        try expectUsage(["make"] + missing + options, "An option is missing its value.")
    }

    @Test("A value option may be given once", arguments: [
        ["-s", "1:1", "-s", "4:3"], ["--resolution=480p", "-r", "1080p"], ["-o", "a.mp4", "--out=b.mp4"], ["-c", "0,0", "-c", "1,1"],
    ] as [[String]])
    func repeatedOption(options: [String]) throws {
        try expectUsage(["make"] + missing + options, "An option can be given only once.")
    }

    @Test("An unknown option is a usage error that does not echo it, and may suggest one known name", arguments: [
        ("--zzz-typed-text", nil), ("-Q", nil), ("--", nil), ("-", nil),
        ("--overwite", "--overwrite"), ("--dryrun", "--dry-run"), ("--quite", "--quiet"), ("--shap", "--shape"),
        ("--resolutoin", "--resolution"), ("--jsno", "--json"), ("--ouput", "--out"),
    ] as [(String, String?)])
    func unknownOption(typed: String, suggestion: String?) throws {
        let result = try CommandProcess.run(["make"] + missing + [typed])
        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        let expected = suggestion == nil
            ? "Unknown option. \(Self.help)\n"
            : "Unknown option. \(Self.help) Did you mean \(suggestion!)?\n"
        #expect(result.stderr == expected)
        #expect(!result.stderr.contains("typed-text"))
    }

    @Test("Options that belong to no command or to check don't apply to make", arguments: ["--version", "-v", "--repo", "-R"])
    func optionsThatDoNotApply(option: String) throws {
        try expectUsage(["make"] + missing + [option], "That option does not apply here.")
    }

    @Test("The make options don't apply to check, or without a command", arguments: ["-o", "-s", "-r", "-c", "-w", "-n", "-q"])
    func makeOptionsOutsideMake(option: String) throws {
        let withCheck = try CommandProcess.run(["check"] + missing + [option])
        #expect(withCheck.status == 2)
        #expect(withCheck.stderr == "That option does not apply here. Run 'song2vid check --help'.\n")
        let alone = try CommandProcess.run([option])
        #expect(alone.status == 2)
        #expect(alone.stderr == "That option does not apply here. Run 'song2vid --help'.\n")
    }

    @Test("Usage is checked before the files are looked at, and options can come between them")
    func usageComesFirst() throws {
        let result = try CommandProcess.run(["make", "no-such-song", "-s", "5:4", "no-such-picture"])
        #expect(result.status == 2)
        #expect(result.stderr == "Shape must be 16:9, 9:16, 1:1, 4:3 or original. \(Self.help)\n")
    }
}
