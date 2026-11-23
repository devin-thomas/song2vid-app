import Foundation
import Testing
@testable import Song2VidCore

/// `--update` against a stand-in for the release lookup, so no test touches the network (SPEC section 14.7).
@Suite("song2vid --update")
struct UpdateCommandTests {
    private func release(_ tag: String) -> UpdateCommand.Fetch {
        { _ in Data(#"{"tag_name":"\#(tag)","name":"anything"}"#.utf8) }
    }

    @Test("Versions are compared as numbers, so 1.10.0 is after 1.9.0")
    func versions() throws {
        func v(_ text: String) throws -> UpdateCommand.Version { try #require(UpdateCommand.Version(text)) }
        #expect(try v("1.10.0") > v("1.9.0"))
        #expect(try v("1.1.0") == v("1.1"))
        #expect(try v("2") > v("1.99.99"))
        #expect(try v("1.1.0") < v("1.1.1"))
        for bad in ["", "v1.1.0", "1.1.0" + ".0", "1..0", "1.x", "-1", "1.1.0-beta", "1234567"] {
            #expect(UpdateCommand.Version(bad) == nil, "\(bad)")
        }
    }

    @Test("The same version is up to date, an older one too, a newer one is available")
    func comparison() {
        let current = Song2VidCommand.version
        #expect(UpdateCommand.run(json: false, environment: [:], fetch: release("v\(current)")).stdout == "Song2Vid \(current) is up to date.\n")
        #expect(UpdateCommand.run(json: false, environment: [:], fetch: release("v0.9.0")).stdout == "Song2Vid \(current) is up to date.\n")
        let newer = UpdateCommand.run(json: false, environment: [:], fetch: release("v99.0.1"))
        #expect(newer.status == 0)
        #expect(newer.stdout == "Song2Vid 99.0.1 is available (you have \(current)). Download it from https://song2vid.pages.dev.\n")
    }

    @Test("--json is one result line with the fixed keys")
    func json() {
        let current = Song2VidCommand.version
        let latest = "99.0.1"
        let output = UpdateCommand.run(json: true, environment: [:], fetch: release(latest))
        #expect(output.stdout == #"{"api_version":"1","type":"result","command":"update","current":"\#(current)","latest":"\#(latest)","update_available":true,"download_page":"https://song2vid.pages.dev"}"# + "\n")
        #expect(output.stderr.isEmpty)
        let same = UpdateCommand.run(json: true, environment: [:], fetch: release("v\(current)"))
        #expect(same.stdout.contains(#""update_available":false"#))
    }

    @Test("A lookup that fails, or answers with something that is not a release, is exit 5 with the code network")
    func network() {
        let silent: UpdateCommand.Fetch = { _ in nil }
        let text = UpdateCommand.run(json: false, environment: [:], fetch: silent)
        #expect(text.status == 5)
        #expect(text.stderr == "Couldn't check for updates. Check the internet connection and try again.\n")
        #expect(text.stdout.isEmpty)
        let json = UpdateCommand.run(json: true, environment: [:], fetch: silent)
        #expect(json.status == 5)
        #expect(json.stderr.isEmpty)
        #expect(json.stdout.contains(#""code":"network""#))
        for body in ["not json", "[]", #"{"tag_name":5}"#, #"{"tag_name":"latest"}"#, #"{}"#] {
            #expect(UpdateCommand.run(json: false, environment: [:], fetch: { _ in Data(body.utf8) }).status == 5, "\(body)")
        }
    }

    @Test("Only GitHub, a file or this computer (localhost) can be asked, whatever the environment says")
    func lookupAddress() {
        let github = UpdateCommand.releaseURL
        #expect(UpdateCommand.lookupURL(environment: [:]).absoluteString == github)
        let key = UpdateCommand.stubVariable
        #expect(UpdateCommand.lookupURL(environment: [key: "file:///tmp/stub.json"]).absoluteString == "file:///tmp/stub.json")
        #expect(UpdateCommand.lookupURL(environment: [key: "http://[::1]:8080/x"]).absoluteString == "http://[::1]:8080/x")
        #expect(UpdateCommand.lookupURL(environment: [key: "http://localhost/x"]).absoluteString == "http://localhost/x")
        for elsewhere in ["https://example.com/x", "http://example.com/x", "http://localhost.example.com/x", "ftp://localhost/x", "nonsense"] {
            #expect(UpdateCommand.lookupURL(environment: [key: elsewhere]).absoluteString == github, "\(elsewhere)")
        }
    }
}
