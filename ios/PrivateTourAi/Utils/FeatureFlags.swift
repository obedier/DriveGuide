import Foundation

enum FeatureFlags {
    /// Whether the user has selected MapLibre + Ferrostar for navigation
    static var useFerrostarNavigation: Bool {
        UserDefaults.standard.string(forKey: "navigationEngine") == "ferrostar"
    }
}
