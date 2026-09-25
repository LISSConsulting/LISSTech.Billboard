import AppKit
import SwiftUI
import BillboardShared

struct BillboardContentView: View {
    @ObservedObject var model: BillboardViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateGradient = false

    private var palette: ThemePalette {
        ThemePalette.resolve(model.config.theme, scheme: colorScheme)
    }

    private var direction: LayoutDirection {
        TextDirectionService.direction(for: model.config.title + "\n" + model.config.message) == .rightToLeft
            ? .rightToLeft
            : .leftToRight
    }

    var body: some View {
        ZStack {
            if model.config.modal {
                Color.black.opacity(0.76).ignoresSafeArea()
            }
            card
                .frame(
                    width: model.config.modal ? 1000 : 520,
                    height: model.config.modal ? 560 : 350)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .environment(\.openURL, OpenURLAction { url in
            guard RichTextRenderer.isAllowedLink(url) else { return .discarded }
            NSWorkspace.shared.open(url)
            return .handled
        })
        .onAppear {
            model.start()
            DispatchQueue.main.async { model.configureWindow() }
            animateGradient = true
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                if model.config.modal && model.config.illustration?.caseInsensitiveCompare("none") != .orderedSame {
                    illustrationPanel
                        .frame(width: 340)
                }
                content
            }
        }
        .background(animatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.border, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.38), radius: 32, y: 16)
    }

    private var animatedBackground: some View {
        LinearGradient(
            colors: palette.background,
            startPoint: animateGradient && palette.animated ? .topTrailing : .topLeading,
            endPoint: animateGradient && palette.animated ? .bottomLeading : .bottomTrailing)
        .animation(
            palette.animated
                ? .easeInOut(duration: 12).repeatForever(autoreverses: true)
                : nil,
            value: animateGradient)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.accentText)
                .frame(width: 32, height: 32)
                .background(palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(typeLabel)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(palette.accent)
            Spacer()
            if let logo = model.logo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 96, maxHeight: 28)
            }
            Button(action: model.dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.body)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(palette.header)
    }

    private var illustrationPanel: some View {
        VStack(spacing: 20) {
            Spacer()
            if let artwork = model.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 290, maxHeight: 360)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 150, weight: .ultraLight))
                    .foregroundStyle(palette.accent.opacity(0.82))
            }
            Spacer()
            Text((model.config.branding?.name ?? "LISS TECHNOLOGIES").uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.body.opacity(0.48))
                .padding(.bottom, 18)
        }
        .background(Color.black.opacity(palette.isDark ? 0.16 : 0.04))
    }

    private var content: some View {
        VStack(alignment: direction == .rightToLeft ? .trailing : .leading, spacing: 18) {
            Text(model.config.title)
                .font(.system(size: model.config.modal ? 27 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(palette.primary)
                .multilineTextAlignment(direction == .rightToLeft ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: direction == .rightToLeft ? .trailing : .leading)
                .environment(\.layoutDirection, direction)

            if !model.config.modal, let artwork = model.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 86)
            }

            ScrollView {
                Text(RichTextRenderer.render(model.config.message))
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(palette.body)
                    .lineSpacing(6)
                    .tint(palette.accent)
                    .multilineTextAlignment(direction == .rightToLeft ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: direction == .rightToLeft ? .trailing : .leading)
                    .environment(\.layoutDirection, direction)
            }

            if let input = model.config.input {
                inputControl(input)
            }

            Spacer(minLength: 4)

            Text(contextText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.body.opacity(0.42))
                .lineSpacing(3)

            buttonPanel
        }
        .padding(.horizontal, model.config.modal ? 40 : 28)
        .padding(.vertical, 28)
        .environment(\.layoutDirection, direction)
    }

    @ViewBuilder
    private func inputControl(_ input: InputDefinition) -> some View {
        let inputDirection: LayoutDirection = TextDirectionService.direction(
            for: model.inputText.isEmpty ? (input.placeholder ?? input.label) : model.inputText) == .rightToLeft
            ? .rightToLeft
            : .leftToRight

        VStack(alignment: inputDirection == .rightToLeft ? .trailing : .leading, spacing: 7) {
            Text(input.required ? "\(input.label) *" : input.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primary)

            if input.multiline {
                ZStack(alignment: inputDirection == .rightToLeft ? .topTrailing : .topLeading) {
                    TextEditor(text: $model.inputText)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.primary)
                        .padding(8)
                    if model.inputText.isEmpty, let placeholder = input.placeholder {
                        Text(placeholder)
                            .foregroundStyle(palette.body.opacity(0.5))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 94)
                .background(palette.input)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border.opacity(0.8)))
            } else {
                TextField(input.placeholder ?? "", text: $model.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(palette.input)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border.opacity(0.8)))
            }

            if let validation = model.validationMessage {
                Text(validation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFF6B6B))
            }
        }
        .environment(\.layoutDirection, inputDirection)
        .onChange(of: model.inputText) { _ in
            model.validationMessage = nil
            model.enforceInputLimit()
        }
    }

    private var buttonPanel: some View {
        HStack(spacing: 12) {
            ForEach(Array(model.config.buttons.enumerated()), id: \.offset) { index, button in
                Button {
                    model.select(button, index: index)
                } label: {
                    Text(button.label)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(BillboardButtonStyleView(style: button.style, palette: palette))
            }
        }
    }

    private var typeLabel: String {
        switch model.config.type {
        case .info: return "INFORMATION"
        case .warn: return "WARNING"
        case .alert: return "ALERT"
        case .critical: return "CRITICAL"
        case .question: return "QUESTION"
        }
    }

    private var symbolName: String {
        switch model.config.type {
        case .info: return "info.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .alert: return "bell.badge.fill"
        case .critical: return "xmark.octagon.fill"
        case .question: return "questionmark.circle.fill"
        }
    }

    private var contextText: String {
        let organization = model.config.branding?.name ?? "your organization"
        return "Sent by \(organization)'s endpoint management system. Contact your IT helpdesk if you need assistance."
    }
}

private struct BillboardButtonStyleView: ButtonStyle {
    let style: BillboardButtonStyle
    let palette: ThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(background(configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1.5))
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch style {
        case .primary: return palette.accentText
        case .ghost: return palette.primary
        case .danger: return .white
        }
    }

    private func background(_ pressed: Bool) -> Color {
        switch style {
        case .primary: return pressed ? palette.accentHover : palette.accent
        case .ghost: return pressed ? palette.primary.opacity(0.16) : palette.primary.opacity(0.08)
        case .danger: return pressed ? Color(hex: 0xB83F45) : Color(hex: 0xDA5657)
        }
    }

    private var border: Color {
        switch style {
        case .primary: return palette.border
        case .ghost: return palette.primary.opacity(0.28)
        case .danger: return Color(hex: 0x9F343A)
        }
    }
}
