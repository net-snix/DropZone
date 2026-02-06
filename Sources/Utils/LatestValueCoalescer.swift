import Foundation

final class LatestValueCoalescer<Value> {
    private let lock = NSLock()
    private var pendingValue: Value?
    private var isFlushScheduled = false
    private let onFlush: @MainActor (Value) -> Void

    init(onFlush: @escaping @MainActor (Value) -> Void) {
        self.onFlush = onFlush
    }

    func submit(_ value: Value) {
        lock.lock()
        pendingValue = value
        let shouldScheduleFlush = !isFlushScheduled
        if shouldScheduleFlush {
            isFlushScheduled = true
        }
        lock.unlock()

        guard shouldScheduleFlush else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.flush()
        }
    }

    @MainActor
    private func flush() {
        while true {
            let nextValue: Value?
            lock.lock()
            nextValue = pendingValue
            pendingValue = nil
            if nextValue == nil {
                isFlushScheduled = false
                lock.unlock()
                return
            }
            lock.unlock()

            if let nextValue {
                onFlush(nextValue)
            }
        }
    }
}
