import SwiftUI

struct AdvancedHomeFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProPreferences.self) private var proPreferences
    @Binding var query: String
    @Binding var statusFilter: HomeStatusFilter
    @Binding var selectedTags: Set<UUID>
    @Binding var favoritesOnly: Bool
    @Binding var selectedPrice: Int?
    @Binding var selectedArea: String
    @Binding var minimumRating: Double
    @Binding var hasPhotosOnly: Bool
    let tags: [Tag]
    let areas: [String]
    @State private var filterName = ""

    var body: some View {
        Form {
            if !proPreferences.savedFilters.isEmpty {
                Section("保存した条件") {
                    ForEach(proPreferences.savedFilters) { filter in
                        Button {
                            apply(filter)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(filter.name)
                                Text(summary(for: filter))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: proPreferences.deleteSavedFilters)
                }
            }

            Section("複合条件") {
                TextField("店名・エリア・メモ", text: $query)
                Picker("状態", selection: $statusFilter) {
                    ForEach(HomeStatusFilter.allCases) { Text($0.title).tag($0) }
                }
                Picker("最低評価", selection: $minimumRating) {
                    Text("指定なし").tag(0.0)
                    ForEach([3.0, 3.5, 4.0, 4.5, 5.0], id: \.self) { rating in
                        Text("★ \(String(format: "%.1f", rating))以上").tag(rating)
                    }
                }
                Picker("価格帯", selection: $selectedPrice) {
                    Text("指定なし").tag(Int?.none)
                    ForEach(1...4, id: \.self) { price in
                        Text(String(repeating: "¥", count: price)).tag(Optional(price))
                    }
                }
                if !areas.isEmpty {
                    Picker("エリア", selection: $selectedArea) {
                        Text("指定なし").tag("")
                        ForEach(areas, id: \.self) { Text($0).tag($0) }
                    }
                }
                Toggle("お気に入りのみ", isOn: $favoritesOnly)
                Toggle("写真がある記録のみ", isOn: $hasPhotosOnly)
            }

            if !tags.isEmpty {
                Section("タグ（すべて一致）") {
                    ForEach(tags) { tag in
                        Toggle(tag.name, isOn: tagBinding(for: tag.id))
                    }
                }
            }

            Section("この条件を保存") {
                TextField("例：新宿の高評価ランチ", text: $filterName)
                Button("条件を保存", action: saveCurrentFilter)
                    .disabled(filterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("同じ名前で保存すると、以前の条件を更新します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("すべての条件を解除", role: .destructive, action: reset)
            }
        }
        .navigationTitle("高度な絞り込み")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tagBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedTags.contains(id) },
            set: { isSelected in
                if isSelected { selectedTags.insert(id) } else { selectedTags.remove(id) }
            }
        )
    }

    private func saveCurrentFilter() {
        let name = filterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        proPreferences.save(SavedHomeFilter(
            name: name,
            query: query,
            statusRaw: statusFilter == .all ? nil : statusFilter.rawValue,
            tagIDs: Array(selectedTags),
            favoritesOnly: favoritesOnly,
            price: selectedPrice,
            area: selectedArea,
            minimumRating: minimumRating,
            hasPhotosOnly: hasPhotosOnly
        ))
        filterName = ""
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

    private func reset() {
        query = ""
        statusFilter = .all
        selectedTags = []
        favoritesOnly = false
        selectedPrice = nil
        selectedArea = ""
        minimumRating = 0
        hasPhotosOnly = false
    }

    private func summary(for filter: SavedHomeFilter) -> String {
        var parts: [String] = []
        if let raw = filter.statusRaw, let status = HomeStatusFilter(rawValue: raw) { parts.append(status.title) }
        if filter.minimumRating > 0 { parts.append("★\(String(format: "%.1f", filter.minimumRating))以上") }
        if let price = filter.price { parts.append(String(repeating: "¥", count: price)) }
        if !filter.area.isEmpty { parts.append(filter.area) }
        if filter.favoritesOnly { parts.append("お気に入り") }
        if filter.hasPhotosOnly { parts.append("写真あり") }
        if !filter.tagIDs.isEmpty { parts.append("タグ\(filter.tagIDs.count)件") }
        return parts.isEmpty ? "すべての記録" : parts.joined(separator: "・")
    }
}

struct ProCustomizationView: View {
    @Environment(ProPreferences.self) private var proPreferences

    var body: some View {
        @Bindable var preferences = proPreferences
        Form {
            Section("テーマカラー") {
                Picker("テーマカラー", selection: $preferences.accentTheme) {
                    ForEach(ProAccentTheme.allCases) { theme in
                        Label {
                            Text(theme.title)
                        } icon: {
                            Circle().fill(theme.color).frame(width: 14, height: 14)
                        }
                        .tag(theme)
                    }
                }
                .pickerStyle(.inline)
                Text("タブ、ボタン、選択中のタグなどに反映されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("ホームの写真表示") {
                Picker("グリッド列数", selection: $preferences.gridColumns) {
                    Text("2列").tag(2)
                    Text("3列").tag(3)
                    Text("4列").tag(4)
                }
                .pickerStyle(.segmented)
                Toggle("状態と評価をカードに表示", isOn: $preferences.showsCardDetails)
            }

            Section("ホームを開いたとき") {
                Picker("初期表示", selection: $preferences.defaultHomeLayoutRaw) {
                    ForEach(HomeLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.icon).tag(layout.rawValue)
                    }
                }
            }

            Section {
                Button("標準設定に戻す", role: .destructive) {
                    preferences.accentTheme = .orange
                    preferences.gridColumns = 2
                    preferences.showsCardDetails = true
                    preferences.defaultHomeLayoutRaw = HomeLayout.grid.rawValue
                }
            }
        }
        .navigationTitle("Proカスタマイズ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
