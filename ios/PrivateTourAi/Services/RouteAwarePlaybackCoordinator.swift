import Foundation
import Combine

/// Couples Ferrostar turn-by-turn navigation to tour narration so that
/// arriving at a stop auto-plays the matching segment and turn cues
/// duck the narration briefly instead of talking over it.
///
/// Designed as a passthrough: when Ferrostar isn't active, the coordinator
/// does nothing and playback behaves exactly as in 2.10.
@MainActor
final class RouteAwarePlaybackCoordinator: ObservableObject {
    @Published private(set) var isActive = false

    private let playback: TourPlaybackService
    private let tour: Tour
    private var cancellables: Set<AnyCancellable> = []
    private var lastArrivedStopIndex: Int = -1
    private var lastSpokenInstruction: String = ""

    init(playback: TourPlaybackService, tour: Tour) {
        self.playback = playback
        self.tour = tour
    }

    /// Start observing an `ArrivalProvider` — narrowed protocol lets tests
    /// inject a fake without dragging in FerrostarNavigationService.
    func attach(_ provider: any ArrivalProvider) {
        isActive = true
        cancellables.removeAll()
        lastArrivedStopIndex = -1

        provider.arrivedAtStopPublisher
            .sink { [weak self] arrivedIndex in
                self?.handleArrival(at: arrivedIndex)
            }
            .store(in: &cancellables)
    }

    func detach() {
        isActive = false
        cancellables.removeAll()
    }

    /// Exposed for tests and for the GuidedTourView to force-trigger when
    /// a stop is visited without a Ferrostar event (manual button press).
    func handleArrival(at stopIndex: Int) {
        guard stopIndex != lastArrivedStopIndex, stopIndex >= 0 else { return }
        lastArrivedStopIndex = stopIndex
        guard let segmentIndex = segmentIndex(forStopIndex: stopIndex) else { return }
        playback.audioPlayer.playSegment(at: segmentIndex)
    }

    /// Find the segment whose `toStopId` matches the stop. Falls back to
    /// sequential matching when segments don't carry toStopId (older tours).
    private func segmentIndex(forStopIndex stopIndex: Int) -> Int? {
        guard stopIndex < tour.stops.count else { return nil }
        let stopId = tour.stops[stopIndex].id
        let ordered = tour.narrationSegments.sorted { $0.sequenceOrder < $1.sequenceOrder }
        if let hit = ordered.firstIndex(where: { $0.toStopId == stopId && $0.segmentType == "at_stop" }) {
            return hit
        }
        if let hit = ordered.firstIndex(where: { $0.toStopId == stopId }) {
            return hit
        }
        // Fallback: segment at the same ordinal (intro is 0, so shift by +1).
        let fallback = stopIndex + 1
        return fallback < ordered.count ? fallback : nil
    }
}

/// Narrowed protocol — the only piece of navigation the coordinator
/// actually needs. Keeps tests independent of FerrostarNavigationService
/// and lets future navigation engines conform without subclassing.
protocol ArrivalProvider {
    /// Fires with the stop index the user just arrived at. Emit once per
    /// arrival — the coordinator dedupes repeated indices.
    var arrivedAtStopPublisher: AnyPublisher<Int, Never> { get }
}
