// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct DiscoveryCandidate {
    let deviceID: String?
    let name: String
    let direct: Bool
    let trusted: Bool
}

/// Discovery is availability, not a distance measurement or authentication.
/// Dismissed/presented device IDs stay quiet until an explicit new search.
struct DiscoverySuggestions {
    private var offered = Set<String>()
    private var paused = false

    mutating func reset() { offered.removeAll(); paused = false }
    mutating func pause() { paused = true }
    mutating func didOffer(_ id: String) { offered.insert(id) }

    func next(in candidates: [DiscoveryCandidate], localID: String,
              enabled: Bool, host: Bool, busy: Bool, editingCode: Bool) -> String? {
        guard enabled, host, !busy, !editingCode, !paused else { return nil }
        return candidates.filter {
            guard let id = $0.deviceID else { return false }
            return $0.direct && id != localID && !offered.contains(id)
        }.sorted {
            if $0.trusted != $1.trusted { return $0.trusted }
            if $0.name != $1.name { return $0.name < $1.name }
            return ($0.deviceID ?? "") < ($1.deviceID ?? "")
        }.first?.deviceID
    }
}
