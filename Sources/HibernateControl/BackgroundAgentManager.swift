import Foundation

enum BackgroundAgentManager {
    static let settingsChangedNotification = Notification.Name("com.hibernatecontrol.settingsChanged")
    static let showSettingsNotification = Notification.Name("com.hibernatecontrol.showSettings")

    private static var launchAgentLabel: String { "com.hibernatecontrol.agent" }

    private static var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    static func executablePath() -> String? {
        Bundle.main.executableURL?.path
    }

    static func isBackgroundRunning() -> Bool {
        runPgrep(arguments: ["-f", "HibernateControl --background"])
    }

    static func ensureRunning() {
        terminateBackgroundInstances()
        guard let executable = executablePath() else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--background"]
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
        } catch {
            NSLog("Hibernate Control: failed to spawn background agent: \(error)")
        }
    }

    static func stopBackgroundAgent() {
        terminateBackgroundInstances()
        _ = runLaunchctl(["bootout", "gui/\(getuid())", launchAgentPlistURL.path])
    }

    static func installLaunchAgent() -> Bool {
        guard let executable = executablePath() else { return false }

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executable, "--background"],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]

        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try FileManager.default.createDirectory(
                at: launchAgentPlistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: launchAgentPlistURL)
            return reloadLaunchAgent()
        } catch {
            NSLog("Hibernate Control: failed to install launch agent: \(error)")
            return false
        }
    }

    static func uninstallLaunchAgent() -> Bool {
        stopBackgroundAgent()
        try? FileManager.default.removeItem(at: launchAgentPlistURL)
        return true
    }

    static func syncLaunchAgent(enabled: Bool) {
        if enabled {
            _ = installLaunchAgent()
        } else {
            _ = uninstallLaunchAgent()
        }
    }

    @discardableResult
    private static func reloadLaunchAgent() -> Bool {
        _ = runLaunchctl(["bootout", "gui/\(getuid())", launchAgentPlistURL.path])
        return runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentPlistURL.path])
    }

    private static func terminateBackgroundInstances() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "HibernateControl --background"]
        process.standardOutput = nil
        process.standardError = nil
        try? process.run()
        process.waitUntilExit()
    }

    @discardableResult
    private static func runPgrep(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return process.terminationStatus == 0 && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func notifySettingsChanged() {
        DistributedNotificationCenter.default().post(name: settingsChangedNotification, object: nil)
    }
}