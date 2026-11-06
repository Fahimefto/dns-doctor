<p align="center">
  <img src="docs/logo.png" width="128" alt="DNS Doctor logo">
</p>

<h1 align="center">DNS Doctor</h1>

<p align="center">
  Fixes the "connected, but no websites load" problem on your Mac in one click.
</p>

---

Sometimes your Mac says it's online but websites won't open. This often happens after
you turn a VPN on or off, wake your Mac from sleep, or switch Wi-Fi networks.

DNS Doctor sits in your menu bar, notices when this happens, and fixes it for you.

## Install

Open **Terminal**, paste this line and press Return:

```sh
curl -fsSL https://raw.githubusercontent.com/Fahimefto/dns-doctor/master/install.sh | zsh
```

That's it. A globe appears in your menu bar, near the clock. Run the same line again
any time to update.

<details>
<summary>Prefer to download it yourself?</summary>

1. Download **DNS-Doctor.dmg** from the
   [latest release](https://github.com/Fahimefto/dns-doctor/releases/latest).
2. Open it and drag **DNS Doctor** into **Applications**.
3. Open the app. If your Mac says it can't verify the app, click **Done**, then go to
   **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
   You only need to do this once.

</details>

Works on macOS 13 or newer, on any Mac.

## Using it

The globe in your menu bar shows how things are:

| You see | It means |
| --- | --- |
| 🟢 Green dot | Everything is working. |
| 🔴 Red dot | You're online, but websites won't load. Time to fix it. |
| 🟠 Orange dot | You're not connected to the internet at all. Check your Wi-Fi or VPN. |

**When the dot turns red:**

1. Click the globe.
2. Click **Repair DNS**.
3. Enter your Mac password (or use Touch ID).

The app fixes the problem and tells you when it's done. If websites still don't load,
click **More fixes → Use public DNS**, or turn your VPN off and on again.

**Tips:**

- Tick **Open at login** so it's always running.
- Allow notifications so you hear about problems right away.
- If you need help, click **More fixes → Copy diagnostics** and send the copied text
  to whoever is helping you.

## What "Repair DNS" does

It tries the gentlest fix first and only goes further if needed:

1. **Quick fix.** It clears the website addresses your Mac has saved. This solves
   most cases.
2. **Deeper fix.** It restarts the part of macOS that looks up websites, removes
   leftover settings a VPN may have left behind, and gets fresh settings from your
   Wi-Fi router. Your connection may drop for a second.

**Use public DNS** is a last resort. It tells your Mac to look up websites through
Cloudflare and Google instead of your network. Click **Restore automatic DNS** to
undo it.

## FAQ

**Why does it need my password?**
macOS requires it for any change to network settings. The app never sees or stores it.

**Why did I get asked for my password twice?**
The quick fix didn't work, so it moved on to the deeper fix.

**Does it change anything without asking?**
No. It only checks. Nothing changes until you click a button.

**Does it collect any data?**
No. It only checks whether a few well-known websites can be reached.

**Does it work with my VPN?**
Yes, with any VPN or network.

## Uninstall

1. If you turned on public DNS, click **Restore automatic DNS** first.
2. Click the globe, then **Quit**.
3. Delete **DNS Doctor** from your Applications folder.

---

<sub>Developers: build with `scripts/build.sh <version>` (needs Xcode Command Line Tools).</sub>
