import AppKit
import SwiftUI

enum Theme {
    static let ink = Color(red: 0.145, green: 0.102, blue: 0.086)
    static let sidebar = Color(red: 0.145, green: 0.110, blue: 0.094)
    static let sidebarRaised = Color.white.opacity(0.05)
    static let paper = Color(red: 0.918, green: 0.867, blue: 0.792)
    static let paperDeep = Color(red: 0.875, green: 0.812, blue: 0.722)
    static let cinnabar = Color(red: 0.78, green: 0.22, blue: 0.16)
    static let gold = Color(red: 0.78, green: 0.64, blue: 0.40)
    static let cream = Color(red: 0.965, green: 0.945, blue: 0.910)
    static let muted = Color(red: 0.67, green: 0.60, blue: 0.52)
    static let line = Color.white.opacity(0.08)

    static func stoneNSColor(_ stone: StoneColor) -> NSColor {
        switch stone {
        case .cinnabar: NSColor(srgbRed: 0.62, green: 0.18, blue: 0.13, alpha: 1)
        case .tianhuang: NSColor(srgbRed: 0.74, green: 0.50, blue: 0.20, alpha: 1)
        case .qingtian: NSColor(srgbRed: 0.36, green: 0.52, blue: 0.47, alpha: 1)
        case .ebony: NSColor(srgbRed: 0.16, green: 0.13, blue: 0.12, alpha: 1)
        }
    }
}

struct SealMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Theme.cinnabar)
            Circle().stroke(Theme.gold.opacity(0.85), lineWidth: max(1, size * 0.035))
                .padding(size * 0.08)
            Text("印")
                .font(.custom("STKaitiSC-Black", size: size * 0.46))
                .foregroundStyle(Theme.cream)
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
    }
}
