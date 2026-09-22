import CryptoKit
import Foundation
import ImageIO
import Photos

/// Normalize width and kana without discarding meaningful dakuten or accents.
enum SearchText {
    static func normalize(_ text: String) -> String {
        let width = text.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja_JP"))
        return (width.applyingTransform(.hiraganaToKatakana, reverse: false) ?? width)
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PhotoCaptureDate {
    /// The photo library keeps this metadata locally, so this avoids downloading the image just to show a date suggestion.
    @MainActor
    static func libraryDate(for identifier: String) -> Date? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject?.creationDate
    }

    static func read(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let value = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        // Keep the photographer's local calendar day for a date-only visit field.
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }
}

struct MonthlyFoodReport {
    let visitCount: Int
    let uniquePlaceCount: Int
    let newPlaceCount: Int
    let averageRating: Double?

    init(month: Date, records: [RestaurantRecord], calendar: Calendar = .current) {
        let valid = records.filter { !$0.isDeleted && $0.status == .visited && $0.visitDate != nil }
        let interval = calendar.dateInterval(of: .month, for: month)
        let visits = valid.filter { record in
            guard let date = record.visitDate, let interval else { return false }
            return date >= interval.start && date < interval.end
        }
        let places = Set(visits.map(\.placeID))
        let previous = Set(valid.filter { ($0.visitDate ?? .distantFuture) < (interval?.start ?? .distantPast) }.map(\.placeID))
        visitCount = visits.count
        uniquePlaceCount = places.count
        newPlaceCount = places.subtracting(previous).count
        let ratings = visits.map(\.displayRating).filter { $0 > 0 }
        averageRating = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
    }
}

/// Persist only hashes, never the user's notes or photo data in preferences.
struct BackupSnapshot: Codable {
    let createdAt: Date
    let records: [String: String]
    let contentHash: String

    static func capture(metadata: Data, at date: Date = .now) throws -> BackupSnapshot {
        guard var root = try JSONSerialization.jsonObject(with: metadata) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        root.removeValue(forKey: "createdAt")
        let rows = root["records"] as? [[String: Any]] ?? []
        let places = root["places"] as? [[String: Any]] ?? []
        let tags = root["tags"] as? [[String: Any]] ?? []
        let collections = root["collections"] as? [[String: Any]] ?? []
        let entries = root["collectionEntries"] as? [[String: Any]] ?? []
        var hashes: [String: String] = [:]
        for row in rows {
            guard let id = row["id"] as? String else { continue }
            let tagIDs = Set(row["tagIDs"] as? [String] ?? [])
            let relatedEntries = entries.filter { $0["recordID"] as? String == id }
            let collectionIDs = Set(relatedEntries.compactMap { $0["collectionID"] as? String })
            let value: [String: Any] = [
                "record": row,
                "places": places.filter { $0["id"] as? String == row["placeID"] as? String },
                "photos": (root["photos"] as? [[String: Any]] ?? []).filter { $0["recordID"] as? String == id },
                "menus": (root["menuItems"] as? [[String: Any]] ?? []).filter { $0["recordID"] as? String == id },
                "tags": tags.filter { tagIDs.contains($0["id"] as? String ?? "") },
                "collections": collections.filter { collectionIDs.contains($0["id"] as? String ?? "") },
                "entries": relatedEntries
            ]
            hashes[id] = try digest(value)
        }
        return try BackupSnapshot(createdAt: date, records: hashes, contentHash: digest(root))
    }

    func changes(since previous: BackupSnapshot) -> (added: Int, updated: Int, removed: Int) {
        let added = records.keys.filter { previous.records[$0] == nil }.count
        let updated = records.keys.filter { previous.records[$0] != nil && previous.records[$0] != records[$0] }.count
        let removed = previous.records.keys.filter { records[$0] == nil }.count
        return (added, updated, removed)
    }

    private static func digest(_ value: Any) throws -> String {
        // Query order is unspecified. Sort model arrays by their stable identifier.
        func stable(_ value: Any) -> Any {
            if let object = value as? [String: Any] { return object.mapValues(stable) }
            if let array = value as? [[String: Any]] {
                return array.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }.map { stable($0) }
            }
            return value
        }
        let data = try JSONSerialization.data(withJSONObject: stable(value), options: [.sortedKeys])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
