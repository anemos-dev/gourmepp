import SwiftUI
import SwiftData
import MapKit
import PhotosUI
import UIKit

struct PlaceDetailView: View {
    @Environment(\.modelContext) private var context; @Environment(\.dismiss) private var dismiss; @Environment(AppErrorCenter.self) private var errors; let recordID: UUID; @Query private var records: [RestaurantRecord]; @Query private var places: [Place]; @Query private var tags: [Tag]; @Query private var photos: [RecordPhoto]; @Query private var menuItems: [RecordMenuItem]; @Query private var collections: [Collection]; @Query private var collectionEntries: [CollectionEntry]; @State private var editing = false; @State private var sharing = false; @State private var showDeleteConfirmation = false
    private var record: RestaurantRecord? { records.first { $0.id == recordID } }; private var place: Place? { guard let record else { return nil }; return places.first { $0.id == record.placeID } }
    var body: some View {
        Group {
            if let record, let place {
                List {
                    Section {
                        ZStack(alignment: .bottomLeading) {
                            heroImage(record: record).frame(height: 230).clipped()
                            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading) { Text(place.name).font(.title.bold()).foregroundStyle(.white); Text("\(place.category)  \(place.address)").foregroundStyle(.white.opacity(0.85)) }.padding()
                        }
                        HStack { Button { record.isFavorite.toggle(); saveChanges() } label: { Label(record.isFavorite ? "お気に入り" : "お気に入りに追加", systemImage: record.isFavorite ? "heart.fill" : "heart") }.tint(Color("BrandOrange")); Spacer(); if record.status == .wantToGo { Button("行ったにする") { record.status = .visited; record.visitDate = .now; saveChanges() }.buttonStyle(.borderedProminent) } }
                    }
                    Section("自分の記録") {
                        LabeledContent("状態", value: record.status.title)
                        if record.displayRating > 0 { LabeledContent("評価", value: "★ \(record.ratingText)") }
                        if let price = record.price { LabeledContent("価格帯", value: String(repeating: "¥", count: price)) }
                        if let visitDate = record.visitDate { LabeledContent("訪問日", value: visitDate.formatted(date: .long, time: .omitted)) }
                        if !record.memo.isEmpty { Text(record.memo) }
                        let recordTags = tags.filter { record.tagIDs.contains($0.id) }
                        if !recordTags.isEmpty { Text(recordTags.map(\.name).joined(separator: "  ")).foregroundStyle(Color("BrandOrange")) }
                        let localPhotos = photos.filter { $0.recordID == record.id }.sorted { $0.order < $1.order }
                        if !localPhotos.isEmpty {
                            NavigationLink {
                                PhotoGalleryView(photos: localPhotos)
                            } label: {
                                ScrollView(.horizontal) {
                                    HStack {
                                        ForEach(localPhotos) { photo in
                                            if let image = LocalPhotoStore().image(at: photo.thumbnailPath) {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 110, height: 110)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                                    .accessibilityLabel("写真 \(photo.order + 1)を拡大")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        NavigationLink { ReleasePhotoManagementView(recordID: record.id) } label: { Label("写真を管理", systemImage: "photo.on.rectangle.angled") }
                    }
                    if !record.relatedLinks.isEmpty {
                        Section("関連リンク") {
                            ForEach(Array(record.relatedLinks.enumerated()), id: \.offset) { _, value in
                                if let url = URL(string: value) {
                                    Link(destination: url) {
                                        Label(RelatedLinkFormatter.label(for: url), systemImage: "link")
                                    }
                                }
                            }
                        }
                    }
                    let localMenuItems = menuItems.filter { $0.recordID == record.id }.sorted { $0.order < $1.order }
                    if !localMenuItems.isEmpty { Section("食べたメニュー") { ForEach(localMenuItems) { item in LabeledContent(item.name, value: item.price.map { "¥\($0.formatted())" } ?? "") } } }
                    Section("店舗情報") {
                        LabeledContent("住所", value: place.address)
                        if !place.phoneNumber.isEmpty, let phoneURL = URL(string: "tel:\(place.phoneNumber.filter { $0.isNumber || $0 == "+" })") {
                            Link(destination: phoneURL) { Label(place.phoneNumber, systemImage: "phone") }
                        }
                        if !place.openingHours.isEmpty { LabeledContent("営業時間", value: place.openingHours) }
                        if let url = URL(string: place.websiteURL), !place.websiteURL.isEmpty {
                            Link(destination: url) { Label("Webサイト", systemImage: "safari") }
                        }
                        if place.latitude != 0 || place.longitude != 0 {
                            MapScreenPreview(place: place)
                            Link(destination: appleMapsURL(place: place)) {
                                Label("マップアプリで開く", systemImage: "map")
                            }
                        }
                        NavigationLink {
                            PlaceEditView(place: place)
                        } label: {
                            Label("店舗情報を編集", systemImage: "building.2.crop.circle")
                        }
                    }
                    Section("まとめ") {
                        let memberships = collections.filter { collection in
                            collectionEntries.contains { $0.collectionID == collection.id && $0.recordID == record.id }
                        }
                        ForEach(memberships) { collection in
                            NavigationLink(collection.title) { CollectionDetailView(collection: collection) }
                        }
                        if collections.isEmpty {
                            Text("設定でまとめを作成できます")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Menu {
                                ForEach(collections) { collection in
                                    let alreadyAdded = collectionEntries.contains { $0.collectionID == collection.id && $0.recordID == record.id }
                                    Button {
                                        add(record, to: collection)
                                    } label: {
                                        Label(collection.title, systemImage: alreadyAdded ? "checkmark" : "plus")
                                    }
                                    .disabled(alreadyAdded)
                                }
                            } label: {
                                Label("まとめへ追加", systemImage: "rectangle.stack.badge.plus")
                            }
                        }
                    }
                    Section("共有") {
                        NavigationLink {
                            ShareCardMakerView(
                                record: record,
                                place: place,
                                photos: photos.filter { $0.recordID == record.id },
                                tags: tags
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("投稿画像を作る", systemImage: "photo.badge.plus")
                                Text("無料テンプレートあり")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button { sharing = true } label: {
                            Label("お店の情報をテキストで共有", systemImage: "square.and.arrow.up")
                        }
                        Text("投稿画像は端末内で作成できます。テキスト共有ではLINEなど、端末に入っているアプリを選べます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("店舗詳細").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { sharing = true } label: { Label("このお店を共有", systemImage: "square.and.arrow.up") }.accessibilityLabel("\(place.name)を共有") }; ToolbarItem(placement: .topBarTrailing) { Menu { Button("記録を編集", systemImage: "pencil") { editing = true }; Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("ゴミ箱に移動", systemImage: "trash") } } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("その他") } }
                .sheet(isPresented: $editing) { NavigationStack { RecordEditView(record: record) } }
                .sheet(isPresented: $sharing) { ShareSheet(items: [restaurantShareText(record: record, place: place)]) }
                .alert("この記録をゴミ箱へ移動しますか？", isPresented: $showDeleteConfirmation) { Button("移動", role: .destructive) { record.isDeleted = true; record.deletedAt = .now; saveChanges(); dismiss() }; Button("キャンセル", role: .cancel) {} }
            } else { ContentUnavailableView("記録が見つかりません", systemImage: "exclamationmark.triangle") }
        }
    }
    private func add(_ record: RestaurantRecord, to collection: Collection) {
        guard !collectionEntries.contains(where: { $0.collectionID == collection.id && $0.recordID == record.id }) else { return }
        let nextOrder = collectionEntries.filter { $0.collectionID == collection.id }.map(\.order).max().map { $0 + 1 } ?? 0
        context.insert(CollectionEntry(collectionID: collection.id, recordID: record.id, order: nextOrder))
        saveChanges()
    }
    @ViewBuilder private func heroImage(record: RestaurantRecord) -> some View { if let photo = photos.filter({ $0.recordID == record.id }).sorted(by: { $0.order < $1.order }).first, let image = LocalPhotoStore().image(at: photo.imagePath) { Image(uiImage: image).resizable().scaledToFill() } else { Rectangle().fill(LinearGradient(colors: [Color("BrandSun"), Color("BrandOrange")], startPoint: .top, endPoint: .bottom)) } }
    private func saveChanges() {
        do { try context.save() } catch { errors.show(error, title: "変更を保存できませんでした") }
    }
    private func appleMapsURL(place: Place) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: place.name),
            URLQueryItem(name: "ll", value: "\(place.latitude),\(place.longitude)")
        ]
        return components.url!
    }
}
struct MapScreenPreview: View { let place: Place; var body: some View { Map(initialPosition: .region(MKCoordinateRegion(center: .init(latitude: place.latitude, longitude: place.longitude), span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)))) { Marker(place.name, coordinate: .init(latitude: place.latitude, longitude: place.longitude)) }.frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12)) } }

struct RecordEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    @Query private var tags: [Tag]
    @Query private var allPhotos: [RecordPhoto]
    @Query private var allMenuItems: [RecordMenuItem]

    let record: RestaurantRecord
    @State private var status: RecordStatus
    @State private var ratingHalfSteps: Int
    @State private var priceTier: Int
    @State private var includeDate: Bool
    @State private var visitDate: Date
    @State private var memo: String
    @State private var relatedLinks: [RelatedLinkDraft]
    @State private var selectedTags: Set<UUID>
    @State private var newTagName = ""
    @State private var menuItems: [MenuDraft] = []
    @State private var newPhotos: [PhotosPickerItem] = []
    @State private var deletedPhotoIDs: Set<UUID> = []
    @State private var didLoadRelatedData = false
    @State private var isSaving = false

    init(record: RestaurantRecord) {
        self.record = record
        _status = State(initialValue: record.status)
        _ratingHalfSteps = State(initialValue: record.ratingHalfSteps > 0 ? record.ratingHalfSteps : record.rating * 2)
        _priceTier = State(initialValue: record.price ?? 0)
        _includeDate = State(initialValue: record.visitDate != nil)
        _visitDate = State(initialValue: record.visitDate ?? .now)
        _memo = State(initialValue: record.memo)
        _relatedLinks = State(initialValue: record.relatedLinks.isEmpty ? [RelatedLinkDraft()] : record.relatedLinks.map { RelatedLinkDraft(value: $0) })
        _selectedTags = State(initialValue: Set(record.tagIDs))
    }

    private var existingPhotos: [RecordPhoto] {
        allPhotos
            .filter { $0.recordID == record.id && !deletedPhotoIDs.contains($0.id) }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        Form {
            Section("基本情報") {
                Picker("状態", selection: $status) {
                    ForEach(RecordStatus.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                RatingPicker(ratingHalfSteps: $ratingHalfSteps)
                Picker("価格帯", selection: $priceTier) {
                    Text("未設定").tag(0)
                    ForEach(1...4, id: \.self) { Text(String(repeating: "¥", count: $0)).tag($0) }
                }
                Toggle("訪問日を記録", isOn: $includeDate)
                if includeDate { DatePicker("訪問日", selection: $visitDate, displayedComponents: .date) }
                TextField("メモ", text: $memo, axis: .vertical)
                    .lineLimit(3...8)
            }

            RelatedLinksEditor(links: $relatedLinks)

            Section("写真") {
                PhotosPicker(selection: $newPhotos, maxSelectionCount: nil, matching: .images) {
                    Label("写真を追加", systemImage: "photo.on.rectangle")
                }
                if !newPhotos.isEmpty {
                    Text("新しい写真 \(newPhotos.count)枚を保存します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(existingPhotos.enumerated()), id: \.element.id) { index, photo in
                    HStack {
                        if let image = LocalPhotoStore().image(at: photo.thumbnailPath) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text("写真 \(index + 1)")
                        Spacer()
                        Button(role: .destructive) { deletedPhotoIDs.insert(photo.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("写真を削除")
                    }
                }
            }

            Section("食べたメニュー") {
                ForEach($menuItems) { $item in
                    HStack {
                        TextField("メニュー名", text: $item.name)
                        YenPriceField(text: $item.price)
                            .frame(width: 110)
                        Button(role: .destructive) { menuItems.removeAll { $0.id == item.id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("メニューを削除")
                    }
                }
                Button { menuItems.append(MenuDraft()) } label: { Label("メニューを追加", systemImage: "plus") }
            }

            Section("タグ") {
                HStack {
                    TextField("新しいタグ", text: $newTagName)
                    Button("追加", action: addTag)
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if tags.isEmpty {
                    Text("タグを追加すると、あとでお店を絞り込めます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(tags) { tag in
                                Button(tag.name) { toggle(tag) }
                                    .buttonStyle(.bordered)
                                    .tint(selectedTags.contains(tag.id) ? Color("BrandOrange") : .gray)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("記録を編集")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .overlay { if isSaving { ProgressView("保存中…").padding().background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12)) } }
        .onAppear(perform: loadRelatedDataIfNeeded)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { await save() } }
                    .disabled(isSaving || hasInvalidRelatedLinks)
                    .accessibilityIdentifier("saveRecordEdits")
            }
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
        }
    }

    private var hasInvalidRelatedLinks: Bool {
        relatedLinks.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && RelatedLinkFormatter.normalized($0.value) == nil }
    }

    private func loadRelatedDataIfNeeded() {
        guard !didLoadRelatedData else { return }
        didLoadRelatedData = true
        menuItems = allMenuItems
            .filter { $0.recordID == record.id }
            .sorted { $0.order < $1.order }
            .map { MenuDraft(id: $0.id, name: $0.name, price: $0.price?.formatted() ?? "") }
    }

    private func toggle(_ tag: Tag) {
        if selectedTags.contains(tag.id) { selectedTags.remove(tag.id) } else { selectedTags.insert(tag.id) }
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let normalized = name.lowercased()
        if let existing = tags.first(where: { $0.normalizedName == normalized }) {
            selectedTags.insert(existing.id)
        } else {
            let tag = Tag(name: name)
            context.insert(tag)
            selectedTags.insert(tag.id)
        }
        newTagName = ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        record.statusRaw = status.rawValue
        record.ratingHalfSteps = ratingHalfSteps
        record.rating = ratingHalfSteps / 2
        record.price = priceTier == 0 ? nil : priceTier
        record.visitDate = includeDate ? visitDate : nil
        record.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        record.relatedLinks = RelatedLinkFormatter.normalizedValues(relatedLinks.map(\.value))
        record.tagIDs = Array(selectedTags)
        record.updatedAt = .now

        let existingMenuItems = allMenuItems.filter { $0.recordID == record.id }
        existingMenuItems.forEach(context.delete)
        for (index, item) in menuItems.filter({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).enumerated() {
            context.insert(RecordMenuItem(
                recordID: record.id,
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                price: yenValue(item.price),
                order: index
            ))
        }

        for photo in allPhotos where photo.recordID == record.id && deletedPhotoIDs.contains(photo.id) {
            LocalPhotoStore().delete(photo: photo)
            context.delete(photo)
        }

        for (index, photo) in existingPhotos.enumerated() { photo.order = index }
        let nextPhotoOrder = existingPhotos.count
        let store = LocalPhotoStore()
        for (offset, item) in newPhotos.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let saved = try store.save(data, recordID: record.id, order: nextPhotoOrder + offset)
                context.insert(RecordPhoto(
                    recordID: record.id,
                    imagePath: saved.imagePath,
                    thumbnailPath: saved.thumbnailPath,
                    order: nextPhotoOrder + offset
                ))
            } catch {
                errors.show(error, title: "写真を保存できませんでした")
                return
            }
        }

        do {
            try context.save()
            dismiss()
        } catch {
            errors.show(error, title: "変更を保存できませんでした")
        }
    }
}

struct CollectionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    let collection: Collection
    @Query private var allEntries: [CollectionEntry]
    @Query private var records: [RestaurantRecord]
    @Query private var places: [Place]
    @Query private var photos: [RecordPhoto]

    private var orderedEntries: [CollectionEntry] {
        allEntries
            .filter { entry in
                entry.collectionID == collection.id && records.contains { $0.id == entry.recordID && !$0.isDeleted }
            }
            .sorted { left, right in
                left.order == right.order ? left.id.uuidString < right.id.uuidString : left.order < right.order
            }
    }

    private var coverCandidates: [(record: RestaurantRecord, place: Place?, photo: RecordPhoto)] {
        orderedEntries.compactMap { entry in
            guard let record = records.first(where: { $0.id == entry.recordID }),
                  let photo = photos.filter({ $0.recordID == record.id }).sorted(by: { $0.order < $1.order }).first else { return nil }
            return (record, places.first { $0.id == record.placeID }, photo)
        }
    }

    private var coverPath: String? {
        if let selected = collection.coverImagePath,
           LocalPhotoStore().image(at: selected) != nil { return selected }
        return coverCandidates.first?.photo.imagePath
    }

    var body: some View {
        List {
            Section {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let coverPath, let image = LocalPhotoStore().image(at: coverPath) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            LinearGradient(colors: [.orange.opacity(0.7), .brown], startPoint: .topLeading, endPoint: .bottomTrailing)
                                .overlay { Image(systemName: "rectangle.stack").font(.largeTitle).foregroundStyle(.white.opacity(0.8)) }
                        }
                    }
                    .frame(height: 190)
                    .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(collection.title).font(.title2.bold())
                        Text("\(orderedEntries.count)件のお店")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .padding()
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Menu {
                    Button {
                        collection.coverImagePath = nil
                        saveChanges()
                    } label: {
                        Label("先頭のお店を自動表示", systemImage: collection.coverImagePath == nil ? "checkmark" : "wand.and.stars")
                    }
                    ForEach(coverCandidates, id: \.photo.id) { candidate in
                        Button {
                            collection.coverImagePath = candidate.photo.imagePath
                            saveChanges()
                        } label: {
                            Label(candidate.place?.name ?? "店舗", systemImage: collection.coverImagePath == candidate.photo.imagePath ? "checkmark" : "photo")
                        }
                    }
                } label: {
                    Label("表紙を選ぶ", systemImage: "photo.on.rectangle")
                }
                .disabled(coverCandidates.isEmpty)
            }

            Section("お店") {
                if orderedEntries.isEmpty {
                    ContentUnavailableView("まだお店がありません", systemImage: "rectangle.stack", description: Text("店舗詳細の「まとめへ追加」から保存できます。"))
                } else {
                    ForEach(orderedEntries) { entry in
                        if let record = records.first(where: { $0.id == entry.recordID }) {
                            NavigationLink {
                                PlaceDetailView(recordID: record.id)
                            } label: {
                                CollectionRecordRow(
                                    record: record,
                                    place: places.first { $0.id == record.placeID },
                                    photo: photos.filter { $0.recordID == record.id }.sorted { $0.order < $1.order }.first
                                )
                            }
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: remove)
                }
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var entries = orderedEntries
        entries.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in entries.enumerated() { entry.order = index }
        saveChanges()
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets {
            let entry = orderedEntries[index]
            let selectedCoverBelongsToRemovedRecord = photos.contains {
                $0.recordID == entry.recordID && $0.imagePath == collection.coverImagePath
            }
            if selectedCoverBelongsToRemovedRecord { collection.coverImagePath = nil }
            context.delete(entry)
        }
        saveChanges()
    }

    private func saveChanges() {
        do { try context.save() } catch { errors.show(error, title: "まとめを保存できませんでした") }
    }
}

private struct CollectionRecordRow: View {
    let record: RestaurantRecord
    let place: Place?
    let photo: RecordPhoto?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let photo, let image = LocalPhotoStore().image(at: photo.thumbnailPath) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.orange.opacity(0.6), .brown], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(place?.name ?? "店舗").font(.headline).lineLimit(2)
                HStack(spacing: 8) {
                    Text(record.status.title)
                    if record.displayRating > 0 { Text("★ \(record.ratingText)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private func restaurantShareText(record: RestaurantRecord, place: Place) -> String {
    var lines = ["おすすめのお店：\(place.name)"]
    if !place.address.isEmpty { lines.append(place.address) }
    if record.displayRating > 0 { lines.append("評価：★ \(record.ratingText)") }
    if !record.memo.isEmpty { lines.append(record.memo) }
    if let website = URL(string: place.websiteURL), !place.websiteURL.isEmpty { lines.append(website.absoluteString) }
    let mapsURL = "https://maps.apple.com/?q=\(place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? place.name)"
    lines.append(mapsURL)
    return lines.joined(separator: "\n")
}

struct ShareSheet: UIViewControllerRepresentable { let items: [Any]; func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }; func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {} }
