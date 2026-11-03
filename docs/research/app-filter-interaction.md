# APP 筛选触发方式与“全部”（2026-11-03，未打包）

用户确认“悬浮 / 点按”指向同一排 APP 筛选按钮，不新增折叠入口。

## 行为

设置 → 交互 → APP 筛选新增“点按筛选 / 悬浮筛选”，默认保持点按，保存在独立 settings 域。
悬浮在 APP 上停留 0.25 秒后切换至单个 APP，不累加来源，不重复取消已选项。
点按与键盘仍保留原有多选／取消逻辑。鼠标快速经过、移出、控件消失、关闭面板、
切换到点按或进入隐私模式会取消等待或阻止延迟回调；无新增后台轮询。

筛选栏最前新增“全部”，一次清除 APP、类型及置顶筛选，保留当前搜索词。
没有筛选时“全部”处于选中状态，但不会被当作实际限制条件撑开搜索框。
它和其他筛选一样支持键盘方向键、组切换、Return 和 VoiceOver。
无历史、无筛选项时仍保留原来的空栏行为。隐私模式不额外暴露来源或筛选列表。

## 实现

- App/FilterInteraction.swift：触发模式与可注入调度器的悬浮等待；取消与代次检查防止旧回调。
- GeneralSettings.swift / AppDelegate.swift / HistoryViewStateStore.swift：独立偏好持久化并实时更新视图。
- Views/FilterBarView.swift / HistoryPanelView.swift：按钮悬浮触发和可见性、隐私、当前偏好校验。
- Adapters/Controllers/ClipboardController.swift：selectSourceFilter 仅接受当前可达 APP；
  allFiltersChipID 清除三个筛选维度，筛选不改写剪贴板或历史。
- Adapters/Presenters/HistoryPresenter.swift / HistoryViewState.swift：统一排序与选中／焦点状态，
  保证视图顺序和键盘顺序一致；“全部”的选中态与 hasActiveChip 分开。
- PanelWiring.swift / PanelActions.guarded：刷新待处理搜索后切换，隐私保护阻止旧动作。
- SettingsView.swift 与 EN / FR / 简体中文目录：设置入口及行为说明。

## 验证

411 项测试／65 个套件全部通过，可测试行覆盖率 91.29%（门槛 90%）。
架构依赖、严格 Swift 格式、三语目录及 git diff --check 通过。
新增测试覆盖默认／持久化／非法值回退、悬浮取消和替换、释放后的回调、
“全部”清除三个维度且保留搜索、重复悬浮幂等性、无效来源、
路由与隐私门控；更新原有精确键盘顺序断言，离屏渲染覆盖两种模式。
全部使用合成数据和模拟剪贴板，不读真实剪贴板或启动实际应用。
真实鼠标体验与 VoiceOver 仍留待用户集中验收。

证据：evidence/2026-11-03/app-filter-tests.log。
遵守用户约定：没有生成应用包、ZIP 或安装包。
