import AppKit
import SwiftUI

// MenuBarExtra sizes its window when it opens but not when the content shrinks later (mirroring
// stops, a section hides), leaving empty space around centred content. This resizes the window to
// the content's height, keeping its top edge under the menu bar.
struct WindowHeightFitter: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let height = height
        DispatchQueue.main.async {
            guard height > 0, let window = nsView.window else { return }
            let delta = height - window.contentRect(forFrameRect: window.frame).height
            guard abs(delta) > 0.5 else { return }
            var frame = window.frame
            frame.size.height += delta
            frame.origin.y -= delta
            window.setFrame(frame, display: true)
        }
    }
}
