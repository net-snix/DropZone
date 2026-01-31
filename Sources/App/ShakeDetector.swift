import CoreGraphics
import QuartzCore

final class ShakeDetector {
    private struct Sample {
        let point: CGPoint
        let time: CFTimeInterval
    }

    private var samples: [Sample] = []
    private var lastShakeTime: CFTimeInterval = 0

    private let window: CFTimeInterval = 0.45
    private let cooldown: CFTimeInterval = 0.8
    private let minDirectionChanges = 3
    private let minTotalDelta: CGFloat = 140
    private let minStep: CGFloat = 8

    func reset() {
        samples.removeAll()
        lastShakeTime = 0
    }

    func ingest(point: CGPoint, time: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        samples.append(Sample(point: point, time: time))
        prune(before: time - window)

        guard time - lastShakeTime > cooldown else { return false }
        guard samples.count >= 4 else { return false }

        var lastSign: CGFloat = 0
        var changes = 0
        var totalAbsDx: CGFloat = 0

        for idx in 1..<samples.count {
            let dx = samples[idx].point.x - samples[idx - 1].point.x
            let absDx = abs(dx)
            guard absDx >= minStep else { continue }
            totalAbsDx += absDx
            let sign: CGFloat = dx > 0 ? 1 : -1
            if lastSign != 0, sign != lastSign {
                changes += 1
            }
            lastSign = sign
        }

        guard changes >= minDirectionChanges, totalAbsDx >= minTotalDelta else { return false }
        lastShakeTime = time
        return true
    }

    private func prune(before time: CFTimeInterval) {
        if let firstIndex = samples.firstIndex(where: { $0.time >= time }) {
            if firstIndex > 0 {
                samples.removeFirst(firstIndex)
            }
        } else {
            samples.removeAll()
        }
    }
}
