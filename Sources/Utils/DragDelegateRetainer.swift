import AppKit
import ObjectiveC

private var dragDelegateKey: UInt8 = 0

func retainDragDelegate(_ delegate: AnyObject, for owner: AnyObject) {
    objc_setAssociatedObject(owner, &dragDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}
