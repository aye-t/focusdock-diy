import AppKit
import SwiftUI

private func fdDynamicColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let mode = appearance.bestMatch(from: [.darkAqua, .aqua])
        return mode == .darkAqua ? dark : light
    })
}

extension Color {
    static let fdBackground = fdDynamicColor(
        light: NSColor(red: 0.965, green: 0.957, blue: 0.972, alpha: 1),
        dark: NSColor(red: 0.105, green: 0.102, blue: 0.125, alpha: 1)
    )
    static let fdSidebar = fdDynamicColor(
        light: NSColor(red: 0.937, green: 0.925, blue: 0.949, alpha: 1),
        dark: NSColor(red: 0.145, green: 0.140, blue: 0.170, alpha: 1)
    )
    static let fdPanel = fdDynamicColor(
        light: NSColor.white,
        dark: NSColor(red: 0.175, green: 0.170, blue: 0.205, alpha: 1)
    )
    static let fdInk = fdDynamicColor(
        light: NSColor(red: 0.16, green: 0.15, blue: 0.20, alpha: 1),
        dark: NSColor(red: 0.91, green: 0.89, blue: 0.94, alpha: 1)
    )
    static let fdMuted = fdDynamicColor(
        light: NSColor(red: 0.49, green: 0.47, blue: 0.53, alpha: 1),
        dark: NSColor(red: 0.67, green: 0.64, blue: 0.73, alpha: 1)
    )
    static let fdLine = fdDynamicColor(
        light: NSColor(red: 0.90, green: 0.88, blue: 0.92, alpha: 1),
        dark: NSColor(red: 0.30, green: 0.285, blue: 0.34, alpha: 1)
    )
    static let fdPurple = fdDynamicColor(
        light: NSColor(red: 0.46, green: 0.40, blue: 0.64, alpha: 1),
        dark: NSColor(red: 0.64, green: 0.56, blue: 0.88, alpha: 1)
    )
    static let fdPurpleSoft = fdDynamicColor(
        light: NSColor(red: 0.93, green: 0.91, blue: 0.97, alpha: 1),
        dark: NSColor(red: 0.245, green: 0.215, blue: 0.315, alpha: 1)
    )
    static let fdCoral = fdDynamicColor(
        light: NSColor(red: 0.84, green: 0.36, blue: 0.31, alpha: 1),
        dark: NSColor(red: 0.96, green: 0.46, blue: 0.40, alpha: 1)
    )
    static let fdGreen = fdDynamicColor(
        light: NSColor(red: 0.44, green: 0.59, blue: 0.52, alpha: 1),
        dark: NSColor(red: 0.48, green: 0.74, blue: 0.63, alpha: 1)
    )
    static let fdBlue = fdDynamicColor(
        light: NSColor(red: 0.31, green: 0.52, blue: 0.78, alpha: 1),
        dark: NSColor(red: 0.42, green: 0.62, blue: 0.92, alpha: 1)
    )
}

extension FloatingTint {
    var color: Color {
        switch self {
        case .purple: .fdPurple
        case .coral: .fdCoral
        case .green: Color(red: 0.31, green: 0.56, blue: 0.47)
        case .blue: Color(red: 0.30, green: 0.52, blue: 0.72)
        case .graphite: Color(red: 0.34, green: 0.32, blue: 0.37)
        }
    }

    var softColor: Color { color.opacity(0.13) }
}

struct PanelModifier: ViewModifier {
    var padding: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.fdPanel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
    }
}

extension View {
    func panel(padding: CGFloat = 22) -> some View { modifier(PanelModifier(padding: padding)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? Color.fdPurple.opacity(0.78) : Color.fdPurple)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.fdMuted)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(configuration.isPressed ? Color.fdLine : Color.fdBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Color.fdCoral : Color.fdCoral.opacity(0.85))
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(configuration.isPressed ? Color.fdCoral.opacity(0.12) : Color.fdCoral.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.fdCoral.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct EditableStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit: String? = nil
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Button {
                value = max(range.lowerBound, value - 1)
            } label: {
                Image(systemName: "minus").font(.system(size: compact ? 8 : 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.fdMuted)
            .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)
            .contentShape(Rectangle())

            TextField("", value: $value, format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .frame(width: compact ? 34 : 42, height: compact ? 20 : 24)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .background(Color.fdBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
                .onChange(of: value) { _, newValue in
                    value = min(range.upperBound, max(range.lowerBound, newValue))
                }

            if let unit {
                Text(unit).font(.system(size: compact ? 10 : 11)).foregroundStyle(Color.fdMuted)
            }

            Button {
                value = min(range.upperBound, value + 1)
            } label: {
                Image(systemName: "plus").font(.system(size: compact ? 8 : 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.fdMuted)
            .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)
            .contentShape(Rectangle())
        }
    }
}
