import Foundation

/// Single-instance lock via flock on a lock file (mirrors approach-6 fcntl.flock).
/// The fd stays open for the process lifetime to hold the lock.
enum SingleInstance {
    private static var fd: Int32 = -1

    /// Returns true if this is the only instance (lock acquired), false if another holds it.
    static func acquire() -> Bool {
        let lockPath = AppPaths.appSupport.appendingPathComponent("WhisperVoice.lock").path
        fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        if fd < 0 { return true }   // can't open lock file → fail open (allow run)
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            fd = -1
            return false            // another instance holds the lock
        }
        ftruncate(fd, 0)
        let pid = "\(getpid())"
        _ = pid.withCString { write(fd, $0, strlen($0)) }
        return true
    }

    static func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }
}
