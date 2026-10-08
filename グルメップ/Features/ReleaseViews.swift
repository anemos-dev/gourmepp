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
    @AppStorage("hasAcceptedReleaseLegal") private var hasAcceptedReleaseLegal = false
    @State private var hasAgreedToLegal = false

    private let pages: [(icon: String, title: String, message: String)] = [
        ("fork.knife.circle.fill", "好きなお店を、忘れない", "行ったお店も、これから行きたいお店も、写真と一緒に自分だけの記録にできます。"),
        ("map.fill", "地図からすぐ見つかる", "位置情報は現在地付近のお店を探すときだけ使用します。住所を手入力して使うこともできます。"),
        ("lock.shield.fill", "記録は端末の中に保存", "このバージョンはアカウント不要です。公開や外部送信はせず、バックアップも自分で管理できます。"),
        ("externaldrive.fill.badge.checkmark", "バックアップで安心", "写真を含む専用ファイルを書き出せます。機種変更や万一のときも復元できます。")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        onboardingPage(pages[index]).tag(index)
                    }
                    legalAgreementPage.tag(pages.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0...pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color("BrandOrange") : .secondary.opacity(0.25))
                            .frame(width: index == page ? 28 : 8, height: 8)
                    }
                }
                Button(page == pages.count ? "同意してはじめる" : "次へ") {
                    if page == pages.count {
                        hasAcceptedReleaseLegal = true
                        completion()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .disabled(page == pages.count && !hasAgreedToLegal)

                if page == pages.count {
                    Button("サンプルを追加してはじめる", action: addSampleAndComplete)
                        .disabled(!hasAgreedToLegal)
                }
            }
            .padding(.vertical, 28)
            .background(Color("PinterestCanvas").ignoresSafeArea())
        }
        .interactiveDismissDisabled()
        .onAppear { hasAgreedToLegal = hasAcceptedReleaseLegal }
    }

    private func onboardingPage(_ item: (icon: String, title: String, message: String)) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: item.icon)
                .font(.system(size: 72))
                .foregroundStyle(Color("BrandOrange"))
                .accessibilityHidden(true)
            Text(item.title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(item.message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }

    private var legalAgreementPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color("BrandOrange"))
                .accessibilityHidden(true)
            Text("ご利用前の確認")
                .font(.largeTitle.bold())
            Text("グルメップは記録を端末内に保存します。ご利用前に、利用規約とプライバシーポリシーをご確認ください。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            HStack(spacing: 16) {
                NavigationLink("利用規約") { TermsView() }
                NavigationLink("プライバシーポリシー") { PrivacyPolicyView() }
            }
            .font(.subheadline.weight(.semibold))
            Toggle("利用規約とプライバシーポリシーに同意する", isOn: $hasAgreedToLegal)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
            Spacer()
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    private func addSampleAndComplete() {
        do {
            try ReleasePreviewSampleData.add(to: context)
            hasAcceptedReleaseLegal = true
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
    @AppStorage("backup.lastSuccessfulSnapshot") private var backupSnapshotData = Data()
    @State private var preparedBackupSnapshot: BackupSnapshot?
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
            #if DEBUG
            Section("開発") {
                NavigationLink {
                    DeveloperMenuView()
                } label: {
                    Label("開発者メニュー", systemImage: "hammer.fill")
                }
                .accessibilityIdentifier("developerMenuLink")

                Text("Debugビルド専用のデータ生成、状態確認、機能フラグ、診断ツールを開きます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            Section("グルメップ Pro") {
                NavigationLink {
                    if proAccess.isProUnlocked { MonthlyFoodReportView() }
                    else { ProPaywallView() }
                } label: {
                    Label("月間ごはんレポート", systemImage: "calendar")
                }
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
                } else {
                    NavigationLink {
                        ProPaywallView()
                    } label: {
                        Label("年間ごはんレポート", systemImage: "chart.bar.fill")
                    }
                    NavigationLink {
                        ProPaywallView()
                    } label: {
                        Label("写真の振り返り", systemImage: "photo.stack.fill")
                    }
                    NavigationLink {
                        ProPaywallView()
                    } label: {
                        Label("表示をカスタマイズ", systemImage: "paintpalette.fill")
                    }
                }
                if proAccess.isProUnlocked {
                    Label("Pro購入済み", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color("BrandOrange"))
                } else {
                    Button {
                        showOfferCodeRedemption = true
                    } label: {
                        Label("特典コードを使う", systemImage: "ticket.fill")
                    }
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
            }

            Section("データ") {
                BackupStatusView()
                Button {
                    exportText = LocalExportImportService().csv(
                        records: records.filter { !$0.isTrashed },
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
                .disabled(isProcessingEPUB || !records.contains { !$0.isTrashed && $0.status == .visited })
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
                    Label("ゴミ箱（\(records.filter(\.isTrashed).count)件）", systemImage: "trash")
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
        .navigationBarTitleDisplayMode(.inline)
        .themeScreenBackground()
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
            switch result {
            case .success:
                if let snapshot = preparedBackupSnapshot, let data = try? JSONEncoder().encode(snapshot) {
                    backupSnapshotData = data
                }
            case .failure(let error):
                errors.show(error, title: "バックアップを保存できませんでした")
            }
            preparedBackupSnapshot = nil
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
        records.filter { $0.isTrashed && ($0.deletedAt ?? .now) < cutoff }.forEach(permanentlyDelete)
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
        preparedBackupSnapshot = nil
        do {
            try context.save()
            preparedBackupSnapshot = try BackupSnapshot.capture(metadata: BackupService().encode(
                places: places, records: records, photos: photos, menuItems: menuItems,
                tags: tags, collections: collections, collectionEntries: collectionEntries,
                includePhotoData: false
            ))
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
            backupSnapshotData = Data()
            errors.show("バックアップを復元しました。")
        } catch {
            errors.show(error, title: "復元できませんでした")
        }
    }

    private func deleteAllData() {
        backupSnapshotData = Data()
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
    @Query(filter: #Predicate<RestaurantRecord> { $0.isTrashed }) private var records: [RestaurantRecord]
    @Query private var allRecords: [RestaurantRecord]
    @Query private var places: [Place]
    @Query private var photos: [RecordPhoto]
    @Query private var menuItems: [RecordMenuItem]
    @Query private var entries: [CollectionEntry]
    @State private var recordToDelete: RestaurantRecord?
    @State private var showEmptyConfirmation = false

    private var deletedRecords: [RestaurantRecord] { records }

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
        .themeScreenBackground()
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
        record.isTrashed = false
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
        if !allRecords.contains(where: { $0.id != record.id && $0.placeID == placeID }),
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
        .themeScreenBackground()
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
        LegalDocumentView(document: .privacy)
    }
}

struct TermsView: View {
    var body: some View {
        LegalDocumentView(document: .terms)
    }
}

private enum LegalDocument {
    case privacy, terms

    var title: String { self == .privacy ? "プライバシーポリシー" : "利用規約" }
    var introduction: String {
        switch self {
        case .privacy:
            "最終更新日：2026年9月21日\n\nグルメップ（以下「本アプリ」）は、飲食店の訪問記録を利用者自身の端末で管理するためのアプリです。本ポリシーは、本アプリで取り扱う情報、その目的、利用者が選べる設定および問い合わせ方法を説明するものです。"
        case .terms:
            "最終更新日：2026年9月21日\n\nこの利用規約（以下「本規約」）は、グルメップ（以下「本アプリ」）の利用条件を定めるものです。利用者は、本規約およびプライバシーポリシーに同意したうえで本アプリを利用するものとします。"
        }
    }
    var sections: [(String, String)] {
        switch self {
        case .privacy:
            [
                ("1. 保存する情報", "本アプリは、利用者が入力、選択または作成した店舗名、住所、カテゴリ、位置情報、電話番号、WebサイトURL、訪問予定・訪問履歴、訪問日、評価、メニュー、メモ、タグ、コレクション、写真および表示・通知等の設定情報を、機能提供のため利用者の端末内に保存します。入力内容には、利用者自身または第三者に関する情報が含まれる場合があります。必要以上の個人情報や、他者のプライバシーを侵害する情報を記録しないようご注意ください。"),
                ("2. 開発者による収集・送信", "現行版の本アプリは、利用者が記録した店舗情報、写真、メモ、位置情報その他の記録を、開発者が運営するサーバーへ送信、収集、販売または広告目的で利用しません。アカウント登録、ログイン、広告SDKおよび行動分析SDKも使用していません。ただし、利用者が自ら共有、書き出し、または外部サービスの検索・地図機能を利用した場合の通信は、この限りではありません。"),
                ("3. 端末の権限", "位置情報は、利用者が現在地付近の店舗を検索する操作を行うためにのみ利用します。写真ライブラリおよびカメラは、利用者が記録に写真を追加するためにのみ利用します。通知は、利用者が月1回のバックアップ通知を有効にした場合にのみ利用します。各権限はiOSの設定からいつでも変更できます。権限を許可しない場合でも、該当機能を除き、店舗情報や記録を手入力して利用できます。"),
                ("4. Appleのサービス", "店舗検索および地図表示にはAppleのMapKitを使用します。これらの機能を利用すると、検索語句、端末の現在地または表示対象の位置情報等がAppleに送信される場合があります。Appleによる情報の取扱いはAppleのプライバシーポリシーおよび関連する条件に従います。本アプリの開発者は、Appleがこれらのサービスを通じて取り扱う情報を管理するものではありません。"),
                ("5. バックアップ、書き出しおよび共有", "利用者が作成するバックアップ、CSVまたはEPUBには、店舗情報、訪問記録、メモ、写真その他の記録が含まれる場合があります。ファイルの保存先、共有先、受領者および第三者サービスにおける取扱いは利用者の責任で管理してください。共有シートから送信した内容は、選択したアプリまたはサービスの規約・ポリシーに従います。公開の場への共有は、位置情報、写真内の人物、メモ等が意図せず開示されないよう特に注意してください。"),
                ("6. 保管期間と削除", "本アプリ内のデータは、利用者が削除するまで端末内に保持されます。ゴミ箱に移した記録は、利用者が設定した保存期間に従って削除される場合があります。設定画面の「すべてのデータを削除」により、端末内の記録と本アプリが管理する写真データを削除できます。アプリを削除した場合のデータの扱いはiOSおよび端末のバックアップ設定に従います。利用者が既に書き出したファイル、共有先のコピー、端末やクラウドのバックアップ内のデータは別途削除が必要です。"),
                ("7. 安全管理", "本アプリは、データを端末内で扱う設計を採用していますが、端末の紛失、第三者による端末へのアクセス、OSや他アプリの不具合、バックアップ先の管理不備等による情報の漏えい・消失を完全に防止するものではありません。端末の画面ロック、OSの更新、信頼できる保存先でのバックアップ管理を推奨します。"),
                ("8. 未成年者", "未成年の利用者は、法定代理人等の同意を得たうえで本アプリを利用してください。写真、位置情報、他者の情報を記録または共有する際は、法令および周囲の方の権利・プライバシーに配慮してください。"),
                ("9. ポリシーの変更", "法令、機能、外部サービスまたは安全対策の変更に応じて、本ポリシーを変更することがあります。重要な変更を行う場合は、本アプリ内または公開ページで、合理的な方法により内容と効力発生日をお知らせします。変更後も本アプリを利用する場合、変更後のポリシーに同意したものとします。"),
                ("10. お問い合わせ", "本ポリシーに関するお問い合わせは、アプリ内の「お問い合わせ内容を共有」または anemos.dev@gmail.com までお寄せください。公開版は https://gourmepp-support.pages.dev/privacy/ でも確認できます。")
            ]
        case .terms:
            [
                ("1. 適用", "本規約は、本アプリの利用に関する開発者と利用者との間の権利義務を定めます。本アプリに関して別途表示される注意事項、購入条件、Apple Media Services利用規約およびプライバシーポリシーは、本規約の一部を構成します。"),
                ("2. 利用条件", "利用者は、自らの責任で本アプリを利用し、入力、保存、書き出しまたは共有する情報について必要な権利と権限を有することを保証します。本アプリは個人の飲食店記録を管理する目的で提供されます。事業用途その他の利用を妨げるものではありませんが、その適法性、正確性および利用結果は利用者自身が確認してください。"),
                ("3. 記録内容と第三者の権利", "店舗情報、写真、メモ、評価、位置情報その他の記録は利用者が管理する内容です。利用者は、著作権、肖像権、プライバシー権、商標権その他の第三者の権利、ならびに法令・店舗ルールを侵害しないように利用してください。第三者が写る写真や非公開情報を共有する場合は、必要な同意を得てください。"),
                ("4. 禁止事項", "利用者は、法令または公序良俗に反する行為、第三者の権利・利益を侵害する行為、不正アクセスや本アプリの解析・妨害を目的とする行為、虚偽または誤認を招く情報を不正な目的で利用する行為、ならびに開発者または第三者に損害を与える行為をしてはなりません。"),
                ("5. 店舗情報・地図情報", "本アプリで表示または検索される店舗、地図、営業時間、所在地その他の情報は、常に正確、完全、最新または利用可能であることを保証しません。来店、予約、購入その他の判断は、利用者が店舗その他の提供元へ確認したうえで行ってください。本アプリは店舗との予約、取引または提携を仲介するものではありません。"),
                ("6. データとバックアップ", "記録は原則として利用者の端末内に保存されます。端末の故障、紛失、OS更新、容量不足、アプリの削除、操作ミス、復元の失敗等によりデータが失われる可能性があります。利用者は必要に応じてバックアップを作成し、安全な場所で保管してください。書き出し・復元・共有によるデータの上書き、重複、漏えいまたは損失について、開発者は法令上責任を負う場合を除き責任を負いません。"),
                ("7. Pro機能と購入", "Pro機能が提供される場合、その内容、価格、購入条件および返金は購入画面ならびにAppleの条件に従います。購入処理、請求、特典コード、返金および購入履歴の管理はAppleが行う場合があります。購入前に表示内容を確認してください。法令上認められる場合を除き、購入済みの権利を他者へ譲渡、換金または転売することはできません。"),
                ("8. 提供の変更・中断", "開発者は、保守、安全性の確保、法令対応、機能改善その他合理的な必要がある場合、本アプリの全部または一部を変更、追加、中断または終了することがあります。可能な場合は事前にお知らせしますが、緊急時は事後のお知らせとなることがあります。"),
                ("9. 免責と責任の制限", "本アプリは現状有姿で提供され、特定目的への適合性、完全性、継続性、無エラー性またはデータの完全な保持を保証しません。開発者は、故意または重過失による場合、消費者契約法その他の強行法規により免責が認められない場合を除き、本アプリの利用または利用不能から生じた間接損害、特別損害、逸失利益およびデータ損失について責任を負いません。"),
                ("10. 規約の変更とお問い合わせ", "開発者は、本規約を変更することがあります。重要な変更は本アプリ内または公開ページで合理的に告知します。変更後も利用を継続した場合、変更後の規約に同意したものとします。本規約に関するお問い合わせは anemos.dev@gmail.com までお寄せください。")
            ]
        }
    }
}

private struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        List {
            Section {
                Text(document.introduction)
            }
            ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                Section(section.0) {
                    Text(section.1)
                }
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .themeScreenBackground()
    }
}
