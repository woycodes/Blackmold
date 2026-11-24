import Foundation

/// The Claude Code hooks that report to the notch through blackmold:// links.
/// `open -g` hands the link over without bringing Blackmold to the front.
enum ClaudeHooks {
    static let json = """
        {
          "hooks": {
            "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "open -g blackmold://claude/thinking" }] }],
            "PreToolUse": [{ "hooks": [{ "type": "command", "command": "open -g blackmold://claude/working" }] }],
            "Notification": [{ "hooks": [{ "type": "command", "command": "open -g blackmold://claude/waiting" }] }],
            "Stop": [{ "hooks": [{ "type": "command", "command": "open -g blackmold://claude/done" }] }]
          }
        }
        """
}
