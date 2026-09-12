# グルメップ開発ガイド

> **このファイルを読む場面:** アプリのコード、SwiftDataモデル、写真・地図、UI、テスト、Xcode設定を変更するとき。

## 製品と構成

- iOS 17以上、Swift 5、SwiftUI / SwiftData / PhotosUI / MapKit / UIKit。
- Bundle ID、Swiftモジュール名、バックアップUTTypeは、既存データとの互換性に関わります。名称変更時も、Bundle ID・UTType・アプリ内課金の商品IDを個別に推測変更せず、移行方針を確認してください。
- `グルメップ/______App.swift`が永続`ModelContainer`と`AppErrorCenter`を構成し、`AppView.swift`がタブの入口です。
- `Models/`はプロフィール、店、訪問記録、写真、タグ、コレクション、設定のモデルです。
- `Features/`は記録、地図、写真・店、詳細・設定、リリース画面、`Core/`はサービスと共通支援です。
- `-seedReleasePreview`はDEBUG時のリリース用サンプル投入に使われます。通常データへ混入させないでください。

## コマンド

```bash
xcodebuild -list -project 'グルメップ.xcodeproj'
xcodebuild -project 'グルメップ.xcodeproj' -scheme 'グルメップ' -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project 'グルメップ.xcodeproj' -scheme 'グルメップ' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`xcodebuild -list`でschemeと3 targetの存在を確認済みです。ビルドとテストは変更後に実行し、写真選択・地図・位置関連はSimulatorの制約を考慮して主要導線を目視します。

## 変更時の注意

- SwiftDataモデルの削除・型変更・必須化は既存ストアを壊し得るため、互換性か移行方針を確認します。
- 写真や位置情報は許可拒否、空状態、エラー状態も確認します。
- Xcodeのファイル同期設定を維持し、生成物や`Assets.xcassets`をソースコード扱いで一括整形しません。

## Gitブランチ運用

- `main` はリリース可能な製品コード専用です。通常の機能追加・修正は最新の`main`から`feature/*`を作り、内容を確認したPRを`main`へ1回だけマージします。
- `developer-menu` は「最新の`main` + デバッグ専用メニュー」です。デバッグ専用コードはこのブランチだけで管理し、`developer-menu`から`main`へはマージしません。
- `main`へのpush後は`.github/workflows/sync-developer-menu.yml`が`main`を`developer-menu`へマージしてpushします。fast-forward可能ならfast-forwardし、分岐していれば通常のmerge commitを作ります。
- 自動同期で競合した場合、Actionはpush前に失敗します。履歴の上書きや自動競合解決は行わず、`developer-menu`側で内容を確認してから手動で`main`をマージします。
- 製品側にも必要になった変更は、最新の`main`から新しい`feature/*`を作ってデバッグ変更と分離し、通常のPRとして取り込みます。
