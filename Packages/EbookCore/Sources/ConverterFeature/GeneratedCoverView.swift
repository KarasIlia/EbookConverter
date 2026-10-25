import SwiftUI

/// The artwork of a generated cover: title and author on a gradient picked deterministically from the title.
///
/// This view is only rendered into a fixed 1200×1600 bitmap by `CoverGenerator`, never shown as UI, so it
/// uses font sizes scaled to that canvas instead of Dynamic Type (an intentional exception to the
/// "no hard-coded font sizes" rule). Text uses the system font, whose fallback cascade covers every script;
/// centered alignment keeps the layout neutral for left-to-right and right-to-left titles alike.
struct GeneratedCoverView: View {
    static let canvasSize = CGSize(width: 1200, height: 1600)

    /// Pairs of gradient stops (top, bottom), as RGB components in 0...1.
    private static let palette: [(top: Color, bottom: Color)] = [
        (Color(red: 0.16, green: 0.24, blue: 0.45), Color(red: 0.05, green: 0.08, blue: 0.20)),
        (Color(red: 0.45, green: 0.13, blue: 0.20), Color(red: 0.20, green: 0.04, blue: 0.09)),
        (Color(red: 0.10, green: 0.38, blue: 0.33), Color(red: 0.03, green: 0.15, blue: 0.14)),
        (Color(red: 0.42, green: 0.27, blue: 0.10), Color(red: 0.18, green: 0.10, blue: 0.03)),
        (Color(red: 0.33, green: 0.18, blue: 0.45), Color(red: 0.12, green: 0.06, blue: 0.20)),
        (Color(red: 0.22, green: 0.27, blue: 0.30), Color(red: 0.07, green: 0.09, blue: 0.11)),
    ]

    let title: String
    let author: String

    var body: some View {
        let colors = Self.colors(for: title)
        VStack(spacing: 48) {
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 112, weight: .bold))
                .lineLimit(7)
                .minimumScaleFactor(0.35)
            Rectangle()
                .fill(.white.opacity(0.6))
                .frame(width: 240, height: 6)
            if !author.isEmpty {
                Text(author)
                    .font(.system(size: 64))
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .opacity(0.9)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(.horizontal, 110)
        .padding(.vertical, 160)
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .background(LinearGradient(colors: [colors.top, colors.bottom], startPoint: .top, endPoint: .bottom))
    }

    /// Picks a palette entry by FNV-1a over the title's UTF-8 bytes (stable across launches, unlike `hashValue`).
    static func colors(for title: String) -> (top: Color, bottom: Color) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in title.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
