import Foundation

enum HibernateRunner {
    private static let logPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/HibernateControl/hibernate.log")

    static func trigger(restoreAfterWake: Bool) {
        DispatchQueue.main.async {
            runWithAdminPrompt(restoreAfterWake: restoreAfterWake)
        }
    }

    private static func runWithAdminPrompt(restoreAfterWake: Bool) {
        do {
            let scriptURL = try writeScript(restoreAfterWake: restoreAfterWake)
            try FileManager.default.createDirectory(
                at: logPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Run synchronously as root. nohup fails under osascript ("Inappropriate ioctl for device").
            // This blocks through hibernate and resumes after wake to restore settings.
            let command = "/bin/bash '\(scriptURL.path)' >> '\(logPath.path)' 2>&1"
            let escapedCommand = command
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")

            let appleScriptSource = "do shell script \"\(escapedCommand)\" with administrator privileges"
            var errorInfo: NSDictionary?
            let appleScript = NSAppleScript(source: appleScriptSource)
            appleScript?.executeAndReturnError(&errorInfo)

            if let errorInfo {
                NSLog("Hibernate Control: hibernate failed: \(errorInfo)")
            }
        } catch {
            NSLog("Hibernate Control: could not prepare hibernate script: \(error)")
        }
    }

    private static func writeScript(restoreAfterWake: Bool) throws -> URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HibernateControl", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        let scriptURL = supportDir.appendingPathComponent("hibernate.sh")
        let body = buildShellScript(restoreAfterWake: restoreAfterWake)
        let script = "#!/bin/bash\n\(body)\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private static func buildShellScript(restoreAfterWake: Bool) -> String {
        var lines = [
            "echo \"=== $(date) hibernate started ===\"",
            "pkill -STOP AMPDeviceDiscoveryAgent 2>/dev/null || true",
            "pkill -STOP AMPDevicesAgent 2>/dev/null || true",
            "tmutil stopbackup 2>/dev/null || true",
            "/usr/bin/pmset -a hibernatemode 25",
            "/usr/bin/pmset -a ttyskeepawake 0",
            "/usr/bin/pmset -a tcpkeepalive 0",
            "/usr/bin/pmset -a womp 0",
            "/usr/bin/pmset -a powernap 0",
            "/usr/bin/pmset -a networkoversleep 0",
            "sleep 3",
            "/usr/bin/pmset sleepnow",
        ]

        if restoreAfterWake {
            lines += [
                "sleep 15",
                "/usr/bin/pmset -a hibernatemode 3",
                "/usr/bin/launchctl start com.apple.AMPDevicesAgent 2>/dev/null || true",
                "/usr/bin/killall Finder 2>/dev/null || true",
                "echo \"=== $(date) restored hibernatemode 3 ===\"",
            ]
        }

        return lines.joined(separator: "\n")
    }
}