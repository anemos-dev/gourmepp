import SwiftUI
import SwiftData
import PhotosUI
import MapKit
import UIKit

enum AppTab: Hashable { case home, map, record, settings }
enum HomeLayout: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var icon: String { switch self { case .grid: "square.grid.2x2"; case .list: "list.bullet" } }
    var title: String { switch self { case .grid: "写真"; case .list: "リスト" } }
}
enum HomeStatusFilter: String, CaseIterable, Identifiable {
    case all, visited, wantToGo
    var id: String { rawValue }
    var title: String { switch self { case .all: "すべて"; case .visited: "行った"; case .wantToGo: "行きたい" } }
    var status: RecordStatus? { switch self { case .all: nil; case .visited: .visited; case .wantToGo: .wantToGo } }
}
enum RecordSort: String, CaseIterable, Identifiable { case updated, visitDate, rating, name; var id: String { rawValue }; var title: String { switch self { case .updated: "追加順"; case .visitDate: "訪問日順"; case .rating: "評価順"; case .name: "店名順" } } }

struct AppView: View {
    @Environment(ProAccessController.self) private var proAccess
    @Environment(ProPreferences.self) private var proPreferences
    @State private var tab: AppTab = .home
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasAcceptedReleaseLegal") private var hasAcceptedReleaseLegal = false
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView() }.tabItem { Label("ホーム", systemImage: "house") }.tag(AppTab.home)
            NavigationStack { MapScreen() }.tabItem { Label("マップ", systemImage: "map") }.tag(AppTab.map)
            NavigationStack { RecordStartView() }.tabItem { Label("記録する", systemImage: "plus.circle.fill") }.tag(AppTab.record)
            NavigationStack { ReleaseSettingsView() }.tabItem { Label("設定", systemImage: "gearshape") }.tag(AppTab.settings)
        }
        .tint(proAccess.isProUnlocked ? proPreferences.accentColor : Color("BrandOrange"))
        .toolbarBackground(Color("PinterestCanvas"), for: .tabBar)
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding || !hasAcceptedReleaseLegal },
            set: { _ in }
        )) {
            OnboardingView {
                hasAcceptedReleaseLegal = true
                hasCompletedOnboarding = true
            }
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProAccessController.self) private var proAccess
    @Environment(ProPreferences.self) private var proPreferences
    @Query(sort: \RestaurantRecord.updatedAt, order: .reverse) private var records: [RestaurantRecord]
    @Query private var places: [Place]
    @Query private var tags: [Tag]
    @Query private var photos: [RecordPhoto]
    @State private var statusFilter: HomeStatusFilter = .all; @State private var query = ""; @State private var selectedTags: Set<UUID> = []; @State private var layout: HomeLayout = .grid; @State private var favoritesOnly = false; @State private var selectedPrice: Int?; @State private var selectedArea = ""; @State private var sort: RecordSort = .updated; @State private var minimumRating = 0.0; @State private var hasPhotosOnly = false; @State private var didApplyHomePreferences = false
    @State private var returnsOnly = false
    private var areas: [String] { Array(Set(places.map { $0.area.isEmpty ? Place.area(from: $0.address) : $0.area }.filter { !$0.isEmpty })).sorted() }
    private var displayed: [RestaurantRecord] {
        let recordsWithPhotos = Set(photos.map(\.recordID))
        let base = records.filtered(query: query, tags: selectedTags, places: places).filter { record in
            !record.isDeleted && (statusFilter.status == nil || record.status == statusFilter.status)
        }
            .filter { !favoritesOnly || $0.isFavorite }
            .filter { record in !returnsOnly || places.first { $0.id == record.placeID }?.wantsToReturn == true }
            .filter { selectedPrice == nil || $0.price == selectedPrice }
            .filter { minimumRating == 0 || $0.displayRating >= minimumRating }
            .filter { !hasPhotosOnly || recordsWithPhotos.contains($0.id) }
        let areaFiltered = selectedArea.isEmpty ? base : base.filter { record in
            let place = places.first { $0.id == record.placeID }
            return (place?.area.isEmpty == false ? place!.area : Place.area(from: place?.address ?? "")) == selectedArea
        }
        switch sort {
        case .updated: return areaFiltered.sorted { $0.updatedAt > $1.updatedAt }
        case .visitDate: return areaFiltered.sorted { ($0.visitDate ?? .distantPast) > ($1.visitDate ?? .distantPast) }
        case .rating: return areaFiltered.sorted { $0.displayRating > $1.displayRating }
        case .name: return areaFiltered.sorted { left, right in (places.first { $0.id == left.placeID }?.name ?? "").localizedCompare(places.first { $0.id == right.placeID }?.name ?? "") == .orderedAscending }
        }
    }
    var body: some View {
        VStack(spacing: 16) {
            statusPicker
            filterChips
            content
        }
        .background(Color("PinterestCanvas").ignoresSafeArea())
        .searchable(text: $query, prompt: "店名・エリア・メモを検索")
        .onAppear(perform: applyHomePreferencesIfNeeded)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("表示形式", selection: $layout) {
                        ForEach(HomeLayout.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    Picker("並び替え", selection: $sort) {
                        ForEach(RecordSort.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("お気に入りのみ", isOn: $favoritesOnly)
                    Toggle("また行きたいのみ", isOn: $returnsOnly)
                    NavigationLink { BulkRecordOrganizer(recordIDs: displayed.map(\.id)) } label: {
                        Label("記録をまとめて整理", systemImage: "checklist")
                    }
                    Menu("価格帯") {
                        Button("すべて") { selectedPrice = nil }
                        ForEach(1...4, id: \.self) { price in
                            Button(String(repeating: "¥", count: price)) { selectedPrice = price }
                        }
                    }
                    if !areas.isEmpty {
                        Menu("エリア") {
                            Button("すべて") { selectedArea = "" }
                            ForEach(areas, id: \.self) { area in Button(area) { selectedArea = area } }
                        }
                    }
                    Divider()
                    if proAccess.isProUnlocked {
                        NavigationLink {
                            AdvancedHomeFilterView(
                                query: $query,
                                statusFilter: $statusFilter,
                                selectedTags: $selectedTags,
                                favoritesOnly: $favoritesOnly,
                                selectedPrice: $selectedPrice,
                                selectedArea: $selectedArea,
                                minimumRating: $minimumRating,
                                hasPhotosOnly: $hasPhotosOnly,
                                tags: tags,
                                areas: areas
                            )
                        } label: {
                            Label("高度な絞り込み", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        if !proPreferences.savedFilters.isEmpty {
                            Menu("保存した条件") {
                                ForEach(proPreferences.savedFilters) { filter in
                                    Button(filter.name) { apply(filter) }
                                }
                            }
                        }
                    } else {
                        NavigationLink {
                            ProPaywallView()
                        } label: {
                            Label("高度な絞り込み（Pro）", systemImage: "lock.fill")
                        }
                    }
                } label: {
                    Image(systemName: layout.icon).foregroundStyle(Color("BrandOrange"))
                }
            }
        }
    }
    private var statusPicker: some View {
        Picker("記録の状態", selection: $statusFilter) {
            ForEach(HomeStatusFilter.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if tags.isEmpty { Text("写真から、お気に入りのお店を探せます").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16) }
                ForEach(tags) { tag in
                    Button(tag.name) {
                        if selectedTags.contains(tag.id) { selectedTags.remove(tag.id) } else { selectedTags.insert(tag.id) }
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(selectedTags.contains(tag.id) ? proPreferences.accentColor : Color.secondary)
                }
            }
            .padding(.horizontal)
        }
    }
    @ViewBuilder private var content: some View {
        if displayed.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "fork.knife")
            } description: {
                Text(hasActiveFilters ? "検索や絞り込み条件を変更してください。" : "「記録する」から最初のお店を保存しましょう。")
            } actions: {
                if hasActiveFilters {
                    Button("絞り込みを解除", action: resetFilters)
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            switch layout {
            case .grid:
                PinterestMasonryGrid(
                    records: displayed,
                    places: places,
                    photos: photos,
                    columnCount: proAccess.isProUnlocked ? proPreferences.gridColumns : 2,
                    showsCardDetails: !proAccess.isProUnlocked || proPreferences.showsCardDetails
                )
            case .list:
                List(displayed) { record in
                    NavigationLink {
                        PlaceDetailView(recordID: record.id)
                    } label: {
                        HomeListCard(
                            record: record,
                            place: places.first { $0.id == record.placeID },
                            photo: primaryPhoto(for: record)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
            }
        }
    }
    private var hasActiveFilters: Bool {
        !query.isEmpty || !selectedTags.isEmpty || returnsOnly || favoritesOnly || selectedPrice != nil || !selectedArea.isEmpty || minimumRating > 0 || hasPhotosOnly
    }
    private var emptyTitle: String {
        if hasActiveFilters { return "条件に合うお店がありません" }
        return statusFilter == .wantToGo ? "行きたいお店はまだありません" : "まだ記録がありません"
    }
    private func resetFilters() {
        query = ""
        selectedTags = []
        favoritesOnly = false
        returnsOnly = false
        selectedPrice = nil
        selectedArea = ""
        minimumRating = 0
        hasPhotosOnly = false
    }
    private func primaryPhoto(for record: RestaurantRecord) -> RecordPhoto? {
        photos.filter { $0.recordID == record.id }.min { $0.order < $1.order }
    }
    private func applyHomePreferencesIfNeeded() {
        guard !didApplyHomePreferences else { return }
        didApplyHomePreferences = true
        guard proAccess.isProUnlocked else { return }
        layout = HomeLayout(rawValue: proPreferences.defaultHomeLayoutRaw) ?? .grid
    }
    private func apply(_ filter: SavedHomeFilter) {
        query = filter.query
        statusFilter = filter.statusRaw.flatMap(HomeStatusFilter.init(rawValue:)) ?? .all
        selectedTags = Set(filter.tagIDs)
        favoritesOnly = filter.favoritesOnly
        selectedPrice = filter.price
        selectedArea = filter.area
        minimumRating = filter.minimumRating
        hasPhotosOnly = filter.hasPhotosOnly
    }
}

private struct HomeListCard: View {
    let record: RestaurantRecord
    let place: Place?
    let photo: RecordPhoto?

    var body: some View {
        HStack(spacing: 12) {
            image
                .frame(width: 96, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(place?.name ?? "店舗")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if record.displayRating > 0 {
                        Label(record.ratingText, systemImage: "star.fill")
                            .foregroundStyle(Color("BrandOrange"))
                    } else {
                        Text("未評価")
                            .foregroundStyle(.secondary)
                    }
                    Text(record.status.title)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))

                if place?.wantsToReturn == true {
                    Label("また行きたい", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.caption).foregroundStyle(Color("BrandOrange"))
                }
                Text([place?.category, place?.area].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "・"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if record.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color("BrandOrange"))
                    .accessibilityHidden(true)
            }
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color("BrandOrange"), lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var image: some View {
        if let photo, let uiImage = LocalPhotoStore().image(at: photo.thumbnailPath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [Color("BrandSun"), Color("BrandOrange")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private var accessibilityText: String {
        let rating = record.displayRating > 0 ? "評価\(record.ratingText)" : "未評価"
        return "\(place?.name ?? "店舗")、\(rating)、\(record.status.title)\(place?.wantsToReturn == true ? "、また行きたい" : "")"
    }
}

private struct PinterestMasonryGrid: View {
    let records: [RestaurantRecord]
    let places: [Place]
    let photos: [RecordPhoto]
    let columnCount: Int
    let showsCardDetails: Bool
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(records) { record in
                    PinterestRecordTile(
                        record: record,
                        place: places.first { $0.id == record.placeID },
                        photo: photos.filter { $0.recordID == record.id }.min { $0.order < $1.order },
                        showsCardDetails: showsCardDetails
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
    }
}

private struct PinterestRecordTile: View {
    let record: RestaurantRecord
    let place: Place?
    let photo: RecordPhoto?
    let showsCardDetails: Bool
    private let fallbackColors: [Color] = [Color("BrandOrange"), .orange, .brown, .teal, .indigo]
    private var fallbackColor: Color {
        let index = record.id.uuidString.utf8.reduce(0) { ($0 + Int($1)) % fallbackColors.count }
        return fallbackColors[index]
    }
    var body: some View {
        NavigationLink {
            PlaceDetailView(recordID: record.id)
        } label: {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    image
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
                    VStack {
                        HStack {
                            if showsCardDetails {
                                Text(record.status.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(.black.opacity(0.42), in: Capsule())
                            }
                            Spacer()
                            if record.isFavorite {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(Color("BrandOrange"))
                                    .padding(8)
                                    .background(.black.opacity(0.42), in: Circle())
                            }
                        }
                        Spacer()
                    }
                    .padding(9)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place?.name ?? "店舗")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        if place?.wantsToReturn == true {
                            Label("また行きたい", systemImage: "arrow.uturn.backward.circle.fill").font(.caption2)
                        }
                        if showsCardDetails && record.displayRating > 0 { Text("★ \(record.ratingText)").font(.caption.weight(.medium)) }
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(10)
                }
            }
            .aspectRatio(0.8, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(place?.name ?? "店舗")、\(record.status.title)\(place?.wantsToReturn == true ? "、また行きたい" : "")")
        .accessibilityIdentifier("restaurantCard-\(record.id.uuidString)")
    }
    @ViewBuilder private var image: some View {
        if let photo, let uiImage = LocalPhotoStore().image(at: photo.thumbnailPath) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [Color("BrandSun"), fallbackColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(.white.opacity(0.75)) }
        }
    }
}

struct RecordCard: View {
    let record: RestaurantRecord; let place: Place?; let compact: Bool; let photo: RecordPhoto?
    init(record: RestaurantRecord, place: Place?, compact: Bool, photo: RecordPhoto? = nil) { self.record = record; self.place = place; self.compact = compact; self.photo = photo }
    var body: some View { VStack(alignment: .leading, spacing: 6) { ZStack(alignment: .bottomLeading) { Group { if let photo, let image = LocalPhotoStore().image(at: photo.thumbnailPath) { Image(uiImage: image).resizable().scaledToFill() } else { Rectangle().fill(LinearGradient(colors: [Color("BrandSun"), Color("BrandOrange")], startPoint: .top, endPoint: .bottom)) } }.aspectRatio(compact ? 1 : 2.4, contentMode: .fit).clipped(); Text(place?.name ?? "店舗").font(compact ? .caption.bold() : .headline).foregroundStyle(.white).lineLimit(2).padding(9).shadow(radius: 2) }; if !compact { HStack { Label(record.status.title, systemImage: record.status == .visited ? "checkmark.circle.fill" : "bookmark.fill"); if record.displayRating > 0 { Text("★ \(record.ratingText)") }; Spacer(); Text(place?.area ?? "").lineLimit(1) }.font(.caption).foregroundStyle(.secondary) } }.clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
