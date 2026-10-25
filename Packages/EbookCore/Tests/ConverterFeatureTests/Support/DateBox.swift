import Foundation
import Synchronization

/// Thread-safe recorder for dates passed to a converter factory.
final class DateBox: Sendable {
    private let storage = Mutex<[Date]>([])

    var values: [Date] { storage.withLock { $0 } }

    func append(_ date: Date) {
        storage.withLock { $0.append(date) }
    }
}
