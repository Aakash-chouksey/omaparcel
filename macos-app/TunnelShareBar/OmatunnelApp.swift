import SwiftUI
import Combine
import AppKit

@main
struct OmatunnelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    var statusItem: NSStatusItem!
    var panel: NSPanel!
    var model = TunnelViewModel()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        
        // 1. Create Status Item in Top Bar
        // squareLength gives a fixed slot — icon can never collapse or disappear
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Omatunnel"
            // Set a visible icon immediately — before any model update fires
            setStatusIcon(symbolName: "network.slash", tint: NSColor.systemBlue)
        }
        
        // 2. Create Persistent Panel (Never auto-closes on outside clicks)
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false // CRITICAL: Stays on screen when user clicks Finder!
        p.hasShadow = true
        p.contentView = NSHostingView(rootView: PanelView(
            model: model,
            onClose: { [weak self] in
                self?.panel.orderOut(nil)
            },
            onQuit: { [weak self] in
                self?.quitApp()
            }
        ))
        self.panel = p
        
        // Keep top bar icon updated with model state
        model.onUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusItemIcon()
            }
        }
    }
    
    @objc func togglePanel() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = NSMenu()
            let titleItem = NSMenuItem(title: "Omatunnel", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            menu.addItem(NSMenuItem.separator())
            if panel.isVisible {
                menu.addItem(NSMenuItem(title: "Close Panel", action: #selector(togglePanel), keyEquivalent: ""))
            } else {
                menu.addItem(NSMenuItem(title: "Open Panel", action: #selector(togglePanel), keyEquivalent: ""))
            }
            menu.addItem(NSMenuItem(title: "Restart Tunnel", action: #selector(restartTunnelFromMenu), keyEquivalent: "r"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit Omatunnel", action: #selector(quitApp), keyEquivalent: "q"))
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }
    
    @objc func restartTunnelFromMenu() {
        model.restartTunnel()
    }
    
    @objc func quitApp() {
        panel?.orderOut(nil)
        TunnelClient.shared.toggleSharing(start: false)
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        TunnelClient.shared.toggleSharing(start: false)
    }
    
    func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        
        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 540
        
        var x = screenRect.midX - (panelWidth / 2)
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let maxX = screen.visibleFrame.maxX - panelWidth - 8
            let minX = screen.visibleFrame.minX + 8
            x = min(maxX, max(minX, x))
        }
        let y = screenRect.minY - panelHeight - 4
        
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        panel.orderFront(nil)
    }
    
    func updateStatusItemIcon() {
        let isUp      = (model.status?.tunnel.state == "up")       && model.isSharing
        let isStarting = (model.status?.tunnel.state == "starting") && model.isSharing
        
        let symbolName = model.menuBarIconName
        let tint: NSColor = isUp ? .systemGreen : isStarting ? .systemOrange : .systemBlue
        setStatusIcon(symbolName: symbolName, tint: tint)
    }
    
    /// Always sets an icon — falls back to a plain circle if the SF Symbol is unavailable.
    private func setStatusIcon(symbolName: String, tint: NSColor) {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Omatunnel")
            ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Omatunnel")
        guard let resolved = img?.withSymbolConfiguration(config) else { return }
        resolved.isTemplate = true
        button.image = resolved
        button.contentTintColor = tint
    }
}

class TunnelViewModel: ObservableObject {
    @Published var status: TunnelStatus?
    @Published var shares: [ShareItem] = []
    @Published var errorMessage: String?
    @Published var isSharing: Bool = false
    @Published var isToggling: Bool = false
    @Published var lastCreatedShare: ShareItem?
    @Published var qrImagePath: String?
    
    // Form state
    @Published var selectedHours: Int = 24
    @Published var usePin: Bool = false
    @Published var pinCode: String = ""
    @Published var showNoteField: Bool = false
    @Published var noteText: String = ""
    @Published var isSharingInProgress: Bool = false
    
    var onUpdate: (() -> Void)? = nil
    
    private var timer: Timer?
    private var isRefreshing: Bool = false
    
    var menuBarIconName: String {
        guard let s = status, isSharing else { return "network.slash" }
        if s.tunnel.state == "up" {
            return "network"
        } else if s.tunnel.state == "starting" {
            return "network"
        } else {
            return "network.slash"
        }
    }
    
    var isLive: Bool {
        return status?.tunnel.state == "up"
    }
    
    /// Resolves the live, active URL for a share using the current tunnel public base.
    func effectiveUrl(for share: ShareItem) -> String {
        if let base = status?.public_base, !base.isEmpty {
            let cleanBase = base.hasSuffix("/") ? String(base.dropLast()) : base
            return "\(cleanBase)/s/\(share.id)"
        }
        if !share.url.isEmpty {
            return share.url
        }
        return "/s/\(share.id)"
    }
    
    init() {
        refresh()
        startPolling()
    }
    
    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                DispatchQueue.main.async {
                    self?.isRefreshing = false
                }
            }
            let result = TunnelClient.shared.fetchStatus()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isToggling { return }
                
                if let err = result.error {
                    if err.contains("Daemon down") {
                        self.errorMessage = nil
                    } else {
                        self.errorMessage = err
                    }
                    self.status = nil
                    self.shares = []
                    self.isSharing = false
                } else {
                    self.errorMessage = nil
                    let oldBase = self.status?.public_base
                    self.status = result.status
                    self.shares = result.rawShares
                    self.isSharing = (result.status != nil)
                    
                    // If public base changed and we have a lastCreatedShare, refresh QR code image
                    if let last = self.lastCreatedShare, let newBase = result.status?.public_base, !newBase.isEmpty, newBase != oldBase {
                        DispatchQueue.global(qos: .userInitiated).async {
                            let newQr = TunnelClient.shared.getQRCodePath(id: last.id)
                            DispatchQueue.main.async {
                                self.qrImagePath = newQr
                            }
                        }
                    }
                }
                self.onUpdate?()
            }
        }
    }
    
    func toggleSharing() {
        guard !isToggling else { return }
        isToggling = true
        let targetState = !isSharing
        isSharing = targetState
        errorMessage = nil
        onUpdate?()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            TunnelClient.shared.toggleSharing(start: targetState)
            Thread.sleep(forTimeInterval: 0.5)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isToggling = false
                if !targetState {
                    self.status = nil
                    self.shares = []
                    self.isSharing = false
                    self.lastCreatedShare = nil
                    self.qrImagePath = nil
                }
                self.refresh()
                self.onUpdate?()
            }
        }
    }
    
    func restartTunnel() {
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            TunnelClient.shared.restartTunnel()
            Thread.sleep(forTimeInterval: 1.0)
            DispatchQueue.main.async {
                self.refresh()
            }
        }
    }
    
    func sharePaths(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        isSharingInProgress = true
        errorMessage = nil
        
        let hours = selectedHours
        let pin = usePin ? pinCode : nil
        let note = showNoteField && !noteText.isEmpty ? noteText : nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = TunnelClient.shared.sharePaths(paths: paths, hours: hours, pin: pin, note: note)
            DispatchQueue.main.async {
                self.isSharingInProgress = false
                if let err = result.error {
                    self.errorMessage = err
                } else if let share = result.share {
                    self.lastCreatedShare = share
                    self.qrImagePath = TunnelClient.shared.getQRCodePath(id: share.id)
                    self.refresh()
                }
            }
        }
    }
    
    func revokeShare(id: String) {
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            TunnelClient.shared.revokeShare(id: id)
            DispatchQueue.main.async {
                if self.lastCreatedShare?.id == id {
                    self.lastCreatedShare = nil
                    self.qrImagePath = nil
                }
                self.refresh()
            }
        }
    }
}
