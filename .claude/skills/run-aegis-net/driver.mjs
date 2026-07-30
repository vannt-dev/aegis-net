#!/usr/bin/env node
// Driver for running AegisNet on an Android emulator from an agent session.
//
//   node .claude/skills/run-aegis-net/driver.mjs <command> [args]
//
// Every command is synchronous and prints what it did. Run `help` for the list.
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..', '..', '..');
const SHOTS = join(HERE, 'screenshots');

const PKG = 'com.aegisnet.app';
const ACTIVITY = `${PKG}/.MainActivity`;
const APK = join(REPO, 'build', 'app', 'outputs', 'flutter-apk', 'app-debug.apk');
const AVD = 'aegis_test';

// ---------------------------------------------------------------- tool paths

function findAdb() {
  if (process.env.ADB_PATH && existsSync(process.env.ADB_PATH)) return process.env.ADB_PATH;
  const home = process.env.LOCALAPPDATA || process.env.HOME || '';
  const candidates = [
    join(home, 'Android', 'Sdk', 'platform-tools', 'adb.exe'),
    join(process.env.ANDROID_HOME || '', 'platform-tools', 'adb.exe'),
    join(process.env.ANDROID_SDK_ROOT || '', 'platform-tools', 'adb.exe'),
    '/usr/bin/adb',
  ];
  for (const c of candidates) if (c && existsSync(c)) return c;
  throw new Error(
    'Khong tim thay adb. Dat bien moi truong ADB_PATH tro toi adb.exe.\n' +
      'Tren may nay no thuong o: %LOCALAPPDATA%\\Android\\Sdk\\platform-tools\\adb.exe',
  );
}

const ADB = findAdb();

function adb(args, opts = {}) {
  const r = spawnSync(ADB, args, { encoding: 'utf8', ...opts });
  if (r.error) throw r.error;
  return (r.stdout || '').trim();
}

function adbOk(args) {
  const out = adb(args);
  return out;
}

// ------------------------------------------------------------------ commands

function devices() {
  const out = adb(['devices']);
  const lines = out.split('\n').slice(1).filter((l) => l.trim() && l.includes('device'));
  return lines.map((l) => l.split(/\s+/)[0]);
}

function boot() {
  if (devices().length > 0) {
    console.log(`Emulator da chay: ${devices().join(', ')}`);
    return;
  }
  console.log(`Khoi dong AVD "${AVD}" ...`);
  // `flutter emulators --launch` tra ve ngay lap tuc va IM LANG — khong in gi,
  // khong doi boot xong, va van tra ve 0 ngay ca khi emulator khong len duoc.
  const r = spawnSync('flutter', ['emulators', '--launch', AVD], {
    cwd: REPO,
    encoding: 'utf8',
    shell: true,
  });
  if (r.status !== 0) {
    throw new Error(`flutter emulators --launch that bai:\n${r.stderr || r.stdout}`);
  }

  // KHONG dung `adb wait-for-device`: no cho VO HAN va khong bao gi neu
  // emulator khong bao gio xuat hien (da bi dinh dung loi nay). Poll co han.
  const appear = Date.now() + 90 * 1000;
  while (devices().length === 0) {
    if (Date.now() > appear) {
      throw new Error(
        'Emulator khong xuat hien sau 90s.\n' +
          'Nguyen nhan hay gap nhat: vua goi "kill" xong da goi "boot" ngay —\n' +
          'lan khoi dong moi dua vao tien trinh cu dang tat. Doi ~15s roi thu lai.',
      );
    }
    sleep(3);
  }

  // sys.boot_completed tra ve rong mot luc truoc khi thanh "1". Phai poll.
  const deadline = Date.now() + 5 * 60 * 1000;
  while (Date.now() < deadline) {
    const b = adb(['shell', 'getprop', 'sys.boot_completed']).replace(/\r/g, '');
    if (b === '1') {
      const rel = adb(['shell', 'getprop', 'ro.build.version.release']).replace(/\r/g, '');
      console.log(`Da boot xong. Android ${rel}, device ${devices()[0]}`);
      return;
    }
    sleep(3);
  }
  throw new Error('Emulator khong boot xong trong 5 phut.');
}

function build() {
  console.log('flutter build apk --debug (bien dich ca Rust core cho 4 ABI, cho vai phut) ...');
  const r = spawnSync('flutter', ['build', 'apk', '--debug'], {
    cwd: REPO,
    stdio: 'inherit',
    shell: true,
  });
  if (r.status !== 0) throw new Error('Build that bai.');
  console.log(`APK: ${APK}`);
}

function install({ clean = false } = {}) {
  if (!existsSync(APK)) throw new Error(`Chua co APK: ${APK}\nChay "build" truoc.`);
  console.log(adbOk(['install', '-r', APK]));
  if (clean) {
    // `adb install -r` GIU NGUYEN app data, va `adb uninstall` cung KHONG du:
    // AndroidManifest khong khai bao android:allowBackup nen Android mac dinh
    // bat Auto Backup, va prefs duoc KHOI PHUC LAI sau khi cai lai. Da kiem
    // chung: sau uninstall + install, shared_prefs van con "app_language=vi".
    // `pm clear` la cach duy nhat chac chan xoa sach.
    adb(['shell', 'pm', 'clear', PKG]);
    console.log('pm clear: da xoa sach app data (prefs, theme, ngon ngu).');
  }
}

function launch() {
  console.log(adbOk(['shell', 'am', 'start', '-n', ACTIVITY]));
  sleep(6);
}

function stop() {
  adb(['shell', 'am', 'force-stop', PKG]);
  console.log(`Da dung ${PKG}`);
}

// Sleep dong bo that su: Atomics.wait chan luong chinh, khong can async/await.
function sleep(sec) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, sec * 1000);
}

function shot(name = 'shot') {
  mkdirSync(SHOTS, { recursive: true });
  const out = join(SHOTS, `${name}.png`);
  // exec-out giu nguyen byte nhi phan; `adb shell screencap` se lam hong file
  // vi chuyen doi xuong dong tren Windows.
  const r = spawnSync(ADB, ['exec-out', 'screencap', '-p'], { maxBuffer: 64 * 1024 * 1024 });
  if (r.error) throw r.error;
  if (!r.stdout || r.stdout.length < 1000) throw new Error('Screencap tra ve rong.');
  writeFileSync(out, r.stdout);
  console.log(`${out} (${r.stdout.length} bytes)`);
  return out;
}

function tap(x, y) {
  adb(['shell', 'input', 'tap', String(x), String(y)]);
  console.log(`tap ${x} ${y}`);
  sleep(2);
}

function swipe(x1, y1, x2, y2, ms = 300) {
  adb(['shell', 'input', 'swipe', String(x1), String(y1), String(x2), String(y2), String(ms)]);
  console.log(`swipe ${x1},${y1} -> ${x2},${y2}`);
  sleep(2);
}

function key(code) {
  adb(['shell', 'input', 'keyevent', code]);
  console.log(`key ${code}`);
  sleep(1);
}

function logs() {
  // Flutter ghi qua tag "flutter"; loi native Android qua AndroidRuntime.
  const out = adb(['logcat', '-d', '-t', '200', '-s', 'flutter:V', 'AndroidRuntime:E', 'AegisNet:V']);
  console.log(out || '(khong co log)');
}

function ui() {
  // AegisNet la app Flutter: Flutter ve len mot Canvas duy nhat, nen cay
  // uiautomator KHONG co node cho tung nut. Lenh nay chu yeu de xac nhan
  // dieu do, va de doc cac dialog cua he thong (vi du xin quyen VPN) —
  // nhung dialog do LA view Android that va co node day du.
  adb(['shell', 'uiautomator', 'dump', '/sdcard/ui.xml']);
  const xml = adb(['shell', 'cat', '/sdcard/ui.xml']);
  const nodes = (xml.match(/<node /g) || []).length;
  console.log(`${nodes} node trong cay uiautomator`);
  const texts = [...xml.matchAll(/text="([^"]+)"/g)].map((m) => m[1]).filter(Boolean);
  console.log('text:', JSON.stringify([...new Set(texts)].slice(0, 40)));
}

function kill() {
  adb(['emu', 'kill']);
  // Doi cho tien trinh tat han. Goi "boot" ngay sau "kill" se dua vao emulator
  // dang shutdown va lan khoi dong moi im lang khong len.
  const deadline = Date.now() + 60 * 1000;
  while (devices().length > 0 && Date.now() < deadline) sleep(2);
  sleep(5);
  console.log('Da tat emulator.');
}

function shots() {
  if (!existsSync(SHOTS)) return console.log('(chua co screenshot nao)');
  for (const f of readdirSync(SHOTS)) console.log(join(SHOTS, f));
}

function help() {
  console.log(`Lenh:
  boot                 khoi dong AVD "${AVD}" va doi boot xong (idempotent)
  build                flutter build apk --debug
  install              cai APK, GIU app data
  install-clean        cai APK roi "pm clear" -> state sach that su
  reset                "pm clear" ma khong cai lai
  launch               mo ${ACTIVITY}
  stop                 force-stop app
  shot <ten>           chup man hinh vao ${SHOTS}
  shots                liet ke screenshot da chup
  tap <x> <y>          cham
  swipe <x1> <y1> <x2> <y2> [ms]
  key <KEYCODE>        vi du KEYCODE_BACK, KEYCODE_HOME
  ui                   dump cay uiautomator (xem ghi chu ve Flutter)
  logs                 200 dong logcat cuoi cua flutter/AndroidRuntime
  kill                 tat emulator
  up                   boot + build + install-clean + launch + shot "launched"

Man hinh emulator: 1080x2400.
adb dang dung: ${ADB}`);
}

function up() {
  boot();
  if (!existsSync(APK)) build();
  install({ clean: true });
  launch();
  shot('launched');
}

// ---------------------------------------------------------------------- main

const [cmd, ...args] = process.argv.slice(2);
const table = {
  boot,
  build,
  install: () => install({ clean: false }),
  'install-clean': () => install({ clean: true }),
  reset: () => {
    adb(['shell', 'pm', 'clear', PKG]);
    console.log('pm clear: da xoa sach app data.');
  },
  launch,
  stop,
  shot: () => shot(args[0]),
  shots,
  tap: () => tap(+args[0], +args[1]),
  swipe: () => swipe(+args[0], +args[1], +args[2], +args[3], args[4] ? +args[4] : 300),
  key: () => key(args[0]),
  ui,
  logs,
  kill,
  up,
  help,
};

if (!cmd || !table[cmd]) {
  help();
  process.exit(cmd ? 1 : 0);
}
table[cmd]();
