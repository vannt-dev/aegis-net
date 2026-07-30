---
name: run-aegis-net
description: Build, launch, drive and screenshot the AegisNet Flutter app on an Android emulator. Use when asked to run, start, build, install, test, screenshot, or interact with the app, verify a UI change on a real device, or check the launcher icon.
---

# Run AegisNet

AegisNet is a Flutter app over a Rust core (`rust/aegis_core`, via `dart:ffi`) that
runs a local VPN for DNS filtering. The only meaningful way to run it is **on an
Android emulator** — the Windows/Chrome desktop targets that `flutter devices`
lists do not have `VpnService`, so the whole point of the app is missing there.

Everything is driven through one script:

```
.claude/skills/run-aegis-net/driver.mjs
```

**All paths below are relative to the repo root** (`C:\Git\flutter`).
All commands below were run and verified on Windows 11 + Git Bash.

## Prerequisites

Already present on this machine — no installs were needed:

- Flutter SDK on `PATH` (`C:\flutter\bin`)
- Node.js 24 (driver is plain ESM, no npm packages)
- Android SDK platform-tools at `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`
  — **not on `PATH`**; the driver finds it itself
- An AVD named `aegis_test`

Check the AVD exists:

```bash
flutter emulators
```

Expected: `aegis_test • aegis test • Google • android`.

## Run (agent path) — start here

One command does everything from cold:

```bash
node .claude/skills/run-aegis-net/driver.mjs up
```

`up` = boot emulator → build APK if missing → install → `pm clear` → launch →
screenshot to `.claude/skills/run-aegis-net/screenshots/launched.png`.

Verified output:

```
Khoi dong AVD "aegis_test" ...
Da boot xong. Android 14, device emulator-5554
Performing Streamed Install
Success
pm clear: da xoa sach app data (prefs, theme, ngon ngu).
Starting: Intent { cmp=com.aegisnet.app/.MainActivity }
...\screenshots\launched.png (216825 bytes)
```

Individual commands:

```bash
node .claude/skills/run-aegis-net/driver.mjs help
node .claude/skills/run-aegis-net/driver.mjs boot           # idempotent
node .claude/skills/run-aegis-net/driver.mjs build
node .claude/skills/run-aegis-net/driver.mjs install-clean  # install + pm clear
node .claude/skills/run-aegis-net/driver.mjs reset          # pm clear only
node .claude/skills/run-aegis-net/driver.mjs launch
node .claude/skills/run-aegis-net/driver.mjs shot <name>
node .claude/skills/run-aegis-net/driver.mjs tap <x> <y>
node .claude/skills/run-aegis-net/driver.mjs swipe <x1> <y1> <x2> <y2> [ms]
node .claude/skills/run-aegis-net/driver.mjs key KEYCODE_BACK
node .claude/skills/run-aegis-net/driver.mjs logs
node .claude/skills/run-aegis-net/driver.mjs stop
node .claude/skills/run-aegis-net/driver.mjs kill           # shut down emulator
```

**Always look at the screenshot you took.** `shot` writes to
`.claude/skills/run-aegis-net/screenshots/<name>.png`; read that file.

### Verified tap coordinates (screen is 1080x2400)

Flutter draws to one canvas, so there is nothing to query by name — you tap
coordinates. These were all verified by tapping and screenshotting:

| Target | x | y |
|---|---|---|
| Nav: Dashboard | 108 | 2266 |
| Nav: Rules | 324 | 2266 |
| Nav: Logs | 540 | 2266 |
| Nav: Analytics | 756 | 2266 |
| Nav: Settings | 972 | 2266 |
| Power button (Dashboard) | 540 | 562 |
| Settings → language "English" | 177 | 437 |
| Settings → language "Tiếng Việt" | 433 | 437 |
| Settings → accent cyan | 165 | 676 |
| Settings → accent emerald | 414 | 676 |
| Settings → accent purple | 663 | 676 |
| Settings → accent gold | 912 | 676 |

Example — switch to the Emerald theme and look at the dashboard:

```bash
D=.claude/skills/run-aegis-net/driver.mjs
node $D tap 972 2266   # Settings
node $D tap 414 676    # emerald swatch
node $D tap 108 2266   # Dashboard
node $D shot emerald
```

## Test

```bash
flutter test
```

Verified: `00:00 +5: All tests passed!` (the Rust core logs
`Aegis Core Engine Initialized` into the test output — that is normal, not an error).

```bash
flutter analyze
```

Verified: `No issues found!`

## Gotchas

These cost real time. None are guessable from the README.

- **App data survives `adb uninstall`.** `android/app/src/main/AndroidManifest.xml`
  never declares `android:allowBackup`, so Android defaults it to **true** and
  Auto Backup restores `shared_prefs` on reinstall. Verified: after a full
  uninstall + reinstall, `shared_prefs/FlutterSharedPreferences.xml` still
  contained `app_language=vi`. **Use `pm clear`** (what `install-clean` and
  `reset` do) — uninstalling is not enough.

  This matters more than it sounds: a leftover theme preference makes the app
  render emerald when the code default is cyan, which will make you "find" a
  theming bug that does not exist. Always `reset` before judging colours.

- **`uiautomator dump` returns ~50 nodes and zero text.** Flutter renders to a
  single canvas and this app does not enable semantics, so there are no
  per-widget accessibility nodes. You cannot find a button by its label. Drive
  by coordinates, verify by screenshot. (The `ui` command exists mainly to
  confirm this and to read genuine *Android* system dialogs, which do have nodes.)

- **The dashboard shows demo numbers until the VPN starts.** Before tapping the
  power button you see `1420 / 385 / 27.1% / 55.1 MB` — those are placeholders.
  After starting, they drop to real counters (`2 / 0 / 0.0%`). Don't report the
  demo values as real behaviour.

- **`flutter emulators --launch` prints nothing, returns immediately, and exits
  0 even when the emulator never starts.** It does not wait for boot, and
  `sys.boot_completed` returns *empty* for a while before it returns `1` — poll
  for the literal value `1`, not for "no error". The driver does this.

- **Never `boot` right after `kill`.** The new launch collides with the old
  emulator still shutting down; `flutter emulators --launch` then silently does
  nothing and you are left waiting forever. This bit me: `adb wait-for-device`
  blocks with **no timeout and no output**, so the session just hangs. The
  driver now waits for the device to disappear inside `kill`, and bounds the
  wait in `boot` to 90s with an explicit error. If you hit it anyway, wait ~15s
  and re-run `boot`.

- **Use `adb exec-out screencap -p`, never `adb shell screencap -p`.** On
  Windows the `shell` variant mangles the binary stream via newline translation
  and you get a corrupt PNG.

- **`flutter build apk --debug` also compiles the Rust core for 4 Android ABIs.**
  First build is minutes, not seconds. It is not hung.

- **Committing is slow.** The pre-commit hook runs `dart format`,
  `flutter analyze` *and* `cargo check` — expect ~90s per commit, and expect
  `flutter analyze` to re-resolve pub dependencies.

- **Checking the launcher icon: use the app drawer, not the dock.** The Pixel
  launcher draws a light plate behind dock icons, which tints a dark icon and
  makes it look wrong. Swipe up to the drawer and check there. Getting to the
  drawer takes two steps — the first swipe opens it focused in search with the
  keyboard up:

  ```bash
  D=.claude/skills/run-aegis-net/driver.mjs
  node $D key KEYCODE_HOME
  node $D swipe 540 2000 540 900 250
  node $D key KEYCODE_BACK      # dismiss the keyboard
  node $D shot drawer
  ```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Khong tim thay adb` | Set `ADB_PATH` to your `adb.exe`. The driver checks `ADB_PATH`, `%LOCALAPPDATA%\Android\Sdk`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`. |
| `flutter devices` shows only Windows/Chrome/Edge | The emulator is not running. `driver.mjs boot`. Emulators never appear until launched. |
| `boot` hangs, or `Emulator khong xuat hien sau 90s` | You launched too soon after `kill`. Confirm nothing is left with `Get-Process \| Where-Object { $_.ProcessName -like "*qemu*" }`, wait ~15s, re-run `boot`. |
| `Chua co APK` | `driver.mjs build` first. |
| Screenshot is blank/tiny | App has not finished its first frame. `launch` already sleeps 6s; sleep longer and re-`shot`. |
| `ERR_UNSUPPORTED_ESM_URL_SCHEME` when importing a repo module by absolute path | Windows absolute paths need a `file:///C:/...` URL in `import`. |
| `node --test <dir>` fails with `Cannot find module` | Node 24 treats a bare directory as an entry point. Use a glob: `node --test "assets/branding/*.test.mjs"`. |

## Human path

`flutter run -d emulator-5554` gives hot reload and an interactive console.
Not verified in this session — the driver path above is what was used and tested.
