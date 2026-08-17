import Foundation

/// Appends timestamped, raw-byte records to a JSONL file so that every
/// capture session is preserved as versionable evidence rather than
/// summarized or discarded. One JSON object per line.
final class PacketCapture {
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder
    private let queue = DispatchQueue(label: "com.dropmixbleprobe.capture")
    private let startTime = DispatchTime.now()

    struct Record: Codable {
        let timestamp: String      // ISO 8601, millisecond precision
        let monotonicMillis: Double
        let kind: String           // "valueUpdate", "discovery", "connect", "disconnect", "info"
        let peripheralUUID: String?
        let serviceUUID: String?
        let characteristicUUID: String?
        let characteristicNote: String?
        let hexBytes: String?
        let byteCount: Int?
        let message: String?
    }

    init(path: String) throws {
        let fm = FileManager.default
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw NSError(domain: "PacketCapture", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: "Could not open \(path) for writing"])
        }
        handle.seekToEndOfFile()
        self.fileHandle = handle
        self.encoder = JSONEncoder()
    }

    private func monotonicMillisNow() -> Double {
        let now = DispatchTime.now()
        return Double(now.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func write(kind: String,
               peripheralUUID: String? = nil,
               serviceUUID: String? = nil,
               characteristicUUID: String? = nil,
               characteristicNote: String? = nil,
               bytes: Data? = nil,
               message: String? = nil) {
        let record = Record(
            timestamp: PacketCapture.isoFormatter.string(from: Date()),
            monotonicMillis: monotonicMillisNow(),
            kind: kind,
            peripheralUUID: peripheralUUID,
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            characteristicNote: characteristicNote,
            hexBytes: bytes.map { $0.map { String(format: "%02x", $0) }.joined() },
            byteCount: bytes?.count,
            message: message
        )
        queue.sync {
            guard let data = try? encoder.encode(record) else { return }
            fileHandle.write(data)
            fileHandle.write("\n".data(using: .utf8)!)
        }
    }

    func close() {
        queue.sync {
            try? fileHandle.close()
        }
    }
}
