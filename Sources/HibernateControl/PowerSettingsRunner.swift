import Foundation

enum PowerSettingsRunner {
    private static let logPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/HibernateControl/power.log")

    static func setKeepAwakeOnPowerAdapter(_ enabled: Bool) {
        DispatchQueue.main.async {
            runAdminCommand(
                enabled
                    ? "/usr/bin/pmset -c sleep 0"
                    : "/usr/bin/pmset -c sleep 10",
                label: enabled ? "enable AC keep-awake" : "restore AC sleep timer"
            )
        }
    }

    static func openTerminalWithPmsetStatus() {
        do {
            let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("HibernateControl", isDirectory: true)
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

            let scriptURL = supportDir.appendingPathComponent("pmset-check.command")
            let script = """
            #!/bin/bash
            pmset -g
            echo ""
            echo "--- custom ---"
            pmset -g custom
            echo ""
            echo "--- assertions ---"
            pmset -g assertions
            echo ""
            echo "Done. You can close this window."
            """
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Terminal", scriptURL.path]
            try process.run()
        } catch {
            NSLog("Hibernate Control: failed to open Terminal for pmset: \(error)")
        }
    }

    private static func runAdminCommand(_ command: String, label: String) {
        do {
            try FileManager.default.createDirectory(
                at: logPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let logged = "echo \"=== $(date) \(label) ===\"; \(command) >> '\(logPath.path)' 2>&1"
            let escaped = logged
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")

            let appleScriptSource = "do shell script \"\(escaped)\" with administrator privileges"
            var errorInfo: NSDictionary?
            NSAppleScript(source: appleScriptSource)?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                NSLog("Hibernate Control: \(label) failed: \(errorInfo)")
            }
        } catch {
            NSLog("Hibernate Control: \(label) setup failed: \(error)")
        }
    }
}