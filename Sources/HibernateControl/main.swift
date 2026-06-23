import AppKit

let isLoginLaunch = CommandLine.arguments.contains("--login")
let app = NSApplication.shared
let delegate = AppDelegate(loginLaunch: isLoginLaunch)
app.delegate = delegate
app.run()