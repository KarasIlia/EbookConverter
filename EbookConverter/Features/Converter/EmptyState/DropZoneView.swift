import SwiftUI

/// Empty-state drop zone: accepts a dropped file or opens one chosen in the file importer.
struct DropZoneView: View {
    /// Message about the last failed import, shown under the zone.
    let errorMessage: LocalizedStringResource?
    /// Called with the file the user dropped or chose.
    let onOpen: (URL) -> Void

    @State private var isTargeted = false
    @State private var isImporterPresented = false

    var body: some View {
        VStack {
            VStack {
                Image(systemName: "doc.badge.plus")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .padding(.bottom)
                Text(.dropFileHere)
                    .font(.title3)
                    .bold()
                Text(.supportedFormatsList)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    isImporterPresented = true
                } label: {
                    Text(.chooseOnDisk)
                }
                .buttonStyle(.link)
                .padding(.top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isTargeted ? AnyShapeStyle(.tint.quaternary) : AnyShapeStyle(.clear),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.secondary),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
            }
            .animation(.default, value: isTargeted)

            if let errorMessage {
                Label {
                    Text(errorMessage)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: ConverterLayout.compactMinSize.width, minHeight: ConverterLayout.compactMinSize.height)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onOpen(url)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: SupportedTypes.inputs) { result in
            if case .success(let url) = result {
                onOpen(url)
            }
        }
    }
}

#Preview("Empty") {
    DropZoneView(errorMessage: nil) { _ in }
}

#Preview("Failed") {
    DropZoneView(errorMessage: .errorUnsupportedFormat) { _ in }
}
