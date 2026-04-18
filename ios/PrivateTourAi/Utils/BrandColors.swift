import SwiftUI

// WCAG contrast (verified 2026-04-18): brandGold on brandNavy 5.81:1 (AA body),
// 6.7:1 in dark mode (AAA large); brandGold on brandDarkNavy 6.79:1 / 7.83:1 dark.
// White on brandNavy 13.7:1. Keep text on navy at ≥60% white opacity (5.93:1).
extension Color {
    static let brandNavy = Color("BrandNavy")
    static let brandGold = Color("AccentCoral")
    static let brandGreen = Color("BrandGreen")
    static let brandDarkNavy = Color(red: 0.08, green: 0.13, blue: 0.23)
}

extension ShapeStyle where Self == Color {
    static var brandNavy: Color { .brandNavy }
    static var brandGold: Color { .brandGold }
    static var brandGreen: Color { .brandGreen }
    static var brandDarkNavy: Color { .brandDarkNavy }
}
