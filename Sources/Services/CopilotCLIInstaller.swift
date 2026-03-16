import Foundation

/// Manages GitHub Copilot CLI plugin registration
enum CopilotCLIInstaller {

    // MARK: - Constants

    private static let pluginDir = NSHomeDirectory() + "/.masko-desktop/copilot-plugin"
    private static let installedPluginsDir = NSHomeDirectory() + "/.copilot/installed-plugins/local/masko-copilot"
    private static let directPluginsDir = NSHomeDirectory() + "/.copilot/installed-plugins/_direct/copilot-plugin"
    private static let copilotHookScript = NSHomeDirectory() + "/.masko-desktop/hooks/copilot-hook.sh"
    private static let copilotHookCommand = "~/.masko-desktop/hooks/copilot-hook.sh"

    // MARK: - Public API

    /// Check if the Copilot CLI binary is available
    static func isCopilotAvailable() -> Bool {
        let paths = ["/usr/local/bin/copilot", "/opt/homebrew/bin/copilot"]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) { return true }
        }
        // Fall back to `which`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["copilot"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Check if the Claude Code binary is available
    static func isClaudeAvailable() -> Bool {
        let paths = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude"]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) { return true }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Check if our plugin is installed
    static func isRegistered() -> Bool {
        FileManager.default.fileExists(atPath: installedPluginsDir + "/plugin.json")
            || FileManager.default.fileExists(atPath: directPluginsDir + "/plugin.json")
    }

    /// Install the Copilot CLI plugin
    static func install() throws {
        // Ensure the shared hook script and Copilot wrapper exist
        try HookInstaller.ensureScriptExists()
        try ensureCopilotHookScript()

        let fm = FileManager.default

        // Create plugin directory
        try fm.createDirectory(atPath: pluginDir, withIntermediateDirectories: true)

        // Write plugin.json
        let pluginManifest: [String: Any] = [
            "name": "masko-copilot",
            "description": "Masko Code companion for GitHub Copilot CLI",
            "version": "1.0.0",
            "author": ["name": "Masko"],
            "license": "MIT",
            "hooks": "hooks.json",
        ]
        let pluginData = try JSONSerialization.data(withJSONObject: pluginManifest, options: [.prettyPrinted, .sortedKeys])
        try pluginData.write(to: URL(fileURLWithPath: pluginDir + "/plugin.json"))

        // Write hooks.json — Copilot CLI uses { version: 1, hooks: { eventName: [...] } }
        // with camelCase event names and "bash" instead of "command".
        var hooksByEvent: [String: Any] = [:]
        for event in HookInstaller.hookEvents {
            let camelEvent = Self.toCamelCase(event)
            hooksByEvent[camelEvent] = [[
                "type": "command",
                "bash": "\(copilotHookCommand) \(event)",
            ]]
        }
        let hooksConfig: [String: Any] = [
            "version": 1,
            "hooks": hooksByEvent,
        ]
        let hooksData = try JSONSerialization.data(withJSONObject: hooksConfig, options: [.prettyPrinted, .sortedKeys])
        try hooksData.write(to: URL(fileURLWithPath: pluginDir + "/hooks.json"))

        // Try to install via copilot CLI
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "copilot plugin install \(pluginDir)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // If CLI install failed, copy directly to the fallback plugins dir
        if process.terminationStatus != 0 {
            let destDir = directPluginsDir
            try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            let pluginSrc = pluginDir + "/plugin.json"
            let hooksSrc = pluginDir + "/hooks.json"
            let pluginDst = destDir + "/plugin.json"
            let hooksDst = destDir + "/hooks.json"
            // Remove existing files if present
            try? fm.removeItem(atPath: pluginDst)
            try? fm.removeItem(atPath: hooksDst)
            try fm.copyItem(atPath: pluginSrc, toPath: pluginDst)
            try fm.copyItem(atPath: hooksSrc, toPath: hooksDst)
        }
    }

    /// Uninstall the Copilot CLI plugin
    static func uninstall() {
        // Try CLI uninstall first
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "copilot plugin uninstall masko-copilot"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        // Also remove the installed plugin directory directly
        try? FileManager.default.removeItem(atPath: installedPluginsDir)
        try? FileManager.default.removeItem(atPath: directPluginsDir)

        // Clean up our staging directory
        try? FileManager.default.removeItem(atPath: pluginDir)

        // Remove the wrapper script
        try? FileManager.default.removeItem(atPath: copilotHookScript)
    }

    // MARK: - Private

    private static let copilotScriptVersion = "# version: 2"

    /// Convert PascalCase (e.g. "PreToolUse") to camelCase (e.g. "preToolUse").
    private static func toCamelCase(_ pascal: String) -> String {
        guard let first = pascal.first else { return pascal }
        return first.lowercased() + pascal.dropFirst()
    }

    /// Write copilot-hook.sh — translates Copilot CLI event format to masko format
    /// Includes version check to auto-update on app startup.
    static func ensureCopilotHookScript() throws {
        // Skip if already up to date
        if FileManager.default.fileExists(atPath: copilotHookScript),
           let contents = try? String(contentsOfFile: copilotHookScript, encoding: .utf8),
           contents.contains(copilotScriptVersion) {
            return
        }

        let script = """
        #!/bin/bash
        \(copilotScriptVersion)
        # copilot-hook.sh — Translates Copilot CLI hook events for masko-desktop
        # Copilot CLI uses camelCase fields and doesn't include hook_event_name,
        # so we inject the event type (passed as $1) and remap field names.
        EVENT_TYPE="$1"
        INPUT=$(cat 2>/dev/null || echo '{}')

        # Inject hook_event_name, source tag, and translate camelCase → snake_case field names
        INPUT=$(echo "$INPUT" | sed \\
            -e "s/^{/{\\\"hook_event_name\\\":\\\"$EVENT_TYPE\\\",\\\"source\\\":\\\"copilot\\\",/" \\
            -e 's/"sessionId"/"session_id"/g' \\
            -e 's/"toolName"/"tool_name"/g' \\
            -e 's/"toolArgs"/"tool_input"/g' \\
            -e 's/"toolResult"/"tool_response"/g' \\
            -e 's/"hookEventName"/"hook_event_name"/g' \\
            -e 's/"transcriptPath"/"transcript_path"/g' \\
            -e 's/"permissionMode"/"permission_mode"/g' \\
            -e 's/"toolUseId"/"tool_use_id"/g' \\
            -e 's/"notificationType"/"notification_type"/g' \\
            -e 's/"stopHookActive"/"stop_hook_active"/g' \\
            -e 's/"lastAssistantMessage"/"last_assistant_message"/g' \\
            -e 's/"agentId"/"agent_id"/g' \\
            -e 's/"agentType"/"agent_type"/g' \\
            -e 's/"taskId"/"task_id"/g' \\
            -e 's/"taskSubject"/"task_subject"/g')

        echo "$INPUT" | ~/.masko-desktop/hooks/hook-sender.sh
        """

        let dir = (copilotHookScript as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try script.write(toFile: copilotHookScript, atomically: true, encoding: .utf8)
        // Make executable
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: copilotHookScript)
    }
}
