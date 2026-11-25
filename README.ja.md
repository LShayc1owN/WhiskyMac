<p align="center"><img src="Assets/icon.png" width="112" alt="WhiskyMac のアプリアイコン"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">コピーした内容を、必要なときにすぐ見つける。<br>macOS 15 以降に対応したクリップボード履歴アプリです。</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac は [Whisk](https://github.com/nathan-poncet/whisk) をベースにした独立プロジェクトで、現在も開発中です。以下の機能は現在のソースコードを基に説明しています。配布版に含まれる機能や署名の状況は、各リリースノートをご確認ください。

## ダウンロードと使い方

**[最新リリース](https://github.com/LShayc1owN/WhiskyMac/releases/latest)**

1. リリースページの **Assets** からアプリ本体の `WhiskyMac-v*.zip` をダウンロードします。展開した `WhiskyMac.app` を「アプリケーション」フォルダに移動します。
2. WhiskyMac を開き、ウェルカムガイドに従います。クリップボードのアクセス許可が必要な場合は、メニューバーの WhiskyMac アイコンを右クリックし、「クリップボードへのアクセスを許可…」を選びます。
3. 別のアプリで内容をコピーしてから、WhiskyMac のメニューバーアイコンをクリックするか、メニューで「履歴を表示」を選びます。設定からグローバルショートカットも有効にできます。

## 主な機能

- **コピーした内容を探す。** テキスト、リッチテキスト、コード、リンク、画像、ファイル、色をローカルに保存します。内容やコピー元アプリを、あいまい一致、部分一致、単語単位、先頭一致、末尾一致で検索できます。アプリ、種類、ピン留め、色タグ、Handoff で絞り込めます。テキストとしてコピーされたファイルパスは `type:path` で探せます。
- **履歴の内容を再利用する。** プレビュー、編集、ドラッグ＆ドロップ、コピー、直接ペースト、プレーンテキストでのペースト、ペーストスタックが使えます。同じ本文のリッチテキストはグループ化され、キーボードや任意の Vim キー操作で選べます。
- **テキストを分割する。** 行、段落、区切り文字で分割したり HTTP(S) リンクを抽出したりできます。結果を確認し、新しいカードの追加、元のカードの置き換え、またはグループとしての保存を選べます。グループをコピーまたはペーストする際は、元の内容か、選択した部分を使えます。
- **履歴を整理する。** ピン留めには検索できるメモと 7 色のタグを付けられ、内容を常に隠すこともできます。履歴パネルまたは専用ウインドウで開けます。時刻、種類、Handoff の由来を指定して、古い項目を一時的に非表示にできます。ピン留めしていない履歴の保存期間と件数を設定でき、消去は取り消せます。
- **表示を管理する。** 手動のプライバシーモードではカードを隠し、検索、絞り込み、ポインタ付近だけの表示を個別に設定できます。カードのメニューから、その場で 1 枚だけ表示することもできます。オプションの画面共有検出は対応する Zoom／Teams の共有ツールバーが対象です。機密扱いのアプリのコピーはメモリ内で期限付きで保持し、除外したアプリのコピーは記録しません。
- **シークレットらしき内容を隠す。** 一般的な API キー、トークン、Cookie、ハッシュの形式をこの Mac 上で検出します。カード上で隠す設定と「シークレット」に分類する設定は別々に変更できます。マスクはカード上の表示に適用されます。
- **Mac に合った外観で使う。** macOS 26 以降では履歴と設定のコントロールに標準の Liquid Glass を使用し、macOS 15 ではすりガラス風の外観を使います。履歴パネルと設定は、それぞれライト、ダーク、システムに合わせる設定を選べます。
- **自分好みに設定する。** カードのサイズ、メニューバーアイコン、カードの操作、ショートカット、オプションのコピー音を変更できます。設定項目を検索でき、ショートカットはカテゴリ別にリセットして取り消せます。表示言語は日本語、英語、フランス語、ドイツ語、イタリア語、簡体字中国語、繁体字中国語です。

詳しい動作と制限は、[プロジェクトの対象範囲](docs/PROJECT.md)と[変更履歴](CHANGELOG.md)をご覧ください。

## プライバシーとデータ

- バンドル ID は `dev.whisky.maclx` で、履歴は `~/Library/Application Support/WhiskyMac` に保存されます。元の Whisk の履歴は自動では取り込みません。テストを分離するには `WHISKYMAC_DATA_DIR` を使用できます。
- グローバルショートカット、リンクのプレビュー、共有の検出、起動時の更新確認は初期状態でオフです。リンクのプレビューを有効にすると、コピーしたリンク先にメタデータを問い合わせます。更新は手動で確認するか、GitHub の WhiskyMac 安定版に対する起動時の確認を任意で有効にできます。App Store ビルドには外部更新確認がありません。
- 直接ペーストと任意の共有検出には macOS の権限が必要になる場合があります。Handoff の判定は参考情報であり、具体的なデバイスやアプリの確認には使えません。プライバシーモードでも、他のアプリへすでに渡した内容は取り戻せません。

詳細は[開発者向けドキュメント](docs/DEVELOPMENT.md)をご覧ください。

## 元のプロジェクトとライセンス

WhiskyMac は [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7) を基にした独立した改変版です。基点となるコミットは `1ebcee1e0735e957777c599017ee411d8046c7e7` です。[元の Whisk プロジェクト](https://github.com/nathan-poncet/whisk)は Nathan Poncet 氏と貢献者によって開発されました。WhiskyMac は **LinShay（琳曦）** が保守しており、Whisk の公式リリースではなく、元の作者による推奨や承認を意味しません。

ソフトウェアは、別ライセンスの第三者素材を除き **GPL-3.0-or-later** で提供されます。[LICENSE](LICENSE)、[プロジェクトの権利表示](NOTICE)、[第三者素材の権利表示](THIRD_PARTY_NOTICES.md)を保持してください。元の Whisk の部分は © 2026 Nathan Poncet 氏および貢献者、WhiskyMac の追加部分は権利を有する範囲で © 2026 LinShay（琳曦）です。

[元の App Store／TestFlight 追加許可](LICENSE-EXCEPTION-APP-STORE.md)は原文のまま保持しています。LinShay の[別個の追加許可](LICENSE-EXCEPTION-WHISKYMAC.md)は、LinShay が許諾できる追加部分だけに適用されます。バイナリを配布する場合、その版に対応する完全なソースコードの提供が必要です。これらの追加許可に基づき App Store／TestFlight で配布する場合は、対応するソースコードを継続して公開する必要があります。Apple の審査、署名、第三者素材の権利には別途要件があります。Neovim のロゴは CC BY 3.0、同梱の Kenney UI Audio と Wyzowl SFX Kit のサウンドは CC0 です。詳しくは[ライセンスの確認資料](docs/LICENSING.md)をご覧ください。

## リリースと支援

過去のバージョンのリリースノートとダウンロードは [GitHub Releases](https://github.com/LShayc1owN/WhiskyMac/releases) にあります。同梱のライセンス文書は WhiskyMac のメニューから「ライセンスと通知…」を選ぶと開けます。

WhiskyMac が役に立った場合は、任意の寄付で独立した開発を支援できます。

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="開発を支援する / Buy me a coffee"></a>

## 関連資料

[プロジェクトの対象範囲](docs/PROJECT.md) · [開発ガイド](docs/DEVELOPMENT.md) · [アーキテクチャ](docs/ARCHITECTURE.md) · [変更履歴](CHANGELOG.md) · [貢献ガイド](CONTRIBUTING.md)
