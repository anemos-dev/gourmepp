import Foundation
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum PhotoQuality: String, CaseIterable, Identifiable {
    case compact
    case standard
    case high

    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: "容量を節約"
        case .standard: "標準"
        case .high: "高画質"
        }
    }
    var compressionQuality: CGFloat {
        switch self {
        case .compact: 0.58
        case .standard: 0.76
        case .high: 0.9
        }
    }
}

struct UserFacingError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@Observable final class AppErrorCenter {
    var current: UserFacingError?

    func show(_ error: Error, title: String = "処理できませんでした") {
        current = UserFacingError(title: title, message: error.localizedDescription)
    }

    func show(_ message: String, title: String = "お知らせ") {
        current = UserFacingError(title: title, message: message)
    }
}

extension View {
    func appErrorAlert(_ center: AppErrorCenter) -> some View {
        alert(item: Binding(
            get: { center.current },
            set: { center.current = $0 }
        )) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("閉じる")))
        }
    }
}

extension UTType {
    static let gourmeppBackup = UTType(exportedAs: "com.anemos.gourmepp.backup")
    static let legacyGohanBiyoriBackup = UTType(importedAs: "com.anemos.gohanbiyori.backup")
}

struct GourmeppEPUBDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.epub] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw EPUBError.invalidFile
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct GourmeppBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.gourmeppBackup, .legacyGohanBiyoriBackup, .json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.invalidFile
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupError: LocalizedError {
    case invalidFile
    case unsupportedVersion
    case missingPhoto

    var errorDescription: String? {
        switch self {
        case .invalidFile: "バックアップファイルを読み込めませんでした。"
        case .unsupportedVersion: "このバックアップ形式には対応していません。"
        case .missingPhoto: "一部の写真データを読み込めませんでした。"
        }
    }
}

struct AppBackup: Codable {
    static let currentVersion = 1
    var version = currentVersion
    var createdAt = Date()
    var places: [BackupPlace]
    var records: [BackupRecord]
    var photos: [BackupPhoto]
    var menuItems: [BackupMenuItem]
    var tags: [BackupTag]
    var collections: [BackupCollection]
    var collectionEntries: [BackupCollectionEntry]
}

struct BackupPlace: Codable {
    var nextMealNote: String? = nil
    var wantsToReturn: Bool? = nil
    var id: UUID
    var externalPlaceID: String?
    var name: String
    var address: String
    var area: String
    var latitude: Double
    var longitude: Double
    var phoneNumber: String
    var websiteURL: String
    var category: String
    var openingHours: String
    var createdAt: Date
}

struct BackupRecord: Codable {
    var id: UUID
    var placeID: UUID
    var statusRaw: String
    var rating: Int
    var ratingHalfSteps: Int
    var memo: String
    var relatedLinks: [String]?
    var visitDate: Date?
    var price: Int?
    var visibilityRaw: String
    var isFavorite: Bool
    var isDeleted: Bool
    var deletedAt: Date?
    var tagIDs: [UUID]
    var companions: [String]
    var placeVisibilityRaw: String
    var ratingVisibilityRaw: String
    var photoVisibilityRaw: String
    var memoVisibilityRaw: String
    var createdAt: Date
    var updatedAt: Date
}

struct BackupPhoto: Codable {
    var id: UUID
    var recordID: UUID
    var order: Int
    var takenAt: Date?
    var latitude: Double?
    var longitude: Double?
    var imageData: Data
}

struct BackupMenuItem: Codable {
    var id: UUID
    var recordID: UUID
    var name: String
    var price: Int?
    var note: String
    var order: Int
}

struct BackupTag: Codable {
    var id: UUID
    var name: String
    var normalizedName: String
    var isSystem: Bool
}

struct BackupCollection: Codable {
    var id: UUID
    var title: String
    var detail: String
    var coverRecordID: UUID?
    var visibilityRaw: String
    var createdAt: Date
}

struct BackupCollectionEntry: Codable {
    var id: UUID
    var collectionID: UUID
    var recordID: UUID
    var order: Int
}

@MainActor
struct BackupService {
    func encode(
        places: [Place],
        records: [RestaurantRecord],
        photos: [RecordPhoto],
        menuItems: [RecordMenuItem],
        tags: [Tag],
        collections: [Collection],
        collectionEntries: [CollectionEntry],
        includePhotoData: Bool = true
    ) throws -> Data {
        let store = LocalPhotoStore()
        let coverRecordIDs = Dictionary(uniqueKeysWithValues: collections.map { collection in
            let recordID = collection.coverImagePath.flatMap { path in
                photos.first(where: { $0.imagePath == path || $0.thumbnailPath == path })?.recordID
            }
            return (collection.id, recordID)
        })
        let backup = AppBackup(
            places: places.map {
                BackupPlace(
                    nextMealNote: $0.nextMealNote, wantsToReturn: $0.wantsToReturn,
                    id: $0.id, externalPlaceID: $0.externalPlaceID, name: $0.name,
                    address: $0.address, area: $0.area, latitude: $0.latitude,
                    longitude: $0.longitude, phoneNumber: $0.phoneNumber,
                    websiteURL: $0.websiteURL, category: $0.category,
                    openingHours: $0.openingHours, createdAt: $0.createdAt
                )
            },
            records: records.map {
                BackupRecord(
                    id: $0.id, placeID: $0.placeID, statusRaw: $0.statusRaw,
                    rating: $0.rating, ratingHalfSteps: $0.ratingHalfSteps, memo: $0.memo,
                    relatedLinks: $0.relatedLinks,
                    visitDate: $0.visitDate, price: $0.price, visibilityRaw: $0.visibilityRaw,
                    isFavorite: $0.isFavorite, isDeleted: $0.isTrashed, deletedAt: $0.deletedAt,
                    tagIDs: $0.tagIDs, companions: $0.companions,
                    placeVisibilityRaw: $0.placeVisibilityRaw,
                    ratingVisibilityRaw: $0.ratingVisibilityRaw,
                    photoVisibilityRaw: $0.photoVisibilityRaw,
                    memoVisibilityRaw: $0.memoVisibilityRaw,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            },
            photos: try photos.map {
                guard let data = includePhotoData ? store.data(at: $0.imagePath) : $0.imagePath.data(using: .utf8) else { throw BackupError.missingPhoto }
                return BackupPhoto(
                    id: $0.id, recordID: $0.recordID, order: $0.order,
                    takenAt: $0.takenAt, latitude: $0.latitude, longitude: $0.longitude,
                    imageData: data
                )
            },
            menuItems: menuItems.map {
                BackupMenuItem(id: $0.id, recordID: $0.recordID, name: $0.name, price: $0.price, note: $0.note, order: $0.order)
            },
            tags: tags.map {
                BackupTag(id: $0.id, name: $0.name, normalizedName: $0.normalizedName, isSystem: $0.isSystem)
            },
            collections: collections.map {
                BackupCollection(
                    id: $0.id, title: $0.title, detail: $0.detail,
                    coverRecordID: coverRecordIDs[$0.id] ?? nil,
                    visibilityRaw: $0.visibilityRaw, createdAt: $0.createdAt
                )
            },
            collectionEntries: collectionEntries.map {
                BackupCollectionEntry(id: $0.id, collectionID: $0.collectionID, recordID: $0.recordID, order: $0.order)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    func decode(_ data: Data) throws -> AppBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(AppBackup.self, from: data)
        guard backup.version == AppBackup.currentVersion else { throw BackupError.unsupportedVersion }
        return backup
    }

    func restore(
        _ backup: AppBackup,
        context: ModelContext,
        currentPlaces: [Place],
        currentRecords: [RestaurantRecord],
        currentPhotos: [RecordPhoto],
        currentMenuItems: [RecordMenuItem],
        currentTags: [Tag],
        currentCollections: [Collection],
        currentEntries: [CollectionEntry]
    ) throws {
        let photoStore = LocalPhotoStore()
        var stagedPhotos: [(value: BackupPhoto, imagePath: String, thumbnailPath: String)] = []
        do {
            for value in backup.photos.sorted(by: { $0.order < $1.order }) {
                let saved = try photoStore.save(value.imageData, recordID: value.recordID, order: value.order)
                stagedPhotos.append((value, saved.imagePath, saved.thumbnailPath))
            }
        } catch {
            for staged in stagedPhotos {
                let temporary = RecordPhoto(
                    recordID: staged.value.recordID,
                    imagePath: staged.imagePath,
                    thumbnailPath: staged.thumbnailPath,
                    order: staged.value.order
                )
                photoStore.delete(photo: temporary)
            }
            throw error
        }

        currentPhotos.forEach { LocalPhotoStore().delete(photo: $0); context.delete($0) }
        currentEntries.forEach(context.delete)
        currentMenuItems.forEach(context.delete)
        currentCollections.forEach(context.delete)
        currentRecords.forEach(context.delete)
        currentPlaces.forEach(context.delete)
        currentTags.forEach(context.delete)

        for value in backup.places {
            let item = Place(name: value.name)
            item.id = value.id
            item.nextMealNote = value.nextMealNote ?? ""
            item.wantsToReturn = value.wantsToReturn ?? false
            item.externalPlaceID = value.externalPlaceID
            item.address = value.address
            item.area = value.area
            item.latitude = value.latitude
            item.longitude = value.longitude
            item.phoneNumber = value.phoneNumber
            item.websiteURL = value.websiteURL
            item.category = value.category
            item.openingHours = value.openingHours
            item.createdAt = value.createdAt
            context.insert(item)
        }
        for value in backup.records {
            let item = RestaurantRecord(placeID: value.placeID, status: RecordStatus(rawValue: value.statusRaw) ?? .wantToGo)
            item.id = value.id
            item.statusRaw = value.statusRaw
            item.rating = value.rating
            item.ratingHalfSteps = value.ratingHalfSteps
            item.memo = value.memo
            item.relatedLinks = value.relatedLinks ?? []
            item.visitDate = value.visitDate
            item.price = value.price
            item.visibilityRaw = value.visibilityRaw
            item.isFavorite = value.isFavorite
            item.isTrashed = value.isDeleted
            item.deletedAt = value.deletedAt
            item.tagIDs = value.tagIDs
            item.companions = value.companions
            item.placeVisibilityRaw = value.placeVisibilityRaw
            item.ratingVisibilityRaw = value.ratingVisibilityRaw
            item.photoVisibilityRaw = value.photoVisibilityRaw
            item.memoVisibilityRaw = value.memoVisibilityRaw
            item.createdAt = value.createdAt
            item.updatedAt = value.updatedAt
            context.insert(item)
        }
        for value in backup.tags {
            let item = Tag(name: value.name, isSystem: value.isSystem)
            item.id = value.id
            item.normalizedName = value.normalizedName
            context.insert(item)
        }
        for value in backup.menuItems {
            let item = RecordMenuItem(recordID: value.recordID, name: value.name, price: value.price, note: value.note, order: value.order)
            item.id = value.id
            context.insert(item)
        }
        var firstPhotoByRecord: [UUID: String] = [:]
        for staged in stagedPhotos {
            let value = staged.value
            let item = RecordPhoto(recordID: value.recordID, imagePath: staged.imagePath, thumbnailPath: staged.thumbnailPath, order: value.order)
            item.id = value.id
            item.takenAt = value.takenAt
            item.latitude = value.latitude
            item.longitude = value.longitude
            context.insert(item)
            if firstPhotoByRecord[value.recordID] == nil { firstPhotoByRecord[value.recordID] = staged.imagePath }
        }
        for value in backup.collections {
            let item = Collection(title: value.title)
            item.id = value.id
            item.detail = value.detail
            item.coverImagePath = value.coverRecordID.flatMap { firstPhotoByRecord[$0] }
            item.visibilityRaw = value.visibilityRaw
            item.createdAt = value.createdAt
            context.insert(item)
        }
        for value in backup.collectionEntries {
            let item = CollectionEntry(collectionID: value.collectionID, recordID: value.recordID, order: value.order)
            item.id = value.id
            context.insert(item)
        }
        try context.save()
    }
}

enum StorageFormatter {
    static func string(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct BackupReminderService {
    static let identifier = "backup-reminder"

    func setEnabled(_ enabled: Bool) async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard enabled else { return false }
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { return false }
        let content = UNMutableNotificationContent()
        content.title = "グルメップをバックアップ"
        content.body = "大切な記録と写真を、設定からバックアップしておきましょう。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60 * 24 * 30, repeats: true)
        try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
        return true
    }
}
