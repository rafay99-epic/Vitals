import Foundation

/// Runs a shell script with administrator privileges through the standard
/// macOS authorization dialog (`do shell script … with administrator
/// privileges`). One native password/Touch ID prompt, one-shot — no persistent
/// daemon. This is the single place the app escalates; both the fan helper
/// install and the deep-clean system pass go through it.
enum PrivilegedShell {
    struct AdminError: Error {
        let message: String
        /// True when the user dismissed the auth dialog (osascript -128).
        let cancelled: Bool
    }

    /// Stages `shellScript` to a temp file and runs it as root. The script
    /// itself must be self-contained and safely constructed by the caller —
    /// callers build it from fixed constants, never from untrusted input.
    nonisolated static func runAsAdmin(_ shellScript: String, prompt: String) async throws {
        let scriptPath = NSTemporaryDirectory() + "vitals-priv-\(UUID().uuidString).sh"
        try shellScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        // The AppleScript string stays a single, safely-escaped command: it
        // only references the temp script path, which we control.
        let appleScript = "do shell script \"/bin/sh '\(scriptPath)'\" with administrator privileges with prompt \"\(prompt)\""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", appleScript]
                let stderr = Pipe()
                process.standardOutput = Pipe()
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
