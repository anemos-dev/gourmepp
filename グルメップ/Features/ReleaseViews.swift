import CoreLocation
import Photos
import StoreKit
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct OnboardingView: View {
    let completion: () -> Void
    @State private var page = 0

    private let pages: [(icon: String, title: String, message: String)] = [
        ("fork.knife.circle.fill", "好きなお店を、忘れない", "行ったお店も、これから行きたいお店も、写真と一緒に自分だけの記録にできます。"),
        ("map.fill", "地図からすぐ見つかる", "位置情報は現在地付近のお店を探すときだけ使用します。住所を手入力して使うこともできます。"),
        ("lock.shield.fill", "記録は端末の中に保存", "このバージョンはアカウント不要です。公開や外部送信はせず、バックアップも自分で管理できます。"),
        ("externaldrive.fill.badge.checkmark", "バックアップで安心", "写真を含む専用ファイルを書き出せます。機種変更や万一のときも復元できます。")
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: pages[page].icon)
                .font(.system(size: 72))
                .foregroundStyle(Color("BrandOrange"))
                .accessibilityHidden(true)
            Text(pages[page].title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(pages[page].message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color("BrandOrange") : .secondary.opacity(0.25))
                        .frame(width: index == page ? 28 : 8, height: 8)
                }
            }
            Button(page == pages.count - 1 ? "はじめる" : "次へ") {
                if page == pages.count - 1 {
                    completion()
                } else {
                    withAnimation { page += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            if page < pages.count - 1 {
                Button("スキップ", action: completion)
                    .foregroundStyle(.secondary)
            } else {
                Button("サンプルを追加してはじめる", action: addSampleAndComplete)
            }
        }
        .padding(.vertical, 28)
        .background(Color("PinterestCanvas").ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    private func addSampleAndComplete() {
        do {
            try ReleasePreviewSampleData.add(to: context)
            completion()
        } catch {
            errors.show(error, title: "サンプルを追加できませんでした")
        }
    }
}

struct ReleaseSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    @Environment(ProAccessController.self) private var proAccess
    @Query private var settingsRows: [AppSettings]
    @Query private var tags: [Tag]
    @Query private var collections: [Collection]
    @Query private var collectionEntries: [CollectionEntry]
    @Query private var records: [RestaurantRecord]
    @Query private var places: [Place]
    @Query private var photos: [RecordPhoto]
    @Query private var menuItems: [RecordMenuItem]
    @State private var collectionName = ""
    @State private var showOfferCodeRedemption = false
    @State private var exportText: String?
    @State private var showCSVShare = false
    @State private var backupDocument: GourmeppBackupDocument?
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var epubDocument: GourmeppEPUBDocument?
    @State private var showEPUBExporter = false
    @State private var showEPUBImporter = false
    @State private var pendingEPUBImport: EPUBImport?
    @State private var showEPUBImportConfirmation = false
    @State private var isProcessingEPUB = false
    @State private var pendingBackup: AppBackup?
    @State private var showRestoreConfirmation = false
    @State private var showDeleteAllConfirmation = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var settings: AppSettings? { settingsRows.first }
    private var storageText: String { StorageFormatter.string(bytes: LocalPhotoStore().totalBytes()) }

    var body: some View {
        List {
            Section("グルメップ Pro") {
                if proAccess.isProUnlocked {
                    NavigationLink {
                        AnnualFoodReportView()
                    } label: {
                        Label("年間ごはんレポート", systemImage: "chart.bar.fill")
                    }
                    NavigationLink {
                        ProPhotoMemoriesView()
                    } label: {
                        Label("写真の振り返り", systemImage: "photo.stack.fill")
                    }
                    NavigationLink {
                        ProCustomizationView()
                    } label: {
                        Label("表示をカスタマイズ", systemImage: "paintpalette.fill")
                    }
                    Label("高度な絞り込みはホーム、地図Proはマップから使えます", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("Pro購入済み", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color("BrandOrange"))
                } else {
                    NavigationLink {
                        ProPaywallView()
                    } label: {
                        Label("Proの機能を見る", systemImage: "sparkles")
                    }
                    Text("買い切りで、年間レポートと振り返り機能を利用できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        showOfferCodeRedemption = true
                    } label: {
                        Label("特典コードを使う", systemImage: "ticket.fill")
                    }
                    Text("App Store Connectで発行されたコードを入力できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("まとめ") {
                ForEach(collections) { collection in
                    NavigationLink {
                        CollectionDetailView(collection: collection)
                    } label: {
                        HStack {
                            Text(collection.title)
                            Spacer()
                            Text("\(collectionEntries.filter { $0.collectionID == collection.id }.count)件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteCollections)
                HStack {
                    TextField("まとめ名", text: $collectionName)
                    Button("作成", action: addCollection)
                        .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("保存と表示") {
                Toggle("月1回バックアップを通知", isOn: notificationBinding)
                Picker("写真品質", selection: photoQualityBinding) {
                    ForEach(PhotoQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                LabeledContent("写真の使用容量", value: storageText)
                Picker("ゴミ箱の保存期間", selection: trashRetentionBinding) {
                    Text("7日").tag(7)
                    Text("30日").tag(30)
                    Text("90日").tag(90)
                    Text("自動削除しない").tag(0)
                }
                Toggle("期限後に自動削除", isOn: autoTrashBinding)
                    .disabled((settings?.trashRetentionDays ?? 30) == 0)
                LabeledContent("記録の公開範囲", value: "自分のみ")
                Text("初版ではすべての記録を端末内だけに保存し、外部には公開しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("データ") {
                Button {
                    exportText = LocalExportImportService().csv(
                        records: records.filter { !$0.isDeleted },
                        places: places,
                        tags: tags
                    )
                    showCSVShare = true
                } label: {
                    Label("CSVを書き出す", systemImage: "tablecells")
                }
                Button(action: prepareBackup) {
                    Label("写真を含むバックアップを作成", systemImage: "externaldrive.badge.plus")
                }
                Button {
                    showBackupImporter = true
                } label: {
                    Label("バックアップから復元", systemImage: "externaldrive.badge.checkmark")
                }
                Button(action: prepareEPUB) {
                    Label("行った記録をEPUBで書き出す", systemImage: "books.vertical")
                }
                .disabled(isProcessingEPUB || !records.contains { !$0.isDeleted && $0.status == .visited })
                Button {
                    showEPUBImporter = true
                } label: {
                    Label("EPUBから行った記録を取り込む", systemImage: "square.and.arrow.down")
                }
                .disabled(isProcessingEPUB)
                if isProcessingEPUB {
                    HStack {
                        ProgressView()
                        Text("EPUBを処理しています…")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("EPUBの取り込みは現在のデータに記録を追加します。同じ店・訪問日・メモの記録は重複して追加しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    ReleaseTrashView()
                } label: {
                    Label("ゴミ箱（\(records.filter(\.isDeleted).count)件）", systemImage: "trash")
                }
                Button(role: .destructive) {
                    showDeleteAllConfirmation = true
                } label: {
                    Label("すべてのデータを削除", systemImage: "trash.slash")
                }
            }

            Section("プライバシーとサポート") {
                NavigationLink("権限の管理") { PermissionSettingsView() }
                NavigationLink("プライバシーポリシー") { PrivacyPolicyView() }
                NavigationLink("利用規約") { TermsView() }
                ShareLink(
                    item: "グルメップについて問い合わせます。\n\nアプリバージョン: \(appVersion)\n端末: \(UIDevice.current.model)\n",
                    subject: Text("グルメップのお問い合わせ")
                ) {
                    Label("お問い合わせ内容を共有", systemImage: "envelope")
                }
                Button("使い方をもう一度見る") {
                    hasCompletedOnboarding = false
                }
            }

            Section("アプリ情報") {
                LabeledContent("バージョン", value: appVersion)
                Text("記録はこの端末内に保存されます。定期的なバックアップをおすすめします。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
        .task { ensureSettingsAndCleanTrash() }
        .offerCodeRedemption(isPresented: $showOfferCodeRedemption) { result in
            switch result {
            case .success:
                Task { await proAccess.prepare() }
            case .failure(let error):
                errors.show(error, title: "Proコードを確認できませんでした")
            }
        }
        .sheet(isPresented: $showCSVShare) {
            if let exportText { ShareSheet(items: [exportText]) }
        }
        .fileExporter(
            isPresented: $showBackupExporter,
            document: backupDocument,
            contentType: .gourmeppBackup,
            defaultFilename: "グルメップ-\(Date.now.formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result { errors.show(error, title: "バックアップを保存できませんでした") }
        }
        .fileImporter(
            isPresented: $showBackupImporter,
            allowedContentTypes: [.gourmeppBackup, .legacyGohanBiyoriBackup, .json]
        ) { result in
            importBackup(result)
        }
        .fileExporter(
            isPresented: $showEPUBExporter,
            document: epubDocument,
            contentType: .epub,
            defaultFilename: "行った記録-\(Date.now.formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result { errors.show(error, title: "EPUBを保存できませんでした") }
        }
        .fileImporter(
            isPresented: $showEPUBImporter,
            allowedContentTypes: [.epub]
        ) { result in
            importEPUB(result)
        }
        .alert("EPUBの記録を追加しますか？", isPresented: $showEPUBImportConfirmation) {
            Button("追加する", action: applyPendingEPUBImport)
            Button("キャンセル", role: .cancel) { pendingEPUBImport = nil }
        } message: {
            if let pendingEPUBImport {
                Text("\(pendingEPUBImport.visits.count)件の訪問記録と\(pendingEPUBImport.photoCount)枚の写真を、現在のデータに追加します。")
            }
        }
        .alert("現在のデータを置き換えますか？", isPresented: $showRestoreConfirmation) {
            Button("復元する", role: .destructive, action: restorePendingBackup)
            Button("キャンセル", role: .cancel) { pendingBackup = nil }
        } message: {
            if let pendingBackup {
                Text("\(pendingBackup.records.count)件の記録と\(pendingBackup.photos.count)枚の写真を復元します。現在のデータは削除されます。")
            }
        }
        .alert("すべてのデータを削除しますか？", isPresented: $showDeleteAllConfirmation) {
            Button("完全に削除", role: .destructive, action: deleteAllData)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("記録、写真、タグ、まとめを削除します。この操作は取り消せません。先にバックアップを作成してください。")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var photoQualityBinding: Binding<PhotoQuality> {
        Binding(
            get: { PhotoQuality(rawValue: settings?.photoQualityRaw ?? "standard") ?? .standard },
            set: {
                settings?.photoQualityRaw = $0.rawValue
                UserDefaults.standard.set($0.rawValue, forKey: "photoQuality")
                save()
            }
        )
    }
    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { settings?.notificationsEnabled ?? false },
            set: { requested in
                Task {
                    do {
                        let enabled = try await BackupReminderService().setEnabled(requested)
                        settings?.notificationsEnabled = enabled
                        save()
                        if requested && !enabled {
                            errors.show("通知が許可されていません。「権限の管理」から設定アプリを開いて変更できます。", title: "通知を有効にできませんでした")
                        }
                    } catch {
                        settings?.notificationsEnabled = false
                        save()
                        errors.show(error, title: "通知を設定できませんでした")
                    }
                }
            }
        )
    }
    private var trashRetentionBinding: Binding<Int> {
        Binding(get: { settings?.trashRetentionDays ?? 30 }, set: { settings?.trashRetentionDays = $0; save() })
    }
    private var autoTrashBinding: Binding<Bool> {
        Binding(get: { settings?.automaticallyEmptyTrash ?? false }, set: { settings?.automaticallyEmptyTrash = $0; save() })
    }
    private func ensureSettingsAndCleanTrash() {
        if settingsRows.isEmpty {
            let row = AppSettings()
            InitialReleasePrivacy.apply(to: row)
            context.insert(row)
            UserDefaults.standard.set(row.photoQualityRaw, forKey: "photoQuality")
        }
        settingsRows.forEach { InitialReleasePrivacy.apply(to: $0) }
        records.forEach { InitialReleasePrivacy.apply(to: $0) }
        collections.forEach { InitialReleasePrivacy.apply(to: $0) }
        save()
        guard settings?.automaticallyEmptyTrash == true,
              let days = settings?.trashRetentionDays, days > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return }
        records.filter { $0.isDeleted && ($0.deletedAt ?? .now) < cutoff }.forEach(permanentlyDelete)
        save()
    }

    private func addCollection() {
        let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        context.insert(Collection(title: name))
        collectionName = ""
        save()
    }

    private func deleteCollections(at offsets: IndexSet) {
        for index in offsets {
            let collection = collections[index]
            collectionEntries.filter { $0.collectionID == collection.id }.forEach(context.delete)
            context.delete(collection)
        }
        save()
    }

    private func prepareBackup() {
        do {
            backupDocument = GourmeppBackupDocument(data: try BackupService().encode(
                places: places, records: records, photos: photos, menuItems: menuItems,
                tags: tags, collections: collections, collectionEntries: collectionEntries
            ))
            showBackupExporter = true
        } catch {
            errors.show(error, title: "バックアップを作成できませんでした")
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { throw BackupError.invalidFile }
            defer { url.stopAccessingSecurityScopedResource() }
            pendingBackup = try BackupService().decode(Data(contentsOf: url))
            showRestoreConfirmation = true
        } catch {
            errors.show(error, title: "バックアップを読み込めませんでした")
        }
    }

    private func prepareEPUB() {
        isProcessingEPUB = true
        defer { isProcessingEPUB = false }
        do {
            epubDocument = GourmeppEPUBDocument(data: try EPUBService().encode(
                records: records,
                places: places,
                tags: tags,
                photos: photos
            ))
            showEPUBExporter = true
        } catch {
            errors.show(error, title: "EPUBを作成できませんでした")
        }
    }

    private func importEPUB(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { throw EPUBError.invalidFile }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            isProcessingEPUB = true
            Task { @MainActor in
                defer { isProcessingEPUB = false }
                do {
                    pendingEPUBImport = try await Task.detached(priority: .userInitiated) {
                        try EPUBService().decode(data)
                    }.value
                    showEPUBImportConfirmation = true
                } catch {
                    errors.show(error, title: "EPUBを読み込めませんでした")
                }
            }
        } catch {
            errors.show(error, title: "EPUBを読み込めませんでした")
        }
    }

    private func applyPendingEPUBImport() {
        guard let pendingEPUBImport else { return }
        isProcessingEPUB = true
        defer { isProcessingEPUB = false }
        do {
            let result = try EPUBService().apply(
                pendingEPUBImport,
                context: context,
                currentPlaces: places,
                currentRecords: records,
                currentTags: tags
            )
            self.pendingEPUBImport = nil
            var message = "\(result.importedRecordCount)件の記録と\(result.importedPhotoCount)枚の写真を取り込みました。"
            if result.skippedDuplicateCount > 0 {
                message += " 重複する\(result.skippedDuplicateCount)件は追加しませんでした。"
            }
            errors.show(message)
        } catch {
            errors.show(error, title: "EPUBを取り込めませんでした")
        }
    }

    private func restorePendingBackup() {
        guard let pendingBackup else { return }
        do {
            try BackupService().restore(
                pendingBackup, context: context,
                currentPlaces: places, currentRecords: records, currentPhotos: photos,
                currentMenuItems: menuItems, currentTags: tags,
                currentCollections: collections, currentEntries: collectionEntries
            )
            self.pendingBackup = nil
            errors.show("バックアップを復元しました。")
        } catch {
            errors.show(error, title: "復元できませんでした")
        }
    }

    private func deleteAllData() {
        photos.forEach { LocalPhotoStore().delete(photo: $0); context.delete($0) }
        collectionEntries.forEach(context.delete)
        menuItems.forEach(context.delete)
        collections.forEach(context.delete)
        records.forEach(context.delete)
        places.forEach(context.delete)
        tags.forEach(context.delete)
        save()
    }

    private func permanentlyDelete(_ record: RestaurantRecord) {
        photos.filter { $0.recordID == record.id }.forEach { LocalPhotoStore().delete(photo: $0); context.delete($0) }
        menuItems.filter { $0.recordID == record.id }.forEach(context.delete)
        collectionEntries.filter { $0.recordID == record.id }.forEach(context.delete)
        let placeID = record.placeID
        context.delete(record)
        if !records.contains(where: { $0.id != record.id && $0.placeID == placeID }),
           let place = places.first(where: { $0.id == placeID }) {
            context.delete(place)
        }
    }

    private func save() {
        do { try context.save() } catch { errors.show(error, title: "変更を保存できませんでした") }
    }
}

struct ReleaseTrashView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    @Query private var records: [RestaurantRecord]
    @Query private var places: [Place]
    @Query private var photos: [RecordPhoto]
    @Query private var menuItems: [RecordMenuItem]
    @Query private var entries: [CollectionEntry]
    @State private var recordToDelete: RestaurantRecord?
    @State private var showEmptyConfirmation = false

    private var deletedRecords: [RestaurantRecord] { records.filter(\.isDeleted) }

    var body: some View {
        Group {
            if deletedRecords.isEmpty {
                ContentUnavailableView("ゴミ箱は空です", systemImage: "trash", description: Text("削除した記録はここから復元できます。"))
            } else {
                List {
                    ForEach(deletedRecords) { record in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(places.first { $0.id == record.placeID }?.name ?? "店舗")
                                if let date = record.deletedAt {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("復元") { restore(record) }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("restoreRecord-\(record.id.uuidString)")
                            Button(role: .destructive) { recordToDelete = record } label: {
                                Image(systemName: "trash.slash")
                            }
                            .accessibilityLabel("完全に削除")
                        }
                    }
                }
            }
        }
        .navigationTitle("ゴミ箱")
        .toolbar {
            if !deletedRecords.isEmpty {
                Button("空にする", role: .destructive) { showEmptyConfirmation = true }
            }
        }
        .alert("完全に削除しますか？", isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button("完全に削除", role: .destructive) {
                if let recordToDelete { permanentlyDelete(recordToDelete); save() }
                recordToDelete = nil
            }
            Button("キャンセル", role: .cancel) { recordToDelete = nil }
        } message: {
            Text("写真を含む記録を削除します。この操作は取り消せません。")
        }
        .alert("ゴミ箱を空にしますか？", isPresented: $showEmptyConfirmation) {
            Button("すべて削除", role: .destructive) {
                deletedRecords.forEach(permanentlyDelete)
                save()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func restore(_ record: RestaurantRecord) {
        record.isDeleted = false
        record.deletedAt = nil
        record.updatedAt = .now
        save()
    }

    private func permanentlyDelete(_ record: RestaurantRecord) {
        photos.filter { $0.recordID == record.id }.forEach { LocalPhotoStore().delete(photo: $0); context.delete($0) }
        menuItems.filter { $0.recordID == record.id }.forEach(context.delete)
        entries.filter { $0.recordID == record.id }.forEach(context.delete)
        let placeID = record.placeID
        context.delete(record)
        if !records.contains(where: { $0.id != record.id && $0.placeID == placeID }),
           let place = places.first(where: { $0.id == placeID }) {
            context.delete(place)
        }
    }

    private func save() {
        do { try context.save() } catch { errors.show(error, title: "変更を保存できませんでした") }
    }
}

@Observable final class PermissionController: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var locationStatus: CLAuthorizationStatus
    var photoStatus: PHAuthorizationStatus
    var notificationStatus: UNAuthorizationStatus = .notDetermined

    override init() {
        locationStatus = CLLocationManager().authorizationStatus
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
        manager.delegate = self
        Task { await refreshNotificationStatus() }
    }

    func requestLocation() { manager.requestWhenInUseAuthorization() }
    func requestPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor [weak self, status] in self?.photoStatus = status }
        }
    }
    func requestNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refreshNotificationStatus()
        }
    }
    func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus
    }
}

struct PermissionSettingsView: View {
    @State private var controller = PermissionController()
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            permissionRow(
                title: "位置情報",
                detail: "現在地付近のお店を検索するときに使用します。",
                icon: "location.fill",
                status: locationText
            ) {
                if controller.locationStatus == .notDetermined {
                    controller.requestLocation()
                } else {
                    openSystemSettings()
                }
            }
            permissionRow(
                title: "写真",
                detail: "食事の写真を記録に追加するときに使用します。",
                icon: "photo.fill",
                status: photoText
            ) {
                if controller.photoStatus == .notDetermined {
                    controller.requestPhotos()
                } else {
                    openSystemSettings()
                }
            }
            permissionRow(
                title: "通知",
                detail: "バックアップを忘れないための月1回のリマインダーに使用します。",
                icon: "bell.fill",
                status: notificationText
            ) {
                if controller.notificationStatus == .notDetermined {
                    controller.requestNotifications()
                } else {
                    openSystemSettings()
                }
            }
            Section {
                Text("許可しなくても、住所の手入力や写真なしの記録は利用できます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("権限の管理")
    }

    private func permissionRow(title: String, detail: String, icon: String, status: String, action: @escaping () -> Void) -> some View {
        Section {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            LabeledContent("現在の状態", value: status)
            Button(status == "未確認" ? "許可を確認" : "設定アプリを開く", action: action)
        }
    }

    private var locationText: String {
        switch controller.locationStatus {
        case .notDetermined: "未確認"
        case .restricted: "制限されています"
        case .denied: "許可されていません"
        case .authorizedAlways, .authorizedWhenInUse: "許可済み"
        @unknown default: "不明"
        }
    }
    private var photoText: String {
        switch controller.photoStatus {
        case .notDetermined: "未確認"
        case .restricted: "制限されています"
        case .denied: "許可されていません"
        case .authorized: "許可済み"
        case .limited: "選択した写真のみ"
        @unknown default: "不明"
        }
    }
    private var notificationText: String {
        switch controller.notificationStatus {
        case .notDetermined: "未確認"
        case .denied: "許可されていません"
        case .authorized, .provisional, .ephemeral: "許可済み"
        @unknown default: "不明"
        }
    }
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("保存する情報") {
                Text("店舗名、住所、評価、メモ、タグ、写真など、利用者が入力した情報を端末内に保存します。")
            }
            Section("外部への送信") {
                Text("グルメップは、記録した情報を開発者のサーバーへ送信しません。店舗検索と地図表示ではAppleのMapKitを利用します。")
            }
            Section("権限") {
                Text("位置情報は周辺検索、写真ライブラリは写真の追加に使用します。許可しない場合も、手入力で記録できます。")
            }
            Section("バックアップ") {
                Text("バックアップファイルには写真やメモなどが含まれます。安全な場所で管理し、第三者への共有にご注意ください。")
            }
            Section("削除") {
                Text("設定の「すべてのデータを削除」から、端末内の記録と写真を削除できます。")
            }
        }
        .navigationTitle("プライバシーポリシー")
    }
}

struct TermsView: View {
    var body: some View {
        List {
            Section("利用について") {
                Text("本アプリは、個人の飲食店記録を管理するためのツールです。店舗情報や営業時間などは最新でない場合があります。")
            }
            Section("データ管理") {
                Text("端末の故障、紛失、アプリの削除に備え、利用者自身で定期的にバックアップを作成してください。")
            }
            Section("禁止事項") {
                Text("法令または第三者の権利を侵害する目的で本アプリを使用しないでください。")
            }
            Section("変更") {
                Text("機能追加や法令の変更に応じて、本内容を更新する場合があります。")
            }
        }
        .navigationTitle("利用規約")
    }
}
