<p align="center">
  <img src="docs/logo.png" width="128" alt="DNS Doctor logo">
</p>

<h1 align="center">DNS Doctor</h1>

<p align="center">
  A lightweight macOS menu bar app that watches your DNS, tells you the moment it breaks,<br>
  and fixes it in one click.
</p>

<p align="center">
  <a href="https://github.com/Fahimefto/dns-doctor/releases/latest"><b>Download</b></a> ·
  <a href="#install">Install</a> ·
  <a href="#using-it">Using it</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#faq">FAQ</a>
</p>

---

## Contents

- [Why DNS Doctor](#why-dns-doctor)
- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [Using it](#using-it)
- [How it works](#how-it-works)
- [What the repairs do](#what-the-repairs-do)
- [Command line](#command-line)
- [Privacy and safety](#privacy-and-safety)
- [Troubleshooting and FAQ](#faq)
- [Uninstall](#uninstall)
- [Build from source](#build-from-source)

## Why DNS Doctor

DNS is how your Mac turns names like `github.com` into addresses it can connect to.
Sometimes it breaks while the network itself is fine. Wi-Fi shows full bars and
apps that connect by address keep working, but every website fails to load.

This happens most often:

- after connecting to or disconnecting from a **VPN** (the VPN can leave its own DNS
  servers behind, or macOS's DNS service gets stuck on stale entries)
- after **waking from sleep** or **switching networks** (home ↔ office ↔ hotspot)
- when a network's **DNS server goes down** while the rest of the connection still works

The usual fix is a Terminal command most people don't remember:

```sh
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

DNS Doctor watches for the problem, shows it in the menu bar, and runs the right fix
for you, including deeper fixes when a cache flush isn't enough.

## Features

- **Status at a glance.** A globe in the menu bar with a green, red or orange dot.
- **Real detection.** It tells "DNS is broken" apart from "no internet at all".
- **Diagnosis.** It checks each DNS server your Mac uses and explains what's wrong.
- **One-click repair** that escalates automatically, from a cache flush up to a full
  DNS reset.
- **Public DNS fallback** (Cloudflare + Google), with one-click restore of your
  original settings.
- **Notifications** when DNS breaks.
- **Open at login**, **copy diagnostics** for support, and a **`--check` command**
  for scripts.
- Tiny and native: written in Swift, under 2 MB, no Dock icon, no background services.

## Requirements

- macOS 13 (Ventura) or newer
- Apple silicon or Intel Mac
- An admin account (to approve repairs, the same as using `sudo`)

## Install

### Option 1: one command (recommended)

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/Fahimefto/dns-doctor/master/install.sh | zsh
```

The script ([install.sh](install.sh)) downloads the latest release, closes any running
copy, copies **DNS Doctor** into `/Applications` and opens it. Run the same command
again at any time to update to the newest version.

### Option 2: download the DMG

1. Download `DNS-Doctor.dmg` from the
   [latest release](https://github.com/Fahimefto/dns-doctor/releases/latest).
2. Open the DMG and drag **DNS Doctor** into **Applications**.
3. Open **DNS Doctor** from Applications.

**First launch warning.** The app isn't notarized by Apple, so the first time you open
a downloaded copy macOS says *"Apple could not verify 'DNS Doctor' is free of
malware."* To allow it (once per Mac), either:

- click **Done**, then go to **System Settings → Privacy & Security**, scroll down
  and click **Open Anyway**, or
- run `xattr -dr com.apple.quarantine "/Applications/DNS Doctor.app"` in Terminal,
  then open the app.

Option 1 skips this step, because files fetched with `curl` aren't flagged by macOS.

### After installing

- The app lives in the **menu bar only**. Look for the globe near the clock.
- Click it and tick **Open at login** so it's always running.
- Allow notifications when asked, so you're alerted as soon as DNS breaks.

## Using it

### The menu bar icon

| Icon | Meaning | What to do |
| --- | --- | --- |
| Globe + 🟢 green dot | DNS is working. | Nothing. |
| Globe + 🔴 red dot | DNS is broken: the internet is reachable, but names don't resolve. | Click the globe → **Repair DNS**. |
| Crossed-out globe + 🟠 orange dot | No internet at all. | Check Wi-Fi, cables or your VPN. |
| Plain globe | Checking (for a moment after launch or a network change). | Wait a second. |

### The panel

Click the globe to open the panel:

- **Status** with a plain-language explanation of what's wrong.
- **Checks**: name lookups for a few well-known sites, plus a connection by IP that
  doesn't use DNS at all.
- **DNS servers in use**: every server your Mac is configured with, and whether each
  one answers.
- A note if any network connection has **manually set DNS servers**.
- **Repair DNS** and a refresh button.
- **More fixes**: Use public DNS / Restore automatic DNS, and Copy diagnostics.
- **Open at login**, **Notify when DNS breaks**, and **Quit**.

### When DNS breaks

1. The dot turns 🔴 red and you get a notification.
2. Click the globe, then **Repair DNS**.
3. Approve the admin prompt with your password or Touch ID.
4. The panel shows progress, then tells you what fixed it. Usually that takes a
   couple of seconds.
5. If it's still broken, open **More fixes → Use public DNS**, or reconnect your
   VPN or network. Use **Restore automatic DNS** to switch back later.

If you need help from someone else, use **More fixes → Copy diagnostics** and paste the
report to them.

## How it works

Every 30 seconds, and about 2 seconds after any network change, DNS Doctor runs three
kinds of checks in parallel:

1. **System lookups.** It resolves `apple.com`, `google.com` and `cloudflare.com`
   through macOS's own resolver, the same path every app uses.
2. **Internet without DNS.** It opens connections straight to `1.1.1.1`, `8.8.8.8`
   and `9.9.9.9` by IP address.
3. **Each DNS server directly.** It asks every configured DNS server for an answer
   with `dig`, bypassing the macOS cache.

From those results:

| Lookups | Internet by IP | Status |
| --- | --- | --- |
| at least one works | any | 🟢 Working |
| all fail | works | 🔴 DNS broken |
| all fail | fails | 🟠 Offline |

Before turning red it re-checks once, so a brief blip doesn't trigger a false alarm.

When DNS is broken, the per-server results tell you why:

- **Some servers still answer** → macOS's DNS service is stuck. A quick repair fixes it.
- **No servers answer** → the DNS servers themselves are dead, often ones a VPN left
  behind. The deeper repair or public DNS fixes it.

## What the repairs do

Every repair asks for permission through the standard macOS admin prompt. Nothing is
installed, nothing keeps running as root, and every change can be undone.

### Repair DNS

**Repair DNS** escalates through two levels and stops as soon as DNS works again.

**Level 1: flush the DNS cache.**

```sh
dscacheutil -flushcache
killall -HUP mDNSResponder
```

It re-checks after about 1.5 seconds. This fixes most cases.

**Level 2: deeper fix.** This runs only if level 1 didn't help:

1. Restarts macOS's DNS service: `killall mDNSResponder mDNSResponderHelper`.
   macOS relaunches it immediately.
2. Resets manually set DNS servers **only if none of them answer** (typically leftovers
   from a VPN) back to automatic: `networksetup -setdnsservers "<service>" empty`.
   DNS servers you set yourself that still work are never touched.
3. Renews the DHCP lease on active connections that use DHCP,
   `ipconfig set <device> DHCP`, so your router hands out fresh DNS servers. The
   connection may drop for a second or two.
4. Flushes the cache again.

It then re-checks every 2 seconds for up to 15 seconds and reports which step fixed it.

### Use public DNS (last resort)

**More fixes → Use public DNS** points every network connection at Cloudflare and
Google:

```sh
networksetup -setdnsservers "<service>" 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4
```

Your previous settings are saved first. **Restore automatic DNS** puts them back
exactly as they were.

> Some company or VPN-only sites only resolve through your network's own DNS. If those
> stop working while public DNS is on, restore your settings once the network is
> healthy again.

## Command line

The same checks are available from Terminal, with no UI:

```sh
"/Applications/DNS Doctor.app/Contents/MacOS/DNSDoctor" --check
```

It prints a diagnostics report and exits with:

| Exit code | Meaning |
| --- | --- |
| `0` | DNS is working |
| `1` | DNS is broken (internet reachable, names don't resolve) |
| `2` | Offline |

Example: `".../DNSDoctor" --check >/dev/null || echo "DNS problem"`.

## Privacy and safety

- **No data collection.** The app has no analytics, no accounts and no servers of
  its own.
- **Network traffic** is limited to the checks described in
  [How it works](#how-it-works).
- **Your password** goes to macOS's own admin prompt. The app never sees or stores it.
- **Nothing changes on its own.** The app only checks until you click a repair
  button.
- **Open source.** Every command it runs is in
  [`DNSRepair.swift`](Sources/DNSDoctor/DNSRepair.swift).

## FAQ

**Why does it ask for my password?**
Flushing the DNS cache and changing DNS settings need admin rights on macOS, the same
as `sudo` in the manual fix.

**Why do I sometimes get two password prompts?**
The first is the quick fix. If DNS was still broken afterwards, the second is for the
deeper fix.

**It says "No internet connection" but I'm online.**
That means even the direct-by-IP connection failed. Usually Wi-Fi just reconnected or
a VPN is still connecting. Wait a few seconds and click refresh. Some networks also
block outside connections, which can cause this.

**Repair says DNS is still broken.**
Your network's DNS servers are probably down. Try **Use public DNS**, or disconnect and
reconnect your VPN or Wi-Fi.

**Does it work with my VPN?**
Yes. It doesn't depend on any particular VPN. It checks DNS the same way regardless of
which VPN or network you use.

**Will it conflict with DNS I set on purpose?**
No. The deeper fix only resets manually set DNS servers that have stopped answering,
and public DNS can always be undone with **Restore automatic DNS**.

**How much battery or CPU does it use?**
Very little. A check is a handful of tiny network requests every 30 seconds.

**Can it fix DNS automatically without me clicking?**
Not yet. Repairs need admin approval each time, so they wait for your click.

## Uninstall

1. If you turned on public DNS, click **Restore automatic DNS** first.
2. Click the globe → **Quit**.
3. Delete `/Applications/DNS Doctor.app`.
4. If you enabled it, remove **DNS Doctor** from
   **System Settings → General → Login Items**.

## Build from source

You need macOS 13 or newer and the Command Line Tools (`xcode-select --install`).
Xcode itself isn't required.

```sh
git clone https://github.com/Fahimefto/dns-doctor.git
cd dns-doctor
scripts/build.sh 1.0.0
```

This builds a universal app (Apple silicon + Intel), generates the icon, signs it
ad-hoc and writes:

- `dist/DNS Doctor.app`
- `dist/DNS-Doctor-1.0.0.dmg` and `dist/DNS-Doctor.dmg`

For a quick debug run, `swift run DNSDoctor` works too. Notifications and Open at
login need the real `.app` bundle.

### Releasing

```sh
scripts/build.sh 1.1.0
gh release create v1.1.0 dist/DNS-Doctor.dmg dist/DNS-Doctor-1.1.0.dmg
```

Always attach the unversioned `DNS-Doctor.dmg`. The installer script downloads that
exact file name from the latest release.

### Project layout

```
Sources/DNSDoctor/
  main.swift             Menu bar item, popover, status icon, --check entry point
  DNSMonitor.swift       Periodic checks, health state, repair flow, notifications
  Probes.swift           System lookups, reach-by-IP, direct DNS server queries
  NetworkServices.swift  Reads per-connection DNS settings via networksetup
  DNSRepair.swift        The privileged fixes (flush, deep fix, public DNS, restore)
  StatusView.swift       The panel UI (SwiftUI)
Resources/Info.plist     App bundle metadata (menu bar only)
scripts/build.sh         Universal build, icon, signing, DMG
scripts/make_icon.swift  Draws the app icon
install.sh               One-line installer
docs/logo.png            Logo
```
