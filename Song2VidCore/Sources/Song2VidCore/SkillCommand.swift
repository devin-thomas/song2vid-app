import Foundation

/// `song2vid --skill` (SPEC section 14.2): prints the agent skill that ships inside the app, byte for byte.
///
/// The file is `Song2Vid.app/Contents/Resources/SKILL.md`, copied there from `skills/song2vid/SKILL.md` by the app's
/// build. The command is found at `Contents/Helpers/song2vid`, also when it is run through a link on the PATH.
enum SkillCommand {
    static let unavailable = CommandError(code: .exportFailed, message: "The agent skill is missing from this copy of Song2Vid.")

    static func run(commandURL: URL? = Bundle.main.executableURL) -> CommandOutput {
        guard let commandURL else { return .failure(unavailable, json: false) }
        let skill = commandURL.resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/SKILL.md")
        guard let text = try? String(contentsOf: skill, encoding: .utf8) else { return .failure(unavailable, json: false) }
        return CommandOutput(stdout: text, status: Song2VidCommand.ExitStatus.success)
    }
}
