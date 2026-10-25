import Foundation
import Testing
@testable import EbookCore

@Suite struct HTMLImageResolverTests {
    @Test func protocolRelativeReferenceIsRemote() {
        let outcome = HTMLImageResolver.loadLocalImage(
            reference: "//cdn.example.com/a.png", relativeTo: URL(filePath: "/tmp/book.html"),
            accessibleFolder: nil, id: "img-1"
        )
        guard case .remote = outcome else {
            Issue.record("expected .remote, got \(outcome)")
            return
        }
    }
}
