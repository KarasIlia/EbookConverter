/// Polls `condition` every 10 ms until it holds or about 5 seconds pass.
@MainActor func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<500 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
