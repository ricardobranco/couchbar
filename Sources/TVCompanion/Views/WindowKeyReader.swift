import AppKit
import SwiftUI

// MenuBarExtra content keeps its view alive between openings, so onAppear fires only once;
// the hosting window's key state tells when the popup is actually open.
struct WindowKeyReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView(onChange: onChange)
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        private let onChange: @MainActor (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onChange: @escaping @MainActor (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            let onChange = onChange
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { onChange(true) }
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { onChange(false) }
                },
            ]
            onChange(window.isKeyWindow)
        }
    }
}
