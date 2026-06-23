import AppKit

let isBackground = CommandLine.arguments.contains("--background")
let app = NSApplication.shared
let delegate = AppDelegate(mode: isBackground ? .background : .settings)
app.delegate = delegate
app.setActivationPolicy(isBackground ? .accessory : .regular)
app.run()