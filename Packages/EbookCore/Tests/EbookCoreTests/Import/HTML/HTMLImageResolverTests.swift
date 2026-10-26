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

    @Test func folderCoveringImagesInDocumentFolderIsDocumentFolder() {
        let file = URL(filePath: "/a/book/doc.md")
        let folder = HTMLImageResolver.folderCovering([URL(filePath: "/a/book/x.png"), URL(filePath: "/a/book/sub/y.png")], relativeTo: file)
        #expect(folder == file.deletingLastPathComponent())
    }

    @Test func folderCoveringSiblingFolderIsCommonParent() {
        let file = URL(filePath: "/a/b/book/doc.md")
        let folder = HTMLImageResolver.folderCovering([URL(filePath: "/a/b/pics/x.png")], relativeTo: file)
        #expect(folder.path(percentEncoded: false) == "/a/b/")
    }

    @Test func folderCoveringUnrelatedPathStopsAtRoot() {
        let file = URL(filePath: "/a/book/doc.md")
        let folder = HTMLImageResolver.folderCovering([URL(filePath: "/z/x.png")], relativeTo: file)
        #expect(folder.path(percentEncoded: false) == "/")
    }

    @Test func unreadableImageReportsItsLocation() {
        let outcome = HTMLImageResolver.loadLocalImage(
            reference: "../pics/nope.png", relativeTo: URL(filePath: "/nonexistent-\(UUID())/book/doc.md"),
            accessibleFolder: nil, id: "img-1"
        )
        guard case .needsFolderAccess(let target) = outcome else {
            Issue.record("expected .needsFolderAccess, got \(outcome)")
            return
        }
        #expect(target.lastPathComponent == "nope.png")
        #expect(target.deletingLastPathComponent().lastPathComponent == "pics")
    }
}
