import PhotosUI
import SwiftData
import SwiftUI

struct PhotoDateSuggestion: View {
    private enum SuggestionState: Equatable {
        case idle
        case loading
        case available([Date])
        case unavailable
        case timedOut
    }

    let photos: [PhotosPickerItem]
    @Binding var visitDate: Date
    @Binding var includeDate: Bool
    @State private var state: SuggestionState = .idle

    private var photoIdentifiers: [String] {
        photos.compactMap(\.itemIdentifier)
    }

    var body: some View {
        Group {
            if !photos.isEmpty {
                switch state {
                case .idle, .loading:
                    ProgressView("撮影日を確認中…")
                case .available(let dates):
                    ForEach(dates, id: \.self) { date in
                        Button {
                            visitDate = date
                            includeDate = true
                        } label: {
                            Label("撮影日を使う：\(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar.badge.clock")
                        }
                    }
                case .unavailable:
                    Text("撮影日を取得できない写真です。訪問日は手入力できます。")
                        .font(.caption).foregroundStyle(.secondary)
                case .timedOut:
                    Text("撮影日の確認に時間がかかっています。訪問日は手入力できます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: photoIdentifiers) {
            guard !photoIdentifiers.isEmpty else {
                state = photos.isEmpty ? .idle : .unavailable
                return
            }

            state = .loading
            let identifiers = photoIdentifiers
            await withTaskGroup(of: SuggestionState.self) { group in
                group.addTask {
                    let dates = await withTaskGroup(of: Date?.self) { dateGroup in
                        for identifier in identifiers {
                            dateGroup.addTask {
                                await MainActor.run {
                                    PhotoCaptureDate.libraryDate(for: identifier)
                                }
                            }
                        }
                        var dates = Set<Date>()
                        for await date in dateGroup {
                            if let date { dates.insert(Calendar.current.startOfDay(for: date)) }
                        }
                        return dates.sorted()
                    }
                    return dates.isEmpty ? .unavailable : .available(dates)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(2))
                    return .timedOut
                }

                guard let result = await group.next(), !Task.isCancelled else { return }
                group.cancelAll()
                state = result
            }
        }
    }
}

struct NextMealNoteSection: View {
    @Environment(ProAccessController.self) private var proAccess
    @Binding var note: String
    @State private var showProPaywall = false

    var body: some View {
        Section {
            if proAccess.isProUnlocked {
                TextField("次は季節のパフェを食べたい", text: $note, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityIdentifier("nextMealNote")
                Text("このお店の次回の記録時にも表示します。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if !note.isEmpty { Text(note) }
                Button { showProPaywall = true } label: {
                    Label("Proで次に食べたいメニューを残す", systemImage: "lock.fill")
                }
            }
        } header: {
            Text("次に食べたい · Pro")
        }
        .proPaywall(isPresented: $showProPaywall)
    }
}

struct NextMealNoteView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProAccessController.self) private var proAccess
    @Environment(AppErrorCenter.self) private var errors
    let place: Place
    @State private var note: String

    init(place: Place) {
        self.place = place
        _note = State(initialValue: place.nextMealNote)
    }

    var body: some View {
        Form {
            Text(place.name).font(.headline)
            NextMealNoteSection(note: $note)
        }
        .navigationTitle("次に食べたい")
        .themeScreenBackground()
        .toolbar {
            if proAccess.isProUnlocked {
                Button("保存") {
                    let previous = place.nextMealNote
                    place.nextMealNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    do { try context.save(); dismiss() }
                    catch { place.nextMealNote = previous; errors.show(error, title: "保存できませんでした") }
                }
            }
        }
    }
}

struct CreateCollectionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppErrorCenter.self) private var errors
    let recordIDs: [UUID]
    @State private var name = ""

    var body: some View {
        Form {
            TextField("まとめ名", text: $name)
                .accessibilityIdentifier("newCollectionName")
            Text("選んだ\(recordIDs.count)件の記録を、新しいまとめに追加します。")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("まとめを作成")
        .themeScreenBackground()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("作成して追加") { create() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func create() {
        let collection = Collection(title: name.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(collection)
        let entries = recordIDs.enumerated().map { CollectionEntry(collectionID: collection.id, recordID: $0.element, order: $0.offset) }
        entries.forEach(context.insert)
        do { try context.save(); dismiss() }
        catch {
            entries.forEach(context.delete)
            context.delete(collection)
            errors.show(error, title: "まとめを作成できませんでした")
        }
    }
}

struct BulkRecordOrganizer: View {
    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    @Query private var allRecords: [RestaurantRecord]
    @Query private var places: [Place]
    @Query private var tags: [Tag]
    @Query private var collections: [Collection]
    @Query private var entries: [CollectionEntry]
    let recordIDs: [UUID]
    @State private var selection: Set<UUID> = []
    @State private var showDelete = false
    @State private var newTag = ""
    @State private var message = ""
    @State private var createCollection: CollectionSelection?

    private var records: [RestaurantRecord] {
        let byID = Dictionary(uniqueKeysWithValues: allRecords.filter { !$0.isTrashed }.map { ($0.id, $0) })
        return recordIDs.compactMap { byID[$0] }
    }
    private var selected: [RestaurantRecord] { records.filter { selection.contains($0.id) } }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("\(selected.count)件を選択")
                    Spacer()
                    Button(selection.isEmpty ? "すべて選択" : "選択解除") {
                        selection = selection.isEmpty ? Set(records.map(\.id)) : []
                    }
                }
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section("操作") {
                Menu {
                    ForEach(tags) { tag in Button(tag.name) { addTag(tag) } }
                } label: { Label("タグを追加", systemImage: "tag") }
                    .disabled(selected.isEmpty || tags.isEmpty)
                HStack {
                    TextField("新しいタグ", text: $newTag)
                    Button("作成して追加") { createTag() }
                        .disabled(selected.isEmpty || newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Menu {
                    ForEach(collections) { collection in
                        Button(collection.title) { addToCollection(collection) }
                    }
                    Button("新しいまとめを作成") { createCollection = CollectionSelection(ids: selected.map(\.id)) }
                } label: { Label("まとめへ追加", systemImage: "rectangle.stack.badge.plus") }
                    .disabled(selected.isEmpty)
                Button("ゴミ箱へ移動", role: .destructive) { showDelete = true }
                    .disabled(selected.isEmpty)
            }
            Section("記録") {
                ForEach(records) { record in
                    Button {
                        if !selection.insert(record.id).inserted { selection.remove(record.id) }
                    } label: {
                        HStack {
                            Image(systemName: selection.contains(record.id) ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text(places.first { $0.id == record.placeID }?.name ?? "店舗")
                                Text(record.visitDate?.formatted(date: .abbreviated, time: .omitted) ?? record.status.title)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityValue(selection.contains(record.id) ? "選択中" : "未選択")
                }
            }
        }
        .navigationTitle("記録をまとめて整理")
        .themeScreenBackground()
        .sheet(item: $createCollection) { item in
            NavigationStack { CreateCollectionView(recordIDs: item.ids) }
        }
        .alert("\(selected.count)件をゴミ箱へ移動しますか？", isPresented: $showDelete) {
            Button("移動", role: .destructive) {
                if apply({
                    for record in selected { record.isTrashed = true; record.deletedAt = .now; record.updatedAt = .now }
                }) {
                    selection = []
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("設定のゴミ箱から復元できます。") }
    }

    @discardableResult
    private func apply(_ change: () -> Void) -> Bool {
        do {
            // Save earlier edits before creating an isolated rollback boundary.
            try context.save()
            change()
            try context.save()
            message = "変更を保存しました"
            return true
        } catch {
            context.rollback()
            errors.show(error, title: "一括変更を保存できませんでした")
            return false
        }
    }
    private func addTag(_ tag: Tag) {
        apply {
            for record in selected where !record.tagIDs.contains(tag.id) {
                record.tagIDs.append(tag.id); record.updatedAt = .now
            }
        }
    }
    private func createTag() {
        let name = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let tag = tags.first(where: { SearchText.normalize($0.name) == SearchText.normalize(name) }) {
            addTag(tag)
        } else {
            apply {
                let tag = Tag(name: name)
                context.insert(tag)
                for record in selected { record.tagIDs.append(tag.id); record.updatedAt = .now }
            }
        }
        newTag = ""
    }
    private func addToCollection(_ collection: Collection) {
        apply {
            var order = (entries.filter { $0.collectionID == collection.id }.map(\.order).max() ?? -1) + 1
            for record in selected where !entries.contains(where: { $0.collectionID == collection.id && $0.recordID == record.id }) {
                context.insert(CollectionEntry(collectionID: collection.id, recordID: record.id, order: order))
                order += 1
            }
        }
    }
}

struct CollectionSelection: Identifiable {
    let id = UUID()
    let ids: [UUID]
}

struct MonthlyFoodReportView: View {
    @Query private var records: [RestaurantRecord]
    @State private var selectedYear = Calendar.current.component(.year, from: .now)
    @State private var selectedMonth = Calendar.current.component(.month, from: .now)
    private var years: [Int] {
        Array(Set(records.compactMap(\.visitDate).map { Calendar.current.component(.year, from: $0) } + [Calendar.current.component(.year, from: .now)])).sorted(by: >)
    }
    private var month: Date {
        Calendar.current.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)) ?? .now
    }

    private var report: MonthlyFoodReport { MonthlyFoodReport(month: month, records: records) }

    var body: some View {
        List {
            Section {
                Picker("年", selection: $selectedYear) {
                    ForEach(years, id: \.self) { Text(String($0) + "年").tag($0) }
                }
                Picker("月", selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
                }
                Text(month.formatted(.dateTime.year().month(.wide))).font(.title2.bold())
            }
            if report.visitCount == 0 {
                ContentUnavailableView("この月の記録はありません", systemImage: "calendar", description: Text("訪問日を設定した「行った」記録が集計されます。"))
            } else {
                Section("今月の記録") {
                    LabeledContent("訪問記録", value: "\(report.visitCount)件")
                    LabeledContent("訪れたお店", value: "\(report.uniquePlaceCount)店")
                    LabeledContent("新規開拓", value: "\(report.newPlaceCount)店")
                    LabeledContent("平均評価", value: report.averageRating.map { String(format: "★ %.1f", $0) } ?? "未評価")
                }
                Section {
                    Text("新規開拓は、保存されている訪問日付きの記録で、この月に初めて訪れたお店の数です。ゴミ箱の記録は除きます。")
                        .font(.caption).foregroundStyle(.secondary)
                    ShareLink(item: "グルメップ \(month.formatted(.dateTime.year().month()))\n訪問記録 \(report.visitCount)件・訪れたお店 \(report.uniquePlaceCount)店・新規開拓 \(report.newPlaceCount)店") {
                        Label("月間サマリーを共有", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("月間ごはんレポート")
        .themeScreenBackground()
    }
}

struct BackupStatusView: View {
    @AppStorage("backup.lastSuccessfulSnapshot") private var snapshotData = Data()
    @Query private var records: [RestaurantRecord]
    @Query private var places: [Place]
    @Query private var photos: [RecordPhoto]
    @Query private var menus: [RecordMenuItem]
    @Query private var tags: [Tag]
    @Query private var collections: [Collection]
    @Query private var entries: [CollectionEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("バックアップ状況", systemImage: "externaldrive.badge.checkmark")
                .font(.headline)
            if let previous = try? JSONDecoder().decode(BackupSnapshot.self, from: snapshotData) {
                Text("最終作成：\(previous.createdAt.formatted(date: .abbreviated, time: .shortened))")
                if let current = currentSnapshot {
                    let change = current.changes(since: previous)
                    Text("その後の記録：追加 \(change.added)件・更新 \(change.updated)件・削除 \(change.removed)件")
                    if current.contentHash != previous.contentHash {
                        Label("未バックアップの変更があります", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    } else {
                        Text("前回作成時から変更はありません")
                    }
                } else { Text("変更状況を確認できませんでした") }
            } else {
                Text("この端末での作成履歴はまだありません")
                Text("写真を含むバックアップを作成して、大切な記録を残しましょう。")
            }
            Text("書き出し完了時に更新します。保存先のファイルが現在も存在するかは確認しません。")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.vertical, 4)
    }

    private var currentSnapshot: BackupSnapshot? {
        guard let data = try? BackupService().encode(places: places, records: records, photos: photos, menuItems: menus, tags: tags, collections: collections, collectionEntries: entries, includePhotoData: false) else { return nil }
        return try? BackupSnapshot.capture(metadata: data)
    }
}
