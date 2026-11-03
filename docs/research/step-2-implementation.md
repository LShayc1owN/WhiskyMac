# 第二步交付：数据一致性与可信测试基线

日期：2026-10-31。开发包版本：0.0.2（本机 arm64）。

## 行为与实现

- `History.recording` 仅将 payload 和 RTF 字节均相同的复制视为重复；复用 ID、
  置顶状态及来源，更新 copiedAt 和排序。不同 RTF 与纯文本复制各自保存，
  按已有容量和保留策略管理。
- `SQLiteHistoryStore.saveContent` 在同 ID 内容发生变化时作条件 UPSERT。
  NULL-safe 比较涵盖所有内容列，使正文、类型、RTF 和来源的替换或清除都能
  保存。排序、时间与置顶变化不触发未变化内容行的 UPDATE；原有事务与表结构
  保留。空 BLOB 与 SQL NULL 区分，保证原始 RTF 字节的往返一致。
- `localized` 按实际选用的资源语言选择复数规则，修复中文系统区域使用英文
  或法文资源时出现 `1 items`、`1 characters` 的问题。
- `FilterBarView` 将水平边距放在滚动文档内部，避免 macOS 15 的 scroll
  contentMargins 扩展可视区域后产生不对称边距。`EditItemView` 的标题行留出
  原生按钮边框空间，使绘制范围保持在居中的编辑列内。

## 验证

完整测试和覆盖率命令：

```sh
COVERAGE_MIN=90 ./scripts/coverage.sh --disable-sandbox
```

在允许访问 macOS 系统服务的环境中运行；所有数据库与内容为合成测试数据，
剪贴板测试使用私有测试板。322 项测试、51 个套件全部通过；可测试代码行
覆盖率 92.86%，90% 门槛通过。此前 5 项失败（6 条断言）已消除，未删除
测试或放宽原断言。依赖规则、严格格式检查与 git diff --check 通过。

新增测试覆盖跨存储实现的同 ID 修改、旧类型列清除、RTF 更新与移除、空 RTF、
关闭连接后编辑和撤销重开、复制不同格式后的回贴、精确格式去重和容量/置顶。
SQLite UPDATE 拒绝触发器验证排序、时间与置顶不重写内容行；ordering 写入
失败测试验证此前的内容修改也随事务回滚。

证据：`docs/research/evidence/2026-10-31/step-2-tests-coverage.log`。
构建与烟测分别记录在同目录的 `step-2-package.log`、`step-2-smoke.log`。
`dist/WhiskyMac.zip` 已解包并通过严格签名与启动烟测，运行时标识为
`dev.whisky.maclx`；版本 0.0.2、Mach-O 最低系统 macOS 15.0 已核对。
烟测使用临时历史目录并跳过剪贴板轮询。

## 当前范围

本轮保留独立格式记录，但尚未实现分组预览和版本选择界面；这些记录暂以
现有单独卡片展示。RTF 不做视觉规范化，因此视觉相同但编码不同的 RTF
可能形成多个版本。不迁移数据库结构，也无法找回旧版已丢弃的格式或编辑。

当前变更保留在本地工作区，沿用 `may/v1.0.3`；没有提交或修改远程。
