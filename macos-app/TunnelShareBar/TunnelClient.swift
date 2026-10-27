import Foundation
import AppKit

struct ShareItem: Codable, Identifiable {
    let id: String
    let url: String
    let path: String
    let note: String?
    let files: Int
    let size: Int?
    let created_at: Double?
    let expires_at: Double
    let pin_set: Bool
}

struct TunnelStatus: Codable {
    let api: Int
    let version: String
    let uptime_s: Int
    let public_base: String
    let tunnel: TunnelInfo
    let shares: Int?
    
    struct TunnelInfo: Codable {
        let mode: String
        let state: String
        let url: String
        let restarts: Int
        let error: String?
        let verified: Bool
    }
}

class TunnelClient {
    static let shared = TunnelClient()
    
    private var backendBundleURL: URL? {
        return Bundle.main.resourceURL?.appendingPathComponent("BackendBundle")
    }
    
    private var resolvedCommand: (executable: String, arguments: [String]) {
        // 1. Check for standalone bundled binary in Resources/
        if let resURL = Bundle.main.resourceURL {
            let standaloneTsctl = resURL.appendingPathComponent("tsctl").path
            if FileManager.default.isExecutableFile(atPath: standaloneTsctl) {
                return (standaloneTsctl, [])
            }
        }
        
        // 2. Check BackendBundle
        if let bundle = backendBundleURL {
            let bundledTsctl = bundle.appendingPathComponent("tsctl.py").path
            let bundledPython = bundle.appendingPathComponent(".venv/bin/python").path
            if FileManager.default.fileExists(atPath: bundledPython) && FileManager.default.fileExists(atPath: bundledTsctl) {
                return (bundledPython, [bundledTsctl])
            }
        }
        
        let venvPython = NSString(string: "~/.local/share/tunnelshare/app/.venv/bin/python").expandingTildeInPath
        let pythonBin = FileManager.default.fileExists(atPath: venvPython) ? venvPython : "python3"
        
        let installedAppTsctl = NSString(string: "~/.local/share/tunnelshare/app/tsctl.py").expandingTildeInPath
        if FileManager.default.fileExists(atPath: installedAppTsctl) {
            return (pythonBin, [installedAppTsctl])
        }
        
        let localPath = NSString(string: "~/.local/bin/tsctl").expandingTildeInPath
        if FileManager.default.fileExists(atPath: localPath) {
            return (localPath, [])
        }
        
        return ("tsctl", [])
    }
    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let localBin = NSString(string: "~/.local/bin").expandingTildeInPath
        let pathEnv = env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(localBin):/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:\(pathEnv)"
        return env
    }
    
    @discardableResult
    private func runCommand(_ args: [String]) -> (output: String, error: String, exitCode: Int32) {
        let task = Process()
        let pipeOut = Pipe()
        let pipeErr = Pipe()
        
        task.standardOutput = pipeOut
        task.standardError = pipeErr
        
        let cmd = resolvedCommand
        task.executableURL = URL(fileURLWithPath: cmd.executable)
        task.arguments = cmd.arguments + args
        task.environment = buildEnvironment()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let dataOut = pipeOut.fileHandleForReading.readDataToEndOfFile()
            let dataErr = pipeErr.fileHandleForReading.readDataToEndOfFile()
            
            let outStr = String(data: dataOut, encoding: .utf8) ?? ""
            let errStr = String(data: dataErr, encoding: .utf8) ?? ""
            
            return (outStr, errStr, task.terminationStatus)
        } catch {
            return ("", error.localizedDescription, -1)
        }
    }
    
    func fetchStatus() -> (status: TunnelStatus?, rawShares: [ShareItem], error: String?) {
        let result = runCommand(["status", "--json"])
        if result.exitCode == 2 {
            return (nil, [], "Daemon down. Start sharing")
        }
        if result.exitCode != 0 {
            let err = result.error.isEmpty ? result.output : result.error
            return (nil, [], err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        let output = result.output
        guard let startIdx = output.firstIndex(of: "{"),
              let endIdx = output.lastIndex(of: "}") else {
            return (nil, [], "Daemon starting up...")
        }
        let jsonString = String(output[startIdx...endIdx])
        
        do {
            let data = Data(jsonString.utf8)
            let decoder = JSONDecoder()
            let status = try decoder.decode(TunnelStatus.self, from: data)
            
            let sharesResult = runCommand(["list", "--json"])
            var shares: [ShareItem] = []
            if sharesResult.exitCode == 0, let sharesOutput = sharesResult.output as String?,
               let sStart = sharesOutput.firstIndex(of: "{"),
               let sEnd = sharesOutput.lastIndex(of: "}") {
                let sJson = String(sharesOutput[sStart...sEnd])
                if let sharesData = sJson.data(using: .utf8) {
                    struct ShareListResponse: Codable {
                        let shares: [ShareItem]
                    }
                    if let decodedShares = try? decoder.decode(ShareListResponse.self, from: sharesData) {
                        shares = decodedShares.shares
                    }
                }
            }
            
            return (status, shares, nil)
        } catch {
            return (nil, [], "Daemon starting up...")
        }
    }
    
    func toggleSharing(start: Bool) {
        if start {
            // Free ports 8080/8081 and kill any zombie instances
            let cleanupTask = Process()
            cleanupTask.executableURL = URL(fileURLWithPath: "/bin/sh")
            cleanupTask.arguments = ["-c", "pkill -f tsd 2>/dev/null || true; pkill -f cloudflared 2>/dev/null || true; lsof -ti :8080 -ti :8081 | xargs kill -9 2>/dev/null || true"]
            try? cleanupTask.run()
            cleanupTask.waitUntilExit()
            
            // 1. Check for standalone bundled tsd binary in Resources/
            if let resURL = Bundle.main.resourceURL {
                let standaloneTsd = resURL.appendingPathComponent("tsd").path
                if FileManager.default.isExecutableFile(atPath: standaloneTsd) {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: standaloneTsd)
                    task.arguments = []
                    task.environment = buildEnvironment()
                    try? task.run()
                    return
                }
            }
            
            if let bundle = backendBundleURL {
                let bundledPython = bundle.appendingPathComponent(".venv/bin/python").path
                let bundledTsd = bundle.appendingPathComponent("tsd.py").path
                if FileManager.default.fileExists(atPath: bundledPython) && FileManager.default.fileExists(atPath: bundledTsd) {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: bundledPython)
                    task.arguments = [bundledTsd]
                    task.environment = buildEnvironment()
                    try? task.run()
                    return
                }
            }
            
            let installPath = NSString(string: "~/.local/share/tunnelshare/app/tsd.py").expandingTildeInPath
            let venvPython = NSString(string: "~/.local/share/tunnelshare/app/.venv/bin/python").expandingTildeInPath
            let pythonBin = FileManager.default.fileExists(atPath: venvPython) ? venvPython : "python3"
            
            if FileManager.default.fileExists(atPath: installPath) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: pythonBin)
                task.arguments = [installPath]
                task.environment = buildEnvironment()
                try? task.run()
            } else {
                _ = runCommand(["install"])
                let task = Process()
                task.executableURL = URL(fileURLWithPath: pythonBin)
                task.arguments = [installPath]
                task.environment = buildEnvironment()
                try? task.run()
            }
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "pkill -TERM -f tsd 2>/dev/null || true; pkill -TERM -f cloudflared 2>/dev/null || true; sleep 0.3; pkill -9 -f tsd 2>/dev/null || true; pkill -9 -f cloudflared 2>/dev/null || true; lsof -ti :8080 -ti :8081 | xargs kill -9 2>/dev/null || true"]
            try? task.run()
            task.waitUntilExit()
        }
    }
    
    func restartTunnel() {
        _ = runCommand(["tunnel", "restart"])
    }
    
    func revokeShare(id: String) {
        _ = runCommand(["revoke", id])
    }
    
    func sharePaths(paths: [String], hours: Int, pin: String?, note: String?) -> (share: ShareItem?, error: String?) {
        var args = ["share"] + paths + ["--json", "--hours", String(hours)]
        if let pin = pin, !pin.isEmpty {
            args += ["--pin", pin]
        }
        if let note = note, !note.isEmpty {
            args += ["--note", note]
        }
        
        let result = runCommand(args)
        if result.exitCode != 0 {
            let err = result.error.isEmpty ? result.output : result.error
            return (nil, err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        do {
            let data = Data(result.output.utf8)
            let decoder = JSONDecoder()
            let share = try decoder.decode(ShareItem.self, from: data)
            return (share, nil)
        } catch {
            return (nil, "Failed to parse share response: \(result.output)")
        }
    }
    
    func getQRCodePath(id: String) -> String? {
        let result = runCommand(["qr", id])
        if result.exitCode == 0 {
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
