<p align="center"><img src="Assets/icon.png" width="112" alt="WhiskyMac のアプリアイコン"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">コピーした内容を、必要なときにすぐ見つける。<br>macOS 15 以降に対応したクリップボード履歴アプリです。</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac は [Whisk](https://github.com/nathan-poncet/whisk) を基にした独立した改変版で、現在開発中です。このリポジトリは非公開で、アプリの一般向けダウンロードはまだ設定されていません。以下は、この作業ツリーからビルドするための手順です。

## 主な機能

- **コピーした内容を探す。** テキスト、リッチテキスト、リンク、画像、ファイル、色をローカルの履歴に保存します。内容やコピー元アプリで検索し、アプリ、種類、ピン留め、色タグ、Handoff の判定で絞り込めます。ファイルパスの文字列には専用フィルターと `type:path` 検索があります。
- **いろいろな方法で再利用する。** コピー、直接ペースト、プレーンテキストとしてのペースト、ドラッグ＆ドロップ、プレビュー、編集、ペーストスタックに対応します。同じプレーンテキストを持つリッチテキストの形式はグループ化されます。キーボード操作と任意の Vim ナビゲーションも利用できます。
- **分割して整理する。** テキストを行、段落、区切り文字で分割したり、HTTP(S) リンクを抽出したりできます。結果を確認してから、新しいカードとして追加、元のカードと置き換え、または永続的なグループとして保存できます。コピーやペーストの際には、元の内容またはグループ内の部分を選べます。
- **大切な項目を残す。** ピン留めには検索可能なメモ、7 色のタグ、常時非表示にする設定があります。履歴内または専用ウインドウで表示できます。ピン留めしていない履歴の保存期間と件数を設定でき、消去は取り消せます。
- **表示する内容を管理する。** 手動のプライバシーモードでは内容を隠せます。Zoom／Teams の共有ツールバーを検出する任意機能には対象範囲の制限があります。検索、フィルター、ポインタ付近だけを表示する機能は個別に設定できます。機密扱いにしたアプリのコピーは期限付きでメモリ内に保持し、除外したアプリのコピーは記録しません。
- **自分好みに設定する。** カードのサイズ、すりガラス風の外観、メニューバーのアイコン、操作方法、ショートカット、任意のコピー音を変更できます。設定内の検索とショートカットのリセット取り消しにも対応します。初回起動時の練習スペースは実際のクリップボードや履歴を読み書きしません。アプリの表示言語は英語、フランス語、ドイツ語、イタリア語、簡体字中国語、繁体字中国語、日本語です。

詳しい動作と制限は、[プロジェクトの対象範囲](docs/PROJECT.md)と[変更履歴](CHANGELOG.md)をご覧ください。

## ソースからビルド

macOS 15 以降、macOS 26 SDK、完全な Xcode インストールが必要です。この作業ツリーで実行します。

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

パッケージ作成スクリプトは `dist/WhiskyMac.app` と `dist/WhiskyMac.zip` を生成します。内部の Swift ターゲット名と実行ファイル名は引き続き `Whisk` です。署名用 ID がない場合はアドホック署名となり、公証済みまたは App Store 提出可能な状態にはなりません。

## プライバシーとデータ

- バンドル ID は `dev.whisky.maclx` で、履歴は `~/Library/Application Support/WhiskMay-Dev` に保存されます。アプリ名の変更によって既存の開発データが移動・削除されることはなく、元の Whisk の履歴も自動では取り込みません。テストを分離するには `WHISK_MAY_DATA_DIR` を使用できます。
- グローバルショートカット、リンクのプレビュー、共有の検出、起動時の更新確認は初期状態でオフです。リンクのプレビューを有効にすると、コピーしたリンク先にメタデータを問い合わせます。更新は手動で確認するか、GitHub の WhiskyMac 安定版に対する起動時の確認を任意で有効にできます。App Store ビルドには外部更新確認がありません。
- 直接ペーストと任意の共有検出には macOS の権限が必要になる場合があります。Handoff の判定は参考情報であり、具体的なデバイスやアプリの確認には使えません。プライバシーモードでも、他のアプリへすでに渡した内容は取り戻せません。

詳細は[開発者向けドキュメント](docs/DEVELOPMENT.md)をご覧ください。

## 元のプロジェクトとライセンス

WhiskyMac は [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7) を基にした独立した改変版です。基点となるコミットは `1ebcee1e0735e957777c599017ee411d8046c7e7` です。[元の Whisk プロジェクト](https://github.com/nathan-poncet/whisk)は Nathan Poncet 氏と貢献者によって開発されました。WhiskyMac は **LinShay（琳曦）** が保守しており、Whisk の公式リリースではなく、元の作者による推奨や承認を意味しません。

ソフトウェアは、別ライセンスの第三者素材を除き **GPL-3.0-or-later** で提供されます。[LICENSE](LICENSE)、[プロジェクトの権利表示](NOTICE)、[第三者素材の権利表示](THIRD_PARTY_NOTICES.md)を保持してください。元の Whisk の部分は © 2026 Nathan Poncet 氏および貢献者、WhiskyMac の追加部分は権利を有する範囲で © 2026 LinShay（琳曦）です。

[元の App Store／TestFlight 追加許可](LICENSE-EXCEPTION-APP-STORE.md)は原文のまま保持しています。LinShay の[別個の追加許可](LICENSE-EXCEPTION-WHISKYMAC.md)は、LinShay が許諾できる追加部分だけに適用されます。バイナリを配布する場合、その版に対応する完全なソースコードの提供が必要です。これらの追加許可に基づき App Store／TestFlight で配布する場合は、対応するソースコードを継続して公開する必要があります。Apple の審査、署名、第三者素材の権利には別途要件があります。Neovim のロゴは CC BY 3.0、同梱の Kenney UI Audio と Wyzowl SFX Kit のサウンドは CC0 です。詳しくは[ライセンスの確認資料](docs/LICENSING.md)をご覧ください。

## リリースと支援

[release-config.json](release-config.json) の公開ソース、サポート、プライバシーポリシーの URL はまだ空欄で、設定が完了するまでリリース検証は通りません。インストール用パッケージは、対応するソースコードとともに GitHub Releases から配布し、ソースリポジトリには追加しない方針です。アプリに同梱される法的文書は `Contents/Resources/Legal` にあり、メニューバーの **Licenses and notices…** から開けます（項目名は表示言語によって変わります）。

WhiskyMac が役に立った場合は、任意の寄付で独立した開発を支援できます。

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="開発を支援する / Buy me a coffee"></a>

## 関連資料

[プロジェクトの対象範囲](docs/PROJECT.md) · [開発](docs/DEVELOPMENT.md) · [アーキテクチャ](docs/ARCHITECTURE.md) · [変更履歴](CHANGELOG.md) · [貢献ガイド](CONTRIBUTING.md)
