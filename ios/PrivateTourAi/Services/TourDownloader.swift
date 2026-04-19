import Foundation

/// Drives a full tour download — hits generateSegmentAudio for each segment
/// that doesn't already have a URL, fetches the audio bytes, and hands them
/// to OfflineTourStore. Progress is reported as 0.0 → 1.0 on the main actor
/// so a SwiftUI view can bind a progress bar directly.
@MainActor
final class TourDownloader: ObservableObject {
    @Published var progress: Double = 0
    @Published var isDownloading = false
    @Published var lastError: String?

    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
        isDownloading = false
    }

    /// Returns true when a download completes successfully, false on cancel or
    /// if zero segments downloaded. `onComplete` fires on success only.
    func download(tour: Tour, voiceEngine: String, voicePreference: String,
                  store: OfflineTourStore = .shared,
                  api: APIClient = .shared,
                  session: URLSession = .shared,
                  onComplete: @escaping @MainActor () -> Void = {}) {
        guard !isDownloading else { return }
        isDownloading = true
        progress = 0
        lastError = nil

        task = Task { [weak self] in
            guard let self else { return }
            let segments = tour.narrationSegments.sorted { $0.sequenceOrder < $1.sequenceOrder }
            guard !segments.isEmpty else {
                self.isDownloading = false
                self.lastError = "Tour has no narration segments"
                return
            }

            var audioMap: [String: Data] = [:]
            let total = Double(segments.count)
            var completed = 0

            for segment in segments {
                if Task.isCancelled { break }
                do {
                    let urlStr: String
                    if let existing = segment.audioUrl, !existing.isEmpty {
                        urlStr = existing
                    } else {
                        urlStr = try await api.generateSegmentAudio(
                            text: segment.narrationText,
                            contentHash: segment.contentHash,
                            voiceEngine: voiceEngine,
                            voicePreference: voicePreference
                        )
                    }
                    guard let url = URL(string: urlStr) else { continue }
                    let (data, response) = try await session.data(from: url)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 200, data.count > 100 {
                        audioMap[segment.contentHash] = data
                    }
                } catch {
                    // Continue on single-segment failure — partial downloads still
                    // yield a partially-playable offline tour.
                    print("[TourDownloader] Segment \(segment.sequenceOrder) failed: \(error)")
                }
                completed += 1
                self.progress = Double(completed) / total
            }

            if Task.isCancelled {
                self.isDownloading = false
                return
            }

            guard !audioMap.isEmpty else {
                self.isDownloading = false
                self.lastError = "No segments downloaded (check your connection)"
                return
            }

            do {
                try await store.saveTour(
                    tour, audioByContentHash: audioMap,
                    voiceEngine: voiceEngine, voicePreference: voicePreference
                )
                await store.evictIfOverBudget()
                self.isDownloading = false
                self.progress = 1.0
                onComplete()
            } catch {
                self.isDownloading = false
                self.lastError = "Failed to save tour: \(error.localizedDescription)"
            }
        }
    }
}
