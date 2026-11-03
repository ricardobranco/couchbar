import SwiftUI

/// Once paired, mirrors the text field focused on the TV, like the Google Home keyboard.
/// Before that, text goes over adb when sent.
struct TVKeyboardField: View {
    @Environment(TVController.self) private var controller
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        if controller.isKeyboardConnected {
            liveField
        } else {
            HStack(spacing: 6) {
                TextField("Type on the TV…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(text.isEmpty)
            }
        }
    }

    private var liveField: some View {
        let field = controller.tvTextField
        return HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .foregroundStyle(field == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            TextField(
                "Type on the TV",
                text: Binding(get: { field?.value ?? "" }, set: { controller.setTVText($0) }),
                prompt: Text(prompt(for: field))
            )
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .disabled(field == nil)
            .onSubmit { controller.submitTVText() }
        }
        .onChange(of: field != nil) { _, isOpen in
            focused = isOpen
        }
        .help(field == nil ? "Select a text field on the TV to type into it" : "Typing here edits the TV's text field")
    }

    private func prompt(for field: TVController.TextField?) -> String {
        guard let field else { return "Select a text field on the TV" }
        return field.label.isEmpty ? "Type on the TV…" : field.label
    }

    private func send() {
        controller.sendText(text)
        text = ""
    }
}
