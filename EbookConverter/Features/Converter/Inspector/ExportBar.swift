import SwiftUI
import AppKit

/// Bottom bar of the inspector: the Convert button and, after a save, the confirmation with "Show in Finder".
struct ExportBar: View {
    let isDisabled: Bool
    let savedURL: URL?
    let onExport: () -> Void

    var body: some View {
        VStack {
            if let savedURL {
                HStack {
                    Label {
                        Text(.savedConfirmation)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Button(.showInFinder, systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                    }
                }
            }
            Button(action: onExport) {
                Text(.convert)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isDisabled)
        }
        .padding()
        .background(.bar)
    }
}
