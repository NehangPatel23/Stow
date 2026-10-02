import AppKit
import SwiftUI

@MainActor
final class LaunchController: NSObject {
    private let model: AppModel
    private let window: NSWindow
    private let state = LaunchState()
    var onFinished: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let root = LaunchRootView(model: model, state: state) { [weak self] in
            self?.finish()
        }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = window.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        window.contentView = host
    }

    func start() {
        window.center()
        window.alphaValue = 0
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            window.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            MainActor.assumeIsolated {
                self?.advance()
            }
        }
    }

    private func advance() {
        if model.showingFirstRun {
            state.phase = .onboarding
            resize(to: NSSize(width: 480, height: 560))
        } else {
            finish()
        }
    }

    private func resize(to size: NSSize) {
        var frame = window.frame
        frame.origin.x -= (size.width - frame.width) / 2
        frame.origin.y -= (size.height - frame.height) / 2
        frame.size = size
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    private func finish() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.45
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.window.orderOut(nil)
                self?.onFinished?()
            }
        })
    }
}

@MainActor
@Observable
final class LaunchState {
    var phase: LaunchPhase = .splash
}

enum LaunchPhase: Equatable {
    case splash
    case onboarding
}

struct LaunchRootView: View {
    @Bindable var model: AppModel
    @Bindable var state: LaunchState
    var onFinished: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = Theme(scheme: scheme)
        ZStack {
            theme.background
            switch state.phase {
            case .splash:
                SplashView(theme: theme)
                    .transition(.opacity)
            case .onboarding:
                OnboardingView(model: model, theme: theme, onFinished: onFinished)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: state.phase)
    }
}

private struct SplashView: View {
    var theme: Theme
    @State private var appear = false
    @State private var progress: CGFloat = 0.12

    var body: some View {
        VStack(spacing: 16) {
            AppIconMark(size: 84)
                .scaleEffect(appear ? 1 : 0.86)
                .opacity(appear ? 1 : 0)
            VStack(spacing: 4) {
                Text("Stow")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("History stays on this Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondary)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 8)
            Capsule()
                .fill(theme.chip)
                .frame(width: 120, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 120 * progress, height: 4)
                }
                .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 1.05, dampingFraction: 0.86)) {
                appear = true
            }
            withAnimation(.easeInOut(duration: 2.4)) {
                progress = 1
            }
        }
    }
}

private struct OnboardingView: View {
    @Bindable var model: AppModel
    var theme: Theme
    var onFinished: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                AppIconMark(size: 28)
                Spacer()
                Text("\(step + 1) of \(pages.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondary)
            }
            .padding(.bottom, 22)
            ZStack(alignment: .topLeading) {
                page(pages[step])
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: step)
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? theme.accent : theme.chip)
                        .frame(width: index == step ? 18 : 6, height: 6)
                        .animation(.snappy(duration: 0.2), value: step)
                }
            }
            .padding(.bottom, 16)
            HStack(spacing: 8) {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if step == pages.count - 1 {
                    Button("Open Accessibility Settings") { AccessibilityClient.openSettings() }
                    Button("Continue") { complete() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
    }

    private func complete() {
        model.finishFirstRun()
        onFinished()
    }

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                symbol: "lock.shield",
                title: "History stays on this Mac.",
                message: "Stow keeps what you copy in a private library on this computer. There is no account, and nothing is sent anywhere."
            ),
            OnboardingPage(
                symbol: "keyboard",
                title: "Open it with \(model.activeHotkeyLabel).",
                message: "The shortcut works from any app. Stow opens just large enough for the clips you have, beside the pointer."
            ),
            OnboardingPage(
                symbol: "return",
                title: "Return copies. Option-Return pastes.",
                message: "Paste goes back into the app you were using. Shift-Option-Return pastes plain text, which is what terminals and editors want."
            ),
            OnboardingPage(
                symbol: "hand.raised",
                title: "Pasting needs Accessibility.",
                message: "macOS asks for that permission so Stow can type the clip back. Password-manager copies are ignored. A private key, card number, or token is skipped until you keep it."
            ),
        ]
    }

    private func page(_ page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: page.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.chipActive))
            Text(page.title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(page.message)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingPage {
    var symbol: String
    var title: String
    var message: String
}
