// Formatters utilities - formatNumber is defined in DailyStats.swift

import SwiftUI
import AppKit

// MARK: - NSColor Extension
public extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1

        switch hex.count {
        case 3: // RGB (12-bit)
            r = CGFloat((int >> 8) * 17) / 255
            g = CGFloat((int >> 4 & 0xF) * 17) / 255
            b = CGFloat((int & 0xF) * 17) / 255
        case 6: // RGB (24-bit)
            r = CGFloat(int >> 16) / 255
            g = CGFloat(int >> 8 & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
        case 8: // ARGB (32-bit)
            a = CGFloat(int >> 24) / 255
            r = CGFloat(int >> 16 & 0xFF) / 255
            g = CGFloat(int >> 8 & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
        default:
            break
        }

        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Color Extension
public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Helpers
public extension View {
    /// 自定义开关样式
    func customToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "58a6ff")))
                .scaleEffect(0.8)
        }
    }
}

/// 自定义开关视图
public struct CustomToggle: View {
    let title: String
    @Binding var isOn: Bool

    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "58a6ff")))
                .scaleEffect(0.8)
        }
    }
}

/// 操作按钮视图
public struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    public init(_ title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }
}
