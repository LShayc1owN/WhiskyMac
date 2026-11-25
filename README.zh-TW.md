<p align="center"><img src="Assets/icon.png" width="112" alt="WhiskyMac 應用程式圖示"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">隨時找回複製過的內容。<br>適用於 macOS 15 及更新版本的剪貼簿管理工具。</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac 是以 [Whisk](https://github.com/nathan-poncet/whisk) 為基礎的獨立專案，目前仍在開發中。下方功能對應目前的原始碼。各公開版本的功能與簽署狀態請參閱各自的發行說明。

## 下載與入門

**[下載最新版本](https://github.com/LShayc1owN/WhiskyMac/releases/latest)**

1. 下載應用程式的 ZIP 檔案，解壓縮後將 `WhiskyMac.app` 移到「應用程式」。
2. 開啟 WhiskyMac，依照「歡迎指南」操作。若 macOS 要求剪貼簿權限，請從 WhiskyMac 選單選擇「允許取用剪貼板…」。
3. 在其他應用程式複製內容，接著按一下 WhiskyMac 的選單列圖示，或選擇「顯示歷史記錄」。也可在設定中啟用全域快速鍵。

## 功能亮點

- **尋找剪貼簿內容。** 文字、格式化文字、程式碼、連結、圖片、檔案及顏色都儲存在本機。可搜尋內容或來源應用程式，支援模糊、包含、完整字詞、開頭及結尾比對。可依應用程式、類型、釘選、顏色標籤或 Handoff 篩選，並用 `type:path` 找出以文字複製的檔案路徑。
- **重複使用。** 支援預覽、編輯、拖放、複製、直接貼上、以純文字貼上及依序貼上。純文字相同的格式化版本可分組選擇，也可使用鍵盤及選用的 Vim 按鍵操作。
- **拆分內容。** 可依行、段落或分隔符號拆分文字，或擷取 HTTP(S) 連結。預覽後可新增卡片、取代原卡片，或儲存為群組。複製或貼上群組時，可選擇原文或指定部分。
- **整理歷史記錄。** 釘選項目可加入可搜尋的備註、七種顏色標籤並選擇一律遮蔽內容，也可在歷史面板或獨立視窗開啟。可依時間、內容類型或 Handoff 來源暫時隱藏較早的記錄。未釘選記錄可設定保留期限與容量，清除後可以復原。
- **掌控顯示內容。** 手動隱私模式會遮蔽卡片，可個別設定搜尋、篩選及指標附近的局部顯示，也能從卡片選單在原處顯示單張卡片。選用的分享偵測涵蓋支援的 Zoom／Teams 分享工具列。敏感應用程式的內容只暫存在記憶體中並按時到期，排除的應用程式會略過。
- **遮蔽可能是金鑰的內容。** 在本機辨識常見的 API 金鑰、權杖、Cookie 與雜湊格式。可個別設定卡片遮蔽和「金鑰」分類。遮蔽會控制卡片上顯示的內容。
- **配合系統外觀。** macOS 26 及更新版本的歷史記錄與設定控制項採用原生 Liquid Glass，macOS 15 使用霧面介面。歷史面板和設定可分別選擇淺色、深色或跟隨系統。
- **依喜好調整。** 可調整卡片尺寸、選單列圖示、卡片操作、快速鍵和選用的複製音效。設定頁可搜尋，也能依類別重設快速鍵並復原。介面支援繁體中文、簡體中文、英文、法文、德文、義大利文及日文。

詳細行為與限制請參閱[專案範圍](docs/PROJECT.md)和[更新紀錄](CHANGELOG.md)。

## 從原始碼建置

需要 macOS 15 或更新版本、macOS 26 SDK，以及完整安裝的 Xcode。在本機專案目錄執行：

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
```

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

自動發行流程會驗證 [release-config.json](release-config.json) 中的公開原始碼、支援及隱私權政策網址。應用程式套件中的授權文件位於 `Contents/Resources/Legal`，可從 WhiskyMac 選單選擇「授權條款與聲明…」開啟。

如果 WhiskyMac 對你有幫助，可以自願贊助這個獨立專案的開發：

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="請我喝杯咖啡 / Buy me a coffee"></a>

## 更多資料

[專案範圍](docs/PROJECT.md) · [開發說明](docs/DEVELOPMENT.md) · [架構](docs/ARCHITECTURE.md) · [更新紀錄](CHANGELOG.md) · [貢獻指南](CONTRIBUTING.md)
