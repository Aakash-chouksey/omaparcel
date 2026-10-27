import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PanelView: View {
    @ObservedObject var model: TunnelViewModel
    var onClose: (() -> Void)? = nil
    var onQuit: (() -> Void)? = nil
    @State private var confirmingRevokeId: String? = nil
    @State private var copiedLinkId: String? = nil
    @State private var copiedPin: Bool = false
    @State private var showQRModal: Bool = false
    @State private var isDropTargeted: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content scroll area
            ScrollView {
                VStack(spacing: 12) {
                    // Drag and Drop Zone
                    dropZoneView
                    
                    // Actions & Options
                    actionSection
                    
                    // Options (PIN, Hours, Note)
                    optionsSection
                    
                    // Result Card (if a share was just created)
                    if let share = model.lastCreatedShare {
                        resultCard(share: share)
                    }
                    
                    // Active Links Section
                    activeLinksSection
                }
                .padding(12)
            }
            
            // Error banner at bottom if any
            if let err = model.errorMessage {
                errorBanner(err: err)
            }
            
            Divider()
            
            // Footer with Quit button
            footerView
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Omatunnel")
                    .font(.headline)
                
                Spacer()
                
                if model.isToggling {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }
                
                Toggle("Sharing", isOn: Binding(
                    get: { model.isSharing },
                    set: { _ in model.toggleSharing() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(model.isToggling)
                
                Button(action: { onClose?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close panel (⌘W)")
                
                Button(action: { onQuit?() }) {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit Omatunnel (⌘Q)")
            }
            
            statusLine
        }
    }
    
    @ViewBuilder
    private var statusLine: some View {
        if let status = model.status {
            if status.tunnel.state == "up" {
                HStack(spacing: 4) {
                    Circle()
                        .fill(status.tunnel.verified ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Live at")
                        .font(.subtleStatusFont)
                    if let url = URL(string: status.public_base) {
                        Link(status.public_base, destination: url)
                            .font(.subheadline)
                            .lineLimit(1)
                    } else {
                        Text(status.public_base)
                            .font(.subheadline)
                    }
                }
            } else if status.tunnel.state == "starting" {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                    Text("Starting the tunnel...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Tunnel down.")
                        .font(.subheadline)
                    Button("Restart") {
                        model.restartTunnel()
                    }
                    .buttonStyle(.link)
                    .font(.subheadline)
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(.red)
                Text("Daemon down.")
                    .font(.subheadline)
                Button("Start sharing") {
                    model.toggleSharing()
                }
                .buttonStyle(.link)
                .font(.subheadline)
                .disabled(model.isToggling)
            }
        }
    }
    
    // MARK: - Drop Zone
    private var dropZoneView: some View {
        VStack(spacing: 8) {
            if model.isSharingInProgress {
                ProgressView()
                    .scaleEffect(0.85)
                Text("Creating share link...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down")
                    .font(.system(size: 24))
                    .foregroundColor(isDropTargeted ? .accentColor : .secondary)
                    .scaleEffect(isDropTargeted ? 1.15 : 1.0)
                    .animation(.spring(response: 0.3), value: isDropTargeted)
                
                Text(isDropTargeted ? "Release to Share" : "Drop files or folders here")
                    .font(.subheadline)
                    .fontWeight(isDropTargeted ? .semibold : .medium)
                    .foregroundColor(isDropTargeted ? .accentColor : .primary)
                
                Text("Drag files freely from Finder or Desktop")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.5, dash: [6, 4])
                )
        )
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }
    
    // MARK: - Actions
    private var actionSection: some View {
        HStack(spacing: 10) {
            Button(action: selectAndShareFiles) {
                HStack {
                    if model.isSharingInProgress {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "doc.badge.plus")
                    }
                    Text("Share files")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isSharingInProgress)
            
            Button(action: selectAndShareFolder) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text("Share folder")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(model.isSharingInProgress)
        }
    }
    
    // MARK: - Options
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Require a code (PIN)", isOn: $model.usePin)
                    .font(.subheadline)
                Spacer()
                Picker("Expires", selection: $model.selectedHours) {
                    Text("1 hour").tag(1)
                    Text("24 hours").tag(24)
                    Text("72 hours").tag(72)
                }
                .frame(width: 100)
            }
            
            if model.usePin {
                HStack {
                    SecureField("4-8 digit PIN", text: $model.pinCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Text("4 to 8 digits")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if model.showNoteField {
                TextField("Add a note (max 200 chars)", text: $model.noteText)
                    .textFieldStyle(.roundedBorder)
            } else {
                Button("+ Add a note") {
                    model.showNoteField = true
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
    
    // MARK: - Result Card
    @ViewBuilder
    private func resultCard(share: ShareItem) -> some View {
        let linkUrl = model.effectiveUrl(for: share)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("New Share Created")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Spacer()
                Button(action: { model.lastCreatedShare = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Text(linkUrl)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .textSelection(.enabled)
            
            HStack(spacing: 8) {
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(linkUrl, forType: .string)
                    copiedLinkId = share.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        if copiedLinkId == share.id { copiedLinkId = nil }
                    }
                }) {
                    Label(copiedLinkId == share.id ? "Copied!" : "Copy link", systemImage: copiedLinkId == share.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                
                if let qrPath = model.qrImagePath, FileManager.default.fileExists(atPath: qrPath),
                   let img = NSImage(contentsOfFile: qrPath) {
                    Button(action: { showQRModal.toggle() }) {
                        Label("QR Code", systemImage: "qrcode")
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showQRModal) {
                        VStack(spacing: 8) {
                            Image(nsImage: img)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 180, height: 180)
                            Text("Scan with phone camera")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                    }
                }
            }
            
            if share.pin_set {
                Divider()
                HStack {
                    Text("PIN protected")
                        .font(.caption)
                        .bold()
                    Spacer()
                    Text("Send code in a separate message")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
    }
    
    // MARK: - Active Links Section
    private var activeLinksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Active Links (\(model.shares.count))")
                .font(.subheadline)
                .bold()
                .foregroundColor(.secondary)
            
            if model.shares.isEmpty {
                Text("Nothing shared yet. Pick a file to start.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.shares) { share in
                    activeLinkRow(share: share)
                }
            }
        }
    }
    
    @ViewBuilder
    private func activeLinkRow(share: ShareItem) -> some View {
        let linkUrl = model.effectiveUrl(for: share)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(share.note?.isEmpty == false ? share.note! : share.path)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)
                Spacer()
                Text(formatExpiry(share.expires_at))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text(linkUrl)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(linkUrl, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy link")
                
                if confirmingRevokeId == share.id {
                    Button("Confirm?") {
                        model.revokeShare(id: share.id)
                        confirmingRevokeId = nil
                    }
                    .font(.caption2)
                    .foregroundColor(.red)
                    .buttonStyle(.bordered)
                    
                    Button("Cancel") {
                        confirmingRevokeId = nil
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                } else {
                    Button(action: { confirmingRevokeId = share.id }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Revoke share")
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }
    
    // MARK: - Error Banner
    private func errorBanner(err: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            Text(err)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button(action: { model.errorMessage = nil }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.red.opacity(0.15))
    }
    
    // MARK: - Actions Helpers
    private func selectAndShareFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "Share files"
        
        panel.begin { response in
            if response == .OK {
                let paths = panel.urls.map { $0.path }
                model.sharePaths(paths)
            }
        }
    }
    
    private func selectAndShareFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Share folder"
        
        panel.begin { response in
            if response == .OK {
                if let url = panel.url {
                    model.sharePaths([url.path])
                }
            }
        }
    }
    
    private func formatExpiry(_ timestamp: Double) -> String {
        let targetDate = Date(timeIntervalSince1970: timestamp)
        let interval = targetDate.timeIntervalSinceNow
        if interval <= 0 { return "expired" }
        let hours = Int(interval / 3600)
        if hours > 24 {
            return "in \(hours / 24)d"
        } else if hours > 0 {
            return "in \(hours)h"
        } else {
            let mins = max(1, Int(interval / 60))
            return "in \(mins)m"
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !model.isSharingInProgress else { return false }
        let group = DispatchGroup()
        var paths: [String] = []
        let lock = NSLock()
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        lock.lock()
                        paths.append(url.path)
                        lock.unlock()
                    } else if let nsUrl = item as? NSURL, let path = nsUrl.path {
                        lock.lock()
                        paths.append(path)
                        lock.unlock()
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        lock.lock()
                        paths.append(url.path)
                        lock.unlock()
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            if !paths.isEmpty {
                model.sharePaths(paths)
            }
        }
        return true
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Text("Omatunnel")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { onQuit?() }) {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .bold))
                    Text("Quit Omatunnel")
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color(NSColor.separatorColor).opacity(0.2))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Quit Omatunnel completely (⌘Q)")
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

extension Font {
    static let subtleStatusFont: Font = .system(size: 11, weight: .regular)
}
