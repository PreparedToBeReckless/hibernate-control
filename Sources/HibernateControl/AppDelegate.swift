import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let loginLaunch: Bool

    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var settingsWindow: NSWindow?
    private var settingsObserver: NSObjectProtocol?
    private var showSettingsObserver: NSObjectProtocol?
    private var hideSettingsObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var becomeActiveObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?
    private var stopServiceObserver: NSObjectProtocol?
    private var startServiceObserver: NSObjectProtocol?

    init(loginLaunch: Bool) {
        self.loginLaunch = loginLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if BackgroundAgentManager.isOtherInstanceRunning() {
            BackgroundAgentManager.requestShowSettings()
            NSApp.terminate(nil)
            return
        }

        installAppMenu()
        if BackgroundAgentManager.isBackgroundServiceActive() {
            startBackgroundService()
        }
        installHotKeyRefreshObservers()

        showSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundAgentManager.showSettingsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.presentSettingsWindow()
        }

        hideSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundAgentManager.hideSettingsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideSettingsWindow()
        }

        stopServiceObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundAgentManager.stopBackgroundServiceNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopBackgroundService()
        }

        startServiceObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundAgentManager.startBackgroundServiceNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startBackgroundService()
        }

        let store = SettingsStore.shared
        if store.launchAtLogin {
            BackgroundAgentManager.syncLaunchAgent(enabled: true)
        }

        if loginLaunch {
            NSApp.setActivationPolicy(.accessory)
        } else {
            presentSettingsWindow()
        }

        NSLog("Hibernate Control: started (pid \(ProcessInfo.processInfo.processIdentifier), login=\(loginLaunch))")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentSettingsWindow()
        return true
    }

    private func presentSettingsWindow() {
        if settingsWindow == nil {
            createSettingsWindow()
        }
        guard let window = settingsWindow else { return }

        NSApp.setActivationPolicy(.regular)
        window.deminiaturize(nil)
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        hotKeyManager?.reregister()
    }

    private func createSettingsWindow() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Hibernate Control"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 580))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        settingsWindow = window
    }

    private func hideSettingsWindow() {
        settingsWindow?.orderOut(nil)
        if BackgroundAgentManager.isBackgroundServiceActive() {
            NSApp.setActivationPolicy(.accessory)
            scheduleHotKeyReregistration()
        }
    }

    private func startBackgroundService() {
        if statusItem == nil {
            installStatusItem()
        }
        registerHotKey()
        scheduleHotKeyReregistration()
        NSLog("Hibernate Control: background service started")
    }

    private func stopBackgroundService() {
        hotKeyManager?.apply(binding: HotKeyBinding(keyCode: 0, modifierFlags: 0))
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        NSLog("Hibernate Control: background service stopped")
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
        addMenuAction(menu, title: "Open Settings", action: #selector(openSettings))
        menu.addItem(.separator())
        addMenuAction(menu, title: "Hibernate Now", action: #selector(hibernateNow))
        menu.addItem(.separator())
        addMenuAction(menu, title: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    private func installAppMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        let hideItem = appMenu.addItem(
            withTitle: "Hide to Menu Bar",
            action: #selector(hideToMenuBar),
            keyEquivalent: "q"
        )
        hideItem.target = self

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
        hideSettingsWindow()
    }

    @objc private func openSettings() {
        presentSettingsWindow()
    }

    @objc private func hibernateNow() {
        performHibernateIfEnabled()
    }

    @objc private func hideToMenuBar() {
        hideSettingsWindow()
    }

    @objc private func quit() {
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

        if settingsObserver == nil {
            settingsObserver = DistributedNotificationCenter.default().addObserver(
                forName: BackgroundAgentManager.settingsChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.registerHotKey()
            }
        }
    }

    private func installHotKeyRefreshObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        wakeObserver = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleHotKeyReregistration()
        }

        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotKeyManager?.reregister()
        }

        screenUnlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleHotKeyReregistration()
        }
    }

    private func scheduleHotKeyReregistration() {
        let delays: [TimeInterval] = loginLaunch ? [1, 3, 8, 15, 30] : [0.5, 2]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.hotKeyManager?.reregister()
            }
        }
    }

    private func performHibernateIfEnabled() {
        let store = SettingsStore.shared
        guard store.hibernateEnabled else { return }
        HibernateRunner.trigger(
            restoreAfterWake: store.restoreAfterWake,
            ejectDrives: store.ejectDrivesBeforeHibernate
        )
    }
}