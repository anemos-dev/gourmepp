#if DEBUG
import Foundation
import SwiftData

/// Debug-only fixtures for checking Tokyo visit density with individual food photos.
@MainActor
enum DeveloperSampleData {
    private struct Draft { let name: String; let address: String; let latitude: Double; let longitude: Double; let category: String; let menu: String; let price: Int }
    static func addFifty(to context: ModelContext) throws {
        let places = try context.fetch(FetchDescriptor<Place>())
        let records = try context.fetch(FetchDescriptor<RestaurantRecord>())
        let photos = try context.fetch(FetchDescriptor<RecordPhoto>())
        let menuItems = try context.fetch(FetchDescriptor<RecordMenuItem>())
        let tag = try context.fetch(FetchDescriptor<Tag>()).first(where: { $0.normalizedName == "訪問サンプル" }) ?? Tag(name: "訪問サンプル")
        if tag.modelContext == nil { context.insert(tag) }
        let store = LocalPhotoStore()
        for (index, draft) in drafts.enumerated() {
            let externalID = "dev-tokyo-visit-\(index + 1)"
            let place = places.first(where: { $0.externalPlaceID == externalID }) ?? Place(name: draft.name, externalPlaceID: externalID)
            if place.modelContext == nil { context.insert(place) }
            place.name = draft.name; place.address = "東京都\(draft.address)"
            place.area = Place.municipality(from: place.address) ?? Place.area(from: place.address)
            place.latitude = draft.latitude; place.longitude = draft.longitude; place.category = draft.category
            let record = records.first(where: { $0.placeID == place.id }) ?? RestaurantRecord(placeID: place.id, status: .visited)
            if record.modelContext == nil { context.insert(record) }
            record.status = .visited; record.isTrashed = false; record.deletedAt = nil
            record.ratingHalfSteps = 7 + index % 4; record.rating = record.ratingHalfSteps / 2; record.price = draft.price
            record.visitDate = visitDate(for: index); record.memo = "\(draft.category)の味をゆっくり楽しめた。都内の訪問密度確認用サンプル。"
            record.tagIDs = [tag.id]; record.isFavorite = index % 5 == 0
            record.createdAt = record.visitDate ?? .now; record.updatedAt = record.visitDate ?? .now
            InitialReleasePrivacy.apply(to: record)
            menuItems.filter { $0.recordID == record.id }.forEach(context.delete)
            context.insert(RecordMenuItem(recordID: record.id, name: draft.menu, price: draft.price, order: 0))
            photos.filter { $0.recordID == record.id }.forEach { photo in store.delete(photo: photo); context.delete(photo) }
            let imageName = String(format: "dev-tokyo-%02d", index + 1)
            let url = Bundle.main.url(forResource: imageName, withExtension: "jpg", subdirectory: "SampleData")
                ?? Bundle.main.url(forResource: imageName, withExtension: "jpg")
            guard let url, let data = try? Data(contentsOf: url) else { throw SampleDataError.missingImage(imageName) }
            let saved = try store.save(data, recordID: record.id, order: 0)
            let photo = RecordPhoto(recordID: record.id, imagePath: saved.imagePath, thumbnailPath: saved.thumbnailPath, order: 0)
            photo.takenAt = record.visitDate; photo.latitude = draft.latitude; photo.longitude = draft.longitude; context.insert(photo)
        }
        try context.save()
    }
    private static func visitDate(for index: Int) -> Date {
        var c = DateComponents(); c.calendar = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")
        c.year = 2026; c.month = 4 + index / 10; c.day = 2 + (index * 3) % 26; c.hour = 11 + index % 9
        return c.date ?? .now
    }
    private static let drafts: [Draft] = [
        Draft(name: "渋谷 鶏白湯めん処 灯", address: "渋谷区渋谷2-8-3", latitude: 35.6598, longitude: 139.7044, category: "ラーメン", menu: "鶏白湯ラーメン", price: 1180),
        Draft(name: "新宿 麦とろ食堂 青葉", address: "新宿区新宿3-14-7", latitude: 35.6921, longitude: 139.7048, category: "和食", menu: "麦とろ定食", price: 1480),
        Draft(name: "銀座 鮨 こはる", address: "中央区銀座4-6-12", latitude: 35.6718, longitude: 139.7649, category: "寿司", menu: "季節の握り", price: 3200),
        Draft(name: "浅草 天ぷら まつ風", address: "台東区浅草1-33-4", latitude: 35.7118, longitude: 139.7965, category: "天ぷら", menu: "海老と野菜の天丼", price: 1680),
        Draft(name: "中目黒 洋食キッチン ポプラ", address: "目黒区上目黒2-18-7", latitude: 35.6432, longitude: 139.6983, category: "洋食", menu: "デミグラスハンバーグ", price: 1580),
        Draft(name: "神楽坂 そば処 風待ち", address: "新宿区神楽坂5-12", latitude: 35.7027, longitude: 139.7402, category: "そば", menu: "鴨せいろ", price: 1450),
        Draft(name: "三軒茶屋 食堂 炭ノ音", address: "世田谷区太子堂4-22-6", latitude: 35.6434, longitude: 139.6707, category: "和食", menu: "豚の生姜焼き", price: 1380),
        Draft(name: "丸の内 おだしうどん 花紋", address: "千代田区丸の内1-6-4", latitude: 35.6821, longitude: 139.7661, category: "うどん", menu: "だしカレーうどん", price: 1280),
        Draft(name: "恵比寿 洋菓子と喫茶 ルル", address: "渋谷区恵比寿南1-9-2", latitude: 35.6468, longitude: 139.7103, category: "カフェ", menu: "苺のショートケーキ", price: 780),
        Draft(name: "築地 海鮮どんぶり 潮路", address: "中央区築地4-10-8", latitude: 35.6651, longitude: 139.7702, category: "海鮮", menu: "海鮮丼", price: 1980),
        Draft(name: "池袋 洋食屋 こぐま", address: "豊島区南池袋1-16-18", latitude: 35.7289, longitude: 139.7115, category: "洋食", menu: "オムライス", price: 1380),
        Draft(name: "吉祥寺 ふわりパンケーキ", address: "武蔵野市吉祥寺本町2-7-3", latitude: 35.7043, longitude: 139.5784, category: "カフェ", menu: "スフレパンケーキ", price: 1480),
        Draft(name: "下北沢 スパイス食堂 夕凪", address: "世田谷区北沢2-26-9", latitude: 35.6615, longitude: 139.6672, category: "カレー", menu: "チキンカレー", price: 1250),
        Draft(name: "上野 とんかつ いち葉", address: "台東区上野6-8-5", latitude: 35.7105, longitude: 139.7758, category: "とんかつ", menu: "ロースかつ定食", price: 1680),
        Draft(name: "六本木 トラットリア ルーチェ", address: "港区六本木6-10-1", latitude: 35.6604, longitude: 139.7292, category: "イタリアン", menu: "きのこのクリームパスタ", price: 1880),
        Draft(name: "清澄白河 珈琲とトースト 日日", address: "江東区白河2-5-4", latitude: 35.6828, longitude: 139.8006, category: "カフェ", menu: "厚切りトースト", price: 980),
        Draft(name: "中野 餃子酒場 まる福", address: "中野区中野5-53-8", latitude: 35.7062, longitude: 139.6668, category: "中華", menu: "焼き餃子", price: 680),
        Draft(name: "押上 すみだ食堂 つむぎ", address: "墨田区押上1-21-2", latitude: 35.7103, longitude: 139.8122, category: "定食", menu: "焼き魚定食", price: 1380),
        Draft(name: "大井町 洋食グリル ひだまり", address: "品川区東大井5-4-12", latitude: 35.6068, longitude: 139.7348, category: "洋食", menu: "和牛ステーキプレート", price: 2480),
        Draft(name: "自由が丘 果実菓子アトリエ", address: "目黒区自由が丘2-11-9", latitude: 35.6081, longitude: 139.6681, category: "カフェ", menu: "季節のフルーツタルト", price: 880),
        Draft(name: "新橋 炭火焼き鳥 つばめ", address: "港区新橋2-15-8", latitude: 35.6662, longitude: 139.7571, category: "焼き鳥", menu: "炭火焼き鳥", price: 1880),
        Draft(name: "日本橋 しゃぶしゃぶ こよみ", address: "中央区日本橋室町1-9-4", latitude: 35.6866, longitude: 139.7745, category: "しゃぶしゃぶ", menu: "豚しゃぶ鍋", price: 2280),
        Draft(name: "早稲田 茶そば処 緑灯", address: "新宿区馬場下町9-3", latitude: 35.7058, longitude: 139.7211, category: "そば", menu: "茶そば", price: 1100),
        Draft(name: "赤坂 ビストロ木立", address: "港区赤坂3-9-2", latitude: 35.6724, longitude: 139.7373, category: "フレンチ", menu: "季節野菜のリゾット", price: 2200),
        Draft(name: "高円寺 ベーカリー麦日和", address: "杉並区高円寺北2-8-5", latitude: 35.7061, longitude: 139.6494, category: "ベーカリー", menu: "クロワッサンとカフェラテ", price: 980),
        Draft(name: "阿佐ヶ谷 町中華 福来", address: "杉並区阿佐谷南1-35-7", latitude: 35.7044, longitude: 139.6359, category: "中華", menu: "麻婆豆腐定食", price: 1180),
        Draft(name: "学芸大学 魚菜ごはん みなも", address: "目黒区鷹番3-6-1", latitude: 35.6283, longitude: 139.6851, category: "海鮮", menu: "刺身盛り合わせ", price: 1880),
        Draft(name: "門前仲町 お好み焼き小町", address: "江東区富岡1-5-8", latitude: 35.6711, longitude: 139.7962, category: "粉もの", menu: "お好み焼き", price: 1280),
        Draft(name: "神田 洋食喫茶 ブラン", address: "千代田区内神田3-7-4", latitude: 35.6915, longitude: 139.7708, category: "洋食", menu: "ローストビーフ丼", price: 1480),
        Draft(name: "水道橋 みそらーめん 森の灯", address: "千代田区神田三崎町2-18-5", latitude: 35.7021, longitude: 139.7544, category: "ラーメン", menu: "味噌ラーメン", price: 1180),
        Draft(name: "目白 和菓子茶房 ひより", address: "豊島区目白3-13-2", latitude: 35.7218, longitude: 139.7064, category: "和菓子", menu: "抹茶あんみつ", price: 980),
        Draft(name: "西荻窪 ピッツェリア オリーブ", address: "杉並区西荻南3-10-9", latitude: 35.7038, longitude: 139.5999, category: "イタリアン", menu: "マルゲリータピザ", price: 1480),
        Draft(name: "北千住 鶏料理 とり松", address: "足立区千住2-31", latitude: 35.7491, longitude: 139.8048, category: "鶏料理", menu: "チキン南蛮", price: 1380),
        Draft(name: "赤羽 おにぎりと味噌汁 かさね", address: "北区赤羽1-11-4", latitude: 35.7781, longitude: 139.7212, category: "和食", menu: "おにぎりと味噌汁", price: 980),
        Draft(name: "蒲田 天ぷら まるいち", address: "大田区西蒲田7-29-6", latitude: 35.5629, longitude: 139.7161, category: "天ぷら", menu: "野菜天ぷら定食", price: 1580),
        Draft(name: "練馬 ごちそう弁当 こまち", address: "練馬区練馬1-6-3", latitude: 35.7374, longitude: 139.6547, category: "弁当", menu: "季節の幕の内弁当", price: 1280),
        Draft(name: "板橋 甘味処 はなみずき", address: "板橋区板橋1-16-8", latitude: 35.7484, longitude: 139.7196, category: "和菓子", menu: "苺大福", price: 580),
        Draft(name: "町田 喫茶 こてまり", address: "町田市原町田6-12-20", latitude: 35.5425, longitude: 139.4451, category: "カフェ", menu: "メロンソーダとパフェ", price: 1180),
        Draft(name: "吉祥寺 旬菜すき焼き ゆらり", address: "武蔵野市吉祥寺南町1-5-5", latitude: 35.7028, longitude: 139.5803, category: "すき焼き", menu: "すき焼き鍋", price: 2280),
        Draft(name: "渋谷 チーズ工房のグラタン", address: "渋谷区宇田川町12-7", latitude: 35.6622, longitude: 139.6987, category: "洋食", menu: "海老グラタン", price: 1580),
        Draft(name: "新宿 うなぎ小料理 ひつじ雲", address: "新宿区西新宿1-5-1", latitude: 35.6936, longitude: 139.6995, category: "うなぎ", menu: "ひつまぶし", price: 2980),
        Draft(name: "銀座 喫茶室 ミモザ", address: "中央区銀座2-8-5", latitude: 35.6729, longitude: 139.7682, category: "カフェ", menu: "プリンと紅茶", price: 980),
        Draft(name: "浅草 たこ焼き たまや", address: "台東区浅草2-7-13", latitude: 35.7152, longitude: 139.7951, category: "粉もの", menu: "たこ焼き", price: 780),
        Draft(name: "品川 うなぎ食堂 水音", address: "港区高輪3-26-27", latitude: 35.6284, longitude: 139.7387, category: "うなぎ", menu: "うなぎ丼", price: 2480),
        Draft(name: "表参道 サンドイッチスタンド 青空", address: "渋谷区神宮前4-9-2", latitude: 35.6661, longitude: 139.7118, category: "カフェ", menu: "海老アボカドサンド", price: 1280),
        Draft(name: "大森 喫茶 うみねこ", address: "大田区大森北1-8-5", latitude: 35.5883, longitude: 139.7281, category: "カフェ", menu: "チーズケーキ", price: 780),
        Draft(name: "錦糸町 カフェバル たんぽぽ", address: "墨田区江東橋3-9-10", latitude: 35.6962, longitude: 139.8141, category: "カフェ", menu: "フレンチトースト", price: 1280),
        Draft(name: "代々木公園 抹茶と甘味 かえで", address: "渋谷区富ヶ谷1-8-5", latitude: 35.6685, longitude: 139.6904, category: "和菓子", menu: "抹茶パフェ", price: 1180),
        Draft(name: "飯田橋 だし茶漬け こもれび", address: "千代田区飯田橋4-8-6", latitude: 35.7008, longitude: 139.7469, category: "和食", menu: "だし茶漬け", price: 1080),
        Draft(name: "神保町 冷やしそば りんどう", address: "千代田区神田神保町1-6-11", latitude: 35.6953, longitude: 139.7571, category: "そば", menu: "冷たいそば", price: 1080),
    ]
}
private enum SampleDataError: LocalizedError {
    case missingImage(String)
    var errorDescription: String? { if case let .missingImage(name) = self { return "サンプル写真が見つかりません: \(name)" }; return nil }
}
#endif
