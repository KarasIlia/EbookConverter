#if DEBUG
import SwiftUI
import ConverterFeature

/// Hands the view model provided by `LoadedBookPreview` to a view that takes it as a parameter.
struct LoadedBookPreviewHost<Content: View>: View {
    @Environment(ConverterViewModel.self) private var viewModel
    @ViewBuilder let content: (ConverterViewModel) -> Content

    var body: some View {
        content(viewModel)
    }
}
#endif
