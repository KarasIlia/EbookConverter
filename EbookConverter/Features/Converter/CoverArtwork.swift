import SwiftUI
import AppKit
import EbookCore

/// The 3:4 cover frame of `CoverWell`: the image, an always-visible dashed drop border,
/// and a hint over the image while the pointer hovers or an image is dragged over it.
struct CoverArtwork: View {
    let cover: ImageAsset?
    let isHovering: Bool
    /// An image is being dragged over the cover: the border and hint take the accent color.
    let isTargeted: Bool

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .background(.quaternary)
            .overlay {
                // Decoded here, in a view that only updates when the cover or the drag state changes.
                if let cover, let image = NSImage(data: cover.data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                if isHovering || isTargeted {
                    VStack {
                        Image(systemName: "photo.badge.plus")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                        Text(.coverDropHint)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.secondary),
                        style: StrokeStyle(lineWidth: isTargeted ? 4 : 2, dash: [6])
                    )
            }
    }
}

#Preview("Hovering") {
    CoverArtwork(cover: nil, isHovering: true, isTargeted: false)
        .frame(width: 160)
        .padding()
}

#Preview("Image dragged over") {
    CoverArtwork(cover: nil, isHovering: false, isTargeted: true)
        .frame(width: 160)
        .padding()
}
