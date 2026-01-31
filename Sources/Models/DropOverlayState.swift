import Foundation

@MainActor
final class DropOverlayState: ObservableObject {
    @Published var isVisible = false
    @Published var isTargeted = false
    @Published var isPulsing = false
    @Published var isDropHold = false

    func pulse() {
        isPulsing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isPulsing = false
        }
    }

    func beginHold() {
        isDropHold = true
    }

    func endHold() {
        isDropHold = false
    }
}
