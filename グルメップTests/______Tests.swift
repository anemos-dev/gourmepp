import Foundation
import SwiftData
import Testing
@testable import Gourmepp

struct グルメップTests {
    @Test func recordStatusAndTagSearch() async throws {
        let shinjuku = Place(name: "ごはん亭", address: "新宿")
        let record = RestaurantRecord(placeID: shinjuku.id, status: .wantToGo)
        let tag = Tag(name: "デート")
        record.tagIDs = [tag.id]

        #expect(record.status == .wantToGo)
        record.status = .visited
        #expect(record.status == .visited)
        #expect([record].filtered(query: "新宿", tags: [tag.id], places: [shinjuku]).count == 1)
        #expect([record].filtered(query: "渋谷", tags: [], places: [shinjuku]).isEmpty)
    }

    @Test func homeStatusFiltersIncludeAllAndMigrateLegacyInterested() {
        #expect(HomeStatusFilter.allCases.map(\.title) == ["すべて", "行った", "行きたい"])
        #expect(RecordStatus.allCases.map(\.title) == ["行った", "行きたい"])

        let record = RestaurantRecord(placeID: UUID(), status: .wantToGo)
        record.statusRaw = "interested"
        #expect(record.status == .wantToGo)
    }

    @Test @MainActor func csvEscapesQuotedMemo() async throws {
        let place = Place(name: "A店")
        let record = RestaurantRecord(placeID: place.id, status: .visited)
        record.memo = "\"また行く\", おすすめ"
        let output = LocalExportImportService().csv(records: [record], places: [place], tags: [])
        #expect(output.contains("\"\"また行く\"\""))
    }

    @Test func yenPriceParsesGroupedInput() async throws {
        #expect(yenValue("1,280") == 1280)
        #expect(yenValue("¥980円") == 980)
        #expect(yenValue("") == nil)
    }

    @Test func priceTierLabelsCoverAllStoredValues() {
        #expect(PriceTier.allCases.map(\.rawValue) == [1, 2, 3, 4, 5, 6])
        #expect(PriceTier.allCases.map(\.label) == [
            "〜¥999", "¥1,000〜¥2,999", "¥3,000〜¥4,999",
            "¥5,000〜¥9,999", "¥10,000〜¥19,999", "¥20,000〜"
        ])
        #expect(PriceTier.label(for: 1) == "〜¥999")
        #expect(PriceTier.label(for: 6) == "¥20,000〜")
        #expect(PriceTier.label(for: nil) == nil)
    }

    @Test @MainActor func backupRoundTripPreservesCoreData() throws {
        let place = Place(name: "復元テスト店", address: "東京都千代田区")
        place.phoneNumber = "03-1234-5678"
        let tag = Tag(name: "ランチ")
        let record = RestaurantRecord(placeID: place.id, status: .visited)
        record.ratingHalfSteps = 9
        record.memo = "バックアップ対象"
        record.relatedLinks = ["https://www.instagram.com/p/example/"]
        record.tagIDs = [tag.id]
        let collection = Collection(title: "お気に入り")
        let entry = CollectionEntry(collectionID: collection.id, recordID: record.id, order: 0)

        let data = try BackupService().encode(
            places: [place],
            records: [record],
            photos: [],
            menuItems: [],
            tags: [tag],
            collections: [collection],
            collectionEntries: [entry]
        )
        let decoded = try BackupService().decode(data)

        #expect(decoded.version == AppBackup.currentVersion)
        #expect(decoded.places.first?.name == "復元テスト店")
        #expect(decoded.places.first?.phoneNumber == "03-1234-5678")
        #expect(decoded.records.first?.ratingHalfSteps == 9)
        #expect(decoded.records.first?.relatedLinks == ["https://www.instagram.com/p/example/"])
        #expect(decoded.records.first?.tagIDs == [tag.id])
        #expect(decoded.collections.first?.title == "お気に入り")
        #expect(decoded.collectionEntries.first?.recordID == record.id)
    }

    @Test @MainActor func backupRestoreReplacesExistingDataInMemory() throws {
        let schema = Schema([
            LocalUserProfile.self, Place.self, RestaurantRecord.self, RecordPhoto.self,
            RecordMenuItem.self, Tag.self, Collection.self, CollectionEntry.self, AppSettings.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let oldPlace = Place(name: "置換前の店")
        let oldRecord = RestaurantRecord(placeID: oldPlace.id, status: .wantToGo)
        context.insert(oldPlace)
        context.insert(oldRecord)
        try context.save()

        let restoredPlace = Place(name: "バックアップの店", address: "東京都台東区")
        let restoredRecord = RestaurantRecord(placeID: restoredPlace.id, status: .visited)
        restoredRecord.memo = "復元済み"
        let service = BackupService()
        let backup = try service.decode(service.encode(
            places: [restoredPlace], records: [restoredRecord], photos: [], menuItems: [],
            tags: [], collections: [], collectionEntries: []
        ))

        try service.restore(
            backup,
            context: context,
            currentPlaces: [oldPlace],
            currentRecords: [oldRecord],
            currentPhotos: [],
            currentMenuItems: [],
            currentTags: [],
            currentCollections: [],
            currentEntries: []
        )

        let places = try context.fetch(FetchDescriptor<Place>())
        let records = try context.fetch(FetchDescriptor<RestaurantRecord>())
        #expect(places.map(\.name) == ["バックアップの店"])
        #expect(records.count == 1)
        #expect(records.first?.memo == "復元済み")
    }

    @Test @MainActor func initialReleasePrivacyNormalizesLegacyVisibility() {
        let record = RestaurantRecord(placeID: UUID(), status: .visited)
        record.visibilityRaw = Visibility.public.rawValue
        record.placeVisibilityRaw = Visibility.link.rawValue
        record.ratingVisibilityRaw = Visibility.public.rawValue
        record.photoVisibilityRaw = Visibility.link.rawValue
        record.memoVisibilityRaw = Visibility.public.rawValue
        let collection = Collection(title: "公開されていたまとめ")
        collection.visibilityRaw = Visibility.public.rawValue
        let settings = AppSettings()
        settings.defaultVisibilityRaw = Visibility.public.rawValue

        InitialReleasePrivacy.apply(to: record)
        InitialReleasePrivacy.apply(to: collection)
        InitialReleasePrivacy.apply(to: settings)

        #expect(record.visibilityRaw == Visibility.private.rawValue)
        #expect(record.placeVisibilityRaw == Visibility.private.rawValue)
        #expect(record.ratingVisibilityRaw == Visibility.private.rawValue)
        #expect(record.photoVisibilityRaw == Visibility.private.rawValue)
        #expect(record.memoVisibilityRaw == Visibility.private.rawValue)
        #expect(collection.visibilityRaw == Visibility.private.rawValue)
        #expect(settings.defaultVisibilityRaw == Visibility.private.rawValue)
    }

    @Test func relatedLinkNormalization() {
        #expect(RelatedLinkFormatter.normalized("instagram.com/p/example") == "https://instagram.com/p/example")
        #expect(RelatedLinkFormatter.normalized(" https://x.com/example/status/1 ") == "https://x.com/example/status/1")
        #expect(RelatedLinkFormatter.normalized("not a url") == nil)
        #expect(RelatedLinkFormatter.normalized("ftp://example.com/post") == nil)
        #expect(RelatedLinkFormatter.normalizedValues(["example.com/post", "https://example.com/post"]) == ["https://example.com/post"])
    }

    @Test func placeAreaParsesJapanesePrefecture() {
        #expect(Place.area(from: "東京都新宿区西新宿") == "東京都")
        #expect(Place.area(from: "大阪府大阪市北区") == "大阪府")
    }

    @Test func placeMunicipalityParsesCityAndWard() {
        #expect(Place.municipality(from: "東京都新宿区西新宿2-8-1") == "新宿区")
        #expect(Place.municipality(from: "大阪府大阪市北区梅田3-1-1") == "大阪市北区")
        #expect(Place.municipality(from: "神奈川県横浜市中区山下町1-1") == "横浜市中区")
    }

    @Test func shareCardFreeAndProOptionsStaySeparated() {
        #expect(ShareCardTemplate.simple.requiresPro == false)
        #expect(ShareCardTemplate.editorial.requiresPro)
        #expect(ShareCardTemplate.collage.requiresPro)
        #expect(ShareCardTemplate.minimal.requiresPro)
        #expect(ShareCardTemplate.typography.requiresPro)
        #expect(ShareCardTemplate.allCases.filter(\.requiresPro).count == 4)
        #expect(ShareCardFormat.portrait.requiresPro == false)
        #expect(ShareCardFormat.square.requiresPro)
        #expect(ShareCardFormat.landscape.requiresPro)
        #expect(ShareCardPalette.warm.requiresPro == false)
        #expect(ShareCardPalette.sage.requiresPro)
        #expect(ShareCardPalette.midnight.requiresPro)
        #expect(ShareCardFormat.portrait.pixelSize == CGSize(width: 1080, height: 1350))
        #expect(ShareCardFormat.square.pixelSize == CGSize(width: 1080, height: 1080))
        #expect(ShareCardFormat.landscape.pixelSize == CGSize(width: 1200, height: 675))
    }

    @Test @MainActor func annualFoodReportAggregatesOnlySelectedYearVisits() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let tokyo = Place(name: "東京食堂", address: "東京都新宿区")
        let osaka = Place(name: "大阪ごはん", address: "大阪府大阪市")
        let lunch = Tag(name: "ランチ")
        let date: (Int, Int, Int) -> Date = { year, month, day in
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }

        let first = RestaurantRecord(placeID: tokyo.id, status: .visited)
        first.visitDate = date(2026, 3, 2)
        first.ratingHalfSteps = 9
        first.tagIDs = [lunch.id]

        let second = RestaurantRecord(placeID: tokyo.id, status: .visited)
        second.visitDate = date(2026, 3, 18)
        second.ratingHalfSteps = 7
        second.tagIDs = [lunch.id]

        let third = RestaurantRecord(placeID: osaka.id, status: .visited)
        third.visitDate = date(2026, 8, 10)
        third.ratingHalfSteps = 10

        let otherYear = RestaurantRecord(placeID: osaka.id, status: .visited)
        otherYear.visitDate = date(2025, 3, 2)

        let deleted = RestaurantRecord(placeID: osaka.id, status: .visited)
        deleted.visitDate = date(2026, 3, 20)
        deleted.isDeleted = true

        let report = AnnualFoodReport(
            year: 2026,
            records: [first, second, third, otherYear, deleted],
            places: [tokyo, osaka],
            tags: [lunch],
            calendar: calendar
        )

        #expect(report.visitCount == 3)
        #expect(report.uniquePlaceCount == 2)
        #expect(report.monthlyCounts[2] == 2)
        #expect(report.monthlyCounts[7] == 1)
        #expect(report.busiestMonth == 3)
        #expect(report.topArea == .init(name: "新宿区", count: 2))
        #expect(report.topTag == .init(name: "ランチ", count: 2))
        #expect(abs((report.averageRating ?? 0) - (13.0 / 3.0)) < 0.001)
        #expect(report.topRatedPlaces.first?.name == "大阪ごはん")
        #expect(report.shareText.contains("訪問記録 3件"))
    }

    @Test @MainActor func proPreferencesPersistCustomizationAndSavedFilters() throws {
        let suiteName = "ProPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = ProPreferences(defaults: defaults)
        preferences.accentTheme = .green
        preferences.gridColumns = 4
        preferences.showsCardDetails = false
        preferences.defaultHomeLayoutRaw = HomeLayout.list.rawValue
        preferences.save(SavedHomeFilter(
            name: "高評価の写真あり",
            query: "",
            statusRaw: HomeStatusFilter.visited.rawValue,
            tagIDs: [],
            favoritesOnly: false,
            price: 6,
            area: "東京都",
            minimumRating: 4.0,
            hasPhotosOnly: true
        ))

        let restored = ProPreferences(defaults: defaults)
        #expect(restored.accentTheme == .green)
        #expect(restored.gridColumns == 4)
        #expect(restored.showsCardDetails == false)
        #expect(restored.defaultHomeLayoutRaw == HomeLayout.list.rawValue)
        #expect(restored.savedFilters.first?.name == "高評価の写真あり")
        #expect(restored.savedFilters.first?.price == 6)
        #expect(restored.savedFilters.first?.minimumRating == 4.0)
        #expect(restored.savedFilters.first?.hasPhotosOnly == true)
    }

    @Test @MainActor func epubRoundTripPreservesVisitFields() throws {
        let place = Place(name: "取り込みテスト食堂", address: "東京都小金井市1-2-3")
        let tag = Tag(name: "記念日ランチ")
        let record = RestaurantRecord(placeID: place.id, status: .visited)
        record.ratingHalfSteps = 7
        record.visitDate = Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 7,
            day: 20
        ))
        record.memo = "魚と野菜がおいしい & また行きたい"
        record.tagIDs = [tag.id]

        let data = try EPUBService().encode(
            records: [record],
            places: [place],
            tags: [tag],
            photos: []
        )
        let imported = try EPUBService().decode(data)
        let visit = try #require(imported.visits.first)

        #expect(imported.visits.count == 1)
        #expect(visit.placeName == "取り込みテスト食堂")
        #expect(visit.address == "東京都小金井市1-2-3")
        #expect(visit.ratingHalfSteps == 7)
        #expect(visit.memo == "魚と野菜がおいしい & また行きたい")
        #expect(visit.tagNames == ["記念日ランチ"])
        let importedDate = try #require(visit.visitDate)
        let dateParts = Calendar(identifier: .gregorian).dateComponents(in: .current, from: importedDate)
        #expect(dateParts.year == 2026)
        #expect(dateParts.month == 7)
        #expect(dateParts.day == 20)
    }

}
