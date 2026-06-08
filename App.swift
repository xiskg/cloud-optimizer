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
        self.isManualOverride = UserDefaults.standard.bool(forKey: kManualOverride)
        let timeoutVal = UserDefaults.standard.integer(forKey: kInactivityTimeout)
        self.inactivityTimeoutSeconds = timeoutVal == 0 ? 300 : (timeoutVal == -1 ? 0 : timeoutVal)
        
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

        let rapportdStatus = shell("ps -axc -o state,command | grep rapportd | grep -v grep").trimmingCharacters(in: .whitespacesAndNewlines)
        let isRapportdSuspendedNow = rapportdStatus.contains("T")
        let ifconfigOutput = shell("ifconfig awdl0").lowercased()
        let isAwdlDownNow = !ifconfigOutput.contains("status: active") || ifconfigOutput.contains("inactive")
        
        DispatchQueue.main.async {
            self.rapportdSuspended = isRapportdSuspendedNow
            self.awdlDown = isAwdlDownNow
        }

        let isPhysicallyOptimized = isRapportdSuspendedNow && isAwdlDownNow

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
                countdownTitle = String(format: "%02d:%02d", mins, secs)
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
                statusTitle = "Grace Period"
            }
        } else {
            let runningApps = NSWorkspace.shared.runningApplications
            let isRunning = runningApps.contains(where: { $0.localizedName == targetApp })
            statusTitle = isRunning ? "Ready" : "Inactive"
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
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
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

// MARK: - Components
struct StatusCard: View {
    let title: String
    let icon: String
    let isActive: Bool
    let activeText: String
    let inactiveText: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isActive ? .white : .secondary)
                .frame(width: 28, height: 28)
                .background(isActive ? Color.orange.opacity(0.8) : Color.gray.opacity(0.1))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(isActive ? activeText : inactiveText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isActive ? .primary : .secondary)
            }
            Spacer()
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .shadow(color: (isActive ? Color.green : Color.red).opacity(0.5), radius: 2)
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

struct CustomToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Toggle("", isOn: $isOn).labelsHidden()
                    .scaleEffect(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main Popover View
struct CustomPopoverView: View {
    @ObservedObject var manager: OptimizerManager
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.statusTitle)
                        .font(.system(size: 16, weight: .bold))
                    if let countdown = manager.countdownTitle {
                        Text("Restoring in \(countdown)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    } else {
                        Text("Monitoring Boosteroid")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: manager.isGamingModeActive || manager.isManualOverride ? "bolt.shield.fill" : "bolt.shield")
                    .font(.system(size: 24))
                    .foregroundColor(manager.isGamingModeActive || manager.isManualOverride ? .orange : .secondary.opacity(0.5))
            }
            .padding(.horizontal, 4)
            
            // Status Grid
            VStack(spacing: 8) {
                StatusCard(title: "Continuity Service", icon: "app.connected.to.app.below.fill", isActive: manager.rapportdSuspended, activeText: "Suspended", inactiveText: "Running")
                StatusCard(title: "Wireless Link", icon: "wifi.circle.fill", isActive: manager.awdlDown, activeText: "Optimized", inactiveText: "Active")
            }
            
            Divider().opacity(0.5)
            
            // Controls
            VStack(spacing: 4) {
                CustomToggle(title: "Force Optimization", icon: "hand.tap.fill", isOn: $manager.isManualOverride)
                CustomToggle(title: "Start at Login", icon: "power", isOn: $manager.launchAtLogin)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "timer")
                            .frame(width: 20)
                        Text("Grace Period")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    Picker("", selection: $manager.inactivityTimeoutSeconds) {
                        Text("1m").tag(60)
                        Text("5m").tag(300)
                        Text("15m").tag(900)
                        Text("∞").tag(0)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
            }
            
            Divider().opacity(0.5)
            
            // Footer Actions
            HStack(spacing: 12) {
                Button(action: { manager.forceRestore() }) {
                    Label("Restore", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }.buttonStyle(.plain)
                
                Button(action: { manager.checkStatus() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }.buttonStyle(.plain)
                
                Spacer()
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(6)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow))
    }
}

// MARK: - Helper Views
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct OnboardingView: View {
    @ObservedObject var manager: OptimizerManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
                .padding(.top, 10)
            
            Text("Ready to Optimize?")
                .font(.title2).bold()
            
            Text("To eliminate ping spikes, I need permission to temporarily pause AirDrop and Continuity services while you game.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("No password prompts while gaming")
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Automatic service restoration")
                }
            }
            .font(.subheadline)
            
            Spacer()
            
            Button(action: { manager.performSudoersSetup() }) {
                Text("Authorize & Start")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
        }
        .padding(30)
        .frame(width: 450, height: 400)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
    }
}

// MARK: - App Entry Point
@main
struct CloudOptimizerApp: App {
    @StateObject private var manager = OptimizerManager()
    
    var body: some Scene {
        MenuBarExtra {
            CustomPopoverView(manager: manager)
        } label: {
            let isActuallyActive = manager.isGamingModeActive || manager.isManualOverride || (manager.rapportdSuspended && manager.awdlDown)
            HStack(spacing: 2) {
                Image(systemName: isActuallyActive ? "bolt.shield.fill" : "bolt.shield")
                if let countdown = manager.countdownTitle {
                    Text(countdown).font(.system(size: 10, weight: .bold))
                }
            }
        }
        .menuBarExtraStyle(.window) // The MAGIC part for custom UI
    }
}
