import SwiftUI
import SwiftData
import PhotosUI
import MapKit

struct MenuDraft: Identifiable {
    let id: UUID
    var name: String
    var price: String

    init(id: UUID = UUID(), name: String = "", price: String = "") {
        self.id = id
        self.name = name
        self.price = price
    }
}

struct RelatedLinkDraft: Identifiable {
    let id: UUID
    var value: String

    init(id: UUID = UUID(), value: String = "") {
        self.id = id
        self.value = value
    }
}

enum RelatedLinkFormatter {
    nonisolated static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = URL(string: trimmed)?.scheme == nil ? "https://\(trimmed)" : trimmed
        guard let components = URLComponents(string: candidate),
              ["http", "https"].contains(components.scheme?.lowercased()),
              components.host?.isEmpty == false,
              let url = components.url else { return nil }
        return url.absoluteString
    }

    nonisolated static func label(for url: URL) -> String {
        let host = (url.host() ?? "").lowercased()
        if host.contains("instagram.com") { return "Instagramの投稿" }
        if host == "x.com" || host.hasSuffix(".x.com") || host.contains("twitter.com") { return "Xの投稿" }
        if host.contains("tiktok.com") { return "TikTokの投稿" }
        if host.contains("youtube.com") || host == "youtu.be" { return "YouTube" }
        return host.replacingOccurrences(of: "www.", with: "").isEmpty ? "関連リンク" : host.replacingOccurrences(of: "www.", with: "")
    }

    nonisolated static func normalizedValues(_ values: [String]) -> [String] {
        values.compactMap(normalized).reduce(into: []) { result, value in
            if !result.contains(value) { result.append(value) }
        }
    }
}

struct RelatedLinksEditor: View {
    @Binding var links: [RelatedLinkDraft]

    var body: some View {
        Section("関連リンク") {
            ForEach($links) { $link in
                HStack {
                    TextField("SNS投稿などのURL", text: $link.value)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(role: .destructive) {
                        links.removeAll { $0.id == link.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("関連リンクを削除")
                }
                if !link.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   RelatedLinkFormatter.normalized(link.value) == nil {
                    Label("開けるURLを入力してください", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Button { links.append(RelatedLinkDraft()) } label: {
                Label("リンクを追加", systemImage: "link.badge.plus")
            }
            Text("このお店を知ったSNS投稿や記事を保存できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct RecordStartView: View {
    @Environment(\.modelContext) private var context; @State private var showManual = false; @State private var query = ""; @State private var results: [PlaceCandidate] = []; @State private var isLoading = false; @State private var locationService = DeviceLocationService(); @State private var searchMessage: String?
    private let search = AppleMapSearchClient()
    var body: some View { List { Section("お店を探す") { HStack { TextField("店名・住所から検索", text: $query).onSubmit { Task { await runSearch() } }; if isLoading { ProgressView() } }; Button { Task { await runSearch() } } label: { Label("検索する", systemImage: "magnifyingglass") }; Button { locationService.request() } label: { Label("現在地を使う", systemImage: "location") }.accessibilityIdentifier("useCurrentLocation"); if locationService.currentLocation != nil { Label("現在地付近を検索します", systemImage: "location.fill").font(.caption).foregroundStyle(.secondary) }; Button { showManual = true } label: { Label("店舗情報を手入力", systemImage: "square.and.pencil") }.accessibilityIdentifier("enterPlaceManually") }
            if let searchMessage { ContentUnavailableView(searchMessage, systemImage: "magnifyingglass", description: Text("店名やエリアを変えて、もう一度お試しください。")) }
            if !results.isEmpty { Section("検索結果（\(results.count)件）") { ForEach(results) { candidate in NavigationLink { RecordEditor(candidate: candidate) } label: { VStack(alignment: .leading, spacing: 3) { Text(candidate.name); Text(candidate.address).font(.caption).foregroundStyle(.secondary).lineLimit(2) } } } } }
        }
        .navigationTitle("記録する")
        .themeScreenBackground()
        .sheet(isPresented: $showManual) { NavigationStack { ManualPlaceView() } }
    }
    private func runSearch() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        isLoading = true
        searchMessage = nil
        defer { isLoading = false }
        let region = locationService.currentLocation.map { MKCoordinateRegion(center: $0.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)) }
        do {
            results = try await search.search(query: trimmedQuery, region: region)
            if results.isEmpty { searchMessage = "候補が見つかりませんでした" }
        } catch {
            results = []
            searchMessage = "検索できませんでした"
        }
    }
}

struct ManualPlaceView: View { @Environment(\.dismiss) private var dismiss; @State private var name = ""; @State private var address = ""; var body: some View { Form { TextField("店名（必須）", text: $name).accessibilityIdentifier("manualPlaceName"); TextField("住所", text: $address).accessibilityIdentifier("manualPlaceAddress"); NavigationLink("このお店を記録") { RecordEditor(candidate: PlaceCandidate(id: UUID().uuidString, name: name, address: address, latitude: 0, longitude: 0, category: "")) }.disabled(name.isEmpty).accessibilityIdentifier("recordManualPlace") }.navigationTitle("店舗を手入力").themeScreenBackground().toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } } } }

struct RecordEditor: View {
    @Environment(ProAccessController.self) private var proAccess
    @State private var nextMealNote = ""
    @State private var wantsToReturn = false
    @State private var didLoadPlacePreferences = false
    @Environment(\.modelContext) private var context; @Environment(\.dismiss) private var dismiss; @Environment(AppErrorCenter.self) private var errors; @Query private var places: [Place]; @Query private var tags: [Tag]
    let candidate: PlaceCandidate; @State private var status: RecordStatus = .visited; @State private var ratingHalfSteps = 0; @State private var memo = ""; @State private var relatedLinks: [RelatedLinkDraft] = [RelatedLinkDraft()]; @State private var visitDate = Date(); @State private var includeDate = true; @State private var selectedTags: Set<UUID> = []; @State private var newTagName = ""; @State private var photos: [PhotosPickerItem] = []; @State private var priceTier = 0; @State private var menuItems: [MenuDraft] = []; @State private var isSaving = false

    var body: some View {
        Form {
            Section("店舗") { Text(candidate.name).font(.headline); Text(candidate.address).font(.caption) }
            Section("必須") { Picker("ステータス", selection: $status) { ForEach(RecordStatus.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented) }
            Section("記録（あとから編集できます）") {
                PhotosPicker(selection: $photos, maxSelectionCount: nil, matching: .images, preferredItemEncoding: .current) { Label("写真を追加", systemImage: "photo.on.rectangle") }
                PhotoDateSuggestion(photos: photos, visitDate: $visitDate, includeDate: $includeDate)
                RatingPicker(ratingHalfSteps: $ratingHalfSteps)
                Picker("価格帯", selection: $priceTier) {
                    Text("未設定").tag(0)
                    ForEach(PriceTier.allCases) { tier in
                        Text(tier.label).tag(tier.rawValue)
                    }
                }
                Toggle("訪問日を記録", isOn: $includeDate)
                if includeDate { DatePicker("訪問日", selection: $visitDate, displayedComponents: .date) }
                TextField("メモ", text: $memo, axis: .vertical)
                    .accessibilityIdentifier("recordMemo")
            }
            Section("次回の楽しみ") { Toggle("また行きたい", isOn: $wantsToReturn) }
            NextMealNoteSection(note: $nextMealNote)
            RelatedLinksEditor(links: $relatedLinks)
            Section("食べたメニュー") {
                ForEach($menuItems) { $item in
                    HStack {
                        TextField("メニュー名", text: $item.name)
                        YenPriceField(text: $item.price)
                            .frame(width: 110)
                        Button(role: .destructive) { menuItems.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("メニューを削除")
                    }
                }
                Button { menuItems.append(MenuDraft()) } label: { Label("メニューを追加", systemImage: "plus") }
            }
            Section("タグ") {
                HStack {
                    TextField("新しいタグ", text: $newTagName)
                    Button("追加", action: addTag).disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if tags.isEmpty { Text("タグを追加すると、あとでお店を絞り込めます。").font(.caption).foregroundStyle(.secondary) }
                else { ScrollView(.horizontal) { HStack { ForEach(tags) { tag in Button(tag.name) { toggle(tag) }.buttonStyle(.bordered).tint(selectedTags.contains(tag.id) ? Color("BrandOrange") : .gray) } } } }
            }
        }
        .navigationTitle("お店を記録")
        .themeScreenBackground()
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            guard !didLoadPlacePreferences else { return }
            didLoadPlacePreferences = true
            if let place = places.first(where: { $0.externalPlaceID == candidate.id }) {
                nextMealNote = place.nextMealNote
                wantsToReturn = place.wantsToReturn
            }
        }
        .disabled(isSaving)
        .overlay { if isSaving { ProgressView("保存中…").padding().background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12)) } }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(isSaving || hasInvalidRelatedLinks).accessibilityIdentifier("saveRecord") } }
    }

    private var hasInvalidRelatedLinks: Bool {
        relatedLinks.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && RelatedLinkFormatter.normalized($0.value) == nil }
    }

    private func toggle(_ tag: Tag) { if selectedTags.contains(tag.id) { selectedTags.remove(tag.id) } else { selectedTags.insert(tag.id) } }
    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let normalized = name.lowercased()
        if let existing = tags.first(where: { $0.normalizedName == normalized }) { selectedTags.insert(existing.id) }
        else { let tag = Tag(name: name); context.insert(tag); selectedTags.insert(tag.id) }
        newTagName = ""
    }
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let store = LocalPhotoStore()
        var staged: [RecordPhoto] = []
        do {
            try context.save()
            let place = places.first { $0.externalPlaceID == candidate.id } ?? Place(name: candidate.name, address: candidate.address, latitude: candidate.latitude, longitude: candidate.longitude, externalPlaceID: candidate.id, category: candidate.category)
            let record = RestaurantRecord(placeID: place.id, status: status)
            for (index, item) in photos.enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let saved = try store.save(data, recordID: record.id, order: index)
                let photo = RecordPhoto(recordID: record.id, imagePath: saved.imagePath, thumbnailPath: saved.thumbnailPath, order: index)
                photo.takenAt = PhotoCaptureDate.read(from: data)
                staged.append(photo)
            }
            if !places.contains(where: { $0.id == place.id }) { context.insert(place) }
            place.wantsToReturn = wantsToReturn
            if proAccess.isProUnlocked { place.nextMealNote = nextMealNote.trimmingCharacters(in: .whitespacesAndNewlines) }
            record.rating = ratingHalfSteps / 2
            record.ratingHalfSteps = ratingHalfSteps
            record.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
            record.relatedLinks = RelatedLinkFormatter.normalizedValues(relatedLinks.map(\.value))
            record.price = priceTier == 0 ? nil : priceTier
            record.visitDate = includeDate ? visitDate : nil
            record.tagIDs = Array(selectedTags)
            InitialReleasePrivacy.apply(to: record)
            context.insert(record)
            for (index, item) in menuItems.filter({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).enumerated() {
                context.insert(RecordMenuItem(recordID: record.id, name: item.name.trimmingCharacters(in: .whitespacesAndNewlines), price: yenValue(item.price), order: index))
            }
            staged.forEach(context.insert)
            try context.save()
            dismiss()
        } catch {
            let stagedPaths = staged.map { ($0.imagePath, $0.thumbnailPath) }
            context.rollback()
            stagedPaths.forEach { store.delete(imagePath: $0.0, thumbnailPath: $0.1) }
            errors.show(error, title: "記録を保存できませんでした")
        }
    }
}

struct RatingPicker: View {
    @Binding var ratingHalfSteps: Int
    private var ratingText: String {
        guard ratingHalfSteps > 0 else { return "未評価" }
        return ratingHalfSteps.isMultiple(of: 2) ? "★ \(ratingHalfSteps / 2)" : "★ \(Double(ratingHalfSteps) / 2)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("評価  \(ratingText)")
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    HalfStarButton(star: star, ratingHalfSteps: $ratingHalfSteps)
                }
                if ratingHalfSteps > 0 {
                    Button {
                        ratingHalfSteps = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("評価をクリア")
                }
            }
            Text("星の左半分で0.5、右半分で1.0刻みで選べます")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HalfStarButton: View {
    let star: Int
    @Binding var ratingHalfSteps: Int

    private var fillAmount: CGFloat {
        let amount = ratingHalfSteps - (star - 1) * 2
        return CGFloat(min(max(amount, 0), 2)) / 2
    }

    var body: some View {
        ZStack {
            Image(systemName: "star")
                .foregroundStyle(.yellow)
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle().frame(width: proxy.size.width * fillAmount)
                    }
                }
            HStack(spacing: 0) {
                ratingButton(value: star * 2 - 1)
                ratingButton(value: star * 2)
            }
            .frame(width: 44, height: 44)
        }
        .font(.title2)
        .frame(width: 44, height: 44)
    }

    private func ratingButton(value: Int) -> some View {
        Button {
            ratingHalfSteps = value
        } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("星 \(Double(value) / 2, format: .number.precision(.fractionLength(1))) にする")
    }
}

struct YenPriceField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            Text("¥")
                .foregroundStyle(.secondary)
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("価格、円")
                .onChange(of: text) { _, newValue in
                    let formatted = formattedYenInput(newValue)
                    if formatted != newValue { text = formatted }
                }
        }
    }
}

func yenValue(_ text: String) -> Int? {
    let digits = text.filter(\.isNumber)
    guard !digits.isEmpty else { return nil }
    return Int(digits)
}

private func formattedYenInput(_ text: String) -> String {
    guard let value = yenValue(text) else { return "" }
    return value.formatted(.number.grouping(.automatic))
}
