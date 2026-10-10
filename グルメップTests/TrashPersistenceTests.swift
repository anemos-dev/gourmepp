import Foundation
import SwiftData
import Testing
@testable import Gourmepp

struct TrashPersistenceTests {
    @Test @MainActor func trashAndRestoreSurviveStoreReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([RestaurantRecord.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("records.store"))
        let id: UUID
        let deletionDate = Date(timeIntervalSince1970: 1_700_000_000)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            let record = RestaurantRecord(placeID: UUID(), status: .visited)
            id = record.id
            context.insert(record)
            try context.save()
            record.isTrashed = true
            record.deletedAt = deletionDate
            try context.save()

            let reloaded = try #require(ModelContext(container).fetch(FetchDescriptor<RestaurantRecord>()).first)
            #expect(reloaded.isTrashed)
            #expect(reloaded.deletedAt == deletionDate)
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            let record = try #require(context.fetch(FetchDescriptor<RestaurantRecord>()).first)
            #expect(record.id == id)
            #expect(record.isTrashed)
            #expect(try context.fetchCount(FetchDescriptor<RestaurantRecord>(predicate: #Predicate { !$0.isTrashed })) == 0)
            #expect(try context.fetchCount(FetchDescriptor<RestaurantRecord>(predicate: #Predicate { $0.isTrashed })) == 1)
            record.isTrashed = false
            record.deletedAt = nil
            try context.save()
        }

        let container = try ModelContainer(for: schema, configurations: [configuration])
        let record = try #require(container.mainContext.fetch(FetchDescriptor<RestaurantRecord>()).first)
        #expect(!record.isTrashed)
        #expect(record.deletedAt == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RestaurantRecord>(predicate: #Predicate { !$0.isTrashed })) == 1)
    }

    @Test @MainActor func backupKeepsLegacyTrashKeyAndRestoresFlag() throws {
        let place = Place(name: "ゴミ箱の記録")
        let record = RestaurantRecord(placeID: place.id, status: .visited)
        record.isTrashed = true
        record.deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let service = BackupService()
        let data = try service.encode(places: [place], records: [record], photos: [], menuItems: [], tags: [], collections: [], collectionEntries: [])
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(json["records"] as? [[String: Any]])
        #expect(rows.first?["isDeleted"] as? Bool == true)
        #expect(rows.first?["isTrashed"] == nil)

        let schema = Schema([Place.self, RestaurantRecord.self, RecordPhoto.self, RecordMenuItem.self, Tag.self, Collection.self, CollectionEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        try service.restore(service.decode(data), context: container.mainContext, currentPlaces: [], currentRecords: [], currentPhotos: [], currentMenuItems: [], currentTags: [], currentCollections: [], currentEntries: [])
        let restored = try #require(ModelContext(container).fetch(FetchDescriptor<RestaurantRecord>()).first)
        #expect(restored.id == record.id)
        #expect(restored.isTrashed)
        #expect(restored.deletedAt == record.deletedAt)
    }
}
