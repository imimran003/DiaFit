import SwiftUI

extension Color {
    static let paper = Color(red: 0.97, green: 0.955, blue: 0.925)
    static let ink = Color(red: 0.105, green: 0.115, blue: 0.11)
    static let quietInk = Color(red: 0.36, green: 0.37, blue: 0.34)
    static let rule = Color(red: 0.81, green: 0.79, blue: 0.73)
    static let lime = Color(red: 0.67, green: 0.91, blue: 0.29)
    static let coral = Color(red: 0.91, green: 0.34, blue: 0.25)
    static let lavender = Color(red: 0.72, green: 0.67, blue: 0.96)
    static let saffron = Color(red: 0.96, green: 0.74, blue: 0.25)
    static let mist = Color(red: 0.91, green: 0.91, blue: 0.86)
}

enum DiafitType {
    static let display = Font.system(size: 34, weight: .medium, design: .serif)
    static let day = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
    static let metric = Font.system(size: 25, weight: .bold, design: .rounded)
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
