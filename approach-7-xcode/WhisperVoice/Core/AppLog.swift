import Foundation
import os

/// Lightweight logger: writes to ~/Library/Logs/WhisperVoice/app.log and os.Logger.
/// Mirrors approach-6's dual file+console logging.
final class AppLog {
    static let shared = AppLog()

    private let logger = Logger(subsystem: "com.alston.WhisperVoice", category: "app")
    private let queue = DispatchQueue(label: "com.alston.WhisperVoice.log")
    private var handle: FileHandle?
    private let formatter: DateFormatter

    private init() {
        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WhisperVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("app.log")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        handle?.seekToEndOfFile()
    }

    enum Level: String {
        case debug = "DEBUG"
        case info  = "INFO "
        case warn  = "WARN "
        case error = "ERROR"
    }

    func log(_ level: Level, _ message: String) {
        let line = "\(formatter.string(from: Date())) \(level.rawValue) \(message)\n"
        queue.async { [weak self] in
            self?.handle?.write(Data(line.utf8))
        }
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info:  logger.info("\(message, privacy: .public)")
        case .warn:  logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }

    // Convenience statics
    static func debug(_ m: String) { shared.log(.debug, m) }
    static func info(_ m: String)  { shared.log(.info, m) }
    static func warn(_ m: String)  { shared.log(.warn, m) }
    static func error(_ m: String) { shared.log(.error, m) }
}
