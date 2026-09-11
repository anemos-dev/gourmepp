# 技術リリース準備監査

最終更新日: 2026-09-12

> 商標確認は完了している。App Store Connectへの登録・アップロード・TestFlight配布・審査提出・公開は、この監査時点では未実施。

## 名称変更対応（2026-08-25）

- アプリの表示名、アプリ内文言、書き出しメタデータ、リリース文書を「グルメップ」へ更新した。
- 新しいBundle ID、UTType、Pro商品ID、Swiftモジュール名はGourmepp系に統一し、既存バックアップを読み込むため旧UTTypeと `.gohanbackup` 拡張子の互換性を維持している。
- Xcodeプロジェクト、ターゲット、ソースフォルダ、テスト名も「グルメップ」へ更新した。

## 実施済みの検証

| 項目 | 結果 | 根拠 |
| --- | --- | --- |
| ユニットテスト | 合格 | 12件成功、失敗・スキップなし |
| テストターゲットのコンパイル | 合格 | 2026-09-11に `build-for-testing` をgeneric iOS Simulator向けに成功。テスト実行はしていない |
| Debugビルドと起動 | 合格 | 既存のiPhone 17 Pro Max Simulatorでビルド・起動成功 |
| Releaseビルド | 合格 | 2026-09-11に `generic/platform=iOS Simulator` で成功。生成物の表示名、Bundle ID、輸出コンプライアンスキー、Privacy Manifest、App Iconを確認 |
| iOS Archive | 合格 | 2026-09-12にVersion `1.0`（Build `1`）をArchive。`Apple Distribution: Anemos (R65SD9LLLX)` で署名され、埋め込みプロファイルは `Gourmepp App Store`、Bundle IDは `R65SD9LLLX.com.anemos.gourmepp`、`get-task-allow = false`。`codesign --verify --deep --strict` とdSYMの生成を確認。Archiveは `/tmp/Gourmepp-1.0-1.xcarchive` |
| App Store配布用IPA | 合格 | 2026-09-12に `app-store-connect` 方式でローカル書き出し成功。Version `1.0`（Build `1`）、arm64、Apple Distribution署名、`Gourmepp App Store`プロファイル、dSYMを確認。IPAは `/tmp/Gourmepp-1.0-1-export/グルメップ.ipa`。アップロードはしていない |
| ホーム画面の目視 | 合格 | リリース用サンプルデータの写真付きカード、検索、カテゴリ、タブを表示確認 |
| App Icon | 合格 | 通常・Dark・Tintedの各1024×1024アセットを確認 |
| プライバシー設定 | 要最終確認 | 権限説明文とPrivacy Manifestを確認。App Store Connectの回答は提出時のSDK構成で再確認が必要 |
| 輸出コンプライアンス | 準備済み | `ITSAppUsesNonExemptEncryption = NO` を追加。独自暗号や新しいSDKを追加した場合は提出前に再判定する |
| ストア掲載原稿 | 準備済み | 説明文、キーワード、カテゴリ・年齢区分の入力方針、公開済みのサポート／プライバシーポリシーURLを `docs/release/` に用意 |
| UIテスト | 未完了 | 5分以上完了せず停止。Simulatorのアクセシビリティ階層取得も失敗 |

## 実装上確認できたこと

- iOS 17以上を対象に、SwiftUI／SwiftDataでローカル保存する構成。
- カメラ、写真ライブラリ、使用中の位置情報の説明文が `Info.plist` にある。
- アプリ内には、権限状態の確認・拒否時の設定画面への遷移・端末内データの全削除・バックアップ復元前の確認がある。
- Privacy Manifest はUserDefaultsの必須理由APIを宣言し、トラッキングなし・開発者による収集データなしとしている。
- バックアップ用UTTypeと拡張子 `.gourmeppbackup` を宣言し、旧 `.gohanbackup` の読み込み互換性も維持している。
- ローカルのアーカイブ・DerivedData・Xcodeユーザー状態を `.gitignore` で除外し、提出物とソース管理対象を分離した。

## 提出前に解消する必須事項

1. **識別子とApple Developer登録**
   - Xcode本体ターゲットは `com.anemos.gourmepp`、Swiftモジュールは `Gourmepp`、Pro商品IDは `com.anemos.gourmepp.pro.lifetime` に統一した。
   - 新しいバックアップUTTypeは `com.anemos.gourmepp.backup` と `.gourmeppbackup`。旧 `.gohanbackup` は読み込み互換性を維持する。
   - Apple Developerで `com.anemos.gourmepp` のApp IDを登録し、同じチームでDistribution署名を作成する。
2. **外部URL**
   - Support URL: `https://gourmepp-support.pages.dev/support/`
   - Privacy Policy URL: `https://gourmepp-support.pages.dev/privacy/`
   - 2026-09-12にCloudflare PagesでHTTPS応答と表示内容を確認済み。
3. **Pro販売設定**
   - 非消費型商品IDは `com.anemos.gourmepp.pro.lifetime`。
   - Bundle ID方針に合わせ、App Store Connectの商品作成とSandbox検証を行う。
4. **UIテストの再実行**
   - 既存SimulatorのUI自動化サービスが応答しないため、実機または安定したSimulatorセッションで再実行する。
5. **実機QA**
   - `RELEASE_QA.md` の権限拒否、写真・カメラ、位置情報、バックアップ復元、EPUB、購入復元を実機で完了する。
6. **リリースビルドの最終確認**
   - 提出直前のソースでReleaseビルドとArchiveを実行し、App Icon、Privacy Manifest、Info.plist、dSYMを確認する。
   - アーカイブを再実行し、Distribution署名で完了することを確認してからアップロードする。
   - 提出直前のソースで、Version／Build番号を確定してArchiveを再実行する。現在のArchiveはVersion `1.0`、Build `1`でDistribution署名済み。

## 変更管理

- この監査では、アプリのソースコードと名称を含む識別子を変更していない。
- Xcodeの署名チーム変更と、このリリース文書群は未コミット。ユーザーの明示的な依頼があるまでコミットしない。
