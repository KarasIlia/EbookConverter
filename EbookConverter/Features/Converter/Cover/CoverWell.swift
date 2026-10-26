import SwiftUI
import ConverterFeature
import EbookCore

/// The book cover in the inspector. A dropped or chosen image replaces it; the dashed border,
/// the hover hint and the highlight while an image is dragged over it make the drop target obvious.
struct CoverWell: View {
    let cover: ImageAsset?
    let source: CoverSource
    /// Called with the bytes of an image the user dropped or chose; returns `false` if they are not a readable image.
    let onSetCover: @MainActor (Data) -> Bool
    let onReset: @MainActor () -> Void

    @State private var isHovering = false
    @State private var isTargeted = false
    @State private var isImporterPresented = false
    @State private var isImageUnreadable = false

    var body: some View {
        VStack {
            CoverArtwork(cover: cover, isHovering: isHovering, isTargeted: isTargeted)
                .frame(maxWidth: ConverterLayout.coverWellWidth)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(.coverAccessibility))
                .accessibilityAddTraits(.isImage)
                .onHover { isHovering = $0 }
                .dropDestination(for: CoverDropItem.self) { items, _ in
                    guard let data = items.first?.loadImageData(), onSetCover(data) else {
                        isImageUnreadable = true
                        return false
                    }
                    return true
                } isTargeted: { targeted in
                    isTargeted = targeted
                }
                .animation(.default, value: isHovering)
                .animation(.default, value: isTargeted)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(.chooseCover, systemImage: "photo") {
                    isImporterPresented = true
                }
                Button(.resetCover, systemImage: "arrow.uturn.backward", action: onReset)
                    .disabled(source != .custom)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: SupportedTypes.coverImages) { result in
            guard case .success(let url) = result else { return }
            Task {
                guard let data = await CoverDropItem.imageData(at: url), onSetCover(data) else {
                    isImageUnreadable = true
                    return
                }
            }
        }
        .alert(Text(.coverImageUnreadable), isPresented: $isImageUnreadable) {}
    }

    private var caption: LocalizedStringResource {
        switch source {
        case .fromFile: .coverFromFile
        case .generated: .coverGenerated
        case .custom: .coverCustom
        }
    }
}

#if DEBUG
#Preview("Generated") {
    @Previewable @State var cover = CoverGenerator().makeCover(title: "Sample Book", author: "Jane Doe")
    CoverWell(cover: cover, source: .generated, onSetCover: { _ in true }, onReset: {})
        .padding()
        .frame(width: 300)
}

#Preview("From file") {
    @Previewable @State var cover = CoverGenerator().makeCover(title: "Sample Book", author: "Jane Doe")
    CoverWell(cover: cover, source: .fromFile, onSetCover: { _ in true }, onReset: {})
        .padding()
        .frame(width: 300)
}

#Preview("Custom") {
    @Previewable @State var cover = CoverGenerator().makeCover(title: "Sample Book", author: "Jane Doe")
    CoverWell(cover: cover, source: .custom, onSetCover: { _ in true }, onReset: {})
        .padding()
        .frame(width: 300)
}
#endif
