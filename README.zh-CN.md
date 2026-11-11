# WhiskyMac

[English](README.md) | [简体中文](README.zh-CN.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

原项目：[Whisk — nathan-poncet/whisk](https://github.com/nathan-poncet/whisk)。

仓库：[lshayc1own/WhiskyMac](https://github.com/lshayc1own/WhiskyMac)。
当前为私有开发仓库，尚未配置公开二进制发行。

WhiskyMac 是基于 [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7)
开发的 macOS 剪贴板管理器。原作者为 Nathan Poncet 及贡献者，基于提交
`1ebcee1e0735e957777c599017ee411d8046c7e7`。

这是由 **LinShay（琳曦）**维护的独立修改版本，并非 Whisk 官方发行版，
也不表示上游作者认可或背书。当前变更见 [CHANGELOG.md](CHANGELOG.md)。

## 功能

- 本地保存文本、富文本、链接、图片、文件及颜色的剪贴板历史；按内容或来源应用搜索，并按应用、类型、固定状态及颜色标签筛选。
- 支持复制、直接粘贴、纯文本粘贴、拖放、预览、文本编辑、顺序粘贴与可选 Vim 导航；相同纯文本的富文本格式可分组选择。
- 按行、段落或分隔符拆分文本，或提取 HTTP(S) 链接；预览后可新增卡片、替换原卡片或保存为持久分组，复制和粘贴时可选择分组内的部分。
- 固定项支持可搜索的备注、七种颜色标签和始终隐藏内容；可在历史中查看或打开独立窗口。普通历史可设置保留期限与容量，清除未固定项后可撤销。
- 手动隐私模式、范围有限的可选共享工具栏检测、可调节的指针区域显示，以及保持内容遮挡时可选的搜索与筛选。普通模式与隐私模式可分别设置卡片交互。
- 可将来源应用设为敏感应用，复制内容仅在内存中暂存并按设定时间过期；也可完全排除指定应用的记录。
- 可暂停捕获、设置登录时启动，并调整卡片尺寸、玻璃外观、状态栏图标、语言、快捷键与卡片操作；设置页支持搜索及按类别重置快捷键并撤销。可选拷贝音效包括 Kenney UI Audio、SFX Kit 和 macOS 系统音效。
- 英文、法文、德文、意大利文、简体中文界面。

具体行为与限制见[开发说明](docs/DEVELOPMENT.md)及[更新日志](CHANGELOG.md)。当前仍为开发版本。

## 构建与验证

运行要求 macOS 15 或更新版本，构建需要 macOS 26 SDK。
测试和本地化资源生成需要完整安装 Xcode。

在本项目目录中执行：

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

打包结果为 `dist/WhiskyMac.app` 和 `dist/WhiskyMac.zip`。
内部 Swift target 与可执行文件仍叫 `Whisk`，以保留现有模块和资源布局。
没有指定签名身份时仅使用临时签名，不表示已完成公证或满足 App Store 上架要求。

## 数据与隐私

Bundle ID 为 `dev.whisky.maclx`。为保留已有开发数据，
历史目录继续使用 `~/Library/Application Support/WhiskMay-Dev`；
应用改名不会迁移或删除历史。隔离测试可使用 `WHISK_MAY_DATA_DIR` 指定目录。
不会自动导入上游 Whisk 的历史数据。

全局快捷键和链接预览默认关闭。启用链接预览后会向所复制网址请求元数据。
当前开发发行方式禁用更新检查。直接粘贴及可选共享检测可能需要 macOS 授权。
隐私保护不能撤回已经导出到其他应用的内容。

## 许可证与署名

软件采用 **GPL-3.0-or-later**，单独许可的第三方素材遵守各自条款。
请保留 [LICENSE](LICENSE)、[NOTICE](NOTICE) 和
[第三方声明](THIRD_PARTY_NOTICES.md)。

- Whisk 原始部分：版权属于 Nathan Poncet 及贡献者，2026 年。
- WhiskyMac 修改部分：在持有相应权利范围内，版权属于 LinShay（琳曦），2026 年。
- 上游 App Store/TestFlight 附加许可：[原文](LICENSE-EXCEPTION-APP-STORE.md)，原样保留。
- LinShay 对有权授权的新增部分授予的附加许可：[独立文件](LICENSE-EXCEPTION-WHISKYMAC.md)。

上游附加许可明确覆盖基于 Whisk 的作品。这些授权解决对应发行渠道的版权许可问题；
Apple 审核、签名和第三方素材权利仍有各自要求。
Neovim 标志由 Jason Long 创作，采用 CC BY 3.0；随包 Kenney UI Audio 与
Wyzowl SFX Kit 音效采用 CC0，详情见第三方声明。

分发二进制时，须按适用条款提供与该版本对应的完整源码，包括修改、
适合编辑的素材源文件及必要构建脚本。只给出未修改的上游源码链接不够。
使用上述 App Store/TestFlight 例外发行时，对应源码须持续公开可用。
维护此派生项目本身无需转让版权、购买许可或申请所谓“GPL 证书”。

## 发布配置

开发仓库目前为私有；公开源码访问、支持页面及隐私政策地址尚未配置。
对外分发二进制前，请填写 [release-config.json](release-config.json)；
字段留空会使发布校验失败。发布目的地不使用上游作者的账号或网址。

打包时会将许可文件放入应用的 `Contents/Resources/Legal`，
菜单栏的“许可证与声明…”会打开“设置 → 关于 → 许可证与声明”，可在页内打开源文件或在访达中显示。
核验依据与尚待补齐的信息见[许可核验说明](docs/LICENSING.md)。
构建产物和本地验收记录不纳入源码仓库；应用安装包通过 GitHub Releases 分发。

贡献说明见 [CONTRIBUTING.md](CONTRIBUTING.md)，架构见
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。
