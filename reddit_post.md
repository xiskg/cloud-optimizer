# Reddit Post Suggestion

**Title:** [Release] Cloud Optimizer: Stop Wi-Fi latency spikes/stuttering on macOS while gaming (Open Source)

**Post Text:**

Hello everyone! 🎮

If you game on a Mac, you've probably noticed those annoying periodic lag spikes (ping jumps from 20ms to 200ms+) even on a fast connection. I've spent a lot of time investigating this and it turns out the culprits are **AWDL (AirDrop/AirPlay)** and **rapportd (Continuity)**. These services constantly scan for other Apple devices, which forces your Wi-Fi chip to momentarily drop its connection to the router.

While you probably don't want to disable these features forever, you definitely don't want them active while trying to play on Boosteroid or other cloud services.

I've developed a native macOS utility to solve this: **[Cloud Optimizer](https://github.com/xiskg/cloud-optimizer)** 🚀

**How it works:**
- It's a lightweight Menu Bar app that **automatically** detects when you open Boosteroid.
- It surgically suspends `rapportd` and brings the `awdl0` interface down only while you are gaming.
- As soon as you close the game, everything is restored to normal instantly.
- **100% Open Source** and native (Swift).

I've been testing this for a while and my latency issues are completely gone. No more "stuttering" every 30 seconds!

Check it out here: https://github.com/xiskg/cloud-optimizer

I'd love to hear your feedback! If you use other services like GeForce NOW or Luna, let me know and I can add support for them too.
