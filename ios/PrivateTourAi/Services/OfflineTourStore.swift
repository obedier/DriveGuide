import Foundation

/// Persistent offline cache for whole tours — tour JSON + every segment's
/// audio data — so downloaded tours keep working with the network off.
///
/// Layout on disk (all under `.documentDirectory/OfflineTours/`):
///
///   <tourId>/tour.json          full Tour serialized
///   <tourId>/manifest.json      metadata (download date, total bytes, segment hashes)
///   <tourId>/segments/<hash>.mp3 one file per NarrationSegment
///
/// Why an actor: downloads happen from background tasks while playback reads
/// cached audio on the main actor. The actor serializes those reads/writes
/// without us having to reason about dispatch queues.
actor OfflineTourStore {
    static let shared = OfflineTourStore()

    struct SegmentEntry: Codable, Sendable {
        var index: Int
        var contentHash: String
        var sizeBytes: Int64
    }

    struct Manifest: Codable, Sendable {
        var tourId: String
        var tourTitle: String
        var downloadedAt: Date
        var segments: [SegmentEntry]
        var totalBytes: Int64
        var voiceEngine: String
        var voicePreference: String
    }

    enum OfflineError: Error {
        case downloadFailed(segmentIndex: Int, underlying: Error?)
        case notDownloaded(tourId: String)
        case manifestCorrupt(tourId: String)
    }

    /// Root directory — injectable so tests can use a temp dir.
    private let root: URL

    init(root: URL? = nil) {
        let computed = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OfflineTours", isDirectory: true)
        self.root = computed
        try? FileManager.default.createDirectory(at: computed, withIntermediateDirectories: true)
    }

    // MARK: - Paths

    private func tourDir(_ tourId: String) -> URL {
        root.appendingPathComponent(tourId, isDirectory: true)
    }

    private func tourJsonURL(_ tourId: String) -> URL {
        tourDir(tourId).appendingPathComponent("tour.json")
    }

    private func manifestURL(_ tourId: String) -> URL {
        tourDir(tourId).appendingPathComponent("manifest.json")
    }

    private func segmentsDir(_ tourId: String) -> URL {
        tourDir(tourId).appendingPathComponent("segments", isDirectory: true)
    }

    private func segmentURL(tourId: String, contentHash: String) -> URL {
        segmentsDir(tourId).appendingPathComponent("\(contentHash).mp3")
    }

    // MARK: - Query

    func isDownloaded(tourId: String) -> Bool {
        FileManager.default.fileExists(atPath: manifestURL(tourId).path)
    }

    func manifest(for tourId: String) throws -> Manifest {
        let url = manifestURL(tourId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OfflineError.notDownloaded(tourId: tourId)
        }
        do {
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(Manifest.self, from: data)
        } catch {
            throw OfflineError.manifestCorrupt(tourId: tourId)
        }
    }

    /// Custom encoders/decoders that preserve sub-second precision so two
    /// downloads that happen milliseconds apart sort deterministically.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    func loadTour(tourId: String) throws -> Tour {
        let url = tourJsonURL(tourId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OfflineError.notDownloaded(tourId: tourId)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Tour.self, from: data)
    }

    /// Audio bytes for a segment, addressed by contentHash (stable even if segment
    /// order changes in a later tour regen).
    func audioData(tourId: String, contentHash: String) -> Data? {
        try? Data(contentsOf: segmentURL(tourId: tourId, contentHash: contentHash))
    }

    /// All cached audio for a tour, ordered to match the tour's segments.
    /// Missing files yield Data() so `AudioPlayerService.hasAudio` semantics
    /// still apply (anything < 100 bytes = unplayable).
    func allAudioData(for tour: Tour) -> [Data] {
        let ordered = tour.narrationSegments.sorted { $0.sequenceOrder < $1.sequenceOrder }
        return ordered.map { seg in
            audioData(tourId: tour.id, contentHash: seg.contentHash) ?? Data()
        }
    }

    func allDownloadedManifests() -> [Manifest] {
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")) else { return nil }
            return try? Self.decoder.decode(Manifest.self, from: data)
        }
        .sorted { $0.downloadedAt > $1.downloadedAt }
    }

    func totalBytes() -> Int64 {
        allDownloadedManifests().reduce(0) { $0 + $1.totalBytes }
    }

    // MARK: - Write

    /// Save a Tour + its pre-downloaded audio bytes (typically fetched by the
    /// caller from the network). `audioByContentHash` must be keyed by the
    /// segment's contentHash.
    ///
    /// Separating the network fetch from the disk write keeps this type
    /// unit-testable without any URL mocking.
    func saveTour(_ tour: Tour, audioByContentHash: [String: Data],
                  voiceEngine: String, voicePreference: String) throws {
        let tourId = tour.id
        try FileManager.default.createDirectory(at: segmentsDir(tourId), withIntermediateDirectories: true)

        var entries: [SegmentEntry] = []
        var totalBytes: Int64 = 0
        let ordered = tour.narrationSegments.sorted { $0.sequenceOrder < $1.sequenceOrder }

        for (i, seg) in ordered.enumerated() {
            guard let data = audioByContentHash[seg.contentHash], data.count > 100 else { continue }
            let url = segmentURL(tourId: tourId, contentHash: seg.contentHash)
            try data.write(to: url, options: .atomic)
            entries.append(SegmentEntry(index: i, contentHash: seg.contentHash, sizeBytes: Int64(data.count)))
            totalBytes += Int64(data.count)
        }

        let tourData = try JSONEncoder().encode(tour)
        try tourData.write(to: tourJsonURL(tourId), options: .atomic)

        let manifest = Manifest(
            tourId: tourId,
            tourTitle: tour.title,
            downloadedAt: Date(),
            segments: entries,
            totalBytes: totalBytes,
            voiceEngine: voiceEngine,
            voicePreference: voicePreference
        )
        try Self.encoder.encode(manifest).write(to: manifestURL(tourId), options: .atomic)
    }

    func delete(tourId: String) throws {
        let dir = tourDir(tourId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    /// Evict least-recently-downloaded tours until totalBytes is under the cap.
    /// Called after a successful download so we don't unbound disk growth.
    @discardableResult
    func evictIfOverBudget(maxBytes: Int64 = 500_000_000) -> [String] {
        var removed: [String] = []
        var manifests = allDownloadedManifests().sorted { $0.downloadedAt < $1.downloadedAt }  // oldest first
        var total = manifests.reduce(0) { $0 + $1.totalBytes }
        while total > maxBytes, let oldest = manifests.first {
            try? delete(tourId: oldest.tourId)
            removed.append(oldest.tourId)
            total -= oldest.totalBytes
            manifests.removeFirst()
        }
        return removed
    }
}
