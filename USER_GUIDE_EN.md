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
9. [iOS System-Wide Encrypted DNS (.mobileconfig) Profile Setup](#9-ios-system-wide-encrypted-dns-mobileconfig-profile-setup)
10. [App Lock (PIN)](#10-app-lock-pin)
11. [Home-Screen Widget (Android)](#11-home-screen-widget-android)
12. [Networks to Protect (Android)](#12-networks-to-protect-android)

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
* On Android, protection comes back on time even if the app is closed during the pause; the notification says until when it is paused.
* On Android you can also pause from the notification: pull down the shade and tap **Pause 5 min** under *AegisNet Shield*. The notification then counts down the time left and offers **Resume** to turn protection back on early. The pause ends on time even if the app is closed.

---

## 3. Managing Rules & Filter Lists
Switch to the **Rules** tab on the bottom navigation bar:
* **Preset Filter Lists**: Toggle standard ad-blocking filters (AdGuard Mobile, EasyList DNS, StevenBlack Hosts, NoCoin).
* **Sync Button 🔄**: Tap the refresh icon in the app bar to download and update the latest active filter rules from the internet.
* **Import a list from a file (Android)**: Tap **IMPORT FILE** and pick a hosts file (`0.0.0.0 ads.example.com`) or a text file with one domain per line. AegisNet checks every line, drops repeated names and lines that are not a domain to block (such as `localhost` or a hosts line pointing at a real address), and tells you how many domains it added. The list appears with the others and blocks right away. It is kept only on this phone: a sync never downloads it, and exporting your settings does not carry the file. Tap the bin icon next to it to remove it.
* **Custom Whitelist & Blacklist**:
  * Type a domain (e.g. `mybank.com`) and tap **ALLOW** to whitelist it.
  * Type a domain (e.g. `bad-site.com`) and tap **BLOCK** to blacklist it.

---

## 4. Live DNS Query Logs
Switch to the **Logs** tab:
* Monitor all real-time DNS queries made by applications on your device.
* **`BLOCKED` (Red)**: Ad networks, trackers, or malicious domains blocked by AegisNet.
* **`ALLOWED` (Green)**: Safe domains passed through to upstream DNS.
* **Allow or block from the log**: Tap any entry to always allow or always block that domain, take it off a list it is already on, or copy the name. The change applies to the next query; a domain is only ever on one of the two lists.
* **Allow for a while**: Tap an entry and pick 15 min, 1 hour or 1 day. The domain is blocked again on time, even if the app is closed; tap the entry again to see until when, or to block it again now. A timed allow never lands on your allow list.
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
* **Custom resolver**: Type a resolver into the field under the provider list and press Done. Use an `https://` DoH URL (`https://dns.nextdns.io/abc123`) or a DNS-over-TLS target (`tls://1.1.1.1`). When the DoT host is an IP address whose certificate is issued for a name, add the name after `#`: `tls://94.140.14.14#dns.adguard-dns.com`. A DNS-over-QUIC resolver is written the same way under `quic://`: `quic://94.140.14.14#dns.adguard-dns.com`. It needs UDP port 853 to be open on your network; where it is not, lookups fail until you choose another resolver. Prefer an address over a hostname: with protection on, the hostname of the resolver would have to be resolved through the resolver itself.

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

---

## 10. App Lock (PIN)
So that someone else holding the phone cannot turn protection off or loosen the filters:
* In the **Settings** tab, turn on **App lock (PIN)**, choose a 4-6 digit PIN and enter it again.
* While it is on, AegisNet asks for the PIN when it opens and when you come back after more than 30 seconds away.
* The PIN is also asked before anything that weakens protection: turning it off or pausing it, allowing a domain, switching off a filter or a blocking option, letting an app skip the VPN, or restoring a backup. A PIN entered within the last minute is not asked again.
* After 5 wrong tries in a row you wait 30 seconds; each further wrong try doubles the wait, up to 15 minutes.
* With the lock on, the **Quick Settings** tile and the home-screen widget open the app instead of turning protection off, and the notification has no **Pause 5 min** button.
* **CHANGE PIN** and turning the lock off both need the current PIN.
* Only a salted PBKDF2 hash of the PIN is stored, never the PIN itself.
* Forgot the PIN? Clear the app data in Android settings (this also erases your rules and lists).
* The lock cannot stop someone from disconnecting the VPN in Android's VPN settings, uninstalling the app or force-stopping it.

---

## 11. Home-Screen Widget (Android)
* Long-press an empty spot on the home screen, choose **Widgets**, find **AegisNet** and drag the **AegisNet Shield** widget onto the screen.
* It shows whether protection is on, paused (and until when) or off, and how many lookups were blocked today.
* Tap it to turn protection off, to end a pause, or to turn protection on. The first time, or after another VPN app took over, it opens AegisNet instead so you can approve the VPN.
* The blocked count comes from the app: it updates while AegisNet is open (about every 30 seconds) and otherwise shows the number from the last time the app was open that day. On a new day it says to open the app until the app has counted again.

---

## 12. Networks to Protect (Android)
* In **Settings**, under **Networks to protect**, choose **All networks** (the default), **Wi-Fi only** or **Mobile data only**.
* On a network left out, AegisNet stays on but does not filter, and the Dashboard says *Not filtering on this network*. Filtering comes back by itself when the phone moves to a network that is in, even with the app closed.
* Turn on **Skip these Wi-Fi networks** to name Wi-Fi networks where protection does not apply, for example a home network that already filters. Type a name exactly (case matters) or tap **ADD CURRENT WI-FI**.
* Android shows Wi-Fi names only to apps with location access, so turning the list on asks for it. AegisNet uses it only to read the name of the Wi-Fi network you are on. Without it the list is not used and the Wi-Fi / mobile data choice still applies.
* With location allowed only while the app is in use, a network's name is read when you open AegisNet on it. Choose **Allow all the time** for the list to work with the app closed. Location must also be turned on in the phone's settings.
* With the app lock on, leaving a network out asks for the PIN.
