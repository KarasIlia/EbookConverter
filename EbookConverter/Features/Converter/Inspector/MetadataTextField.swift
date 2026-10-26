import SwiftUI

/// An editable metadata field with its label above a bordered text box, so it reads as editable
/// (a plain Form text field looks like static text on macOS).
struct MetadataTextField: View {
    let label: LocalizedStringResource
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField(text: $text, prompt: Text(label)) {
                Text(label)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
        }
    }
}
