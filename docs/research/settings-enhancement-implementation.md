# WhiskyMac 0.0.6：设置、外观与接力提示

日期：2026-11-01。本地 arm64 开发包，macOS 15+；应用身份仍为 `dev.whisky.maclx`。

## 已实现的行为

- 设置页分为常规、外观、历史记录、交互、隐私和快捷键；顶部按钮或外观设置可切换顶部／侧边标签栏，选择会持久化，当前页面保持不变，切换页面回到滚动起点。采用原生 SwiftUI、系统字体、分组表单和较淡的卡片／导航背景。
- Magpie 参考对象为本机 `/Applications/magpie.app`（com.yetone.magpie，0.1.2562）。依据其公开的 [GUI shell 设计](https://github.com/yetone/magpie/blob/main/docs/subsystems/gui-shell.md)和 [app.css](https://github.com/yetone/magpie/blob/main/internal/gui/assets/app.css) 研究导航与视觉层级；没有复制其代码、图标、素材或加入 WebView。公开源码可能较本机版本更新，本轮不是逐像素复刻。
- 菜单栏图标单击可选择显示剪贴板卡片或菜单；右键始终显示菜单。继续复用同一个 NSStatusItem，菜单中保留打开卡片和设置的入口。
- 语言支持跟随系统、English、Français、简体中文。应用内标签、菜单、窗口标题和历史计数立即更新，保留每种翻译的单复数规则，不修改系统 AppleLanguages。使用 AppResources 定位包内资源；SwiftPM 会把 zh-Hans 目录转换为小写，使用显式本地化资源查询兼容该布局。原生系统授权弹窗等系统 UI 的语言仍由系统决定。
- 强调色可跟随系统或通过原生 ColorPicker 自选不透明 sRGB。设置控件、筛选和搜索强调、代码搜索命中以及当前选中剪贴板卡片的边框采用同一颜色；运行时设置变化刷新已打开的面板。保留上游 matcha 类型访问名称以减少同步冲突，其颜色现在来自用户偏好。
- 程序坞图标支持跟随窗口、不显示、始终显示。跟随窗口仅统计设置和欢迎等普通窗口；剪贴板浮窗及详情不触发显示。关闭最后一个普通窗口后恢复 accessory 模式；始终显示时，点程序坞图标重新打开设置。不显示模式仍可通过菜单栏使用应用。

默认值：顶部标签栏、系统语言、系统强调色、单击显示卡片、程序坞跟随普通窗口。偏好统一保存在开发版的独立 UserDefaults 域。

## 来源提示及存储兼容性

`AppKitPasteboard.source(types:appName:bundleID:)` 通过公开的 NSPasteboard 类型元数据读取
`com.apple.is-remote-clipboard`。这个标记由 [NSPasteboard 社区约定](https://github.com/NSPasteboard/NSPasteboard.org/blob/main/index.md)记录，并被 [Maccy](https://github.com/p0deje/Maccy)用于区分通用剪贴板；它不是 Apple 承诺稳定或经过认证的来源接口。

带标记的新记录使用 `SourceApp.Origin.handoffMarker`，卡片和筛选显示“接力内容（系统标记）”；
不保存当时 Mac 前台应用为它的来源，不声称具体来自 iPhone、哪台设备或哪个应用。无标记的新记录仍采用上游前台应用／菜单栏拥有者估计，提示文字明确实际来源未经验证；缺少标记不能证明来自本机。旧记录无法追溯分类。来源标记不能代替 concealed/transient 敏感内容排除，后者始终优先。

SQLite 在 `content` 表追加可空 `source_origin` 列。旧记录保持原字段，空值按普通观察来源解释；只保存明确的 handoffMarker，新增字段在同 ID 更新时可清除。没有更换数据库目录，也没有在开发测试中打开真实用户数据库。用户启动新版时，其开发版历史会执行此追加字段操作。

相同 payload 与 RTF 仍去重。当新捕获跨越普通来源／接力标记边界时，更新该记录的来源，保留 ID、置顶与格式；普通来源之间仍保持上游首次来源归属规则。用户从历史复制或粘贴不会凭空改变来源。分组的卡片标题继续表示最新格式记录，各格式保留自身元数据。

新增类型集中在 AppearanceSettings、SettingsPage、SourceApp.Origin；运行时应用策略在 AppDelegate，
数据库兼容在 SQLiteHistoryStore。没有增加私有 API、依赖包或新的远程配置。

## 验证与交付

- `AppearancePreferences`：独立偏好持久化与容错、颜色编码、菜单映射、程序坞规则、显式语言与单复数，以及六个设置页在两种导航布局下的离屏渲染。
- `HandoffAttribution`：类型标记、来源隔离、筛选、敏感标记优先、跨来源去重，以及合成旧库追加字段与重开持久化。
- 367 项测试／58 个 suite 通过，可测试代码行覆盖率 91.33%（门槛 90%）。架构规则、严格格式、翻译同步和 diff 检查通过。旧抹茶颜色断言按已批准的系统强调色默认行为改为与系统颜色的精确比较；没有放宽其他断言。
- 两种导航的截图在 `evidence/2026-11-01/settings-enhancement-ui/`，涵盖所有页面。完整测试、打包和烟测日志见同目录 settings-enhancement-*.log。
- 0.0.6 使用 `WHISK_PACKAGE_SUBDIR=0.0.6` 打包到独立目录，保留旧开发包。解压后的应用进行签名、资源路径和 LaunchServices 启动检查；附加偏好烟测在独立 defaults 与临时历史下验证法语／中文切换、自选色、三种程序坞模式及设置窗口开关。

交付：`dist/0.0.6/WhiskyMac 0.0.6.zip`。请先退出正在运行的旧 WhiskyMac，再解压打开新版。
真实 iPhone／Mac 接力、不同系统版本和第三方剪贴板桥接是否附带该标记仍待实机验收；
合成标记测试不等于覆盖所有接力方式。原生权限弹窗、VoiceOver 和用户实际窗口焦点体验也需要界面验收。
Git 未提交、未配置远程或推送；当前代码保留第 6、7 项的敏感会话及有限自动保护功能。
