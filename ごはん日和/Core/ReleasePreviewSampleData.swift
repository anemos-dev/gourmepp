import Foundation
import SwiftData

/// Photo-backed fictional records used for local App Store preview screenshots.
/// Nothing in this fixture is fetched from or sent to a network service.
@MainActor
enum ReleasePreviewSampleData {
    private static let fixtureVersion = 2
    private static let fixtureVersionKey = "releasePreviewSampleVersion"

    private struct Draft {
        let name: String
        let address: String
        let coordinate: (latitude: Double, longitude: Double)
        let category: String
        let status: RecordStatus
        let ratingHalfSteps: Int
        let price: Int
        let visitDate: Date?
        let memo: String
        let tags: [String]
        let photoName: String
        let menu: [(name: String, price: Int)]
        let favorite: Bool
    }

    static func add(to context: ModelContext) throws {
        let existingRecords = try context.fetch(FetchDescriptor<RestaurantRecord>())
        let existingPlaces = try context.fetch(FetchDescriptor<Place>())
        let samplePlaceIDs: Set<UUID> = Set(existingPlaces.compactMap { place -> UUID? in
            guard place.externalPlaceID?.hasPrefix("release-preview-") == true else { return nil }
            return place.id
        })
        let hasCompleteCurrentFixture = samplePlaceIDs.count == drafts.count
            && existingRecords.filter { samplePlaceIDs.contains($0.placeID) }.count == drafts.count
            && UserDefaults.standard.integer(forKey: fixtureVersionKey) == fixtureVersion
        guard !hasCompleteCurrentFixture else { return }

        let existingPhotos = try context.fetch(FetchDescriptor<RecordPhoto>())
        let existingMenuItems = try context.fetch(FetchDescriptor<RecordMenuItem>())
        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        let existingCollections = try context.fetch(FetchDescriptor<Collection>())
        let existingEntries = try context.fetch(FetchDescriptor<CollectionEntry>())

        var tags: [String: Tag] = [:]
        for name in ["ランチ", "ひとりごはん", "カフェ", "また行きたい", "麺", "和食", "記念日"] {
            if let existing = existingTags.first(where: { $0.normalizedName == name.lowercased() }) {
                tags[name] = existing
            } else {
                let tag = Tag(name: name)
                context.insert(tag)
                tags[name] = tag
            }
        }

        let store = LocalPhotoStore()
        var createdRecords: [(record: RestaurantRecord, imagePath: String)] = []

        for (index, draft) in drafts.enumerated() {
            let externalPlaceID = "release-preview-\(index)"
            let place = existingPlaces.first(where: { $0.externalPlaceID == externalPlaceID })
                ?? Place(name: draft.name, externalPlaceID: externalPlaceID)
            if !existingPlaces.contains(where: { $0.id == place.id }) { context.insert(place) }
            place.name = draft.name
            place.address = draft.address
            place.area = Place.area(from: draft.address)
            place.latitude = draft.coordinate.latitude
            place.longitude = draft.coordinate.longitude
            place.category = draft.category

            let record = existingRecords.first(where: { $0.placeID == place.id })
                ?? RestaurantRecord(placeID: place.id, status: draft.status)
            if !existingRecords.contains(where: { $0.id == record.id }) { context.insert(record) }
            record.status = draft.status
            record.ratingHalfSteps = draft.ratingHalfSteps
            record.rating = draft.ratingHalfSteps / 2
            record.price = draft.price
            record.visitDate = draft.visitDate
            record.memo = draft.memo
            record.tagIDs = draft.tags.compactMap { tags[$0]?.id }
            record.isFavorite = draft.favorite
            record.createdAt = date(day: 10 - index, hour: 10)
            record.updatedAt = date(day: 10 - index, hour: 18)

            existingMenuItems.filter { $0.recordID == record.id }.forEach(context.delete)
            for (menuIndex, item) in draft.menu.enumerated() {
                context.insert(RecordMenuItem(recordID: record.id, name: item.name, price: item.price, order: menuIndex))
            }

            existingPhotos.filter { $0.recordID == record.id }.forEach { photo in
                store.delete(photo: photo)
                context.delete(photo)
            }
            let data = try imageData(named: draft.photoName)
            let saved = try store.save(data, recordID: record.id, order: 0)
            let photo = RecordPhoto(recordID: record.id, imagePath: saved.imagePath, thumbnailPath: saved.thumbnailPath, order: 0)
            photo.takenAt = draft.visitDate
            photo.latitude = draft.coordinate.latitude
            photo.longitude = draft.coordinate.longitude
            context.insert(photo)
            createdRecords.append((record, saved.imagePath))
        }

        let favorites = existingCollections.first(where: { $0.title == "また行きたい、東京のお店" })
            ?? Collection(title: "また行きたい、東京のお店")
        if !existingCollections.contains(where: { $0.id == favorites.id }) { context.insert(favorites) }
        favorites.detail = "写真で振り返る、気分のいいお店たち"
        favorites.coverImagePath = createdRecords.first(where: { $0.record.isFavorite })?.imagePath
        existingEntries.filter { $0.collectionID == favorites.id }.forEach(context.delete)
        for (index, value) in createdRecords.filter({ $0.record.isFavorite }).enumerated() {
            context.insert(CollectionEntry(collectionID: favorites.id, recordID: value.record.id, order: index))
        }

        try context.save()
        UserDefaults.standard.set(fixtureVersion, forKey: fixtureVersionKey)
    }

    private static func imageData(named name: String) throws -> Data {
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "SampleData")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        guard let url, let data = try? Data(contentsOf: url) else {
            throw SampleDataError.missingImage(name)
        }
        return data
    }

    private static func date(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Asia/Tokyo")
        components.year = 2026
        components.month = 8
        components.day = day
        components.hour = hour
        return components.date ?? .now
    }

    private static let drafts: [Draft] = [
        Draft(name: "湯気ラーメン 代々木", address: "東京都渋谷区代々木1-8-4", coordinate: (35.6835, 139.7022), category: "ラーメン", status: .visited, ratingHalfSteps: 9, price: 2, visitDate: date(day: 10, hour: 12), memo: "鶏のうまみがじんわり。半熟たまごも好みで、雨の日にまた来たい。", tags: ["ランチ", "ひとりごはん", "麺", "また行きたい"], photoName: "sample-ramen", menu: [("鶏白湯ラーメン", 1_180), ("味玉", 150)], favorite: true),
        Draft(name: "季節の食堂 こもれび", address: "東京都目黒区中目黒2-14-6", coordinate: (35.6426, 139.6993), category: "和食", status: .visited, ratingHalfSteps: 10, price: 3, visitDate: date(day: 9, hour: 13), memo: "焼き魚がふっくら。小鉢まで丁寧で、ゆっくりしたい日のランチに。", tags: ["ランチ", "和食", "また行きたい"], photoName: "sample-washoku", menu: [("季節の焼き魚定食", 1_680)], favorite: true),
        Draft(name: "Café Lento", address: "東京都世田谷区三軒茶屋1-23-8", coordinate: (35.6430, 139.6690), category: "カフェ", status: .visited, ratingHalfSteps: 8, price: 2, visitDate: date(day: 8, hour: 10), memo: "朝の光が心地いいカフェ。ラテとアボカドトーストでゆっくり読書。", tags: ["カフェ", "ひとりごはん"], photoName: "sample-cafe", menu: [("アボカドトースト", 1_250), ("カフェラテ", 620)], favorite: false),
        Draft(name: "Trattoria Sera", address: "東京都港区麻布十番2-5-11", coordinate: (35.6555, 139.7376), category: "イタリアン", status: .visited, ratingHalfSteps: 9, price: 3, visitDate: date(day: 7, hour: 19), memo: "パスタのソースが濃厚で、食後のティラミスまで大満足。", tags: ["記念日", "また行きたい"], photoName: "sample-italian", menu: [("ボロネーゼ", 1_780), ("ティラミス", 780)], favorite: true),
        Draft(name: "朝のパン研究所", address: "東京都台東区蔵前3-7-2", coordinate: (35.7047, 139.7905), category: "ベーカリー", status: .visited, ratingHalfSteps: 8, price: 1, visitDate: date(day: 6, hour: 9), memo: "サクッと軽い朝ごはんにぴったり。次は季節のスープも試したい。", tags: ["カフェ", "ひとりごはん"], photoName: "sample-cafe", menu: [("トーストプレート", 980)], favorite: false),
        Draft(name: "出汁そば ひとやすみ", address: "東京都新宿区神楽坂4-3-7", coordinate: (35.7020, 139.7375), category: "そば", status: .wantToGo, ratingHalfSteps: 0, price: 2, visitDate: nil, memo: "友人のおすすめ。平日のお昼に行ってみたい。", tags: ["ランチ", "麺"], photoName: "sample-ramen", menu: [], favorite: false),
        Draft(name: "小皿食堂 灯", address: "東京都中央区日本橋人形町2-11-9", coordinate: (35.6865, 139.7854), category: "定食", status: .wantToGo, ratingHalfSteps: 0, price: 2, visitDate: nil, memo: "季節の定食が気になる。仕事帰りにも良さそう。", tags: ["和食", "また行きたい"], photoName: "sample-washoku", menu: [], favorite: false),
        Draft(name: "夜カフェ Orbis", address: "東京都渋谷区恵比寿西1-18-5", coordinate: (35.6486, 139.7097), category: "カフェ", status: .wantToGo, ratingHalfSteps: 0, price: 2, visitDate: nil, memo: "デザートがきれい。次の休日の候補。", tags: ["カフェ", "記念日"], photoName: "sample-italian", menu: [], favorite: false),
    ]
}

private enum SampleDataError: LocalizedError {
    case missingImage(String)

    var errorDescription: String? {
        switch self {
        case .missingImage: "サンプル写真を読み込めませんでした。アプリを再インストールして、もう一度お試しください。"
        }
    }
}
