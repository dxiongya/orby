import Cocoa
import SwiftUI

/// Bridges AppKit coordinate system to SwiftUI
/// Gets the mouse position in the SwiftUI view's own coordinate space
struct MouseCaptureView: NSViewRepresentable {
    let onCaptured: (CGPoint, CGSize) -> Void

    func makeNSView(context: Context) -> _MouseCaptureNSView {
        let view = _MouseCaptureNSView()
        view.onCaptured = onCaptured
        return view
    }

    func updateNSView(_ nsView: _MouseCaptureNSView, context: Context) {}
}

class _MouseCaptureNSView: NSView {
    var onCaptured: ((CGPoint, CGSize) -> Void)?
    private var didCapture = false

    override func layout() {
        super.layout()
        capture()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Retry after a brief delay to ensure layout is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.capture()
        }
    }

    private func capture() {
        guard !didCapture, let window = window, bounds.width > 0, bounds.height > 0 else { return }
        didCapture = true

        let screenMouse = NSEvent.mouseLocation
        let windowMouse = window.convertPoint(fromScreen: screenMouse)
        let localMouse = convert(windowMouse, from: nil)
        // NSView: (0,0) at bottom-left → SwiftUI: (0,0) at top-left
        let flipped = CGPoint(x: localMouse.x, y: bounds.height - localMouse.y)
        let size = CGSize(width: bounds.width, height: bounds.height)

        NSLog("[MouseCapture] screen=(%.0f,%.0f) window=(%.0f,%.0f) local=(%.0f,%.0f) flipped=(%.0f,%.0f) bounds=%.0fx%.0f",
              screenMouse.x, screenMouse.y,
              windowMouse.x, windowMouse.y,
              localMouse.x, localMouse.y,
              flipped.x, flipped.y,
              bounds.width, bounds.height)

        DispatchQueue.main.async {
            self.onCaptured?(flipped, size)
        }
    }
}
