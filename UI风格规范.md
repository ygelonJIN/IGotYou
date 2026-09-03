# IGotYou UI 风格规范（论对错 · 法庭之秤）

> 本文档是 IGotYou 的**全局 UI 规范**。所有页面（现有保险柜主页、解锁页、
> 设置侧栏、条目编辑页、备份页，以及未来新增的任何页面）都必须遵循本规范。
>
> 全应用只有**一套主题**（论对错 · 法庭之秤）与**一种字体**（Noto Serif SC），
> 不存在多主题切换。

---

## 1. 设计总纲

1. **全屏沉浸**：页面主体内容铺满全屏，顶部/底部控件悬浮在内容之上，不抢主视觉。
2. **主题即语义**：深墨背景 + 金色主色 = 理性、克制、秩序感（"保险柜"的严肃气质）。
3. **克制但有戏剧性**：整体排版克制，通过卡片、金线描边、渐变遮罩、金色按钮
   制造"储藏室/审判庭"的庄重感。
4. **内容优先**：真正要看的是一行行密码条目，而不是空洞的壳。
5. **统一的组件语言**：按钮、卡片、弹窗、输入框、提示框全部共享同一套形状
   （直角）与阴影规则。

---

## 2. 色彩令牌（`lib/theme/tokens.dart` 的 `AppColors`）

| 角色 | 值 | 用途 |
| --- | --- | --- |
| `bg` | `0xFF1C1B1E` | 整页背景（深墨） |
| `surface` | `0xFF2D2A24` | 次级面板 / 卡片外层 / 输入框底 |
| `surfaceAlt` | `0xFF241F1A` | 更深一级的强调底（钥匙块） |
| `gold` | `0xFFE0AE40` | 主色：按钮主填充 / 强调 / 图标 |
| `goldDim` | `0xFFB09B74` | 弱化金：辅助文字 / 弱化描边 |
| `textPrimary` | `0xFFF2E9D6` | 正文（浅米白） |
| `textSecondary` | `0xFFB09B74` | 次级文字 / 占位 |
| `keyOff` | `0xFF6F6B60` | 钥匙"关"图标色（比次级文字更灰） |
| `onGold` | `0xFF241C07` | gold 底上的前景文字 |

### 规则

- 颜色按「角色」使用，禁止在组件里写死 hex。
- 主色按钮文字一律 `AppColors.onGold`（深色），不用白色。

---

## 3. 形状系统：直角

- 全部圆角统一为 **2px 直角**（`AppRadius.input/card/button/dialog/gate = 2`）。
- 输入框保留 `goldDim` 1px 描边；卡片 / 门面可用更亮的金线（`AppColors.gold`）。
- 不做额外聚焦高亮，保持克制的判词感。

---

## 4. 字体

- 全局唯一字体：**Noto Serif SC**（衬线宋体），`theme.dart` 全局生效。
- 缺字时回退系统字体（PingFang SC → sans-serif）。
- **所有文字（含加密内容）一律使用主体字体**，不切换等宽、不引入其它字体。
- 禁止在业务代码中直接构造 `TextStyle`，一律引用 `AppTextStyles` 组合样式。

字体资产只保留一个文件：`assets/fonts/NotoSerifSC-Regular.otf`。

---

## 5. 页面结构模型：全屏内容 + 浮层控制

所有页面遵守同一套结构：

```
Stack
├─ 主体内容区（全屏、可滚动）
├─ 顶部渐变遮罩（IgnorePointer，内容滚到浮层下时柔和淡出）
├─ 顶部浮层（SafeArea）
└─ 底部渐变遮罩 + 底部浮层（SafeArea）
```

### 5.1 保险柜主页（`vault_screen.dart`）

1. 背景色铺满全屏
2. 中央为条目卡片流（全屏滚动），列表上下内边距统一为
   `EdgeInsets.fromLTRB(16, 140, 16, 236)`（`contentTopInset` / `contentBottomInset`）
3. 顶部左侧「设置」胶囊（`PillButton` 高亮态），右上角为全局「上锁」胶囊
   （`VaultLockButtonOverlay`，与「设置」同一水平线）
4. 底部为检索输入条 + **独立在检索框之外**的「添加」金色方形按钮
   （`_SearchAddChip`，宽 94，不并入输入框）
5. 空态为两行克制引文（无英文，24/20 号字）

### 5.2 设置页：左侧滑入侧栏（`settings_panel.dart`）

设置页不是 push 的新页面，而是从左侧滑入的侧栏：

- 宽度占页面 **75%**（`width * 0.75`），**通栏满高**（阴影从顶到底无缝，不套 SafeArea）
- 主页右移 `settingsWidth`（75% 屏宽），仅主页右端约 25% 露在遮罩后（点击遮罩收起）
- 动画 340ms `easeOutCubic`
- 顶部**只有标题「设置」**（米白大字）+ 右上角上锁胶囊（宽 94）——无返回箭头；
  收起方式 = 点击遮罩 / 系统返回键
- 顶部与底部渐隐遮罩**与面板同色**（`surface`，`surfaceTopScrim` / `surfaceBottomScrim`），不出现其它颜色色带
- 底部固定工具区（备份 / 重置）悬浮在 surface 同色渐隐之上

### 5.3 二级页面（条目编辑 / 备份）

- 顶部用统一 `VaultTopBar`：左上角「返回胶囊（与主页设置胶囊同款同位置）+ 纯文字标题」，
  与主页「设置」胶囊完全对齐（SafeArea + `16/8/16/0`）
- 首条目位置 = **140**（与主页一致，`VaultTopBar.totalHeight`）
- 底部统一 `VaultBottomScrim` 渐隐遮罩
- 内容区从遮罩淡出区之下开始滚动

### 5.4 全局上锁按钮（`widgets/vault_lock_button.dart`）

- 由 `MaterialApp.builder` 在导航器外层渲染**一次**，全应用共用、永远存在
- 固定**右上角**：右缘 `pageEdge` 16，上缘 = 状态栏 + `topChromeInset` 8
  （与主页顶部「设置」胶囊同一水平线）
- 样式与「设置」胶囊一致（`PillButton` 高亮态）；设置侧栏展开时隐藏
  （侧栏内右上角自带同款上锁胶囊）
- 只在已解锁时显示；点击：失焦（触发页面自动保存）→ 等待页面注册的
  `beforeLock`（编辑页/设置页）→ 锁定 → 收起所有二级路由回到根页

---

## 6. 核心组件规范

### 6.1 胶囊按钮 `PillButton`（`widgets/pill_button.dart`）

- 左侧图标 + 右侧文字，直角方角
- `highlight = true`：金色填充 + 深色字（强调态）
- `highlight = false`：`surface` 底 + 金线描边（普通态）
- 用于顶部「设置」、全局上锁按钮、次要导航入口

### 6.2 主按钮 / 危险按钮 / 文字按钮（`widgets/vault_button.dart`）

- 主按钮：金色填充、深色字、直角、高 48（解锁等处高 56）
- 危险按钮：surface 底 + 金线描边（不做刺眼的红色；危险操作靠文案与确认步骤表达）
- 文字按钮：无底色、金色文字（弹窗内主/次操作）

### 6.3 输入框 `VaultField`（`widgets/vault_field.dart`）

- surface 底 + 1px `goldDim` 描边 + 直角
- 前缀图标（可选）+ 后缀按钮槽（`trailing`，可选）
- `mono: true` 时使用加密内容样式（仍为全局主体字体）
- `obscure: true` 掩盖明文

### 6.4 条目行 `VaultEntryTile`（`widgets/vault_entry_tile.dart`）

- 一行 = 左侧钥匙块（点击切换是否作为钥匙）+ 右侧名称卡片
- 金色钥匙 = 作为钥匙；**灰钥匙**（`keyOff`，比次级文字更灰）= 不作为
- 二次加密条目：钥匙块内显示**两把钥匙上下排列、居中**（不加金边框）
- 名称卡片：surface 底 + 弱金描边，标题用金色

### 6.5 保险柜门面 `VaultGate`（`widgets/vault_gate.dart`）

解锁 / 创建页的居中卡片：surface 底 + **金色**描边 + 直角 + 轻阴影。
内放输入区与主按钮，其余信息一律不出现。

### 6.6 提示横幅 `showVaultBanner`（`widgets/vault_banner.dart`）

全局提示/报错统一用顶部滑入横幅（不混用原生 SnackBar）：

- surface 卡底 + 金线描边 + 直角
- 从屏幕最上方滑入，自动消失，支持上滑手动关闭
- 统一金色锁图标 + 金色正文，不区分成功/失败

### 6.7 渐变遮罩（`vault_bottom_scrim.dart` + `AppGradients`）

- 顶部：从背景色逐渐透明（内容滚到浮层下时淡出）
- 底部：从背景色逐渐透明
- 各页遮罩/留白数值（px，均以屏幕顶端/底端为基准）：
  - 主页：首个条目距顶 **140**；顶部遮罩 **170**；底部遮罩 **160** + 底部安全区；内容底部留白 **236**
  - 设置侧栏：内容顶部 **状态栏 + 80**；顶部遮罩 **150**（surface 同色）；底部遮罩 **200**（surface 同色）；内容底部 **安全区 + 150**
  - 二级页（查看/添加/备份）：首条目距顶 **140**（与主页一致，`VaultTopBar.totalHeight`）；顶部遮罩 **170**（`VaultTopBar.totalScrimHeight`）；底部遮罩 **安全区 + 160**（`VaultBottomScrim.totalHeight`）；内容底部留白与主页一致 **236**

---

## 7. 排版与间距

- 页面左右边距 16；卡片内 padding 12~20
- 组件间距节奏：4 / 8 / 12 / 16 / 24（`AppSpacing`）
- 字号：页面标题 20 / 卡片标题 16 / 正文 14 / 辅助 12
- 正文行高舒展（1.5 上下），辅助信息紧凑

## 8. 阴影与边框

- 阴影只为层级：透明度低、模糊适中（`AppShadows.banner` 等）
- 边框用于强调结构：卡片用弱金线，高亮项（选中/当前）用金色
- 危险操作不靠红色，靠文案与确认步骤

## 9. 动效

- 主动画 180~340ms，柔和缓出（`easeOutCubic`）
- 侧栏滑入 / 滑出 340ms
- 横幅滑入 240ms / 滑出 200ms
- 动效只服务于"哪里展开了、哪里收起了"

## 10. 文案风格

- 克制、直接、稳定，不夸张
- 多用"正在…""已…""可…""建议…"，少用感叹号
- 文案**只用中文**，不夹英文装饰词
- 空态与主题一致：主页空态为两行中文引文

---

## 11. 快速摘要

> **深墨打底、金色点睛、方形直角、衬线宋体；用统一的卡片语言和浮层布局，
> 把每一次开柜变成一桩严肃的小仪式。**

三个关键词：**全屏沉浸 / 主题即语义 / 卡片化的克制**

---

## 12. 文件地图

| 文件 | 内容 |
| --- | --- |
| `lib/theme/tokens.dart` | 色彩 / 字号 / 字重 / 文本样式 / 间距 / 圆角 / 渐变 / 时长 / 阴影 / 尺寸令牌 |
| `lib/theme/theme.dart` | `buildVaultTheme()`：全局 ThemeData（含唯一字体） |
| `lib/ui/widgets/pill_button.dart` | 胶囊按钮 |
| `lib/ui/widgets/vault_lock_button.dart` | 全局上锁按钮（右上角悬浮层） |
| `lib/ui/widgets/vault_button.dart` | 主 / 危险 / 文字按钮 |
| `lib/ui/widgets/vault_field.dart` | 输入框（含检索条 `VaultSearchBar`） |
| `lib/ui/widgets/vault_entry_tile.dart` | 条目行卡片 |
| `lib/ui/widgets/vault_gate.dart` | 解锁 / 创建 / 二次加密门面 |
| `lib/ui/widgets/vault_top_bar.dart` | 二级页顶部浮层 |
| `lib/ui/widgets/vault_bottom_scrim.dart` | 底部渐隐遮罩 |
| `lib/ui/widgets/vault_banner.dart` | 全局提示横幅 |
| `lib/ui/widgets/settings_panel.dart` | 设置侧栏（滑入面板） |
| `lib/ui/widgets/missing_key_prompt.dart` | 二次加密钥匙明文缺失输入弹窗 |
| `lib/ui/vault_screen.dart` | 主页：全屏列表 + 浮层 + 侧栏容器 |
| `lib/ui/unlock_screen.dart` | 解锁 / 首次创建 |
| `lib/ui/entry_edit_screen.dart` | 条目编辑（含二次加密门禁） |
| `lib/ui/backup_screen.dart` | 导出 / 导入备份 |

---

## 13. 新增页面 checklist

- [ ] 背景用 `AppColors.bg`，不使用其它底色
- [ ] 页面按「全屏内容 + 浮层控制」搭建（遮罩 + 浮层，不 push 裸页面）
- [ ] 按钮用 `PillButton` / `VaultButton` / `VaultTextButton`，不手搓按钮
- [ ] 输入框用 `VaultField`，不手搓 TextField 样式
- [ ] 提示用 `showVaultBanner`，确认弹窗继承全局 dialogTheme
- [ ] 所有文字引用 `AppTextStyles`，不手写 TextStyle
- [ ] 所有颜色引用 `AppColors`，不写死 hex
- [ ] 直角（2px 圆角），不引入非规范圆角
- [ ] 文案只用中文，不夹英文装饰词
- [ ] 所有文字（含加密内容）一律用主体字体，不切等宽或其它字体