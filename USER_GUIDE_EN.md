# 📖 AegisNet Application User Guide

**AegisNet** is a high-performance system-wide DNS privacy guard & ad-blocking application built with **Flutter** and powered by an ultra-fast **Rust Core Engine**.

> **Platform availability:** system-wide DNS filtering is functional on
> **Android** (verified). **iOS** is still in progress and currently runs the UI
> only. On any platform without the native engine, the app runs a pure-Dart
> simulation so the interface stays fully usable. See
> [CHANGELOG.md](CHANGELOG.md) for details.

---

## 📋 Table of Contents
1. [Starting Protection & Local VPN](#1-starting-protection--local-vpn)
2. [Quick Protection Pause](#2-quick-protection-pause)
3. [Managing Rules & Filter Lists](#3-managing-rules--filter-lists)
4. [Live DNS Query Logs](#4-live-dns-query-logs)
5. [Analytics & Reports](#5-analytics--reports)
6. [App-by-App Split Tunneling](#6-app-by-app-split-tunneling)
7. [DNS Speed Test & Cyberpunk Themes](#7-dns-speed-test--cyberpunk-themes)
8. [Export & Import Configuration](#8-export--import-configuration)

---

## 1. Starting Protection & Local VPN
* Launch the **AegisNet** app.
* On the **Dashboard**, tap the large **Neon Power Button** in the center.
* Once the app status badge changes to **`PROTECTED`** and the button glows, all DNS requests on your device are actively filtered and protected.

---

## 2. Quick Protection Pause
If you need to access a website or service that is temporarily blocked:
* Under the power switch on the Dashboard, tap one of the quick pause chips:
  * **5m** (Pause for 5 minutes)
  * **15m** (Pause for 15 minutes)
  * **1h** (Pause for 1 hour)
* While paused, a countdown timer will display. Tap **`RESUME NOW`** to immediately re-enable protection.

---

## 3. Managing Rules & Filter Lists
Switch to the **Rules** tab on the bottom navigation bar:
* **Preset Filter Lists**: Toggle standard ad-blocking filters (AdGuard Mobile, EasyList DNS, StevenBlack Hosts, NoCoin).
* **Sync Button 🔄**: Tap the refresh icon in the app bar to download and update the latest active filter rules from the internet.
* **Custom Whitelist & Blacklist**:
  * Type a domain (e.g. `mybank.com`) and tap **ALLOW** to whitelist it.
  * Type a domain (e.g. `bad-site.com`) and tap **BLOCK** to blacklist it.

---

## 4. Live DNS Query Logs
Switch to the **Logs** tab:
* Monitor all real-time DNS queries made by applications on your device.
* **`BLOCKED` (Red)**: Ad networks, trackers, or malicious domains blocked by AegisNet.
* **`ALLOWED` (Green)**: Safe domains passed through to upstream DNS.
* Use the search bar at the top to filter specific domains.

---

## 5. Analytics & Reports
Switch to the **Analytics** tab:
* View the **Top 5 Most Blocked Ad Networks** (e.g. `doubleclick.net`, `graph.facebook.com`).
* Inspect the hourly query distribution chart.

---

## 6. App-by-App Split Tunneling
Switch to the **Settings** tab:
* Under **App-by-App Split Tunneling**, enter the Package Name of an app (e.g., `com.zing.zalo` or `com.vietcombank.mobile`) and tap **ADD**.
* Selected apps will bypass Aegis Local VPN and connect directly to the internet.

---

## 7. DNS Speed Test & Cyberpunk Themes
Switch to the **Settings** tab:
* **Cyberpunk Neon Themes**: Choose from 4 vibrant accent themes (Neon Cyan, Emerald Green, Electric Purple, Sunset Gold).
* **DNS Speed Test**: Tap the **`SPEED TEST`** button next to Upstream Resolver. AegisNet will measure latency ($ms$) across Cloudflare, Google, AdGuard, and Quad9, automatically tagging the **`FASTEST`** provider.

---

## 8. Export & Import Configuration
* Under **Export / Import Configuration** in the **Settings** tab:
* Tap **`EXPORT JSON`** to export Whitelists, Blacklists, bypass apps, and upstream DNS preferences into a backup JSON string.

---

## 9. iOS System-Wide Encrypted DNS (.mobileconfig) Profile Setup
For iPhone & iPad users:
* Navigate to the **Settings** tab.
* Under **iOS Encrypted DNS Profile**, tap **`Install iOS Encrypted DNS Profile`**.
* AegisNet will generate an Apple Encrypted DNS (`.mobileconfig`) payload and open Safari.
* When iOS prompts **"Profile Downloaded"**, open the iPhone **Settings app** ➔ tap **Profile Downloaded** ➔ tap **Install**.
* System-wide Encrypted DNS protection (DoH) will be active across Wi-Fi & Cellular networks without requiring a $99/yr Apple Developer Account!
