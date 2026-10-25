#if DEBUG
import SwiftUI
import ConverterFeature

/// Preview modifier that opens the `PreviewBookConverter` sample book before the preview renders
/// and provides the loaded view model through the environment.
struct LoadedBookPreview: PreviewModifier {
    static func makeSharedContext() async throws -> ConverterViewModel {
        let viewModel = ConverterViewModel(makeConverter: { _ in PreviewBookConverter() })
        await viewModel.open(URL(filePath: "/preview/Sample.txt"))
        await viewModel.waitForSizeComputation()
        return viewModel
    }

    func body(content: Content, context: ConverterViewModel) -> some View {
        content.environment(context)
    }
}
#endif
