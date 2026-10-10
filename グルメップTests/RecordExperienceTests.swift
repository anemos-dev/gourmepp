import Foundation
import CoreGraphics
import UniformTypeIdentifiers
import ImageIO
import SwiftData
import Testing
@testable import Gourmepp

struct RecordExperienceTests {
    @Test func searchNormalizesKanaWidthAndCase() {
        let place = Place(name: "Ｃａｆｅ ガーデン", address: "東京都")
        let record = RestaurantRecord(placeID: place.id, status: .visited)
        record.memo = "プリンがおいしい"
        #expect([record].filtered(query: "cafe ｶﾞｰﾃﾞﾝ", tags: [], places: [place]).count == 1)
        #expect([record].filtered(query: "ぷりん", tags: [], places: [place]).count == 1)
        #expect(SearchText.normalize("カフェ") != SearchText.normalize("ガフェ"))
        #expect([record].filtered(query: "ぷりん", tags: [UUID()], places: [place]).isEmpty)
    }

    @Test func monthlyReportUsesFirstVisitAndExclusiveEnd() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ month: Int, _ day: Int = 1) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
        }
        let oldPlace = UUID(), newPlace = UUID()
        func visit(_ place: UUID, _ when: Date) -> RestaurantRecord {
            let record = RestaurantRecord(placeID: place, status: .visited)
            record.visitDate = when
            return record
        }
        let previous = visit(oldPlace, date(8))
        let returning = visit(oldPlace, date(9))
        returning.ratingHalfSteps = 7
        let first = visit(newPlace, date(9, 20))
        let second = visit(newPlace, date(9, 21))
        let nextMonth = visit(UUID(), date(10))
        let deleted = visit(UUID(), date(9)); deleted.isTrashed = true
        let wishlist = visit(UUID(), date(9)); wishlist.status = .wantToGo
        let undated = RestaurantRecord(placeID: UUID(), status: .visited)
        let report = MonthlyFoodReport(month: date(9), records: [previous, returning, first, second, nextMonth, deleted, wishlist, undated], calendar: calendar)
        #expect(report.visitCount == 3)
        #expect(report.uniquePlaceCount == 2)
        #expect(report.newPlaceCount == 1)
        #expect(report.averageRating == 3.5)
        #expect(MonthlyFoodReport(month: date(7), records: [], calendar: calendar).averageRating == nil)
    }

    @Test @MainActor func backupPreservesNewFieldsAndReadsLegacyPlace() throws {
        let place = Place(name: "いつものお店")
        place.nextMealNote = "季節のパフェ"
        place.wantsToReturn = true
        let record = RestaurantRecord(placeID: place.id, status: .visited)
        let service = BackupService()
        let data = try service.encode(places: [place], records: [record], photos: [], menuItems: [], tags: [], collections: [], collectionEntries: [])
        let backup = try service.decode(data)
        #expect(backup.places.first?.nextMealNote == "季節のパフェ")
        #expect(backup.places.first?.wantsToReturn == true)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var places = try #require(object["places"] as? [[String: Any]])
        places[0].removeValue(forKey: "nextMealNote")
        places[0].removeValue(forKey: "wantsToReturn")
        object["places"] = places
        let legacy = try service.decode(JSONSerialization.data(withJSONObject: object))
        #expect(legacy.places.first?.nextMealNote == nil)
        #expect(legacy.places.first?.wantsToReturn == nil)
        let schema = Schema([Place.self, RestaurantRecord.self, RecordPhoto.self, RecordMenuItem.self, Tag.self, Collection.self, CollectionEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        try service.restore(backup, context: container.mainContext, currentPlaces: [], currentRecords: [], currentPhotos: [], currentMenuItems: [], currentTags: [], currentCollections: [], currentEntries: [])
        let restored = try #require(container.mainContext.fetch(FetchDescriptor<Place>()).first)
        #expect(restored.nextMealNote == "季節のパフェ")
        #expect(restored.wantsToReturn)
    }

    @Test @MainActor func snapshotTracksPhotosPlaceChangesAndOrdering() throws {
        let place = Place(name: "テスト")
        let record = RestaurantRecord(placeID: place.id, status: .visited)
        let other = RestaurantRecord(placeID: place.id, status: .wantToGo)
        let photo = RecordPhoto(recordID: record.id, imagePath: "test/photo.jpg", thumbnailPath: "test/thumb.jpg", order: 0)
        let menu = RecordMenuItem(recordID: record.id, name: "ランチ")
        func snapshot(_ records: [RestaurantRecord], photos: [RecordPhoto] = []) throws -> BackupSnapshot {
            try BackupSnapshot.capture(metadata: BackupService().encode(places: [place], records: records, photos: photos, menuItems: [menu], tags: [], collections: [], collectionEntries: [], includePhotoData: false))
        }
        let before = try snapshot([record, other])
        #expect(try snapshot([other, record]).contentHash == before.contentHash)
        let withPhoto = try snapshot([record, other], photos: [photo])
        #expect(withPhoto.changes(since: before).updated == 1)
        place.nextMealNote = "パフェ"
        #expect(try snapshot([record, other]).changes(since: before).updated == 2)
        place.nextMealNote = ""
        menu.price = 1200
        #expect(try snapshot([record, other]).changes(since: before).updated == 1)
        #expect(try snapshot([record]).changes(since: before).removed == 1)
        #expect(try before.changes(since: snapshot([record])).added == 1)
    }

    @Test func photoDatePreservesTheCaptureCalendarDay() throws {
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2025:12:31 23:45:00"]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let date = try #require(PhotoCaptureDate.read(from: data as Data))
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2025 && parts.month == 12 && parts.day == 31)
    }

    @Test func invalidPhotoHasNoDate() {
        #expect(PhotoCaptureDate.read(from: Data("not a photo".utf8)) == nil)
    }
}
