import Foundation
import SwiftData

enum RecordStatus: String, CaseIterable, Codable, Identifiable {
    case visited, wantToGo
    var id: String { rawValue }
    var title: String { switch self { case .visited: "行った"; case .wantToGo: "行きたい" } }
}

enum PriceTier: Int, CaseIterable, Identifiable {
    case upTo999 = 1
    case from1000To2999
    case from3000To4999
    case from5000To9999
    case from10000To19999
    case from20000

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .upTo999: "〜¥999"
        case .from1000To2999: "¥1,000〜¥2,999"
        case .from3000To4999: "¥3,000〜¥4,999"
        case .from5000To9999: "¥5,000〜¥9,999"
        case .from10000To19999: "¥10,000〜¥19,999"
        case .from20000: "¥20,000〜"
        }
    }

    static func label(for rawValue: Int?) -> String? {
        guard let rawValue else { return nil }
        return Self(rawValue: rawValue)?.label
    }
}

enum Visibility: String, CaseIterable, Codable, Identifiable {
    case `private`, link, `public`
    var id: String { rawValue }
    var title: String { switch self { case .private: "自分のみ"; case .link: "リンクを知る人"; case .public: "全体公開" } }
}

enum InitialReleasePrivacy {
    static let visibilityRaw = Visibility.private.rawValue

    static func apply(to record: RestaurantRecord) {
        record.visibilityRaw = visibilityRaw
        record.placeVisibilityRaw = visibilityRaw
        record.ratingVisibilityRaw = visibilityRaw
        record.photoVisibilityRaw = visibilityRaw
        record.memoVisibilityRaw = visibilityRaw
    }

    static func apply(to collection: Collection) {
        collection.visibilityRaw = visibilityRaw
    }

    static func apply(to settings: AppSettings) {
        settings.defaultVisibilityRaw = visibilityRaw
    }

    @MainActor
    static func normalize(in context: ModelContext) throws {
        try context.fetch(FetchDescriptor<RestaurantRecord>()).forEach(apply)
        try context.fetch(FetchDescriptor<Collection>()).forEach(apply)
        try context.fetch(FetchDescriptor<AppSettings>()).forEach(apply)
        try context.save()
    }
}

@Model final class LocalUserProfile {
    var id: UUID = UUID(); var displayName: String = "グルメップユーザー"; var username: String = "local-user"; var bio: String = ""; var profileImagePath: String?; var createdAt: Date = Date(); var defaultVisibilityRaw: String = "private"
    init() {}
}

@Model final class Place {
    var nextMealNote: String = ""
    var wantsToReturn: Bool = false
    var id: UUID = UUID(); var externalPlaceID: String?; var name: String = ""; var address: String = ""; var area: String = ""; var latitude: Double = 0; var longitude: Double = 0; var phoneNumber: String = ""; var websiteURL: String = ""; var category: String = ""; var openingHours: String = ""; var createdAt: Date = Date()
    init(name: String, address: String = "", latitude: Double = 0, longitude: Double = 0, externalPlaceID: String? = nil, category: String = "") { self.name = name; self.address = address; self.area = Self.area(from: address); self.latitude = latitude; self.longitude = longitude; self.externalPlaceID = externalPlaceID; self.category = category }
    static func area(from address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = trimmed.firstIndex(of: ",") { return String(trimmed[..<comma]).trimmingCharacters(in: .whitespaces) }
        let prefectures = ["東京都", "北海道", "大阪府", "京都府", "神奈川県", "埼玉県", "千葉県", "愛知県", "福岡県", "兵庫県", "静岡県"]
        if let prefecture = prefectures.first(where: { trimmed.hasPrefix($0) }) { return prefecture }
        return trimmed.components(separatedBy: .whitespaces).first ?? ""
    }

    /// 市区町村より細かい住所をまとめ、年間レポートのエリア集計に使います。
    static func municipality(from address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cityWithWardPattern = "(?:都|道|府|県)([^0-9\\s]+?市(?:[^0-9\\s]+?区)?)"
        if let range = trimmed.range(of: cityWithWardPattern, options: .regularExpression) {
            return String(trimmed[range].dropFirst())
        }

        let wardPattern = "(?:都|道|府|県)([^0-9\\s]+?区)"
        if let range = trimmed.range(of: wardPattern, options: .regularExpression) {
            return String(trimmed[range].dropFirst())
        }
        return nil
    }
}

@Model final class RestaurantRecord {
    var id: UUID = UUID(); var placeID: UUID = UUID(); var statusRaw: String = "wantToGo"; var rating: Int = 0; var ratingHalfSteps: Int = 0; var memo: String = ""; var relatedLinks: [String] = []; var visitDate: Date?; var price: Int?; var visibilityRaw: String = "private"; var isFavorite = false; var isDeleted = false; var deletedAt: Date?; var tagIDs: [UUID] = []; var companions: [String] = []; var placeVisibilityRaw: String = "private"; var ratingVisibilityRaw: String = "private"; var photoVisibilityRaw: String = "private"; var memoVisibilityRaw: String = "private"; var createdAt: Date = Date(); var updatedAt: Date = Date()
    init(placeID: UUID, status: RecordStatus) { self.placeID = placeID; self.statusRaw = status.rawValue }
    var status: RecordStatus { get { RecordStatus(rawValue: statusRaw) ?? .wantToGo } set { statusRaw = newValue.rawValue; updatedAt = .now } }
    /// Preserves ratings of records created before half-star ratings were introduced.
    var displayRating: Double { ratingHalfSteps > 0 ? Double(ratingHalfSteps) / 2 : Double(rating) }
    var ratingText: String {
        let value = displayRating
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

@Model final class RecordPhoto {
    var id: UUID = UUID(); var recordID: UUID = UUID(); var imagePath: String = ""; var thumbnailPath: String = ""; var order: Int = 0; var takenAt: Date?; var latitude: Double?; var longitude: Double?
    init(recordID: UUID, imagePath: String, thumbnailPath: String, order: Int) { self.recordID = recordID; self.imagePath = imagePath; self.thumbnailPath = thumbnailPath; self.order = order }
}

@Model final class RecordMenuItem {
    var id: UUID = UUID(); var recordID: UUID = UUID(); var name: String = ""; var price: Int?; var note: String = ""; var order: Int = 0
    init(recordID: UUID, name: String, price: Int? = nil, note: String = "", order: Int = 0) { self.recordID = recordID; self.name = name; self.price = price; self.note = note; self.order = order }
}

@Model final class Tag { var id: UUID = UUID(); var name: String = ""; var normalizedName: String = ""; var isSystem = false; init(name: String, isSystem: Bool = false) { self.name = name; self.normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); self.isSystem = isSystem } }
@Model final class Collection { var id: UUID = UUID(); var title: String = ""; var detail: String = ""; var coverImagePath: String?; var visibilityRaw: String = "private"; var createdAt: Date = Date(); init(title: String) { self.title = title } }
@Model final class CollectionEntry { var id: UUID = UUID(); var collectionID: UUID = UUID(); var recordID: UUID = UUID(); var order: Int = 0; init(collectionID: UUID, recordID: UUID, order: Int) { self.collectionID = collectionID; self.recordID = recordID; self.order = order } }
@Model final class AppSettings {
    var id: UUID = UUID()
    var notificationsEnabled = false
    var defaultVisibilityRaw: String = "private"
    var photoQualityRaw: String = "standard"
    var trashRetentionDays: Int = 30
    var automaticallyEmptyTrash = false
    var createdAt: Date = Date()
    init() {}
}

extension Array where Element == RestaurantRecord {
    func filtered(query: String, tags: Set<UUID>, places: [Place]) -> [RestaurantRecord] {
        let needle = SearchText.normalize(query)
        return filter { record in
            let place = places.first { $0.id == record.placeID }
            let matchesText = needle.isEmpty || [place?.name ?? "", place?.address ?? "", place?.area ?? "", record.memo].contains { SearchText.normalize($0).contains(needle) }
            return matchesText && tags.isSubset(of: Set(record.tagIDs))
        }
    }
}
