#if canImport(UIKit)
import SwiftUI
import UIKit

/// Reports where a long press landed, in the coordinates of the view it is
/// attached to.
///
/// SwiftUI's `LongPressGesture` says only that it fired, never where, and a
/// zero-distance drag sequenced after it to find out never reports a finger
/// that has not moved — which is exactly the finger a long press ends with.
/// UIKit's recognizer carries the location, so this takes it from there.
///
/// The recognizer hangs off the enclosing scroll view rather than off a view of
/// its own: a view large enough to catch every press would also swallow the
/// taps the grid below it needs, and one that lets them through cannot be
/// pressed. This view is only a coordinate frame — it never takes a touch.
struct LongPressLocator: UIViewRepresentable {
    var minimumDuration: TimeInterval = 0.45
    var onPress: (CGPoint) -> Void

    func makeUIView(context: Context) -> FrameView {
        context.coordinator.view
    }

    func updateUIView(_ view: FrameView, context: Context) {
        context.coordinator.onPress = onPress
        context.coordinator.press.minimumPressDuration = minimumDuration
        // Also tried here because the scroll view is not always an ancestor yet
        // the first time the frame lands in a window.
        context.coordinator.attach()
    }

    static func dismantleUIView(_ view: FrameView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPress: onPress) }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let view = FrameView()
        let press = UILongPressGestureRecognizer()
        var onPress: (CGPoint) -> Void

        init(onPress: @escaping (CGPoint) -> Void) {
            self.onPress = onPress
            super.init()
            press.addTarget(self, action: #selector(handle(_:)))
            // The scroll view keeps its pan and the grid keeps its taps: this
            // recognizer only listens.
            press.cancelsTouchesInView = false
            press.delaysTouchesBegan = false
            press.delegate = self
            view.onEnterWindow = { [weak self] in self?.attach() }
        }

        func attach() {
            guard press.view == nil, let host = view.enclosingScrollView else { return }
            host.addGestureRecognizer(press)
        }

        func detach() {
            press.view?.removeGestureRecognizer(press)
        }

        @objc private func handle(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            onPress(recognizer.location(in: view))
        }

        nonisolated func gestureRecognizer(
            _: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// Text fields keep their own press menu.
        nonisolated func gestureRecognizer(
            _: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            MainActor.assumeIsolated {
                var candidate = touch.view
                while let view = candidate {
                    if view is UITextField || view is UITextView { return false }
                    candidate = view.superview
                }
                return true
            }
        }
    }

    /// A frame to measure presses against, and nothing else.
    final class FrameView: UIView {
        var onEnterWindow: (() -> Void)?

        /// Never takes a touch: everything under it stays reachable.
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onEnterWindow?() }
        }

        var enclosingScrollView: UIScrollView? {
            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? UIScrollView { return scrollView }
                candidate = view.superview
            }
            return nil
        }
    }
}
#endif
