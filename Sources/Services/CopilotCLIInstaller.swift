import Foundation

/// Manages GitHub Copilot CLI plugin registration
enum CopilotCLIInstaller {

    // MARK: - Constants

    private static let pluginDir = NSHomeDirectory() + "/.masko-desktop/copilot-plugin"
    private static let installedPluginsDir = NSHomeDirectory() + "/.copilot/installed-plugins/local/masko-copilot"
    private static let directPluginsDir = NSHomeDirectory() + "/.copilot/installed-plugins/_direct/copilot-plugin"
    private static let hookCommand = "~/.masko-desktop/hooks/hook-sender.sh"

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

    /// Check if our plugin is installed
    static func isRegistered() -> Bool {
        FileManager.default.fileExists(atPath: installedPluginsDir + "/plugin.json")
            || FileManager.default.fileExists(atPath: directPluginsDir + "/plugin.json")
    }

    /// Install the Copilot CLI plugin
    static func install() throws {
        // Ensure the shared hook script exists
        try HookInstaller.ensureScriptExists()

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

        // Write hooks.json using the same events as HookInstaller
        let hookEntry: [String: Any] = [
            "matcher": "",
            "hooks": [["type": "command", "command": hookCommand]],
        ]
        var hooksConfig: [String: Any] = [:]
        for event in HookInstaller.hookEvents {
            hooksConfig[event] = [hookEntry]
        }
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
    }
}
