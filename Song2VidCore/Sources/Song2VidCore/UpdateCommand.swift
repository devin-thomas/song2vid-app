import Foundation

/// `song2vid --update` (SPEC section 14.7): asks GitHub for the latest release and says whether it is newer.
/// It downloads and replaces nothing (ADR-020), and it sends nothing about the person: one plain GET.
enum UpdateCommand {
    static let releaseURL = "https://api.github.com/repos/devin-thomas/song2vid-app/releases/latest"
    static let downloadPage = "https://song2vid.pages.dev"
    /// Tests point the lookup at a local stub with this variable. Only a file or this computer (localhost) is accepted, so
    /// it can't send the request anywhere else.
    static let stubVariable = "SONG2VID_UPDATE_URL"

    static let networkError = CommandError(
        code: .network, message: "Couldn't check for updates. Check the internet connection and try again."
    )

    /// Gets the body at a URL, or nil when it can't be read.
    typealias Fetch = @Sendable (URL) -> Data?

    static func run(json: Bool, environment: [String: String], fetch: Fetch = UpdateCommand.fetchOverTheNetwork) -> CommandOutput {
        let url = lookupURL(environment: environment)
        // A framework that logs to stderr must not mix into the output (CommandSilence).
        let latest = withSystemOutputSilenced { latestVersion(at: url, fetch: fetch) }
        guard let latest else { return .failure(networkError, json: json) }
        let current = Song2VidCommand.version
        let available = Version(latest)! > Version(current)!
        if json {
            let line = JSONValue.line(type: "result", [
                (.command, .string("update")),
                (.current, .string(current)),
                (.latest, .string(latest)),
                (.updateAvailable, .bool(available)),
                (.downloadPage, .string(downloadPage)),
            ])
            return CommandOutput(stdout: line.line, status: 0)
        }
        let text = available
            ? "Song2Vid \(latest) is available (you have \(current)). Download it from \(downloadPage).\n"
            : "Song2Vid \(current) is up to date.\n"
        return CommandOutput(stdout: text, status: 0)
    }

    /// The release address: GitHub's, or a local stub named in the environment.
    static func lookupURL(environment: [String: String]) -> URL {
        if let stub = environment[stubVariable], let url = URL(string: stub), isLocal(url) { return url }
        return URL(string: releaseURL)!
    }

    private static func isLocal(_ url: URL) -> Bool {
        switch url.scheme {
        case "file": true
        case "http": ["localhost", "::1"].contains(url.host ?? "")
        default: false
        }
    }

    /// The `tag_name` of the release at the URL as a plain version ("1.2.0"), or nil if the answer isn't one.
    static func latestVersion(at url: URL, fetch: Fetch) -> String? {
        guard let data = fetch(url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var tag = object["tag_name"] as? String else { return nil }
        if tag.hasPrefix("v") { tag.removeFirst() }
        return Version(tag) == nil ? nil : tag
    }

    static let fetchOverTheNetwork: Fetch = { url in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("song2vid", forHTTPHeaderField: "User-Agent")
        let done = DispatchSemaphore(value: 0)
        let box = FetchBox()
        let task = URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                box.data = nil
            } else {
                box.data = data
            }
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + 15) == .timedOut {
            task.cancel()
            return nil
        }
        return box.data
    }

    private final class FetchBox: @unchecked Sendable {
        var data: Data?
    }

    /// A dotted version of one to three numbers, ordered as numbers ("1.10.0" is after "1.9.0").
    struct Version: Comparable {
        let parts: [Int]

        init?(_ text: String) {
            let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
            guard (1...3).contains(pieces.count) else { return nil }
            var numbers: [Int] = []
            for piece in pieces {
                guard !piece.isEmpty, piece.count <= 6, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(piece) else { return nil }
                numbers.append(number)
            }
            parts = numbers + Array(repeating: 0, count: 3 - numbers.count)
        }

        static func < (lhs: Version, rhs: Version) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
    }
}
