# Cloud Optimizer 🎮🚀

**Cloud Optimizer** is a modern macOS utility designed to eliminate Wi-Fi latency spikes and stuttering while using cloud gaming services like **Boosteroid**. Built with **SwiftUI**, it provides a sleek, native experience with a custom popover interface.

## The Problem: macOS Wi-Fi Spikes

On macOS, background services like **AirDrop**, **AirPlay**, and **Sidecar** use a protocol called **AWDL (Apple Wireless Direct Link)**. To keep these services active, the system's Wi-Fi chip periodically scans for other devices. 

During these scans, your Wi-Fi interface is momentarily diverted, causing **ping spikes (50ms to 200ms)** and **packet loss**. For competitive gaming and high-bitrate cloud streaming, this results in visible stuttering and input lag.

Additionally, the `rapportd` daemon (responsible for Continuity features) frequently triggers network activity that can further interfere with a stable gaming connection.

## The Solution

**Cloud Optimizer** provides a smart, automated way to manage these services based on your activity:

1.  **Focus-Based Activation**: Optimization (suspending `rapportd` and bringing `awdl0` down) triggers instantly when your game (Boosteroid) is the frontmost application.
2.  **Custom SwiftUI Popover**: A beautiful, interactive menu bar interface for real-time monitoring and control.
3.  **Smart Inactivity Timer**: If you switch to another app, the optimizer stays active for a grace period (configurable) before restoring services.
4.  **Real-Time Monitoring**: The app checks focus and system state every 2 seconds to ensure optimization is enforced.
5.  **Live Menu Bar Info**: See your optimization status and grace period countdown directly in the menu bar.

## Features

-   **Modern Interface**: Status cards with vibrant indicators and stylized controls.
-   **Manual Override**: Force optimization "on" regardless of game focus.
-   **Configurable Grace Period**: Choose how long the optimizer stays active in the background.
-   **Start at Login**: Native support for macOS 13+ (Ventura and newer).
-   **Zero-Config Onboarding**: A beautiful setup window guides you through the one-time authorization.

## Installation

### Option 1: Homebrew (Recommended)
The easiest way to install and keep Cloud Optimizer updated:

```bash
brew tap xiskg/tap
brew install --cask cloud-optimizer --no-quarantine
```
*The `--no-quarantine` flag is recommended to avoid macOS blocking the app since it's not signed with an Apple Developer certificate.*

### Option 2: Pre-built Binary
1. Download the latest `CloudOptimizer_v1.2.0.zip` from the [Releases](https://github.com/xiskg/cloud-optimizer/releases) page.
2. Extract and move `CloudOptimizer.app` to your `/Applications` folder.
3. Open it and follow the one-time onboarding.

### Option 3: Building from Source
Ensure you have Swift installed (included with Xcode) and are running **macOS 13.0+**:

1.  Clone this repository:
    ```bash
    git clone https://github.com/xiskg/cloud-optimizer.git
    cd cloud-optimizer
    ```
2.  Run the build script:
    ```bash
    ./build.sh
    ```
3.  The `CloudOptimizer.app` bundle will be created in the root directory.

## 🛠 Troubleshooting

### "App is damaged" or "Cannot be opened"
Because this app is not signed with an official Apple Developer certificate ($99/year), macOS Gatekeeper might flag it as "damaged" or "corrupted" when downloaded manually.

To fix this, open your Terminal and run:
```bash
xattr -d com.apple.quarantine /Applications/CloudOptimizer.app
```

### Why does it need sudo?
The app uses `pkill -STOP` and `ifconfig awdl0 down`. These are system-level commands that require root privileges. The onboarding process creates a surgical sudoers rule at `/etc/sudoers.d/cloud_optimizer` so the app can run these *specific* commands without asking for your password every time.

## Technical Details

The app configures a granular `sudoers` rule in `/etc/sudoers.d/cloud_optimizer` to allow running specific commands without a password:
- `/usr/bin/pkill -STOP rapportd`
- `/usr/bin/pkill -CONT rapportd`
- `/sbin/ifconfig awdl0 down`
- `/sbin/ifconfig awdl0 up`

This is the safest way to grant the app only the specific privileges it needs to optimize your network.

---
*Created by [xiskg](https://github.com/xiskg)*
