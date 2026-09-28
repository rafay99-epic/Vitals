import Foundation

/// Runs a shell script as root through the standard macOS authorization dialog
/// (`do shell script … with administrator privileges`), one-shot, no daemon.
/// The single place the app escalates: deep clean, the cleanup retry, and
/// system-domain uninstall.
enum PrivilegedShell {
    struct AdminError: Error {
        let message: String
        /// True when the user dismissed the auth dialog (osascript -128).
        let cancelled: Bool
    }

    /// Stages `shellScript` to a temp file and runs it as root. Callers must build
    /// it from fixed constants or re-validated paths, never untrusted input.
    nonisolated static func runAsAdmin(_ shellScript: String, prompt: String) async throws {
        let scriptPath = NSTemporaryDirectory() + "vitals-priv-\(UUID().uuidString).sh"
        try shellScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        // The command only references the temp script path, which we control.
        // `prompt` is interpolated unescaped, so it must not contain quotes.
        let appleScript = "do shell script \"/bin/sh '\(scriptPath)'\" with administrator privileges with prompt \"\(prompt)\""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", appleScript]
                let stderr = Pipe()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = stderr
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: AdminError(message: error.localizedDescription, cancelled: false))
                    return
                }
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume()
                    return
                }
                let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let cancelled = output.contains("-128")
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(throwing: AdminError(
                    message: trimmed.isEmpty ? "Helper command failed." : trimmed,
                    cancelled: cancelled
                ))
            }
        }
    }
}
