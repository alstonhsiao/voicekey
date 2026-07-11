import Foundation

/// Minimal multipart/form-data body builder. Fields keep insertion order;
/// the file part should be added last (matches approach-6 Grok field order).
struct MultipartBuilder {
    let boundary = "----VoiceKey-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func finalize() -> Data {
        var out = body
        out.append("--\(boundary)--\r\n")
        return out
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
