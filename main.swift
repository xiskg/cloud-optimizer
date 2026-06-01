import AppKit
import Foundation
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var timer: Timer?
    var inactivityTimer: Timer?
    var uiUpdateTimer: Timer?
    
    var statusMenuItem: NSMenuItem?
    var countdownMenuItem: NSMenuItem?
    var manualOverrideMenuItem: NSMenuItem?
    var launchAtLoginMenuItem: NSMenuItem?
    var rapportdMenuItem: NSMenuItem?
    var awdlMenuItem: NSMenuItem?
    
    var onboardingWindow: NSWindow?
    
    let targetApp = "Boosteroid"
    let sudoersPath = "/etc/sudoers.d/cloud_optimizer"
    let pkillPath = "/usr/bin/pkill"
    let ifconfigPath = "/sbin/ifconfig"
    
    var isGamingModeActive = false
    var timerEndDate: Date?

    // Settings
    private let kInactivityTimeout = "inactivityTimeout"
    private let kManualOverride = "manualOverride"

    var inactivityTimeoutSeconds: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: kInactivityTimeout)
            return val == 0 ? 300 : (val == -1 ? 0 : val)
        }
        set {
            UserDefaults.standard.set(newValue == 0 ? -1 : newValue, forKey: kInactivityTimeout)
            setupMenu() // Refresh menu checkmarks
        }
    }
    
    var isManualOverride: Bool {
        get { UserDefaults.standard.bool(forKey: kManualOverride) }
        set { 
            UserDefaults.standard.set(newValue, forKey: kManualOverride)
            if newValue {
                enableGamingMode()
            } else {
                checkIfTargetRunning() // Reset to focus-based state
            }
        }
    }

    var isLaunchAtLoginEnabled: Bool {
        get {
            return SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update Launch at Login: \(error)")
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !hasSudoersSetup() {
            showOnboardingWindow()
        }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupMenu()
        
        // Monitoring
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appDeactivated), name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appTerminated), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        
        // Initial check
        if isManualOverride {
            enableGamingMode()
        } else {
            checkIfTargetRunning()
        }
        
        timer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(checkStatus), userInfo: nil, repeats: true)
        uiUpdateTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(refreshUIStrings), userInfo: nil, repeats: true)
        checkStatus()
    }

    func setupMenu() {
        let menu = NSMenu()
        
        statusMenuItem = NSMenuItem(title: "Status: Checking...", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu.addItem(statusMenuItem!)
        
        countdownMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        countdownMenuItem?.isHidden = true
        countdownMenuItem?.isEnabled = false
        menu.addItem(countdownMenuItem!)
        
        menu.addItem(NSMenuItem.separator())
        
        manualOverrideMenuItem = NSMenuItem(title: "Force Optimization", action: #selector(toggleManualOverride), keyEquivalent: "f")
        manualOverrideMenuItem?.state = isManualOverride ? .on : .off
        menu.addItem(manualOverrideMenuItem!)

        launchAtLoginMenuItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem?.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLoginMenuItem!)
        
        let timeoutMenu = NSMenu()
        let timeouts = [(60, "1 Minute"), (300, "5 Minutes"), (900, "15 Minutes"), (0, "Never (Always On)")]
        for (sec, title) in timeouts {
            let item = NSMenuItem(title: title, action: #selector(setTimeout(_:)), keyEquivalent: "")
            item.representedObject = sec
            item.state = (inactivityTimeoutSeconds == sec) ? .on : .off
            timeoutMenu.addItem(item)
        }
        
        let timeoutParent = NSMenuItem(title: "Disable inactivity after...", action: nil, keyEquivalent: "")
        timeoutParent.submenu = timeoutMenu
        menu.addItem(timeoutParent)
        
        menu.addItem(NSMenuItem.separator())
        
        rapportdMenuItem = NSMenuItem(title: "rapportd: Checking...", action: nil, keyEquivalent: "")
        awdlMenuItem = NSMenuItem(title: "awdl0: Checking...", action: nil, keyEquivalent: "")
        rapportdMenuItem?.isEnabled = false
        awdlMenuItem?.isEnabled = false
        
        menu.addItem(rapportdMenuItem!)
        menu.addItem(awdlMenuItem!)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Restore Services Now", action: #selector(forceRestore), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(checkStatus), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }

    @objc func forceRestore() {
        isManualOverride = false
        isGamingModeActive = true // Force true so disableGamingMode runs
        disableGamingMode()
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        timerEndDate = nil
        setupMenu()
    }

    @objc func toggleManualOverride() {
        isManualOverride = !isManualOverride
        setupMenu() // Refresh UI
    }

    @objc func toggleLaunchAtLogin() {
        isLaunchAtLoginEnabled = !isLaunchAtLoginEnabled
        setupMenu()
    }

    @objc func setTimeout(_ sender: NSMenuItem) {
        if let sec = sender.representedObject as? Int {
            inactivityTimeoutSeconds = sec
        }
    }

    @objc func refreshUIStrings() {
        if let endDate = timerEndDate, isGamingModeActive, !isManualOverride {
            let remaining = Int(max(0, endDate.timeIntervalSinceNow))
            if remaining > 0 {
                let mins = remaining / 60
                let secs = remaining % 60
                countdownMenuItem?.title = String(format: "Restoring in %02d:%02d...", mins, secs)
                countdownMenuItem?.isHidden = false
            } else {
                countdownMenuItem?.isHidden = true
            }
        } else {
            countdownMenuItem?.isHidden = true
        }
        
        if isManualOverride {
            statusMenuItem?.title = "Status: Optimized (Manual)"
        } else if isGamingModeActive {
            if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.localizedName == targetApp {
                statusMenuItem?.title = "Status: Optimized (Active)"
            } else {
                statusMenuItem?.title = "Status: Grace Period (Timer)"
            }
        } else {
            let runningApps = NSWorkspace.shared.runningApplications
            let isRunning = runningApps.contains(where: { $0.localizedName == targetApp })
            if isRunning {
                statusMenuItem?.title = "Status: Ready (Waiting Focus)"
            } else {
                statusMenuItem?.title = "Status: Inactive (App Closed)"
            }
        }
    }
    
    @objc func appActivated(_ notification: Notification) {
        // Handled by checkStatus timer
    }
    
    @objc func appDeactivated(_ notification: Notification) {
        // Handled by checkStatus timer
    }
    
    @objc func appTerminated(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.localizedName == targetApp {
            inactivityTimer?.invalidate()
            inactivityTimer = nil
            timerEndDate = nil
            if !isManualOverride {
                disableGamingMode()
            }
        }
    }
    
    func checkIfTargetRunning() {
        if isManualOverride { return }
        if let frontmostApp = NSWorkspace.shared.frontmostApplication, frontmostApp.localizedName == targetApp {
            enableGamingMode()
        }
    }

    
    func enableGamingMode() {
        guard !isGamingModeActive else { return }
        isGamingModeActive = true
        
        // Give the PWA a moment to load as in the original script
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            if self.isGamingModeActive {
                _ = self.shell("sudo \(self.pkillPath) -STOP rapportd")
                _ = self.shell("sudo \(self.ifconfigPath) awdl0 down")
                _ = self.shell("touch /tmp/gamemode_on")
            }
        }
    }
    
    func disableGamingMode() {
        guard isGamingModeActive else { return }
        isGamingModeActive = false
        
        _ = self.shell("sudo \(self.pkillPath) -CONT rapportd")
        _ = self.shell("sudo \(self.ifconfigPath) awdl0 up")
        _ = self.shell("rm -f /tmp/gamemode_on")
    }
    
    func hasSudoersSetup() -> Bool {
        let rule = "%admin ALL=(ALL) NOPASSWD: \(pkillPath) -STOP rapportd, \(pkillPath) -CONT rapportd, \(ifconfigPath) awdl0 down, \(ifconfigPath) awdl0 up"
        
        if FileManager.default.fileExists(atPath: sudoersPath) {
            if let content = try? String(contentsOfFile: sudoersPath, encoding: .utf8), content.trimmingCharacters(in: .whitespacesAndNewlines) == rule {
                return true
            }
        }
        return false
    }
    
    @discardableResult
    func performSudoersSetup() -> Bool {
        let rule = "%admin ALL=(ALL) NOPASSWD: \(pkillPath) -STOP rapportd, \(pkillPath) -CONT rapportd, \(ifconfigPath) awdl0 down, \(ifconfigPath) awdl0 up"
        let script = "do shell script \"mkdir -p /etc/sudoers.d && echo '\(rule)' > \(sudoersPath)\" with administrator privileges"
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let err = error {
            print("Setup failed: \(err)")
            return false
        }
        return true
    }
    
    func showOnboardingWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 300), 
                             styleMask: [.titled, .closable], 
                             backing: .buffered, defer: false)
        window.title = "Cloud Optimizer Setup"
        window.center()
        window.isReleasedWhenClosed = false
        
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 300))
        
        let titleLabel = NSTextField(labelWithString: "Welcome to Cloud Optimizer")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 20, y: 240, width: 410, height: 30)
        titleLabel.alignment = .center
        contentView.addSubview(titleLabel)
        
        let descText = "To ensure the best gaming experience, this app reduces Wi-Fi latency spikes by temporarily suspending background services (like AirPlay/AirDrop and Continuity) while Boosteroid is running.\n\nClick below to enable the optimizer. You will need to enter your Mac password once to authorize these system changes."
        let descLabel = NSTextField(wrappingLabelWithString: descText)
        descLabel.font = NSFont.systemFont(ofSize: 13)
        descLabel.frame = NSRect(x: 40, y: 80, width: 370, height: 140)
        descLabel.alignment = .center
        contentView.addSubview(descLabel)
        
        let button = NSButton(title: "Enable Optimizer", target: self, action: #selector(requestPermissionsAndClose))
        button.frame = NSRect(x: 145, y: 30, width: 160, height: 40)
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r" // Enter key
        contentView.addSubview(button)
        
        window.contentView = contentView
        self.onboardingWindow = window
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func requestPermissionsAndClose() {
        if performSudoersSetup() {
            onboardingWindow?.close()
            checkStatus() // Refresh immediately
        }
    }
    
    @objc func checkStatus() {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let isTargetFrontmost = frontmostApp?.localizedName == targetApp
        
        let runningApps = NSWorkspace.shared.runningApplications
        let isTargetRunning = runningApps.contains(where: { $0.localizedName == targetApp })

        // Physical status check
        let rapportdStatus = shell("ps -ax -o state,comm | grep rapportd | grep -v grep").trimmingCharacters(in: .whitespacesAndNewlines)
        let isRapportdSuspended = rapportdStatus.contains("T")
        let ifconfigOutput = shell("ifconfig awdl0").lowercased()
        let isAwdlDown = !ifconfigOutput.contains("status: active") || ifconfigOutput.contains("inactive")
        let isPhysicallyOptimized = isRapportdSuspended && isAwdlDown

        // 1. RECONCILIATION LOGIC
        if isManualOverride {
            enableGamingMode()
        } else if isTargetFrontmost {
            // Boosteroid is focused: Active mode, no timer
            inactivityTimer?.invalidate()
            inactivityTimer = nil
            timerEndDate = nil
            enableGamingMode()
        } else if isTargetRunning {
            // Boosteroid running in background
            if isGamingModeActive {
                // We are already in gaming mode (grace period)
                if inactivityTimeoutSeconds > 0 {
                    if inactivityTimer == nil {
                        startInactivityTimer()
                    }
                }
            } else if isPhysicallyOptimized {
                // DESYNC: System is optimized but app thinks it's not. 
                // Since Boosteroid is running, we "take over" and start the grace period.
                isGamingModeActive = true
                startInactivityTimer()
            }
        } else {
            // Boosteroid not running at all
            if isGamingModeActive || isPhysicallyOptimized {
                disableGamingMode()
            }
            inactivityTimer?.invalidate()
            inactivityTimer = nil
            timerEndDate = nil
        }
        
        // 2. ENFORCE PHYSICAL STATE
        if isGamingModeActive {
            _ = shell("sudo \(ifconfigPath) awdl0 down")
            // (pkill -STOP is handled by enableGamingMode to avoid repeating sudo unnecessarily)
        }
        
        let fileExists = FileManager.default.fileExists(atPath: "/tmp/gamemode_on")
        
        DispatchQueue.main.async {
            self.updateUI(file: fileExists, rapportdSuspended: isRapportdSuspended, awdlDown: isAwdlDown)
        }
    }

    func startInactivityTimer() {
        inactivityTimer?.invalidate()
        let timeout = TimeInterval(inactivityTimeoutSeconds)
        timerEndDate = Date().addingTimeInterval(timeout)
        let t = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
            self?.disableGamingMode()
            self?.timerEndDate = nil
            self?.inactivityTimer = nil
        }
        inactivityTimer = t
        RunLoop.main.add(t, forMode: .common)
    }
    
    func updateUI(file: Bool, rapportdSuspended: Bool, awdlDown: Bool) {
        guard let button = statusItem?.button else { return }
        
        // Icon is green if gaming mode is active OR the manual trigger file exists
        let isActuallyActive = isGamingModeActive || file || (rapportdSuspended && awdlDown)
        
        if isActuallyActive {
            // Use Hierarchical color configuration for the green icon
            let config = NSImage.SymbolConfiguration(hierarchicalColor: NSColor.systemGreen)
            if let image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "Boosteroid On")?.withSymbolConfiguration(config) {
                image.isTemplate = false
                button.image = image
                button.contentTintColor = nil
            }
        } else {
            // Standard adaptive icon for inactive state
            if let image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Boosteroid Off") {
                image.isTemplate = true
                button.image = image
                button.contentTintColor = nil
            }
        }
        
        rapportdMenuItem?.title = "rapportd: " + (rapportdSuspended ? "🔴 Suspended" : "🟢 Running")
        awdlMenuItem?.title = "awdl0: " + (awdlDown ? "🔴 Down" : "🟢 Up")
    }
    
    func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
