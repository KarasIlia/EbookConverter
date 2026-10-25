import SwiftUI
import ConverterFeature

@main
struct EbookConverterApp: App {
    @State private var viewModel = ConverterViewModel()

    var body: some Scene {
        Window(Text(.appName), id: "converter") {
            ConverterRootView(viewModel: viewModel)
                .onOpenURL { url in
                    Task { await viewModel.open(url) }
                }
        }
        .windowResizability(.contentMinSize)
    }
}
