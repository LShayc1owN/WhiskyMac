# WhiskyMac 0.0.4：独立启动修复

日期：2026-11-01。崩溃报告中，0.0.3 在 HistoryViewStateStore 初始化时，
因本地化调用生成的 Bundle.module 而触发资源包不存在的断言。该访问器
首先查找 app 根目录，再回退到构建机器的绝对路径；实际资源打包在
Contents/Resources。此前烟测借用了构建目录资源，未验证独立运行。

Localization.swift 新增 AppResources，在运行时搜索标准资源位置，不依赖
开发机器路径。缺少资源时构建脚本立即失败。烟测核对运行时资源目录的文件
身份，兼容 /tmp 与 /private/tmp 的别名；可选经 LaunchServices 验证启动。

验证：338 项测试、53 个套件通过；可测试代码行覆盖率 90.88%。新增测试
覆盖移动后的应用资源目录、缺失资源以及运行时目录查找。临时隐藏 Release
构建资源目录后，从 0.0.4 ZIP 解包，直接运行和 LaunchServices 启动均成功，
并确认资源来自应用自身；之后已恢复构建目录。所有烟测使用临时历史目录，
不轮询剪贴板或注册全局快捷键。原版和开发版历史均未迁移或覆盖。

证据：evidence/2026-11-01/resource-fix-tests-coverage.log、
resource-fix-package.log 和 resource-fix-standalone-smoke.log。
交付：dist/WhiskyMac 0.0.4.zip。
