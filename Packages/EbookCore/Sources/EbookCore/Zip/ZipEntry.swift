import Foundation

/// A single file to be placed into a ZIP archive.
public struct ZipEntry: Sendable {
    public enum Method: UInt16, Sendable {
        case stored = 0
        case deflated = 8
    }

    public var path: String
    public var data: Data
    public var method: Method

    public init(path: String, data: Data, method: Method = .deflated) {
        self.path = path
        self.data = data
        self.method = method
    }
}
