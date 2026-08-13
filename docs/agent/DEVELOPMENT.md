# ごはん日和開発ガイド

> **このファイルを読む場面:** アプリのコード、SwiftDataモデル、写真・地図、UI、テスト、Xcode設定を変更するとき。

## 製品と構成

- iOS 17以上、Swift 5、SwiftUI / SwiftData / PhotosUI / MapKit / UIKit。
- `ごはん日和/______App.swift`が永続`ModelContainer`と`AppErrorCenter`を構成し、`AppView.swift`がタブの入口です。
- `Models/`はプロフィール、店、訪問記録、写真、タグ、コレクション、設定のモデルです。
- `Features/`は記録、地図、写真・店、詳細・設定、リリース画面、`Core/`はサービスと共通支援です。
- `-seedReleasePreview`はDEBUG時のリリース用サンプル投入に使われます。通常データへ混入させないでください。

## コマンド

```bash
xcodebuild -list -project 'ごはん日和.xcodeproj'
xcodebuild -project 'ごはん日和.xcodeproj' -scheme 'ごはん日和' -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project 'ごはん日和.xcodeproj' -scheme 'ごはん日和' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`xcodebuild -list`でschemeと3 targetの存在を確認済みです。ビルドとテストは変更後に実行し、写真選択・地図・位置関連はSimulatorの制約を考慮して主要導線を目視します。

## 変更時の注意

- SwiftDataモデルの削除・型変更・必須化は既存ストアを壊し得るため、互換性か移行方針を確認します。
- 写真や位置情報は許可拒否、空状態、エラー状態も確認します。
- Xcodeのファイル同期設定を維持し、生成物や`Assets.xcassets`をソースコード扱いで一括整形しません。
