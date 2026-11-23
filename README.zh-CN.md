<p align="center"><img src="Assets/icon.png" width="112" alt="WhiskyMac 应用图标"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">随时找回复制过的内容。<br>适用于 macOS 15 及以上版本的剪贴板管理器。</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac 是基于[原项目 Whisk](https://github.com/nathan-poncet/whisk) 的独立修改版，目前仍在开发中。当前仓库为私有仓库，尚未配置公开下载；下方说明适用于从此项目目录自行构建。

## 功能亮点

- **快速查找。** 本地保存文本、富文本、链接、图片、文件和颜色；按内容或来源应用搜索，并按应用、类型、固定项、颜色标签及 Handoff 来源筛选。文件路径文本有独立筛选项，也支持 `type:path` 搜索。
- **灵活复用。** 复制、直接粘贴、纯文本粘贴、拖放、预览、编辑和顺序粘贴都可使用。相同纯文本的富文本版本会分组展示；支持键盘操作与可选的 Vim 导航。
- **拆分与整理。** 按行、段落、分隔符拆分文本，或提取 HTTP(S) 链接。预览后可新增卡片、替换原卡片或保存为分组；复制或粘贴时可选择原文或分组中的部分。
- **保留重要内容。** 固定项支持可搜索备注、七种颜色标签及始终隐藏内容；可在历史中查看，也可打开独立窗口。未固定历史可设置保留期限和容量，清除操作支持撤销。
- **控制内容显示。** 手动隐私模式可遮挡面板内容；可选的 Zoom/Teams 共享工具栏检测范围有限。搜索、筛选和指针区域显示可分别开启。敏感应用的内容仅暂存于内存并按时过期；排除的应用不会被记录。
- **按喜好设置。** 可调整卡片大小、磨砂外观、状态栏图标、交互、快捷键和可选拷贝音效。设置页支持搜索，快捷键重置后可撤销。首次启动练习区不会读取或修改真实剪贴板及历史。界面支持英、法、德、意、简体中文、繁体中文和日语。

详细行为和限制见[项目说明](docs/PROJECT.md)与[更新日志](CHANGELOG.md)。

## 从源码构建

需要 macOS 15 或更新版本、macOS 26 SDK，以及完整安装的 Xcode。在此项目目录中运行：

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

打包脚本生成 `dist/WhiskyMac.app` 与 `dist/WhiskyMac.zip`。内部 Swift target 和可执行文件仍名为 `Whisk`。未提供签名身份时仅进行临时签名，不代表已完成公证或满足 App Store 上架条件。

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

[release-config.json](release-config.json) 中公开源码、支持及隐私政策地址尚未填写；发布校验会阻止未配置的发行。将来应通过 GitHub Releases 连同对应源码发布安装包，构建产物不纳入源码仓库。应用包中的法律文件位于 `Contents/Resources/Legal`，可通过菜单栏的“许可证与声明…”访问。

如果 WhiskyMac 对你有帮助，可以自愿赞助这个独立项目的开发：

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="请我喝杯咖啡 / Buy me a coffee"></a>

## 更多资料

[项目说明](docs/PROJECT.md) · [开发文档](docs/DEVELOPMENT.md) · [架构](docs/ARCHITECTURE.md) · [更新日志](CHANGELOG.md) · [贡献指南](CONTRIBUTING.md)
