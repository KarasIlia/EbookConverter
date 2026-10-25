import SwiftUI

/// A chapter title, or "Untitled" for chapters without one.
struct ChapterTitleLabel: View {
    let title: String?

    var body: some View {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            Text(title)
                .lineLimit(2)
        } else {
            Text(.untitledSection)
                .foregroundStyle(.secondary)
        }
    }
}
