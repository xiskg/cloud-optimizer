import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Manager Logic
class OptimizerManager: ObservableObject {
    @Published var isGamingModeActive = false
    @Published var isManualOverride: Bool {
        didSet {
            UserDefaults.standard.set(isManualOverride, forKey: kManualOverride)
            if isManualOverride {
                enableGamingMode()
            } else {
                checkStatus()
            }
        }
    }
    
    @Published var inactivityTimeoutSeconds: Int {
        didSet {
            UserDefaults.standard.set(inactivityTimeoutSeconds == 0 ? -1 : inactivityTimeoutSeconds, forKey: kInactivityTimeout)
        }
    }
    
    @Published var rapportdSuspended = false
    @Published var awdlDown = false
    @Published var timerEndDate: Date?
    @Published var showOnboarding = false
    @Published var statusTitle = "Checking..."
    @Published var countdownTitle: String? = nil
    @Published var launchAtLogin = false {
        didSet {
            updateLaunchAtLogin(launchAtLogin)
        }
    }
    
    let targetApp = "Boosteroid"
    let sudoersPath = "/etc/sudoers.d/cloud_optimizer"
    let pkillPath = "/usr/bin/pkill"
    let ifconfigPath = "/sbin/ifconfig"
    
    private let kInactivityTimeout = "inactivityTimeout"
    private let kManualOverride = "manualOverride"
    
    private var checkTimer: Timer?
    private var uiTimer: Timer?
    private var inactivityTimer: Timer?
    
    init() {
        // Load settings
        self.isManualOverride = UserDefaults.standard.bool(forKey: kManualOverride)
        let timeoutVal = UserDefaults.standard.integer(forKey: kInactivityTimeout)
        self.inactivityTimeoutSeconds = timeoutVal == 0 ? 300 : (timeoutVal == -1 ? 0 : timeoutVal)
        
        // Initial state
        let needsOnboarding = !hasSudoersSetup()
        self.showOnboarding = needsOnboarding
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        
        setupObservers()
        startTimers()
        
        if isManualOverride {
            enableGamingMode()
        }
        checkStatus()
        
        if needsOnboarding {
            showOnboardingWindow()
        }
    }
    
    private func setupObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in self.checkStatus() }
        nc.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { _ in self.checkStatus() }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.localizedName == self.targetApp {
                self.inactivityTimer?.invalidate()
                self.inactivityTimer = nil
                self.timerEndDate = nil
                if !self.isManualOverride {
                    self.disableGamingMode()
                }
            }
        }
    }
    
    private func startTimers() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in self.checkStatus() }
        uiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in self.refreshUIStrings() }
    }
    
    @objc func checkStatus() {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let isTargetFrontmost = frontmostApp?.localizedName == targetApp
        
        let runningApps = NSWorkspace.shared.runningApplications
        let isTargetRunning = runningApps.contains(where: { $0.localizedName == targetApp })

        // Physical status check
        let rapportdStatus = shell("ps -axc -o state,command | grep rapportd | grep -v grep").trimmingCharacters(in: .whitespacesAndNewlines)
        let isRapportdSuspendedNow = rapportdStatus.contains("T")
        
        let ifconfigOutput = shell("ifconfig awdl0").lowercased()
        let isAwdlDownNow = !ifconfigOutput.contains("status: active") || ifconfigOutput.contains("inactive")
        
        DispatchQueue.main.async {
            self.rapportdSuspended = isRapportdSuspendedNow
            self.awdlDown = isAwdlDownNow
        }

        let isPhysicallyOptimized = isRapportdSuspendedNow && isAwdlDownNow

        // 1. RECONCILIATION LOGIC
        if isManualOverride {
            enableGamingMode()
        } else if isTargetFrontmost {
            inactivityTimer?.invalidate()
            inactivityTimer = nil
            timerEndDate = nil
            enableGamingMode()
        } else if isTargetRunning {
            if isGamingModeActive {
                if inactivityTimeoutSeconds > 0 && inactivityTimer == nil {
                    startInactivityTimer()
                }
            } else if isPhysicallyOptimized {
                isGamingModeActive = true
                startInactivityTimer()
            }
        } else {
            if isGamingModeActive || isPhysicallyOptimized {
                disableGamingMode()
            }
            inactivityTimer?.invalidate()
            inactivityTimer = nil
            timerEndDate = nil
        }
        
        // 2. ENFORCE PHYSICAL STATE
        if isGamingModeActive {
            if !isAwdlDownNow { _ = shell("sudo \(ifconfigPath) awdl0 down") }
            if !isRapportdSuspendedNow { _ = shell("sudo \(pkillPath) -STOP rapportd") }
        }
    }
    
    func refreshUIStrings() {
        if let endDate = timerEndDate, isGamingModeActive, !isManualOverride {
            let remaining = Int(max(0, endDate.timeIntervalSinceNow))
            if remaining > 0 {
                let mins = remaining / 60
                let secs = remaining % 60
                countdownTitle = String(format: "Restoring in %02d:%02d...", mins, secs)
            } else {
                countdownTitle = nil
            }
        } else {
            countdownTitle = nil
        }
        
        if isManualOverride {
            statusTitle = "Optimized (Manual)"
        } else if isGamingModeActive {
            if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.localizedName == targetApp {
                statusTitle = "Optimized (Active)"
            } else {
                statusTitle = "Grace Period (Timer)"
            }
        } else {
            let runningApps = NSWorkspace.shared.runningApplications
            let isRunning = runningApps.contains(where: { $0.localizedName == targetApp })
            statusTitle = isRunning ? "Ready (Waiting Focus)" : "Inactive (App Closed)"
        }
    }

    func enableGamingMode() {
        guard !isGamingModeActive else { return }
        isGamingModeActive = true
        DispatchQueue.global().async {
            _ = self.shell("sudo \(self.pkillPath) -STOP rapportd")
            _ = self.shell("sudo \(self.ifconfigPath) awdl0 down")
            _ = self.shell("touch /tmp/gamemode_on")
        }
    }
    
    func disableGamingMode() {
        guard isGamingModeActive else { return }
        isGamingModeActive = false
        DispatchQueue.global().async {
            _ = self.shell("sudo \(self.pkillPath) -CONT rapportd")
            _ = self.shell("sudo \(self.ifconfigPath) awdl0 up")
            _ = self.shell("rm -f /tmp/gamemode_on")
        }
    }
    
    func forceRestore() {
        isManualOverride = false
        isGamingModeActive = true 
        disableGamingMode()
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        timerEndDate = nil
    }

    func startInactivityTimer() {
        inactivityTimer?.invalidate()
        let timeout = TimeInterval(inactivityTimeoutSeconds)
        timerEndDate = Date().addingTimeInterval(timeout)
        let t = Timer(timeInterval: timeout, repeats: false) { _ in
            self.disableGamingMode()
            self.timerEndDate = nil
            self.inactivityTimer = nil
        }
        inactivityTimer = t
        RunLoop.main.add(t, forMode: .common)
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

    func performSudoersSetup() {
        let rule = "%admin ALL=(ALL) NOPASSWD: \(pkillPath) -STOP rapportd, \(pkillPath) -CONT rapportd, \(ifconfigPath) awdl0 down, \(ifconfigPath) awdl0 up"
        let script = "do shell script \"mkdir -p /etc/sudoers.d && echo '\(rule)' > \(sudoersPath)\" with administrator privileges"
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if error == nil {
            self.showOnboarding = false
            // Close the onboarding window if it's open
            NSApp.windows.first(where: { $0.title == "Cloud Optimizer Setup" })?.close()
            self.checkStatus()
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        let status = SMAppService.mainApp.status
        if enabled && status != .enabled {
            try? SMAppService.mainApp.register()
        } else if !enabled && status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
    }

    func showOnboardingWindow() {
        DispatchQueue.main.async {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.center()
            window.title = "Cloud Optimizer Setup"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(manager: self))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - SwiftUI Views
struct OnboardingView: View {
    @ObservedObject var manager: OptimizerManager
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Cloud Optimizer")
                .font(.headline)
            
            Text("To ensure the best gaming experience, this app reduces Wi-Fi latency spikes by temporarily suspending background services (like AirPlay/AirDrop and Continuity) while Boosteroid is running.\n\nClick below to enable the optimizer. You will need to enter your Mac password once to authorize these system changes.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Enable Optimizer") {
                manager.performSudoersSetup()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(30)
        .frame(width: 450, height: 300)
    }
}

struct MenuView: View {
    @ObservedObject var manager: OptimizerManager
    
    var body: some View {
        Group {
            Text("Status: \(manager.statusTitle)")
                .disabled(true)
            
            if let countdown = manager.countdownTitle {
                Text(countdown)
                    .disabled(true)
            }
            
            Divider()
            
            Button(manager.isManualOverride ? "Stop Manual Optimization" : "Force Optimization") {
                manager.isManualOverride.toggle()
            }
            .keyboardShortcut("f")
            
            Toggle("Start at Login", isOn: $manager.launchAtLogin)
            
            Menu("Disable inactivity after...") {
                let options = [(60, "1 Minute"), (300, "5 Minutes"), (900, "15 Minutes"), (0, "Never (Always On)")]
                ForEach(options, id: \.0) { sec, title in
                    Button(title) {
                        manager.inactivityTimeoutSeconds = sec
                    }
                    .tag(sec)
                    if manager.inactivityTimeoutSeconds == sec {
                        // SwiftUI Menu handles checkmarks automatically if using Pickers, 
                        // but for simple Buttons we can't easily show the dot without custom views.
                        // However, MenuBarExtra menus behave like standard menus.
                    }
                }
            }
            
            Divider()
            
            Text("rapportd: \(manager.rapportdSuspended ? "🔴 Suspended" : "🟢 Running")")
                .disabled(true)
            Text("awdl0: \(manager.awdlDown ? "🔴 Down" : "🟢 Up")")
                .disabled(true)
            
            Divider()
            
            Button("Restore Services Now") {
                manager.forceRestore()
            }
            
            Button("Refresh Now") {
                manager.checkStatus()
            }
            .keyboardShortcut("r")
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

// MARK: - App Entry Point
@main
struct CloudOptimizerApp: App {
    @StateObject private var manager = OptimizerManager()
    
    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: manager)
        } label: {
            let isActuallyActive = manager.isGamingModeActive || manager.isManualOverride || (manager.rapportdSuspended && manager.awdlDown)
            if isActuallyActive {
                Image(systemName: "gamecontroller.fill")
            } else {
                Image(systemName: "desktopcomputer")
            }
        }
    }
}
