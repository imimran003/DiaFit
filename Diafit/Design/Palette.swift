import SwiftUI
import UIKit

extension Color {
    static let paper = adaptive(light: (0.97, 0.955, 0.925), dark: (0.075, 0.078, 0.072))
    static let ink = adaptive(light: (0.105, 0.115, 0.11), dark: (0.93, 0.925, 0.89))
    static let quietInk = adaptive(light: (0.36, 0.37, 0.34), dark: (0.66, 0.66, 0.62))
    static let rule = adaptive(light: (0.81, 0.79, 0.73), dark: (0.25, 0.25, 0.22))
    static let lime = Color(red: 0.67, green: 0.91, blue: 0.29)
    static let coral = Color(red: 0.91, green: 0.34, blue: 0.25)
    static let lavender = Color(red: 0.72, green: 0.67, blue: 0.96)
    static let saffron = Color(red: 0.96, green: 0.74, blue: 0.25)
    static let mist = adaptive(light: (0.91, 0.91, 0.86), dark: (0.16, 0.165, 0.15))

    private static func adaptive(
        light: (red: CGFloat, green: CGFloat, blue: CGFloat),
        dark: (red: CGFloat, green: CGFloat, blue: CGFloat)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
        })
    }
}

enum DiafitType {
    static let display = Font.system(.largeTitle, design: .serif, weight: .medium)
    static let day = Font.system(.headline, design: .rounded, weight: .semibold)
    static let title = Font.system(.title3, design: .rounded, weight: .semibold)
    static let body = Font.system(.body, design: .rounded, weight: .regular)
    static let caption = Font.system(.caption, design: .rounded, weight: .medium)
    static let metric = Font.system(.title2, design: .rounded, weight: .bold)
}

struct PaperCard: ViewModifier {
    var radius: CGFloat = 28
    var fill: Color = .white.opacity(0.72)

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 22, y: 11)
    }
}

extension View {
    func paperCard(radius: CGFloat = 28, fill: Color = .white.opacity(0.72)) -> some View {
        modifier(PaperCard(radius: radius, fill: fill))
    }
}
