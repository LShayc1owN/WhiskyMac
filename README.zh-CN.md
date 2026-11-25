<p align="center"><img src="Assets/icon.png" width="112" alt="WhiskyMac 应用图标"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">随时找回复制过的内容。<br>适用于 macOS 15 及以上版本的剪贴板管理器。</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac 是基于 [Whisk](https://github.com/nathan-poncet/whisk) 开发的独立项目，目前仍在开发中。下方功能对应当前源码，各公开版本所含功能和签名状态请查看各自的发行说明。

## 下载与入门

**[下载最新版本](https://github.com/LShayc1owN/WhiskyMac/releases/latest)**

1. 在发行页面的 **Assets** 列表中下载 `WhiskyMac-v*.zip` 安装包。解压后，将 `WhiskyMac.app` 拖到「应用程序」文件夹。
2. 打开 WhiskyMac，按欢迎指南操作。如果需要授予剪贴板权限，请右键点击 WhiskyMac 的菜单栏图标，选择「允许访问剪贴板…」。
3. 在其他应用复制一段内容，然后点 WhiskyMac 的菜单栏图标，或从菜单选择「显示历史记录」。也可以在设置中启用全局快捷键。

## 功能亮点

- **查找剪贴板内容。** 文本、富文本、代码、链接、图片、文件和颜色保存在本机。可按内容或来源应用搜索，支持模糊、包含、整词、开头和结尾匹配。可按应用、类型、固定项、颜色标签或 Handoff 筛选，用 `type:path` 查找以文本形式复制的文件路径。
- **复用内容。** 支持预览、编辑、拖放、复制、直接粘贴、纯文本粘贴和顺序粘贴。相同正文的富文本版本可分组选择，支持键盘操作和可选的 Vim 键位。
- **拆分内容。** 文本可按行、段落或分隔符拆分，也可提取 HTTP(S) 链接。预览后可新增卡片、替换原卡片或保存为分组。复制或粘贴分组时，可选择原文或指定部分。
- **整理历史记录。** 固定项支持可搜索备注、七种颜色标签和始终隐藏内容的选项，可在历史面板或独立窗口打开。也可按时间、内容类型或 Handoff 来源暂时隐藏较早的记录。未固定记录可设置保留期限和容量，清除后可撤销。
- **控制显示内容。** 手动隐私模式会遮挡卡片，可分别配置搜索、筛选和指针附近的局部显示，也可从卡片菜单在原处显示单张卡片。可选的共享检测仅覆盖受支持的 Zoom/Teams 共享工具栏。敏感应用的内容只在内存中暂存并按时过期，排除的应用不会被记录。
- **遮蔽疑似密钥。** 在本机识别常见的 API 密钥、令牌、Cookie 和哈希格式。可分别设置卡片遮蔽和「密钥」分类。遮蔽控制的是卡片上的显示内容。
- **随系统呈现。** macOS 26 及更新版本的历史记录和设置控件采用原生 Liquid Glass，macOS 15 使用磨砂界面。历史面板和设置可分别选择浅色、深色或跟随系统。
- **按喜好设置。** 可调整卡片大小、菜单栏图标、卡片交互、快捷键与可选的拷贝音效。设置支持搜索，也可按类别重置快捷键并撤销。界面支持简体中文、繁体中文、英语、法语、德语、意大利语和日语。

详细行为和限制见[项目说明](docs/PROJECT.md)与[更新日志](CHANGELOG.md)。

## 隐私与数据

- Bundle ID 为 `dev.whisky.maclx`，历史保存在 `~/Library/Application Support/WhiskMay-Dev`。改名不会迁移或删除已有开发数据，也不会自动导入上游 Whisk 的历史。隔离测试可使用 `WHISK_MAY_DATA_DIR`。
- 全局快捷键、链接预览、共享检测和启动时更新检查默认关闭。启用链接预览后会向所复制的网址请求元数据。可手动检查更新，或主动开启从 GitHub 稳定版获取更新信息；App Store 构建不进行外部更新检查。
- 直接粘贴和可选共享检测可能需要 macOS 授权。Handoff 来源仅是尽力而为的提示，不能确认具体设备或应用。隐私模式无法撤回已传给其他应用的内容。

更多说明见[开发文档](docs/DEVELOPMENT.md)。

## 原项目与许可证

WhiskyMac 基于 [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7) 修改，基础提交为 `1ebcee1e0735e957777c599017ee411d8046c7e7`。[原项目 Whisk](https://github.com/nathan-poncet/whisk) 由 Nathan Poncet 及贡献者开发。WhiskyMac 是 **LinShay（琳曦）**维护的独立版本，并非 Whisk 官方发行版，也不表示上游作者背书。

软件采用 **GPL-3.0-or-later**，单独许可的第三方素材遵守各自条款。请保留[许可证](LICENSE)、[项目声明](NOTICE)和[第三方声明](THIRD_PARTY_NOTICES.md)。Whisk 原始部分 © 2026 Nathan Poncet 及贡献者；WhiskyMac 新增部分 © 2026 LinShay（琳曦），以其持有的权利为限。

[上游 App Store/TestFlight 附加许可](LICENSE-EXCEPTION-APP-STORE.md)按原文保留；LinShay 的[独立附加许可](LICENSE-EXCEPTION-WHISKYMAC.md)仅覆盖其有权授权的新增部分。分发二进制时须提供与该版本对应的完整源码；依这些例外在 App Store/TestFlight 分发时，源码须持续公开可用。Apple 审核、签名及第三方素材权利另有要求。Neovim 标志采用 CC BY 3.0；随包 Kenney UI Audio 与 Wyzowl SFX Kit 音效采用 CC0。详见[许可核验说明](docs/LICENSING.md)。

## 发布与支持

历次发行的说明和下载都可在 [GitHub Releases](https://github.com/LShayc1owN/WhiskyMac/releases) 查看。应用内的许可文件可从 WhiskyMac 菜单的「许可证与声明…」打开。

如果 WhiskyMac 对你有帮助，可以自愿赞助这个独立项目的开发：

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="请我喝杯咖啡 / Buy me a coffee"></a>

## 更多资料

[项目说明](docs/PROJECT.md) · [开发指南](docs/DEVELOPMENT.md) · [架构](docs/ARCHITECTURE.md) · [更新日志](CHANGELOG.md) · [贡献指南](CONTRIBUTING.md)
