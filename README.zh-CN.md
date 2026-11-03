# WhiskyMac

[English](README.md) | [简体中文](README.zh-CN.md)

仓库：[lshayc1own/WhiskyMac](https://github.com/lshayc1own/WhiskyMac)。
当前准备存放在私有开发仓库，尚未配置公开二进制发行。

WhiskyMac 是基于 [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7)
开发的 macOS 剪贴板管理器。原作者为 Nathan Poncet 及贡献者，基于提交
`1ebcee1e0735e957777c599017ee411d8046c7e7`。

这是由 **LinShay（琳曦）**维护的独立修改版本，并非 Whisk 官方发行版，
也不表示上游作者认可或背书。修改说明日期：**2026-11-03**。

## 功能

- 本地保存文本、富文本、链接、图片、文件及颜色的剪贴板历史。
- 搜索、应用与类型筛选、固定、保留策略和顺序粘贴。
- 富文本版本分组、可配置的卡片交互及预览。
- 手动隐私保护、可选的共享检测、临时敏感会话。
- 外观、快捷键和可选拷贝音效设置。
- 英文、法文、德文、简体中文界面。

具体实现与限制见[开发说明](WHISK_MAY_DEV.md)。当前仍为开发版本。

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
Neovim 标志由 Jason Long 创作，采用 CC BY 3.0；随包 Kenney UI Audio 音效由
Kenney Vleugels 创作，采用 CC0，详情见第三方声明。

分发二进制时，须按适用条款提供与该版本对应的完整源码，包括修改、
适合编辑的素材源文件及必要构建脚本。只给出未修改的上游源码链接不够。
使用上述 App Store/TestFlight 例外发行时，对应源码须持续公开可用。
维护此派生项目本身无需转让版权、购买许可或申请所谓“GPL 证书”。

## 发布配置

开发仓库计划保持私有；公开源码访问、支持页面及隐私政策地址尚未配置。
对外分发二进制前，请填写 [release-config.json](release-config.json)；
字段留空会使发布校验失败。发布目的地不使用上游作者的账号或网址。

打包时会将许可文件放入应用的 `Contents/Resources/Legal`，
可通过菜单栏的“许可证与声明…”打开。
核验依据与尚待补齐的信息见[许可核验说明](docs/LICENSING.md)。
`disc/` 中已有的应用和压缩包属于旧本地产物，需要重新构建才能获得改名后的应用及许可文件。

贡献说明见 [CONTRIBUTING.md](CONTRIBUTING.md)，架构见
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。
