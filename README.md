# Cloud Optimizer 🎮🚀

**Cloud Optimizer** is a lightweight macOS utility designed to eliminate Wi-Fi latency spikes and stuttering while using cloud gaming services like **Boosteroid**, **GeForce NOW**, and **Xbox Cloud Gaming**.

## The Problem: macOS Wi-Fi Spikes

On macOS, background services like **AirDrop**, **AirPlay**, and **Sidecar** use a protocol called **AWDL (Apple Wireless Direct Link)**. To keep these services active, the system's Wi-Fi chip periodically scans for other devices. 

During these scans, your Wi-Fi interface is momentarily diverted, causing **ping spikes (50ms to 200ms)** and **packet loss**. For competitive gaming and high-bitrate cloud streaming, this results in visible stuttering and input lag.

Additionally, the `rapportd` daemon (responsible for Continuity features) frequently triggers network activity that can further interfere with a stable gaming connection.

## The Solution

**Cloud Optimizer** automatically monitors when you are gaming and takes surgical action:

1.  **Smart Monitoring**: It watches for the launch of your gaming app (hardcoded for Boosteroid, but extensible).
2.  **Service Suspension**: It suspends `rapportd` (using the `STOP` signal) and brings the `awdl0` interface `down`.
3.  **Automatic Enforcement**: It ensures these services stay disabled as long as you are gaming, as macOS often tries to re-enable them.
4.  **Instant Recovery**: As soon as you close your game, it resumes `rapportd` and brings `awdl0` back `up`, restoring all macOS features immediately.

## Features

-   **Zero-Config Onboarding**: A friendly window explains permissions and sets up the system for you.
-   **Passwordless Operation**: After a one-time setup, the app runs privileged commands silently without prompting for your password every time.
-   **Native Experience**: A lightweight Menu Bar app with real-time status icons.
-   **Privacy Focused**: No data collection, no external servers. Just a simple Swift tool.

## Installation

### Pre-built Version
1.  Download the latest `CloudOptimizer.app` from the [Releases](https://github.com/YOUR_USERNAME/cloud-optimizer/releases) section.
2.  Move it to your `/Applications` folder.
3.  Open it, follow the onboarding instructions, and enter your password once to authorize the optimizer.

### Building from Source
If you prefer to build it yourself, ensure you have Swift installed (included with Xcode):

1.  Clone this repository:
    ```bash
    git clone https://github.com/YOUR_USERNAME/cloud-optimizer.git
    cd cloud-optimizer
    ```
2.  Run the build script:
    ```bash
    ./build.sh
    ```
3.  The `CloudOptimizer.app` bundle will be created in the root directory.

## Technical Details

The app configures a granular `sudoers` rule in `/etc/sudoers.d/cloud_optimizer` to allow running specific commands without a password:
- `/usr/bin/pkill -STOP rapportd`
- `/usr/bin/pkill -CONT rapportd`
- `/sbin/ifconfig awdl0 down`
- `/sbin/ifconfig awdl0 up`

This is the safest way to grant the app only the specific privileges it needs to optimize your network.

---
*Created by [xiskg](https://github.com/xiskg)*
