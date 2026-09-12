#if DEBUG
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct DeveloperMenuView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    @Environment(ProAccessController.self) private var proAccess
    @Environment(ProPreferences.self) private var proPreferences

    @Query private var profiles: [LocalUserProfile]
    @Query private var places: [Place]
    @Query private var records: [RestaurantRecord]
    @Query private var photos: [RecordPhoto]
    @Query private var menuItems: [RecordMenuItem]
    @Query private var tags: [Tag]
    @Query private var collections: [Collection]
    @Query private var collectionEntries: [CollectionEntry]
    @Query private var settingsRows: [AppSettings]

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var pendingDestructiveAction: DestructiveAction?
    @State private var isSchedulingNotification = false

    var body: some View {
        List {
            environmentSection
            dataSummarySection
            testDataSection
            featureStateSection
            diagnosticsSection
            destructiveSection
        }
        .navigationTitle("開発者メニュー")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $pendingDestructiveAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text(action.actionTitle)) {
                    perform(action)
                },
                secondaryButton: .cancel(Text("キャンセル"))
            )
        }
    }

    private var environmentSection: some View {
        Section("実行環境") {
            LabeledContent("構成", value: "Debug")
            LabeledContent("実行先", value: runtimeName)
            LabeledContent("アプリ", value: appVersion)
            LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "不明")
            LabeledContent("OS", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            LabeledContent("端末", value: UIDevice.current.model)
            if !ProcessInfo.processInfo.arguments.isEmpty {
                DisclosureGroup("起動引数") {
                    ForEach(ProcessInfo.processInfo.arguments, id: \.self) { argument in
                        Text(argument)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var dataSummarySection: some View {
        Section("ローカルデータ") {
            LabeledContent("訪問記録", value: "\(activeRecords.count)件")
            LabeledContent("行きたい", value: "\(wishRecords.count)件")
            LabeledContent("ゴミ箱", value: "\(trashedRecords.count)件")
            LabeledContent("店舗", value: "\(places.count)件")
            LabeledContent("写真", value: "\(photos.count)枚")
            LabeledContent("メニュー項目", value: "\(menuItems.count)件")
            LabeledContent("タグ", value: "\(tags.count)件")
            LabeledContent("まとめ", value: "\(collections.count)件")
            LabeledContent("写真ファイル容量", value: StorageFormatter.string(bytes: LocalPhotoStore().totalBytes()))

            Button(action: runIntegrityCheck) {
                Label("データ整合性をチェック", systemImage: "checkmark.shield")
            }
        }
    }

    private var testDataSection: some View {
        Section("テストデータ") {
            Button(action: addOrRefreshSampleData) {
                Label("リリース用サンプルを生成・更新", systemImage: "wand.and.stars")
            }
            Button(action: normalizePrivacy) {
                Label("公開範囲を端末内限定に正規化", systemImage: "lock.shield")
            }
            Text("サンプル生成は既存のリリース用データだけを更新し、通常の記録は残します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var featureStateSection: some View {
        Section("機能と画面状態") {
            Toggle("Pro機能を強制的に有効化", isOn: developerProBinding)
            Toggle("オンボーディング完了", isOn: $hasCompletedOnboarding)
            NavigationLink {
                PermissionSettingsView()
            } label: {
                Label("権限状態を確認", systemImage: "hand.raised")
            }
            Text("Proの強制解除は購入状態を書き換えず、Debugビルド内の表示確認だけに使用します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var diagnosticsSection: some View {
        Section("診断とテスト") {
            Button(action: scheduleTestNotification) {
                HStack {
                    Label("5秒後にテスト通知", systemImage: "bell.badge")
                    if isSchedulingNotification {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isSchedulingNotification)

            Button {
                UNUserNotificationCenter.current().removePendingNotificationRequests(
                    withIdentifiers: [Self.testNotificationIdentifier]
                )
                errors.show("保留中の開発用テスト通知を取り消しました。")
            } label: {
                Label("テスト通知を取り消す", systemImage: "bell.slash")
            }

            Button {
                errors.show("これは開発者メニューから発生させたテストエラーです。", title: "テストエラー")
            } label: {
                Label("エラー表示をテスト", systemImage: "exclamationmark.triangle")
            }

            ShareLink(item: diagnosticReport, subject: Text("グルメップ診断レポート")) {
                Label("診断レポートを共有", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var destructiveSection: some View {
        Section("リセット") {
            Button(role: .destructive) {
                pendingDestructiveAction = .preferences
            } label: {
                Label("開発用設定を初期化", systemImage: "arrow.counterclockwise")
            }

            Button(role: .destructive) {
                pendingDestructiveAction = .allData
            } label: {
                Label("すべてのローカルデータを削除", systemImage: "trash.slash")
            }

            Text("全データ削除は写真ファイルを含みます。元に戻せません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var developerProBinding: Binding<Bool> {
        Binding(
            get: { proAccess.hasDeveloperPro },
            set: { proAccess.setDeveloperProUnlocked($0) }
        )
    }

    private var activeRecords: [RestaurantRecord] {
        records.filter { !$0.isDeleted && $0.status == .visited }
    }

    private var wishRecords: [RestaurantRecord] {
        records.filter { !$0.isDeleted && $0.status == .wantToGo }
    }

    private var trashedRecords: [RestaurantRecord] {
        records.filter(\.isDeleted)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "不明"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "不明"
        return "\(version) (\(build))"
    }

    private var runtimeName: String {
        #if targetEnvironment(simulator)
        "Simulator"
        #else
        "実機"
        #endif
    }

    private var integrityIssues: [String] {
        let placeIDs = Set(places.map(\.id))
        let recordIDs = Set(records.map(\.id))
        let collectionIDs = Set(collections.map(\.id))
        let store = LocalPhotoStore()
        var issues: [String] = []

        let recordsWithoutPlace = records.filter { !placeIDs.contains($0.placeID) }.count
        if recordsWithoutPlace > 0 {
            issues.append("店舗が存在しない記録: \(recordsWithoutPlace)件")
        }

        let orphanedPhotos = photos.filter { !recordIDs.contains($0.recordID) }.count
        if orphanedPhotos > 0 {
            issues.append("記録が存在しない写真: \(orphanedPhotos)枚")
        }

        let orphanedMenuItems = menuItems.filter { !recordIDs.contains($0.recordID) }.count
        if orphanedMenuItems > 0 {
            issues.append("記録が存在しないメニュー項目: \(orphanedMenuItems)件")
        }

        let orphanedEntries = collectionEntries.filter {
            !recordIDs.contains($0.recordID) || !collectionIDs.contains($0.collectionID)
        }.count
        if orphanedEntries > 0 {
            issues.append("参照先が存在しないまとめ項目: \(orphanedEntries)件")
        }

        let missingPhotoFiles = photos.filter {
            !store.exists(at: $0.imagePath) || !store.exists(at: $0.thumbnailPath)
        }.count
        if missingPhotoFiles > 0 {
            issues.append("ファイルが見つからない写真: \(missingPhotoFiles)枚")
        }

        if settingsRows.count > 1 {
            issues.append("設定レコードの重複: \(settingsRows.count)件")
        }
        return issues
    }

    private var diagnosticReport: String {
        let issues = integrityIssues
        return """
        グルメップ 診断レポート
        生成日時: \(Date.now.formatted(date: .numeric, time: .standard))
        アプリ: \(appVersion)
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "不明")
        構成: Debug / \(runtimeName)
        OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        端末: \(UIDevice.current.model)

        データ件数
        - 訪問記録: \(activeRecords.count)
        - 行きたい: \(wishRecords.count)
        - ゴミ箱: \(trashedRecords.count)
        - 店舗: \(places.count)
        - 写真: \(photos.count)
        - タグ: \(tags.count)
        - まとめ: \(collections.count)
        - 写真ファイル容量: \(StorageFormatter.string(bytes: LocalPhotoStore().totalBytes()))

        整合性
        \(issues.isEmpty ? "- 問題は検出されませんでした" : issues.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private func addOrRefreshSampleData() {
        do {
            try ReleasePreviewSampleData.add(to: context)
            errors.show("リリース用サンプルデータを生成・更新しました。")
        } catch {
            errors.show(error, title: "サンプルデータを生成できませんでした")
        }
    }

    private func normalizePrivacy() {
        do {
            try InitialReleasePrivacy.normalize(in: context)
            errors.show("公開範囲を端末内限定に正規化しました。")
        } catch {
            errors.show(error, title: "公開範囲を正規化できませんでした")
        }
    }

    private func runIntegrityCheck() {
        let issues = integrityIssues
        if issues.isEmpty {
            errors.show("参照切れ、写真ファイルの欠損、設定レコードの重複は検出されませんでした。", title: "整合性チェック完了")
        } else {
            errors.show(issues.joined(separator: "\n"), title: "\(issues.count)項目の問題を検出")
        }
    }

    private func scheduleTestNotification() {
        isSchedulingNotification = true
        Task {
            defer { isSchedulingNotification = false }
            do {
                let center = UNUserNotificationCenter.current()
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    errors.show("通知が許可されていません。権限状態を確認してください。", title: "テスト通知を予約できませんでした")
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "グルメップ 開発用通知"
                content.body = "開発者メニューから予約したテスト通知です。"
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                let request = UNNotificationRequest(
                    identifier: Self.testNotificationIdentifier,
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
                errors.show("5秒後にテスト通知が届きます。通知を確認するにはアプリをバックグラウンドへ移動してください。")
            } catch {
                errors.show(error, title: "テスト通知を予約できませんでした")
            }
        }
    }

    private func perform(_ action: DestructiveAction) {
        switch action {
        case .preferences:
            resetDeveloperPreferences()
        case .allData:
            deleteAllLocalData()
        }
    }

    private func resetDeveloperPreferences() {
        proAccess.setDeveloperProUnlocked(false)
        proPreferences.resetToDefaults()
        hasCompletedOnboarding = false
        UserDefaults.standard.removeObject(forKey: "releasePreviewSampleVersion")
        UserDefaults.standard.removeObject(forKey: "photoQuality")
        settingsRows.forEach {
            $0.notificationsEnabled = false
            $0.photoQualityRaw = PhotoQuality.standard.rawValue
            $0.trashRetentionDays = 30
            $0.automaticallyEmptyTrash = false
            InitialReleasePrivacy.apply(to: $0)
        }
        do {
            try context.save()
            UserDefaults.standard.set(PhotoQuality.standard.rawValue, forKey: "photoQuality")
            errors.show("開発用フラグ、オンボーディング、表示設定を初期化しました。")
        } catch {
            errors.show(error, title: "設定を初期化できませんでした")
        }
    }

    private func deleteAllLocalData() {
        do {
            try LocalPhotoStore().deleteAll()
            collectionEntries.forEach(context.delete)
            menuItems.forEach(context.delete)
            photos.forEach(context.delete)
            collections.forEach(context.delete)
            records.forEach(context.delete)
            places.forEach(context.delete)
            tags.forEach(context.delete)
            profiles.forEach(context.delete)
            settingsRows.forEach(context.delete)
            try context.save()
            UserDefaults.standard.removeObject(forKey: "releasePreviewSampleVersion")
            hasCompletedOnboarding = false
            errors.show("写真を含むすべてのローカルデータを削除しました。")
        } catch {
            errors.show(error, title: "ローカルデータを削除できませんでした")
        }
    }

    private static let testNotificationIdentifier = "developer.test-notification"
}

private enum DestructiveAction: String, Identifiable {
    case preferences
    case allData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: "開発用設定を初期化しますか？"
        case .allData: "すべてのローカルデータを削除しますか？"
        }
    }

    var message: String {
        switch self {
        case .preferences:
            "Pro強制解除、オンボーディング、表示設定、サンプル更新状態を初期値に戻します。記録と写真は残ります。"
        case .allData:
            "記録、店舗、写真、タグ、まとめ、プロフィール、設定を端末から削除します。この操作は取り消せません。"
        }
    }

    var actionTitle: String {
        switch self {
        case .preferences: "初期化"
        case .allData: "すべて削除"
        }
    }
}

#Preview {
    DeveloperMenuPreview()
}

@MainActor
private struct DeveloperMenuPreview: View {
    @State private var errors = AppErrorCenter()
    @State private var proAccess = ProAccessController()
    @State private var proPreferences = ProPreferences()
    private let container: ModelContainer

    init() {
        let schema = Schema([
            LocalUserProfile.self,
            Place.self,
            RestaurantRecord.self,
            RecordPhoto.self,
            RecordMenuItem.self,
            Tag.self,
            Collection.self,
            CollectionEntry.self,
            AppSettings.self,
        ])
        container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    var body: some View {
        NavigationStack {
            DeveloperMenuView()
        }
        .modelContainer(container)
        .environment(errors)
        .environment(proAccess)
        .environment(proPreferences)
        .appErrorAlert(errors)
    }
}
#endif
