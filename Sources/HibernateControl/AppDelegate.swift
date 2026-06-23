import AppKit
import SwiftUI

enum AppMode {
    case settings
    case background
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let mode: AppMode

    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var settingsWindow: NSWindow?
    private var settingsObserver: NSObjectProtocol?
    private var showSettingsObserver: NSObjectProtocol?

    init(mode: AppMode) {
        self.mode = mode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch mode {
        case .background:
            startBackgroundAgent()
        case .settings:
            startSettingsApp()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard mode == .settings else { return }
        presentSettingsWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        mode == .settings
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard mode == .settings else { return false }
        presentSettingsWindow()
        return true
    }

    // MARK: - Settings app

    private func startSettingsApp() {
        NSApp.setActivationPolicy(.regular)
        installAppMenu(title: "Quit Hibernate Control")

        showSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundAgentManager.showSettingsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.presentSettingsWindow()
        }

        let store = SettingsStore.shared
        if store.launchAtLogin {
            BackgroundAgentManager.syncLaunchAgent(enabled: true)
        }
        BackgroundAgentManager.ensureRunning()
        presentSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentSettingsWindow() {
        if settingsWindow == nil {
            createSettingsWindow()
        }
        guard let window = settingsWindow else { return }
        bringSettingsWindowToFront(window)
    }

    private func createSettingsWindow() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Hibernate Control"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed, .fullScreenNone, .moveToActiveSpace]
        window.delegate = self
        settingsWindow = window
    }

    private func bringSettingsWindowToFront(_ window: NSWindow) {
        window.deminiaturize(nil)
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Background agent

    private func startBackgroundAgent() {
        NSApp.setActivationPolicy(.accessory)
        installAppMenu(title: "Quit Background Agent")
        DispatchQueue.main.async { [weak self] in
            self?.installStatusItem()
        }
        registerHotKey()
        NSLog("Hibernate Control: background agent started (pid \(ProcessInfo.processInfo.processIdentifier))")

        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundAgentManager.settingsChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerHotKey()
        }
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let item = statusItem, let button = item.button else { return }
        StatusBarSupport.makeVisible(item)
        StatusBarSupport.configure(
            button: button,
            toolTip: "Hibernate Control — click for Open Settings, Hibernate Now, Quit"
        )

        let menu = NSMenu()
        addMenuAction(menu, title: "Open Settings", action: #selector(openSettingsApp))
        menu.addItem(.separator())
        addMenuAction(menu, title: "Hibernate Now", action: #selector(hibernateNow))
        menu.addItem(.separator())
        addMenuAction(menu, title: "Quit Background Agent", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    private func installAppMenu(title: String) {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let quitItem = appMenu.addItem(
            withTitle: title,
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self

        NSApp.mainMenu = mainMenu
    }

    private func addMenuAction(
        _ menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
    }

    func windowWillClose(_ notification: Notification) {
        guard mode == .settings else { return }
        settingsWindow = nil
        NSApp.terminate(nil)
    }

    @objc private func openSettingsApp() {
        DistributedNotificationCenter.default().post(
            name: BackgroundAgentManager.showSettingsNotification,
            object: nil
        )

        guard let appURL = Bundle.main.bundleURL as URL? else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        config.promptsUserIfNeeded = false

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error {
                NSLog("Hibernate Control: open settings failed: \(error)")
                let fallback = NSWorkspace.OpenConfiguration()
                fallback.activates = true
                fallback.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: fallback, completionHandler: nil)
            }
        }
    }

    @objc private func hibernateNow() {
        performHibernateIfEnabled()
    }

    @objc private func quit() {
        if mode == .background {
            BackgroundAgentManager.stopBackgroundAgent()
        }
        NSApp.terminate(nil)
    }

    private func registerHotKey() {
        if hotKeyManager == nil {
            hotKeyManager = HotKeyManager { [weak self] in
                self?.performHibernateIfEnabled()
            }
        }
        let store = SettingsStore.shared
        if store.hibernateEnabled {
            hotKeyManager?.apply(binding: store.hotKey)
        } else {
            hotKeyManager?.apply(binding: HotKeyBinding(keyCode: 0, modifierFlags: 0))
        }
    }

    private func performHibernateIfEnabled() {
        let store = SettingsStore.shared
        guard store.hibernateEnabled else { return }
        HibernateRunner.trigger(restoreAfterWake: store.restoreAfterWake)
    }
}