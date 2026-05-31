import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var timer: Timer?
    
    var rapportdMenuItem: NSMenuItem?
    var awdlMenuItem: NSMenuItem?
    
    var onboardingWindow: NSWindow?
    
    let targetApp = "Boosteroid"
    let sudoersPath = "/etc/sudoers.d/cloud_optimizer"
    let pkillPath = "/usr/bin/pkill"
    let ifconfigPath = "/sbin/ifconfig"
    
    var isGamingModeActive = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !hasSudoersSetup() {
            showOnboardingWindow()
        }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        let menu = NSMenu()
        rapportdMenuItem = NSMenuItem(title: "rapportd: Checking...", action: nil, keyEquivalent: "")
        awdlMenuItem = NSMenuItem(title: "awdl0: Checking...", action: nil, keyEquivalent: "")
        
        menu.addItem(rapportdMenuItem!)
        menu.addItem(awdlMenuItem!)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(checkStatus), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        
        // Monitoring
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appLaunched), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appTerminated), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        
        // Initial check
        checkIfTargetRunning()
        
        timer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(checkStatus), userInfo: nil, repeats: true)
        checkStatus()
    }
    
    @objc func appLaunched(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.localizedName == targetApp {
            enableGamingMode()
        }
    }
    
    @objc func appTerminated(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.localizedName == targetApp {
            disableGamingMode()
        }
    }
    
    func checkIfTargetRunning() {
        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.contains(where: { $0.localizedName == targetApp }) {
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
        if isGamingModeActive {
            _ = shell("sudo \(ifconfigPath) awdl0 down")
        }
        
        let fileExists = FileManager.default.fileExists(atPath: "/tmp/gamemode_on")
        let rapportdStatus = shell("ps -ax -o state,comm | grep rapportd | grep -v grep").trimmingCharacters(in: .whitespacesAndNewlines)
        let isRapportdSuspended = rapportdStatus.contains("T")
        let ifconfigOutput = shell("ifconfig awdl0").lowercased()
        let isAwdlDown = !ifconfigOutput.contains("status: active") || ifconfigOutput.contains("inactive")
        
        DispatchQueue.main.async {
            self.updateUI(file: fileExists, rapportdSuspended: isRapportdSuspended, awdlDown: isAwdlDown)
        }
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
