import SwiftUI
import TVCompanionCore

struct RemotePad: View {
    @Environment(TVController.self) private var controller
    @FocusState private var padFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Remote")
            HStack(alignment: .center, spacing: 16) {
                dPad
                    .focusable()
                    .focused($padFocused)
                    .focusEffectDisabled()
                    .onKeyPress(action: handleKey)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.accentColor.opacity(padFocused ? 0.6 : 0), lineWidth: 2)
                    }
                    .help("Click, then use the arrow keys, Return and Delete")
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        RemoteButton(symbol: "arrow.uturn.backward", help: "Back") { controller.press(.back) }
                        RemoteButton(symbol: "house.fill", help: "Home") { controller.press(.home) }
                    }
                    HStack(spacing: 8) {
                        RemoteButton(symbol: "line.3.horizontal", help: "Menu") { controller.press(.menu) }
                        RemoteButton(symbol: "gearshape.fill", help: "TV settings") { controller.press(.settings) }
                    }
                    HStack(spacing: 8) {
                        RemoteButton(symbol: "chevron.up.2", help: "Channel up") { controller.press(.channelUp) }
                        RemoteButton(symbol: "chevron.down.2", help: "Channel down") { controller.press(.channelDown) }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            TVKeyboardField()
        }
    }

    private var dPad: some View {
        ZStack {
            Circle()
                .fill(.quinary)
            VStack(spacing: 0) {
                arrow("chevron.up", .up)
                HStack(spacing: 0) {
                    arrow("chevron.left", .left)
                    Button {
                        controller.press(.center)
                    } label: {
                        Text("OK")
                            .font(.callout.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.quaternary, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    arrow("chevron.right", .right)
                }
                arrow("chevron.down", .down)
            }
        }
        .frame(width: 124, height: 124)
    }

    private func arrow(_ symbol: String, _ key: TVKey) -> some View {
        Button {
            controller.press(key)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let key: TVKey? = switch press.key {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        case .return, .space: .center
        case .delete: .back
        default: nil
        }
        guard let key else { return .ignored }
        controller.press(key)
        return .handled
    }
}

private struct RemoteButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 40, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .help(help)
    }
}
