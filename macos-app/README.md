# Omatunnel for macOS

A native macOS menu bar app for **TunnelShare**, written in Swift & SwiftUI (`MenuBarExtra` / `NSPanel`). It acts as a thin client over `tsctl` and `tsd`, giving you instant file and folder sharing through Cloudflare tunnels without requiring any terminal commands.

---

## Installation Guide for Mac

### Method 1: Pre-built DMG (Recommended for Most Users)

No Python, Homebrew, or Xcode required. Everything (the daemon, CLI, and `cloudflared`) is completely self-contained in the bundle.

1. **Download the Installer**:
   Download the latest **`Omatunnel.dmg`** from the [GitHub Releases](https://github.com/Aakash-chouksey/omatunnel/releases/latest) page.

2. **Install**:
   - Double-click `Omatunnel.dmg` to open it.
   - Drag **Omatunnel** into the **Applications** folder.

3. **First Launch & macOS Gatekeeper**:
   Because Omatunnel is open-source and not signed with an Apple Developer Program certificate ($99/year), macOS Gatekeeper may show a warning on first launch (*"Apple cannot check it for malicious software"*).

   To open it the first time, choose any of these easy options:
   - **Option A (Easiest)**: Double-click the **`Open Me (If Blocked by macOS).command`** script included inside the DMG.
   - **Option B**: Right-click (or Control-click) `Omatunnel` in `/Applications`, choose **Open**, and then click **Open Anyway**.
   - **Option C**: Open **System Settings** → **Privacy & Security** → scroll to the **Security** section, and click **"Open Anyway"** next to *Omatunnel*.
   - **Option D (Terminal)**: Run:
     ```bash
     xattr -cr /Applications/Omatunnel.app
     ```

4. **Launch**:
   Open **Omatunnel** from your Applications folder or Spotlight (`⌘ + Space`).  
   A new icon will appear in your top macOS menu bar.

---

### Method 2: Build from Source (For Developers)

#### Prerequisites
- macOS 13.0 (Ventura) or newer
- **Xcode 14+** (from the Mac App Store) or Xcode Command Line Tools (`xcode-select --install`)
- **Python 3.10+**: `brew install python@3.11`
- **cloudflared**: `brew install cloudflared`

#### 1-Command Automated Build:
Clone the repository and run the packaging script:
```bash
git clone https://github.com/Aakash-chouksey/omatunnel.git
cd omatunnel
./macos-app/build_dmg.sh
```
This script will:
1. Compile standalone Mach-O binaries for `tsd` and `tsctl` using PyInstaller.
2. Bundle `cloudflared` into the application resources.
3. Build the Release version of `Omatunnel.app` via `xcodebuild`.
4. Codesign all executables with an ad-hoc signature.
5. Create a self-contained `Omatunnel.dmg` at the repository root.

#### Running in Xcode directly:
1. Open `macos-app/Omatunnel.xcodeproj` in Xcode.
2. Select the `Omatunnel` scheme with target **My Mac**.
3. Press **`Cmd + R`** to compile and run.

---

## How to Use Omatunnel

### 1. Starting and Stopping Sharing
- Click the **Omatunnel** icon in the macOS menu bar to toggle the panel.
- Flip the **Sharing** switch in the top header.
  - When the switch is turned on, the local `tsd` daemon launches and creates a secure Cloudflare tunnel.
  - Once connected, the status turns **green** (*Live at https://*.trycloudflare.com*).
  - The menu bar icon changes to indicate live sharing.

### 2. Sharing Files & Folders
- **Drag and Drop**: Drag any file or folder directly from Finder or your Desktop and drop it into the dashed drop zone.
- **File Chooser**: Click **Share files** (multi-selection supported) or **Share folder** to choose via standard macOS Finder dialogs. Paths with spaces and special characters are handled safely.

### 3. Protection & Expiry Options
Before sharing, configure options right in the panel:
- **Expires**: Set link lifetime (`1 hour`, `24 hours`, `72 hours`).
- **PIN Protection**: Check *Require a code (PIN)* and type a 4–8 digit PIN.
- **Note**: Click *+ Add a note* to add an optional description (up to 200 characters).

### 4. Distributing Links & QR Codes
- After a share is created, click **Copy link** to put the public URL on your clipboard.
- If a PIN was configured, copy the PIN separately to send to your recipient in a second message.
- Click **QR Code** to view and scan the transfer code directly with a phone camera.

### 5. Managing Active Links
- The **Active Links** section shows all currently shared items with their expiry timers.
- Click the copy button to re-copy any active link.
- Click the trash icon (with 2-step confirmation) to immediately revoke a share.

---

## Menu Bar Icon Reference

| Icon State | Appearance | Meaning |
| :--- | :--- | :--- |
| **Off / Idle** | Dim / Gray `network.slash` | Sharing is stopped. Daemon is idle. |
| **Starting** | Orange `network` | The daemon is launching and connecting the Cloudflare tunnel. |
| **Live** | Green `network` | Tunnel is connected and actively serving shares. |
| **Error** | Red `exclamationmark.triangle` | The tunnel encountered an error or was disconnected. Click *Restart* in the panel. |

---

## Uninstalling

To completely remove Omatunnel and all associated data from your Mac:

```bash
# 1. Quit the app and remove it from Applications
pkill -f Omatunnel || true
rm -rf /Applications/Omatunnel.app

# 2. Remove configuration and database
rm -rf ~/.config/tunnelshare ~/.local/share/tunnelshare
```
*(Your shared files outside these directories are never modified or deleted.)*
