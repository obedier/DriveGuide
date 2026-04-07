import SwiftUI

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
