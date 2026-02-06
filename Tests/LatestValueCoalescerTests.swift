import Foundation
import XCTest
@testable import DropZone

final class LatestValueCoalescerTests: XCTestCase {
    func testSubmitCoalescesBurstToLatestValue() async {
        let recorder = await MainActor.run { MainActorRecorder<Int>() }

        let coalescer = LatestValueCoalescer<Int> { value in
            recorder.values.append(value)
        }

        await MainActor.run {
            for value in 1...100 {
                coalescer.submit(value)
            }
        }

        try? await Task.sleep(for: .milliseconds(50))
        let values = await MainActor.run { recorder.values }
        XCTAssertEqual(values, [100])
    }

    func testSubmitSupportsMultipleFlushCycles() async {
        let recorder = await MainActor.run { MainActorRecorder<Int>() }

        let coalescer = LatestValueCoalescer<Int> { value in
            recorder.values.append(value)
        }

        await MainActor.run {
            coalescer.submit(1)
            coalescer.submit(2)
        }
        try? await Task.sleep(for: .milliseconds(50))

        await MainActor.run {
            coalescer.submit(3)
            coalescer.submit(4)
        }
        try? await Task.sleep(for: .milliseconds(50))

        let values = await MainActor.run { recorder.values }
        XCTAssertEqual(values, [2, 4])
    }
}

@MainActor
private final class MainActorRecorder<Value> {
    var values: [Value] = []
}
