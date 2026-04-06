import Foundation
import SwiftUI

@MainActor
class TourViewModel: ObservableObject {
    @Published var currentPreview: TourPreview?
    @Published var currentTour: Tour?
    @Published var isGenerating = false
    @Published var generationProgress: String = ""
    @Published var error: String?

    // Input state
    @Published var searchText = ""
    @Published var selectedDuration: Int = 60
    @Published var selectedThemes: Set<String> = []

    let durations = [30, 60, 90, 120, 180, 240, 360]
    let availableThemes = ["history", "food", "scenic", "hidden-gems", "architecture", "culture", "nature", "nightlife"]

    func generatePreview() async {
        guard !searchText.isEmpty else { return }

        isGenerating = true
        error = nil
        generationProgress = "Researching \(searchText)..."

        do {
            generationProgress = "Finding the best stops..."
            let preview = try await APIClient.shared.generatePreview(
                location: searchText,
                durationMinutes: selectedDuration,
                themes: Array(selectedThemes)
            )

            generationProgress = "Tour ready!"
            currentPreview = preview
        } catch {
            self.error = error.localizedDescription
        }

        isGenerating = false
        generationProgress = ""
    }

    func generateFullTour() async {
        guard !searchText.isEmpty else { return }

        isGenerating = true
        error = nil
        generationProgress = "Crafting your personalized tour..."

        do {
            let response = try await APIClient.shared.generateTour(
                location: searchText,
                durationMinutes: selectedDuration,
                themes: Array(selectedThemes)
            )

            if let tour = response.tour {
                currentTour = tour
                generationProgress = "Tour ready!"
            } else if let preview = response.preview {
                currentPreview = preview
                generationProgress = "Preview ready! Sign up for the full tour."
            }
        } catch {
            self.error = error.localizedDescription
        }

        isGenerating = false
        generationProgress = ""
    }

    func clearTour() {
        currentPreview = nil
        currentTour = nil
        error = nil
    }

    func openInGoogleMaps() {
        guard let url = currentTour?.mapsDirectionsUrl,
              let mapsUrl = URL(string: url) else { return }
        UIApplication.shared.open(mapsUrl)
    }

    var durationLabel: String {
        if selectedDuration < 60 {
            return "\(selectedDuration) min"
        } else {
            let hours = selectedDuration / 60
            let mins = selectedDuration % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
    }
}
