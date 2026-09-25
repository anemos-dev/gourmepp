# グルメップ

飲食店での体験を、写真・評価・メモと一緒に端末内へ記録するiOSアプリです。行きたいお店と訪問したお店を整理し、あとから地図やコレクションで振り返れます。

## 主な機能

- お店の検索、地図表示、手入力での店舗登録
- 訪問記録、写真、評価、メニュー、メモの保存
- タグ、コレクション、検索、絞り込みによる整理
- CSV・EPUB・バックアップの書き出しとバックアップからの復元
- 任意のグルメップ Pro（買い切り）による追加機能

店舗の記録は端末内に保存します。地図と店舗検索にはAppleのMapKitを使用します。写真や位置情報へのアクセスは任意です。

## 動作環境

- iOS 17以降
- SwiftUI、SwiftData、MapKit、StoreKit

## ビルド

Xcodeで `グルメップ.xcodeproj` を開き、`グルメップ` schemeを選択してビルドしてください。コマンドラインからは次のように実行できます。

```sh
xcodebuild \
  -project 'グルメップ.xcodeproj' \
  -scheme 'グルメップ' \
  -destination 'generic/platform=iOS Simulator' \
  build
```

実機へのインストールや配布用Archiveには、Apple Developerの署名設定が必要です。

## サポートとプライバシー

- サポート: <https://gourmepp-support.pages.dev/support/>
- プライバシーポリシー: <https://gourmepp-support.pages.dev/privacy/>
