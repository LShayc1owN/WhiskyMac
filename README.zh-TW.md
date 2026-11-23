<p align="center"><img src="Assets/icon.png" width="112" alt="WhiskyMac 應用程式圖示"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">隨時找回複製過的內容。<br>適用於 macOS 15 及更新版本的剪貼簿管理工具。</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac 是以[原始專案 Whisk](https://github.com/nathan-poncet/whisk) 為基礎的獨立修改版本，目前仍在開發中。此儲存庫為私人儲存庫，尚未提供公開下載；以下步驟適用於從本機專案目錄自行建置。

## 功能亮點

- **快速尋找。** 在本機保存文字、格式化文字、連結、圖片、檔案及顏色的剪貼簿歷史紀錄。可搜尋內容或來源應用程式，並依應用程式、類型、釘選項目、顏色標籤及 Handoff 來源篩選。檔案路徑文字有獨立篩選項，也支援 `type:path` 搜尋。
- **靈活重複使用。** 支援複製、直接貼上、以純文字貼上、拖放、預覽、編輯及依序貼上。純文字內容相同的格式化文字版本會分組顯示；亦支援鍵盤操作和選用的 Vim 導覽。
- **拆分與整理。** 依行、段落或分隔符號拆分文字，也可擷取 HTTP(S) 連結。預覽結果後，可新增卡片、取代原卡片，或儲存為持續保留的群組；複製或貼上時可選擇原文或群組中的個別部分。
- **保留重要內容。** 釘選項目可加入可搜尋的備註、七種顏色標籤，並可設定為始終遮蔽內容；可在歷史紀錄中檢視，或開啟獨立視窗。未釘選的歷史紀錄可設定保留期限與容量，清除後可復原。
- **掌控內容顯示。** 手動隱私模式會遮蔽面板內容；選用的 Zoom／Teams 分享工具列偵測有其範圍限制。搜尋、篩選及指標附近的局部顯示可分別開啟。敏感應用程式的內容只會暫存在記憶體中，並於設定時間後過期；排除的應用程式不會被記錄。
- **依喜好調整。** 可調整卡片尺寸、霧面外觀、選單列圖示、互動方式、快速鍵與選用的複製音效。設定頁可搜尋，重設快速鍵後也可復原。初次啟動的練習區不會讀取或修改真正的剪貼簿與歷史紀錄。應用程式介面支援英文、法文、德文、義大利文、簡體中文、繁體中文及日文。

詳細行為與限制請參閱[專案範圍](docs/PROJECT.md)和[更新紀錄](CHANGELOG.md)。

## 從原始碼建置

需要 macOS 15 或更新版本、macOS 26 SDK，以及完整安裝的 Xcode。在本機專案目錄執行：

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

打包指令碼會產生 `dist/WhiskyMac.app` 和 `dist/WhiskyMac.zip`。內部 Swift target 與執行檔仍名為 `Whisk`。若未提供簽署身分，套件只會使用臨時簽署；這不代表已完成公證或可直接送交 App Store 審核。

## 隱私與資料

- Bundle ID 為 `dev.whisky.maclx`，歷史紀錄儲存在 `~/Library/Application Support/WhiskMay-Dev`。重新命名應用程式不會搬移或刪除既有開發資料，也不會自動匯入原始 Whisk 的歷史紀錄。隔離測試可使用 `WHISK_MAY_DATA_DIR`。
- 全域快速鍵、連結預覽、分享偵測及啟動時檢查更新預設關閉。啟用連結預覽後，應用程式會向複製連結所指向的網站要求中繼資料。可手動檢查更新，或自行開啟從 GitHub 穩定版本取得更新資訊的功能；App Store 版本不進行外部更新檢查。
- 直接貼上及選用的分享偵測可能需要 macOS 權限。Handoff 來源僅為盡力提供的提示，無法確認具體裝置或應用程式。隱私模式無法收回已傳送至其他應用程式的內容。

更多細節請參閱[開發說明](docs/DEVELOPMENT.md)。

## 原始專案與授權

WhiskyMac 修改自 [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7)，基礎提交為 `1ebcee1e0735e957777c599017ee411d8046c7e7`。[原始專案 Whisk](https://github.com/nathan-poncet/whisk) 由 Nathan Poncet 及貢獻者開發。WhiskyMac 是由 **LinShay（琳曦）**維護的獨立版本，並非 Whisk 官方發行版，也不代表原作者認可或背書。

軟體採用 **GPL-3.0-or-later**；另行授權的第三方素材依各自條款使用。請保留[授權條款](LICENSE)、[專案聲明](NOTICE)及[第三方聲明](THIRD_PARTY_NOTICES.md)。Whisk 原始部分 © 2026 Nathan Poncet 及貢獻者；WhiskyMac 新增部分 © 2026 LinShay（琳曦），以其擁有的權利為限。

[原專案的 App Store／TestFlight 附加許可](LICENSE-EXCEPTION-APP-STORE.md)依原文保留；LinShay 的[獨立附加許可](LICENSE-EXCEPTION-WHISKYMAC.md)僅涵蓋其有權授權的新增部分。散布二進位版本時，須提供與該版本對應的完整原始碼；依這些例外於 App Store／TestFlight 散布時，原始碼須持續公開可取得。Apple 審核、簽署及第三方素材權利另有要求。Neovim 標誌採用 CC BY 3.0；隨附的 Kenney UI Audio 與 Wyzowl SFX Kit 音效採用 CC0。詳見[授權查核說明](docs/LICENSING.md)。

## 發布與支持

[release-config.json](release-config.json) 中公開原始碼、支援及隱私權政策的網址尚未填寫；發布驗證會阻止設定不完整的發行版。日後應透過 GitHub Releases 連同對應原始碼提供安裝套件，建置產物不納入原始碼儲存庫。應用程式套件中的法律文件位於 `Contents/Resources/Legal`，可由選單列的 **Licenses and notices…** 開啟；選單名稱會隨介面語言變更。

如果 WhiskyMac 對你有幫助，可以自願贊助這個獨立專案的開發：

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="請我喝杯咖啡 / Buy me a coffee"></a>

## 更多資料

[專案範圍](docs/PROJECT.md) · [開發說明](docs/DEVELOPMENT.md) · [架構](docs/ARCHITECTURE.md) · [更新紀錄](CHANGELOG.md) · [貢獻指南](CONTRIBUTING.md)
