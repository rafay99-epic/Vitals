import Foundation
import Darwin

enum ProcessControl {
    enum Failure: Error, Equatable {
        case gone
        case protected
        case denied(Int32)

        var message: String {
            switch self {
            case .gone: return "Process already exited"
            case .protected: return "Process is protected"
            case let .denied(code): return "macOS refused (\(String(cString: strerror(code))))"
            }
        }
    }

    static func apply(_ action: ProcessAction, isProtected: (pid_t) -> Bool) -> Failure? {
        let pid = action.target.pid
        guard pid > 1, ProcessSampler.startTimeMs(of: pid) == action.target.startTimeMs else { return .gone }
        guard ProcessSampler.owner(of: pid) == getuid(), pid != getpid(), !isProtected(pid) else { return .protected }
        let result: Int32
        switch action.action {
        case .throttle: result = setpriority(PRIO_DARWIN_PROCESS, id_t(pid), PRIO_DARWIN_BG)
        case .unthrottle: result = setpriority(PRIO_DARWIN_PROCESS, id_t(pid), 0)
        case .pause: result = kill(pid, SIGSTOP)
        case .resume: result = kill(pid, SIGCONT)
        case .terminate: result = kill(pid, SIGTERM)
        case .kill: result = kill(pid, SIGKILL)
        }
        return result == 0 ? nil : .denied(errno)
    }
}
