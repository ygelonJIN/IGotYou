# IGotYou · 电子密码库 · 开发文档

> 版本：v1.0（2026-08-30）
> 状态：设计定稿，作为后续全部开发的唯一基准。
> 本文档之后的所有代码、UI、行为，一律以本文档为准；如有变更需求，先改文档，再改代码。

---

## 1. 产品概述

### 1.1 一句话定位

一个**纯记忆证明**的兜底密码库：你把所有账号密码都存进一个加密保险柜，靠记住其中几条口令、盲输命中后打开，找回你忘记的所有内容。

### 1.2 核心价值

- **兜底**：密码记不清没关系，你对自己设定的口令有印象。输入若干条记得的口令，即可打开保险柜，找回全部账号密码。
- **安全感**：所有内容（名称、加密密钥、内容）全部加密。知道一条口令永远打不开，必须命中设定数量的条目才能打开。
- **本地 + 手动备份**：无云、无账号，一个加密备份文件 `.igotyou`，可隔空投送 / 传文件到新设备。

### 1.3 明确不做（非目标）

以下内容**当前明确不做**，防止范围蔓延：

- 不自动锁定。只提供**锁定按钮**，用户自己关保险柜的门；不点就不锁。
- 不提供防截屏、防录屏、防截断（真实的保险库也没有这些）。
- 无云同步、无账号系统、无网络请求。
- 不引入任何装饰性图标与图形；仅允许 Material 内置**功能性图标**（输入框前缀：锁/钥匙/标签/备注/搜索；列表条目钥匙开关：钥匙），尺寸与颜色一律走 token（见 9.5）。
- 不做多因子（手表/文件/面容/指纹）——本期只做多口令，架构预留扩展（见第 14 章）。

---

## 2. 核心概念与术语

| 术语 | 定义 |
|---|---|
| **条目 Entry** | 保险柜里的一个记录。固定 **3 行**：名称、加密密钥、内容。 |
| **名称** | 第一行。用于检索。必须加密存储。 |
| **加密密钥** | 第二行。任意可输入内容（中文、数字、字母、任何字符）。**既是存储的秘密，也是解锁钥匙的值**。必须加密存储。 |
| **内容** | 第三行（字段名 `note`，UI 文案"内容"）。自由文本。必须加密存储。 |
| **钥匙 Key** | 条目上的一个开关。开启"作为钥匙"的条目，其加密密钥才参与解锁；关闭的条目不参与解锁（即使你记得它的内容，输入它也不命中）。 |
| **钥匙数 N** | 当前"作为钥匙"的条目数量。 |
| **命中数 K** | 解锁所需命中的**不同**口令值数量。K ≤ N 是硬约束。 |
| **机会数 M** | 每轮可输入次数。 |
| **盲输** | 解锁时只显示一个输入框，不显示任何列表、任何提示；系统自动判断命中。 |
| **命中** | 用户输入的某个值，与某个"作为钥匙"条目的加密密钥完全一致。 |
| **冷却** | 一轮机会耗尽后，禁止输入的等待期。时长按可配置序列增长。 |

---

## 3. 解锁机制（纯记忆证明）

### 3.1 原理

用户预先写入 N 个条目（其中"作为钥匙"的条目数即钥匙数）。打开保险柜时：

1. 完全盲输：只有一个自由输入框，不显示任何列表。
2. 每次输入一个值，系统自动判定是否命中（与某个钥匙条目的加密密钥一致）。
3. 每轮最多输入 M 次（机会数）。
4. 一旦命中的**不同值**数量达到 K，立即"打开成功"，进入保险柜。
5. 机会耗尽仍未达到 K，本轮"打开失败"，进入冷却（见第 4 章）。

### 3.2 参数（全部可自定义，见设置）

| 参数 | 含义 | 默认值 |
|---|---|---|
| N | 钥匙数（由"作为钥匙"开关决定，非直接设置） | — |
| K | 解锁所需命中数 | 3 |
| M | 每轮机会数 | 30 |
| C | 冷却后每轮机会数 | 1 |
| 冷却序列 | 见第 4 章 | `[1]` 分钟，增长率 `2`（即 1→2→4→8…） |

### 3.3 命中判定规则

- 输入值先 **trim（去首尾空白）** + **NFC 规范化**，再与钥匙条目的加密密钥（同样规范化后的值）做**完全等值**比较。
- **按值去重**：命中的单位是"不同的输入值"，不是"条目"。
  - 两个条目加密密钥相同 → 输入一次，只算命中 **1**，绝不"一输入命中两个"。
  - 同一值重复输入 → 不重复计命中（但仍消耗一次机会）。
- 未开启"作为钥匙"的条目，其加密密钥即使输入正确也**不命中**。
- 输入不存在的值 → 不命中，消耗一次机会。

### 3.4 盲输原则（信息最小化）

解锁全程**只允许出现以下信息**：

- 允许：输入框、提交按钮、"剩余机会：X"、冷却倒计时、"打开成功"、"打开失败"。
- **禁止**：任何命中数（如"已命中 3 个"）、任何条目列表、任何命中提示（如"这个对了"）、任何"一共 5 中 3"形式的句子。
- 即使本轮全部输入完毕、全部比对完毕，也**只显示"打开成功"或"打开失败"**。

### 3.5 机会与重置

- 每输入一次消耗一次机会（无论是否命中、是否重复）。
- 打开成功 → **立即重置**所有机会与冷却状态（回到满血）。
- 打开失败 → 进入冷却，不重置。
- 在保险柜内部点"锁定" → 回到解锁页，机会与冷却**不重置**（未解锁成功就不重置；当前轮剩余机会保留，冷却状态保留）。

> 注：机会/冷却属于"尝试记录"，不含任何秘密内容，明文存放于库外的状态文件（见 4.4）。攻击者即使篡改它，也只能重置或跳过冷却，无法获得任何库内容。

---

## 4. 冷却机制

### 4.1 冷却序列模型

冷却时长由两部分配置：

- **基础序列 baseSequence**：一组分钟数，如 `[1]` 或 `[10, 10, 10]`。
- **增长率 growthFactor**：如 `2`（翻倍）、`1`（不增长）。

第 i 次冷却（i = 1, 2, 3, …，按失败累计次数递增）时长：

```
if i <= len(baseSequence):  duration = baseSequence[i-1]
else:                       duration = last(baseSequence) * growthFactor ^ (i - len(baseSequence))
```

示例：

| baseSequence | growthFactor | 冷却序列 |
|---|---|---|
| `[1]` | 2 | 1, 2, 4, 8, 16, …（无限翻倍）|
| `[10,10,10]` | 2 | 10, 10, 10, 20, 40, 80, … |
| `[5]` | 1 | 5, 5, 5, 5, …（固定）|

- 冷却序列**无限叠加**，无上限。
- 全部可自定义：基础序列任意长度、任意分钟数，增长率任意。

### 4.2 冷却流程

```
一轮机会耗尽（M 次未达 K 命中）
        ↓
   打开失败 → 进入冷却（时长 = 序列第 i 个值）
        ↓
   冷却结束 → 新一轮，机会数 = C（默认 1，可自定义）
        ↓
   该轮机会耗尽 → 打开失败 → 再次冷却（时长 = 序列第 i+1 个值）…
        ↓
   任意时刻打开成功 → 全部重置（机会、冷却序号）
```

- 冷却期间输入框禁用，仅显示倒计时（如"冷却 3:24"）。
- 冷却后一轮（C 次机会）输错，继续冷却，时长取序列下一个值。

### 4.3 默认冷却参数

- baseSequence = `[1]`（分钟）
- growthFactor = `2`
- 冷却后机会数 C = `1`

### 4.4 尝试状态存储

- 解锁状态（剩余机会、当前冷却序号、失败时间戳）存入库外独立小文件 `attempt_state.json`。
- 明文存储（不含任何秘密内容）。每次解锁成功后重置为初始状态。
- 该文件丢失（如重装应用）→ 视为无失败记录，机会满血。此行为可接受：不泄露内容，仅放宽尝试限制。

---

## 5. 安全架构（核心）

### 5.1 密钥体系总览

```
                    ┌──────────────────────────┐
                    │   库文件 .igotyou        │
                    │                          │
  MK ──────────────►│  主体密文（条目/配置）    │
  (256-bit 随机)     │  SSS 份额密文            │
   │                └──────────────────────────┘
   │
   ├─ SSS 拆分（N 份，至少 K 份重构）
   │     份额 s_i = (x_i, y_i)
   │     每份用 KEK_i 加密存储
   │
   ▼
 KEK_i = Argon2id(口令_i, salt, 高成本参数)
```

### 5.2 主密钥 MK 与 Shamir 秘密共享（N 中 K）

- 首次创建保险柜时，生成 256-bit 随机主密钥 **MK**。
- MK 是整个库（条目、配置）的加密密钥。
- MK 使用 **Shamir 秘密共享（SSS）** 拆分为 N 份（N = 钥匙数），每份对应一个钥匙条目，字段 `(x_i, y_i)`：
  - `x_i` = 条目 id 的 128-bit 确定性哈希（全局唯一）。
  - 阈值为 K：**任意 K 份可重构 MK，少于 K 份无法获得任何关于 MK 的信息**。这正是"只知道一个密码打不开"的数学保证。
- 每一份 `s_i` 使用该条目口令派生的 `KEK_i` 加密后写入库文件。

### 5.3 口令派生（Argon2id）

- 每个钥匙条目的口令（加密密钥）经 **Argon2id** 派生为 256-bit KEK。
- 派生参数（全局统一，写入文件头，可随版本迁移）：
  - 默认：`memory = 64 MiB`，`iterations = 3`，`parallelism = 1`，输出 32 字节。
  - 派生输入为 trim + NFC 规范化后的口令 UTF-8 字节。
- 全部钥匙条目共用同一个全局 salt（写入文件头）。解锁时输入一个值 → 一次 Argon2id → 尝试解密所有份额密文，解开的即为该值对应的份额。

### 5.4 库主体加密（AES-256-GCM）

- 整个库序列化为单个 JSON（条目列表 + 配置），用 **AES-256-GCM(MK)** 加密为主体密文。
- AES-GCM 自带认证，任何篡改都会导致打开失败。
- 每条 AES-GCM 加密使用独立随机 nonce；加密数据末尾附加 16 字节认证标签。

### 5.6 威胁模型与安全边界

| 威胁 | 防护 | 边界说明 |
|---|---|---|
| 拿到库文件暴力破解口令 | Argon2id 高成本参数 + 盲输/冷却机制（在线防护） | 离线暴力破解强度取决于 Argon2id 参数，默认参数约 64 MiB / 数百 ms 每次 |
| 知道一条口令 | SSS 阈值 K：少于 K 份无法重构 MK | 数学上无法绕过 |
| 篡改库文件 | AES-GCM 认证 | 篡改导致打开失败，不泄露内容 |
| 篡改尝试状态文件 | 无（明文） | 仅影响冷却/机会，不泄露任何内容 |
| 本地明文残留 | 内存中解密后常驻，锁定时清零 | 不保证防止内存抓取 |

### 5.7 内存安全

- 解锁后：条目与配置的解密数据驻留内存（文本数据量小），供显示与检索。
- 锁定：清空内存中的全部解密数据与密钥（MK、KEK、明文条目），强制 GC。
- 应用退到后台**不自动锁定**（尊重"不自动锁定"原则）；用户可手动点"锁定"。

---

## 6. 数据模型

### 6.1 条目 Entry

```dart
class Entry {
  String id;          // 唯一 id，UUID
  String name;        // 第一行 · 名称（加密存储）
  String secret;      // 第二行 · 加密密钥（加密存储；作为钥匙时即解锁口令）
  String note;        // 第三行 · 内容（UI"内容"，加密存储；可为空）
  bool isKey;         // 是否作为钥匙（参与解锁）
  DateTime createdAt;
  DateTime updatedAt;
}
```

### 6.2 库配置 VaultConfig（全部可自定义）

```dart
class VaultConfig {
  int hitCount;           // K 命中数（默认 3）
  int roundChances;       // M 每轮机会数（默认 30）
  int cooldownChances;    // C 冷却后每轮机会数（默认 1）
  List<int> cooldownBase; // 冷却基础序列（分钟，默认 [1]）
  int cooldownGrowth;     // 冷却增长率（默认 2）
}
```

### 6.3 份额存储 ShareRecord

```dart
class ShareRecord {
  String entryId;    // 对应钥匙条目
  int x;             // SSS x 坐标（条目 id 哈希）
  Uint8List nonce;   // AES-GCM nonce
  Uint8List cipher;  // 份额 s_i 密文 + 认证标签
}
```

### 6.4 硬约束规则

- **K ≤ 不同钥匙口令数**：任何时刻必须成立，否则保险柜永远打不开。
  - 这里的"不同"指**去重后的口令值**：多把钥匙共用同一口令时，打开时按值去重只能命中一次，故在 K 约束里只算一把（见 3.3）。这正是"相同口令算一把钥匙"的语义。
  - 保存任何导致"不同钥匙口令数 < K"的变更（关闭钥匙开关、删除条目、修改钥匙口令）时，**自动将 K 调整为不同钥匙口令数**（下限 1）。
  - 在设置中手动调高 K 时，若 K > 不同钥匙口令数，**禁止**并提示（如"当前钥匙密码 2 种，命中数最大 2"）。
  - 新增钥匙条目使不同口令数 ≥ 原 K 时，K **不自动回升**（防止混淆），由用户手动调整。
- **至少保留一把钥匙**：关闭"作为钥匙"或删除条目导致钥匙数为 0 时，份额列表会变成空、主密钥无法重建，库永久锁死。因此**最后一把钥匙不允许关闭/删除**，操作被拒绝并提示"至少保留一把钥匙，否则保险柜将永久锁死"。
- **K ≥ 1**：任何时刻 K 不小于 1（双向钳制：K ≤ 不同钥匙口令数，且 K ≥ 1）。
- **写盘前份额校验**：`save()` 落盘前必须保证份额数 == 钥匙条目数，否则立即重切分；钥匙集为空或阈值非法时抛异常，**绝不写空份额**。
- 机会数 M ≥ 1；冷却后机会数 C ≥ 1；冷却序列每个值 ≥ 1（分钟）；增长率 ≥ 1。

---

## 7. 文件格式 `.igotyou`

### 7.1 整体结构

```
┌─────────────────────────────────────────────┐
│ HEADER（明文）                                │
│  magic "IGOTYOU1" · version ·                │
│  argon2 参数 · global_salt · 库版本号        │
│  params: K / M / C / 冷却序列 / 增长率        │
│    （解锁参数镜像，见下方说明）                │
├─────────────────────────────────────────────┤
│ SHARES 区（明文信封，份额密文）                │
│  [ShareRecord × N]                           │
├─────────────────────────────────────────────┤
│ BODY 区（密文）                               │
│  AES-256-GCM(MK)：库 JSON                    │
│  （条目、配置）                             │
└─────────────────────────────────────────────┘
```

- 文件头为单一 JSON 明文，只含派生参数、salt、版本等非敏感信息。
- **解锁参数镜像**：HEADER 额外镜像存放 `params`（K/M/C/冷却序列/增长率，即 `VaultConfig` 的全部字段）。理由：解锁引擎在解密 BODY 之前就必须知道 K（何时判定打开成功）、M/C/冷却（机会与倒计时），而这些参数均非秘密（与 Argon2 参数同级，泄露不损害安全）；BODY 内的完整 `VaultConfig` 仍为权威配置，两者在每次保存时保持同步。若校验不一致，以 BODY 内为准并报"文件损坏"。
- 备份导出 = 直接复制该文件；导入 = 打开该文件并盲输解锁，成功后成为当前库。

### 7.2 版本与迁移

- 文件头含版本号；读取时先校验版本，不支持的高版本提示"备份版本过高，请升级应用"。
- 派生参数升级只影响新建库；旧库沿用文件头中的参数解密（向后兼容）。

---

## 8. 功能需求

### 8.1 首次创建（默认参数，无引导）

- 首次打开 → 保险柜门面（VaultGate）内的"创建保险柜"表单，仅三个输入框：**名称**、**加密密钥**、**内容（可选）**，下方一个主操作按钮"创建"。
- 门面内除输入框与创建按钮外**不放任何其他元素**（无标题、无说明、无装饰）。
- **回车焦点流转**：名称框回车 → 焦点跳加密密钥；加密密钥回车 → 跳内容；内容回车 → 收起键盘。**回车不触发创建**，必须手动点"创建"。
- 点击创建 → 用**默认参数**直接建库：K=3、M=30、C=1、冷却 `[1]×2`。
- 首个条目自动标记为"作为钥匙"；因 K 约束，此时 K 自动降为 1。
- 后续条目在保险柜内添加，设置中可随时调整全部参数。

### 8.2 解锁页

- 保险柜门面（VaultGate）内**仅两个元素居中**：单行密码输入框（锁图标前缀）+ 主操作按钮。
- 主按钮即剩余机会 / 冷却的唯一载体：正常"解锁（剩余 X 次）"，冷却"冷却 m:ss"（禁用）；门面右上角不再单独显示剩余机会。
- **最后一步高亮**：已命中 K-1 个、只差一个正确值即可打开时，按钮不再显示剩余次数、只显示"解锁"，并加金色粗边框高亮。
- 盲输交互：输入框回车仅收一条密码（清空输入框等下一条，不消耗机会、不校验）；按主按钮才批量提交校验。最后一条必须按按钮才能"打开成功"，回车不会直接进入。
- 提交后：命中数不足 → 仅机会 -1；命中达 K → "打开成功"进入保险柜；机会耗尽 → "打开失败"→ 冷却。
- 冷却期间：输入框与按钮禁用，按钮显示"冷却 mm:ss"，每秒刷新倒计时。
- 门面内不放任何其他元素（无标题"IGotYou"、无"请输入密码"、无"参数调整需进入保险柜"提示）。

### 8.3 保险柜主页（列表 · 全屏覆盖布局）

- **顶部覆盖面板**（`VaultTopBar`，渐变遮罩 `topScrim` 向下平滑淡出，无分割线）：金色主按钮「上锁」56 高，常驻顶部同一位置；上锁 → 清空内存解密数据 → 回解锁页。
- **列表全屏**：条目从面板下方铺满全屏；滚动时条目**从渐变遮罩下透出渐隐**（不是实心遮挡）。
- 列表：每个条目显示 **钥匙图标 + 名称（金色）** 一行，**不显示加密密钥与内容**（进入查看页可见）。
- **钥匙图标即钥匙开关**：金色 = 作为钥匙；灰色（`goldDim`）= 不作为钥匙。点击图标直接切换，无需进入查看页；触发 6.4 约束时提示。钥匙图标在条目卡片左侧独立成列，方形点击反馈、与卡片同高。
- 点条目主体 → 查看页。
- 空态：文字"暂无条目"。
- **检索输入框失焦**：点击列表或页面任意空白处收起系统键盘（`FocusScope.unfocus`）。
- **底部浮层**（检索框 + 「设置」「备份」「添加」按钮）：直接压在底部渐隐遮罩（`bottomScrim` 向上平滑淡出）之上，与遮罩分离——遮罩只做视觉（`IgnorePointer`），浮层可交互。
- **列表底部留白**：略高于检索浮层顶（`homeListBottomInset`），条目滚动到底时可**滑入遮罩下方渐隐淡出**，不是硬切到遮罩边缘。

### 8.4 添加 / 查看条目（全屏表单 · 无保存按钮 · 可选二次加密）

- **全屏覆盖布局**：顶部 `VaultTopBar` 渐变遮罩（关闭叉 + "查看"/"添加"标题），底部 `VaultBottomScrim` 渐隐遮罩。
- **普通条目直接查看**：解锁后点条目主体即显示表单（名称、加密密钥、内容均可看可改），无需额外输入。
- **可选二次加密（DEVELOPMENT 8.5b）**：条目可单独开启二次加密——开启时输入新密钥（两次确认），`secret`/`note` 不再落盘明文，而是整体 AES-GCM 加密进 `doubleCipher`（独立盐 `doubleSalt` 派生 KEK）。
  - 查看二次加密条目：先输入该条目的加密密钥（真实解密验证），正确才显示内容；错误提示"加密密钥不正确"。
  - 修改密钥：需先输入当前密钥验证，再输新密钥两次。
  - 关闭二次加密：输入当前密钥解密后正文回填明文。
  - 明文密钥只缓存于会话内存（锁定清空，不落盘）。
  - 二次加密条目**可同时作为解锁钥匙**：份额 KEK 从该密钥派生，解锁时输入该密钥即可命中；但会话内未输入过该密钥时，触发份额重切会要求先查看该条目输入密钥（`VaultKeyMissingException` 引导）。
  - 这是"保护加密密钥 + 保护内容"的双重防线：解锁保险柜 ≠ 能看每个条目；且懂技术的人拿文件也读不出（正文是独立加密的密文）。
- 三个字段居中窄列（`gateMaxWidth` 360，与首次创建页一致）：名称（必填）、加密密钥（必填）、内容（可选）。
- **无保存按钮**：查看模式字段失去焦点即自动保存；关闭（叉/返回/系统返回）前若有改动先保存再退出。
- **修改钥匙口令必须验证旧值**：普通（非二次加密）钥匙条目的加密密钥被修改时，弹窗要求**先输入当前密钥确认**，且文案警告"修改后旧密钥立即失效"。防止误改后把保险柜锁死（见 17.8）。
- **添加模式**：名称框回车即创建并关闭（其余字段可留空后补）；关闭时名称非空则创建保存，空则直接关闭。
- **重复标注**：加密密钥输入时，若与库内其他条目加密密钥相同，实时显示标注文字（如"与条目【银行】相同"）。仅标注，不阻止保存。
- **无"作为钥匙"开关**（该入口仅主页钥匙图标）。
- 保存时执行 6.4 约束校验。
- 删除条目：底部统一危险按钮，确认提示"删除后不可恢复"。删除钥匙条目时若触发 K 约束，按 6.4 自动调整 K 并提示。

### 8.6 设置（全部可自定义项 · 无保存按钮）

- **顶栏**：`VaultTopBar` 渐变遮罩（返回箭头 + "设置"标题），底部 `VaultBottomScrim` 渐隐遮罩。
- 命中数 K、每轮机会 M、冷却后机会 C：每个字段下方有小字备注说明用途（"解锁需要命中的不同密码数量"、"每轮最多可输入次数，机会耗尽进入冷却"、"冷却结束后每轮的机会数"）。
- 冷却基础序列（分钟，数组编辑：如 `1` 或 `10,10,10`）、冷却增长率：小字备注说明（"每次失败的冷却时长，如 1 或 10,10,10"、"冷却时长按此倍数递增，1 为固定不变"）。
- **无保存按钮**：字段失去焦点即自动保存（有改动才保存）；校验失败在顶部横幅报错；返回/锁定前若有改动先保存再退出。
- 修改任意解锁参数时执行约束校验（K ≤ 钥匙数；机会 ≥ 1；冷却 ≥ 1 分钟；增长率 ≥ 1）。
- 显示当前钥匙数 N 与"作为钥匙"的条目清单（跳转可改开关）。
- **清空保险柜**：底部统一危险按钮。点击后弹窗**必须输入"清空"二字才能确认**；确认后删除库文件与尝试状态文件，回到首次创建页。确认弹窗文案说明"清空后所有条目与设置将删除，无法恢复"。

### 8.7 备份：导出 / 导入

- **顶栏**：`VaultTopBar` 渐变遮罩（返回箭头 + "备份"标题），底部 `VaultBottomScrim` 渐隐遮罩。
- 导出：生成 `.igotyou` 文件，通过系统分享（iOS 隔空投送 / Android 文件共享）发送。备份即该文件，复用同一套钥匙。
- 导入：选择 `.igotyou` 文件 → 校验 magic/版本 → 盲输解锁（N 中 K）→ 成功则**替换/合并**当前库（默认替换，可确认）。
- 导入失败（密码不足）→ 仅显示"打开失败"，原库不受影响。

### 8.8 提示（`VaultBanner` 顶部横幅）

- 全应用提示/报错统一用顶部金色横幅 `showVaultBanner(context, 文案)`：金属渐变底 + 柔和阴影，从屏幕最上方滑入，停留后滑出。**不区分成功/失败颜色**，一律金色模板。
- **可手动划走**：横幅支持向上滑动手势，向上拖过阈值立即消失（不等自动到时）。
- 所有页面**禁止使用 SnackBar**（含解锁页的"打开成功/打开失败/冷却中"）。

### 8.9 离线

- 全应用离线运行，无任何网络权限。

---

## 9. UI 设计规范（全局唯一规范）

> ## 🔒 强制规范（HARD RULE · 写任何页面前必读）
> **所有页面（`lib/ui/**`）与组件（`lib/ui/widgets/**`）必须 100% 复用全局主题 token，来源唯一 = `lib/theme/tokens.dart`（组合样式在 `theme.dart` 落地）。**
>
> 1. **文字样式必须引用组合 token `AppTextStyles.*`**（见 9.3d）。页面/组件**严禁**出现 `TextStyle(` 自行组装字号/字重/颜色。
> 2. 颜色只允许 `AppColors.*`；字体只允许 `AppFontFamilies.*`；字号 `AppFontSizes.*`；字重 `AppFontWeights.*`；间距 `AppSpacing.*`；圆角 `AppRadius.*`；边框 `AppBorder.*`；尺寸 `AppSizes.*`；渐变 `AppGradients.*`；阴影 `AppShadows.*`；时长 `AppDurations.*`。
> 3. **严禁任何硬编码字面量**：`Color(0x…)`、`Colors.x`、`fontSize:`、`FontWeight.w…`、`fontFamily:`、`EdgeInsets.all(16)`、`height: 56`、`size: 24`、`blurRadius:`、`Duration(milliseconds:`、`letterSpacing: 4`、`BoxConstraints(minWidth: 40)` 等。逻辑常量（`if (x < 1)` / `~/ 60` 等）除外。
> 4. **高度算式不重复**：页面列表底部/顶部预留高度一律用 `VaultBottomScrim.height(mq)` / `VaultTopBar.totalHeight(mq)`，禁止各页面自行拼装。
> 5. 验收标准：对 `lib/ui` 跑 9.7 末尾的审查命令，**必须零命中**；命中即不合格，打回重写。
>
> 一句话：**写页面 = 拼 token，不许写字面量。缺 token 先补 `tokens.dart`（优先复用现有组合），再写 UI。**

### 9.1 设计原则

现代化、强硬、绝对安全，像保险柜。庄严、严肃、简单、高效。无图标、无装饰、无动画花活；信息密度克制，操作路径最短；报错与提示一律一句话。

### 9.2 黑金色彩体系（Design Token · `AppColors`）

| Token | 色值 | 用途 |
|---|---|---|
| `bg` | `#0D0D0D` | 全局背景（近黑） |
| `surface` | `#161616` | 卡片 / 输入框底 |
| `surfaceAlt` | `#1E1E1E` | 按压态 / 次级表面 |
| `gold` | `#C9A227` | 主强调：标题、主按钮、激活态、成功 |
| `goldDim` | `#8A7120` | 边框、分隔线（暗金） |
| `textPrimary` | `#EDE8DC` | 主文字（暖白） |
| `textSecondary` | `#8F8A80` | 次级文字（暖灰） |
| `danger` | `#B3402A` | 失败 / 危险操作 |
| `onGold` | `#0D0D0D`（同 `bg`） | `gold` 底上的前景文字（主按钮 / 主操作大按钮） |

- 状态语义：成功 = 金；失败 = 暗红。不用绿/蓝。
- 背景只允许 `bg`；卡片只允许 `surface`；强调色只允许 `gold`。

### 9.3 字体、字号、字重（Design Token）

- 字体 token（`AppFontFamilies`）：默认系统字体；`mono = 'monospace'`（**加密密钥一律使用等宽字体**，便于辨认字符）。
- 字号 token（`AppFontSizes`）：`title 20`、`heading 16`、`body 14`、`meta 12`、`mono 14`；标题字距 `titleSpacing 4`（IGotYou 字标专用）。
- 字重 token（`AppFontWeights`）：`strong 600`（标题 / 主按钮）、`normal 400`（正文）。

### 9.3d 组合文本样式 token（`AppTextStyles` · 页面唯一文字出口）

> 页面/组件**必须**按用途直接引用组合样式，**严禁**自行组装 `TextStyle`。

| Token | 组成（字号 / 字重 / 颜色） | 用途 |
|---|---|---|
| `wordmark` | title / strong / gold + `titleSpacing` | IGotYou 字标 |
| `title` | title / strong / gold | 页面大标题（顶栏标题，如"设置""备份""编辑"） |
| `heading` | heading / strong / textPrimary | 块标题（"创建保险柜""请输入密码"） |
| `headingGold` | heading / strong / gold | 条目名称行 |
| `body` | body / normal / textPrimary | 正文、字段标签、弹窗正文 |
| `bodySecondary` | body / normal / textSecondary | 占位、空态、次级正文 |
| `bodyGold` | body / normal / gold | 钥匙"开" |
| `bodyError` | body / normal / danger | 报错文字 |
| `meta` | meta / normal / textSecondary | 小字提示、钥匙状态"关" |
| `metaGold` | meta / normal / gold | 小字强调（钥匙状态"开"） |
| `metaDim` | meta / normal / goldDim | 重复标注等辅助说明 |
| `metaDanger` | meta / normal / danger | 冷却倒计时、删除标记 |
| `mono` | mono / normal / textPrimary + `AppFontFamilies.mono` | 加密密钥 |
| `buttonLabel` | body / strong（颜色随按钮前景） | 主按钮 / 次按钮文字 |

- 页面内**不得**出现 `TextStyle(`、`fontWeight:`、`fontSize:`、`fontFamily:` 等；一律引用上述组合 token。
- 需要新文字形态时，**优先用现有组合拼接语义**（如 `metaGold` 已含"小字+金色"）；确无对应组合才在 `tokens.dart` 新增。

### 9.4 间距 / 圆角 / 边框 / 时长

- 间距 token（`AppSpacing`）：`unit 4`、`unit2 8`、`unit3 12`、`unit4 16`、`unit6 24`。
- 圆角 token（`AppRadius`）：输入框与按钮 2（锐利、强硬，不用大圆角）。
- 边框 token（`AppBorder`）：`width 1`，颜色 `goldDim` / 激活 `gold`，门面 `gateWidth 1`。

### 9.4b 渐变 token（`AppGradients`）

- `gateMetal`：保险柜门面金属渐变，上亮下暗（`surfaceAlt → surface → bg`），模拟金属柜门受光。仅用于保险柜门面（解锁 / 创建页）与提示横幅。
- `topScrim`：顶部覆盖遮罩（`bg` 实心 → 0.90 → 0.48 → 透明，四档平滑淡出），主页/设置/备份/编辑页顶栏用——条目滚动穿过时渐隐显现，**不是实心遮挡**。
- `bottomScrim`：底部渐隐遮罩（自下而上 `bg` 实心 → 0.90 → 0.48 → 透明，四档平滑淡出），主页检索浮层与各页面底部用。

> 规则：任何"覆盖在内容之上的半透明层"一律用 `AppGradients.*` 遮罩 token，**禁止**在页面里裸写 `Color(0x…)` 透明度；需要新遮罩先加 token。

### 9.4c 时长 token（`AppDurations`）

- `cooldownTick 1s`：解锁页冷却倒计时刷新间隔。
- `bannerIn 240ms` / `bannerOut 200ms` / `bannerHold 2600ms`：顶部提示横幅滑入 / 滑出 / 停留时长。

### 9.4d 阴影 token（`AppShadows`）

- `banner`：顶部提示横幅投影（`Color(0x80000000)` / blur 12 / offset (0,4)）。
- 阴影一律走 `AppShadows.*`；页面内禁止裸写 `BoxShadow(...)` / `blurRadius:` / `offset: Offset(...)`。

### 9.5b 保险柜门面组件（解锁 / 创建页专用）

**`VaultGate`（保险柜门面）**——解锁 / 创建页的视觉主体：

- 全页居中，最大宽度 360（`AppSizes.gateMaxWidth`），可滚动（小屏适配）。
- 背景 `AppGradients.gateMetal` 金属渐变；边框 1px `gold`（`AppBorder.gateWidth`）；圆角 2（`AppRadius.gate`）；内边距 32（`AppSizes.gatePadding`）。
- 门面内**只允许放输入区与主按钮**，禁止任何标题、说明、铭文、装饰。
- 输入区与主按钮间距 24（`AppSizes.gateGap`）。

### 9.5 组件规范

- **主按钮**：`gold` 底、`#0D0D0D` 文字、圆角 2、高 48（`AppSizes.buttonHeight`）、文字居中。禁用态降为 `surfaceAlt` 底 `textSecondary` 字。
- **主操作大按钮**（打开 / 锁定保险柜）：主按钮样式，高 56（`AppSizes.heroButtonHeight`）。全应用仅这两个动作使用。**上锁按钮常驻顶栏**（`VaultTopBar` 内），永不隐藏、永不禁用。
- **顶部小导航按钮**（主页设置/备份/添加）：高 34（`AppSizes.navButtonHeight`）、`surfaceAlt` 底 + `gold` 字、无边框。主页底部浮层内一行并排。
- **页面顶栏**（主页/设置/备份/编辑页）：`VaultTopBar` 渐变遮罩覆盖（`topScrim`），前置图标 24（`AppSizes.topBarIconSize`），无前置按钮时占位 48（`AppSizes.topBarLeadingWidth`）保持标题对齐；高度 `totalHeight = safeTop + scrimHeight`。
- **底部渐隐遮罩**：`VaultBottomScrim` 纯视觉遮罩（`bottomScrim`，`IgnorePointer`，不拦截点击），高度 `height = safeBottom + bottomMaskHeight(180)`；页面用 `VaultBottomScrim.height(mq)` 预留列表底部空间，禁止自行拼高度。
- **主页底部浮层**：检索框 + 设置/备份/添加按钮，作为 `Positioned` 浮层压在渐隐遮罩之上（遮罩与浮层分离）；列表底部留白 `homeListBottomInset(128)`，让条目可滑入遮罩下方渐隐。
- **次按钮（文字按钮）**：无底色、`gold` 文字。用于"设置""备份""添加"等；危险操作（删除 / 清空）用 `danger` 文字。
- **输入框**：`surface` 底、1px `goldDim` 边框、聚焦时 `gold` 边框、`textPrimary` 文字、`textSecondary` 占位。前缀图标（如锁/钥匙）尺寸 18（`AppSizes.iconSize`）、`goldDim` 色。
- **列表条目**：`surface` 底卡片，一行内容 = 左侧钥匙图标（`Icons.key`，尺寸 18）+ 名称（`headingGold`），卡片间距 8。**不显示加密密钥与内容**。
- **钥匙图标开关**：点击图标直接切换钥匙状态。金色 = 作为钥匙；灰色（`goldDim`）= 不作为钥匙。
- **对话框**：`surface` 底、`goldDim` 边框、标题 `heading`、正文 `body`、主/次按钮。危险确认（清空保险柜）要求**输入指定文字才能确认**。
- **提示（顶部横幅）**：一句话，如"已保存""删除后不可恢复""打开成功""打开失败"；**统一金色模板，不区分成功/失败颜色**（见 8.8）。
- **设置项备注**：设置页每个可配置字段下方有一行 `meta` 小字说明用途。

### 9.6 文案规范（简单高效）

- 所有文案为短语/短句，不加标点废话。
- **禁止出现"口令"字样**，统一用"密码"（如"请输入密码"）；UI 文案示例：
  - 成功："打开成功" / "已保存"
  - 失败："打开失败"
  - 报错："请输入名称" / "请输入加密密钥" / "当前钥匙密码 2 种，命中数最大 2" / "备份版本过高，请升级应用" / "文件损坏"
  - 确认："删除后不可恢复，确认？" / 清空保险柜需输入"清空"二字确认
  - 空态："暂无条目"
- 解锁页**永不出现**命中数文案（见 3.4）。

### 9.7 禁止事项（违反即不合格）

- ❌ 任何装饰性图标、emoji、SVG 图形（功能性前缀图标除外，见 1.3 / 9.5）。
- ❌ **在 `lib/ui/**`（页面 + 组件）内出现 `TextStyle(`**：文字样式必须用 `AppTextStyles.*` 组合 token。
- ❌ **任何硬编码样式字面量**：颜色、字号、字重、间距、圆角、边框、尺寸、阴影、时长一律引用 `tokens.dart` 的 token。禁止裸写 `Color(0x…)`、`Colors.x`、`fontSize:`、`FontWeight.w…`、`fontFamily:`、`EdgeInsets.all(16)`、`height: 56`、`size: 24`、`blurRadius: 12`、`Offset(0, 4)`、`letterSpacing: 4`、`BoxConstraints(minWidth: 40)`、`Duration(seconds: 1)` 等。逻辑常量（`if (x < 1)`、`~/ 60` 等）除外。
- ❌ 多步骤引导、介绍动画。
- ✅ 新样式一律先加 token（优先复用 `AppTextStyles` 现有组合），再在 UI 引用；全局改风格只动 `tokens.dart` / `theme.dart` 两处。
- ✅ 页面高度计算复用组件静态方法（`VaultTopBar.totalHeight` / `VaultBottomScrim.height`），禁止各页面自行拼装。

**审查命令（写任何页面/组件后必须自查，命中即打回重写）：**

```bash
# 期望输出为零；裸露的 TextStyle/Color/fontSize/数字尺寸/阴影/时长 = 不合格
rg -n 'TextStyle|\bColors\.|Color\(0x|fontSize:|FontWeight\.|fontFamily:|EdgeInsets\.all\([0-9]|letterSpacing: [0-9]|width: [0-9]|height: [0-9]|size: [0-9]|blurRadius|Duration\(' lib/ui
```

---

## 10. 页面清单与导航

```
解锁页 UnlockScreen
  ├─ 创建保险柜（仅首次）
  └─ 保险柜 VaultScreen
       ├─ 条目编辑 EntryEditScreen（添加/编辑共用）
       ├─ 设置 SettingsScreen（顶部"设置"按钮进入）
       └─ 备份 BackupScreen（顶部"备份"按钮进入）
```

- 解锁成功后 → VaultScreen；锁定 → 清内存 → UnlockScreen。
- **设置/备份/添加入口均在保险柜内部**：主页顶部"设置""备份"靠左、"添加"在右上；解锁页门面内不放任何文字入口提示（见 8.2）。
- 上锁按钮在主页、设置、备份、编辑页顶栏**全部常驻**（任何页面可紧急锁定，锁定后回到解锁页）。

---

## 11. 解锁流程状态机

```
[IDLE] --首次创建--> [ACTIVE]
[ACTIVE] --点锁定--> [LOCKED] --盲输解锁--> [ACTIVE]
[LOCKED] --输入值--> 判定：
    ├─ 命中不同值数 ≥ K ──► 打开成功 → 重置尝试状态 → [ACTIVE]
    ├─ 命中不足 且 机会 > 0 ──► 机会-1 → 继续 [LOCKED]
    └─ 命中不足 且 机会 = 0 ──► 打开失败 → 冷却序号+1 → [COOLDOWN]
[COOLDOWN] --倒计时结束--> 机会=C → [LOCKED]
[COOLDOWN] --倒计时中--> 禁止输入
```

- 冷却序号在每次打开失败后 +1，打开成功归 0。

---

## 12. 技术栈与工程结构

### 12.1 技术选型

| 项 | 选型 | 说明 |
|---|---|---|
| 框架 | Flutter（Dart） | Android + iOS |
| 加密 | `cryptography` 包 | Argon2id、AES-GCM、HKDF 纯 Dart 实现，可挂平台后端 |
| 文本规范化 | `unorm_dart` | NFC 规范化（命中判定，见 3.3）；Dart 核心库无此能力 |
| SSS | 自实现（GF(2^128) Lagrange） | 代码短、无依赖、可控 |
| 文件 | `path_provider` | 应用私有目录 |
| 分享/导出 | `share_plus` | iOS 隔空投送、Android 分享 |
| 导入 | `file_picker` | 选择 .igotyou |
| 状态管理 | `provider` | 轻量状态管理 |
| 网络 | 无 | 无网络权限 |

> 依赖最小化原则：除上述外不引入任何包。所有 UI 自绘，无图标库、无 UI 框架。

### 12.2 目录结构

```
lib/
  main.dart
  theme/
    tokens.dart          # 全部设计 token（9 章唯一来源）
    theme.dart           # 生成 ThemeData
  core/
    crypto/
      argon2.dart        # 口令派生封装
      aes_gcm.dart       # 加解密封装
      hkdf.dart
      shamir.dart        # SSS 拆分/重构
      keychain.dart      # MK 生成、份额管理
    models/
      entry.dart
      vault_config.dart
    file/
      vault_file.dart    # .igotyou 读写（header/shares/body）
    unlock/
      unlock_engine.dart # 命中判定、去重、状态机
      attempt_state.dart # 机会/冷却持久化
  ui/
    unlock_screen.dart
    vault_screen.dart
    entry_edit_screen.dart
    settings_screen.dart
    backup_screen.dart
    widgets/
      vault_button.dart
      vault_field.dart
      vault_entry_tile.dart
      vault_top_bar.dart       # 页面顶栏（渐变遮罩覆盖 + 上锁按钮）
      vault_bottom_scrim.dart  # 底部渐隐遮罩（纯视觉，IgnorePointer）
      vault_banner.dart      # 顶部提示横幅（统一提示/报错）
      vault_gate.dart        # 保险柜门面（解锁/创建页）
```

### 12.3 性能与轻量要求（验收指标）

- 启动到解锁页：< 1s。
- Argon2id 一次派生：< 1s（默认参数）。
- 解锁打开库（100 条文本条目）：< 1.5s。
- 应用常驻内存：目标 < 80MB。
- 库文件体积：纯文本条目 < 1MB。

### 12.4 代码质量要求（简单 · 高效 · 优雅 · 轻量）

> 产品级原则（2026-08-31 定稿）：**代码要简单、高效、优雅，应用要轻量、快速**。任何新增/修改代码都必须先问三个问题：能不能更简单？有没有重复？是否符合全局规范？

**写 UI 的固定流程（改前端必守）：**

1. **先查 token，有就用**：颜色/字号/字重/间距/圆角/边框/尺寸/渐变/阴影/时长，一律查 `tokens.dart`（`AppColors / AppFontSizes / AppFontWeights / AppFontFamilies / AppTextStyles / AppSpacing / AppRadius / AppBorder / AppGradients / AppShadows / AppDurations / AppSizes`）。存在就直接引用。
2. **没有就加 token，绝不硬编码**：需要的新样式先补进 `tokens.dart`（优先复用现有组合），再在 UI 引用。全局改风格只动 `tokens.dart` / `theme.dart` 两处。
3. **组件复用**：重复出现的 UI 结构先看 `lib/ui/widgets/` 有没有现成组件（`vault_button / vault_field / vault_entry_tile / vault_top_bar / vault_bottom_scrim / vault_banner / vault_gate`）；没有就抽组件，不复制粘贴。
4. **页面高度用组件静态方法**：`VaultTopBar.totalHeight(mq)`、`VaultBottomScrim.height(mq)`，禁止各页面自行拼装高度算式。
5. **跑审查命令**：写完必须跑 9.7 末尾的审查命令，零命中才合格。

**审查重点（写出即自查）：**

- 无重复实现：同一段逻辑/同一个布局在不同页面出现 ≥2 次，就要抽成共享方法或组件。
- 无硬编码：`lib/ui/**` 内不允许任何样式字面量（见 9.7），高度算式不允许重复。
- 无死代码：未使用的 import、方法、变量一律删除。
- 无注释噪音：代码自解释的地方不写注释；只有非显然的意图（安全约束、时序）才配说明。
- 轻量：不引入多余依赖、不做过度抽象；一个 widget 能解决的不造框架。
- 简洁：文案一句话；样式最克制；不改动全局规范去迁就单个页面。

**前端代码量基准（2026-08-31 统计）：** `lib/` 共 31 个文件 ≈ 4400 行；其中 UI（`lib/ui/`）13 个文件 ≈ 2300 行（约 52%），核心逻辑（`lib/core/`）15 个文件 ≈ 1800 行，主题 3 个文件 ≈ 340 行。UI 是主体但由统一 widget + token 支撑，新增页面不得复制粘贴扩量——**复用优先，能不加文件就不加**。

---

## 13. 环境与工具链：Flutter 怎么用（对齐 SoWhat，2026-08-30）

> 本仓库环境与 SoWhat 完全一致、无残留。详细说明另见根目录 `环境与工具链.md`，此处为 DEVELOPMENT 内嵌版。

### 13.1 三件套：SDK 本体放本机 + 项目只放软链 + 统一入口

| 层 | 位置 | 说明 |
|---|---|---|
| SDK 本体 | 本机 `/Users/jinfeiqing/fvm/versions/3.47.0`（Flutter 3.47.0 stable / Dart 3.13.0） | 只此一份，绝不复制进项目 |
| 项目内软链 | `.fvm/versions/stable -> /Users/jinfeiqing/fvm/versions/3.47.0` | `readlink` 可验证；`.gitignore` 忽略 `.fvm/`，本体不进 git |
| 版本锁定 | `.fvmrc = {"flutter":"stable"}` | 进 git，团队换机器版本一致 |
| 统一入口 | `tool/flutter` + `tool/analyze`（chmod +x） | 人人走同一入口，不依赖 PATH 里的 flutter/fvm |

### 13.2 两个入口脚本（直接照搬 SoWhat）

**`tool/flutter`**：固定 `FLUTTER_ROOT` 到本机 SDK、`PUB_CACHE` 到 `.fvm/pub-cache`（pub 包不写 `~/.pub-cache`），然后等价官方 `bin/flutter` bootstrap。

```bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="$(cd "$ROOT/.fvm/versions/stable" && pwd)"
export FLUTTER_ROOT="$SDK"
export PUB_CACHE="${PUB_CACHE:-$ROOT/.fvm/pub-cache}"
# …source shared.sh 并 shared::execute "$@"
```

**`tool/analyze`**：直接调 SDK 自带 dart 的 `analyze`，跳过 flutter 自更新；`HOME` 指到 `.fvm/analyze-home`，让 `~/.dartServer` 落到项目内。

```bash
DART="$SDK/bin/cache/dart-sdk/bin/dart"
export HOME="$ROOT/.fvm/analyze-home"
mkdir -p "$HOME"
exec "$DART" analyze "$@"
```

### 13.3 沙箱分工（为什么 flutter 必须去 Terminal 跑）

编辑器内嵌终端有 macOS 沙箱限制：写不了 `~/`（`Operation not permitted`），但能写项目目录和 `/tmp`；Terminal/iTerm 不受限。因此：

| 事项 | 在哪跑 |
|---|---|
| `./tool/flutter run / build / pub get / clean / pub add` | **Terminal**（要写 cache，沙箱下不可写） |
| `./tool/analyze` | Cursor 或 Terminal 均可（HOME 已钉进 `.fvm/analyze-home`） |
| 代码编辑 / 文档维护 | Cursor |

### 13.4 iOS / SPM 现状（对齐 SoWhat）

- Flutter 3.47 首次真机构建自动迁移：最低 iOS 15.0，改 `project.pbxproj` / `AppFrameworkInfo.plist` / `Podfile`，加入 SPM 集成 + UIScene 迁移。
- 现状为混合态：`ios/Podfile` / `Podfile.lock` / `ios/Pods/` 仍保留，插件已是 Swift Package。发 iOS 版前再手动迁纯 SPM（本章待办）。
- 换 SDK 后的 `A precompiled file has been changed...` 报错：`./tool/flutter clean` + 删 `~/Library/Developer/Xcode/DerivedData/Runner-*` 后重建，一次性问题。

### 13.5 缓存联动与 git 边界

- `.dart_tool/`、`.fvm/`、`.fvm/pub-cache`、`.fvm/analyze-home` 三者联动，全部 gitignore，不进 git。
- **进 git**：`.fvmrc`、`tool/flutter`、`tool/analyze`、`.gitignore`、本文档、`环境与工具链.md`。

### 13.6 Flutter 工作流速查

```bash
# 一律在 Terminal（首次 pub get 自动生成 .dart_tool 指向 .fvm/pub-cache）
./tool/flutter pub get
./tool/flutter run --release -d <device-id>
./tool/flutter build ios
./tool/flutter clean

# 静态检查，Cursor 内可直接跑
./tool/analyze
./tool/analyze lib
```

### 13.7 已弃用（勿再使用）

- IGotYou 曾把整套 SDK 复制进 `.fvm/versions/stable` 实目录（约 4GB），已删除重建软链。
- 外接盘旧 SDK `/Volumes/TUF ESD-T1A Media/.fvm/`（Flutter 3.38.0）已弃用，可删。
- 不要用 PATH 里的裸 `flutter` / `fvm` 命令。

---

## 14. 多因子扩展规划（未来，本期不做）

- 预留抽象 **Factor**：本期仅实现 `PassphraseFactor`（多口令 N 中 K）。
- 未来因子：`DeviceFactor`（信任手表/设备）、`FileFactor`（信任文件）、`BiometricFactor`（面容/指纹）。
- 解锁条件模型：因子级条件（如"口令 5 中 3"）与因子间组合（AND/OR，如"口令 5 中 3 且 面容 1"）可配置。
- 实现要点：MK 的 SSS 拆分扩展为"每因子一组份额"，由组合规则决定重构路径。本期不实现，仅保证 `unlock_engine` 与文件格式预留版本字段与因子字段。

---

## 15. 开发里程碑

| 阶段 | 内容 | 产出 |
|---|---|---|
| M1 | 工程骨架 + 主题 tokens + 页面导航 | 可运行空壳 |
| M2 | 加密核心：argon2 / aes_gcm / shamir / keychain（含单元测试） | 密码学层 |
| M3 | 文件格式读写 + 尝试状态 | 数据层 |
| M4 | 创建 / 解锁状态机 + 冷却 | 核心流程 |
| M5 | 保险柜列表 / 检索 / 条目编辑 / 重复标注 / 钥匙开关 | 主功能 |
| M6 | 锁定 / 设置 / 备份导出导入 | 完整功能 |
| M7 | 双端打包 + 真机验收（性能、轻量、体验） | 发布 |

---

## 16. 验收标准（DoD）

1. 全新安装 → 极简创建 → 添加 10 个条目（均开启钥匙）→ 设置 K=5、M=30 → 盲输 5 个不同正确值 → "打开成功"；只输入 4 个 → 机会耗尽 → "打开失败" → 冷却倒计时正确。
2. 两个条目加密密钥相同 → 输入一次只算命中 1；输入同一个值两次只消耗两次机会、命中仍为 1；且两把同口令钥匙时 K 上限自动按"1 种口令"计（见 6.4）。
3. 冷却序列 `[10,10,10]×2` → 前三次冷却 10 分钟，之后 20、40…；解锁成功后全部重置。
4. 保险柜列表每行显示钥匙图标 + 名称；点击图标切换钥匙状态（金色 = 开 / 灰色 = 关）→ 输入其内容是否命中随之变化；最后一把钥匙不可关闭/删除，操作被拒绝并提示。
5. 名称/加密密钥/内容在磁盘上均无明文（静态检查文件字节）。
6. 编辑条目内容 → 导出 .igotyou → 新设备导入 → 同套密码盲输打开 → 内容完整可读。
7. 应用内无任何装饰性图标（功能性钥匙图标除外）；全应用样式 token 唯一来源；`lib/ui` 跑 9.7 审查命令**零命中**（无 `TextStyle(`、无硬编码颜色/字号/间距/字重/字体字面量）。
8. 上锁按钮**永远固定在顶栏同一位置、永远可点击**；点击后立即回到解锁页，内存密钥清零（可抽查）。
9. 机会与冷却在解锁页有明确显示；解锁过程全程无命中数提示；每次提交后输入框清空。
10. 保险柜列表**只显示名称**，不显示加密密钥与备注；点击空白处收起键盘。
11. 设置页每个参数有用途小字备注；**清空保险柜必须输入"清空"确认**，确认后回到首次创建页。
12. 冷启动 < 1s；解锁打开 100 条库 < 1.5s；常驻内存 < 80MB。

---

## 17. 缺陷修复记录

> 每条记录：缺陷 → 根因 → 修复。新增/回归一律补测试（`test/`），修改核心逻辑后必须跑 `dart analyze` 与 `flutter test`。

### 17.1 致命：普通保存可写空份额，库永久锁死（2026-08-31）

- **缺陷**：解锁后仅编辑非钥匙条目的名称/备注（不触发重切分）再保存，份额列表被写成空 → 主密钥无法重建，库永久锁死。
- **根因**：`VaultSession.open()` 时 `_shares` 恒为空列表，且仅在钥匙集变化（`_sharesDirty`）时重切分；`save()` 未校验即把 `_shares` 写盘。
- **修复**：`save()` 写盘前强制校验 `份额数 == 钥匙条目数`，不匹配立即重切分（`vault_session.dart`）。
- **测试**：`test/vault_session_test.dart`（改非钥匙备注保存、改钥匙名称保存两用例）。

### 17.2 致命：关闭/删除最后一把钥匙 → K=0、空份额，库永久锁死（2026-08-31）

- **缺陷**：关闭最后一把钥匙或删除最后一把钥匙，`_enforceKConstraint()` 把 K 降到 0，`Shamir.split(secret, 0, [])` 在 release 下返回空份额并写盘。
- **根因**：K 约束无下限；钥匙集无守卫。
- **修复**（三层防御，`vault_session.dart`）：
  1. `setEntryKey` / `deleteEntry` 拒绝移除最后一把钥匙（抛 `StateError`，UI 捕获提示）；
  2. `_enforceKConstraint()` 双向钳制：`1 ≤ K ≤ 不同钥匙口令数`；
  3. `_resplitShares()` 校验钥匙集非空、阈值合法，非法即抛异常，绝不写空份额。
- **测试**：`test/vault_session_test.dart`（最后钥匙守卫 2 用例 + K=0 脏数据钳制用例）。

### 17.3 致命（配置级）：多把钥匙同口令 + K≥2 → 永远打不开（2026-08-31）

- **缺陷**：两把钥匙填同一口令，K 上限按钥匙条目数算成 2；打开时按值去重只能命中 1，永远凑不齐 K。
- **根因**：K 约束按"钥匙条目数"而非"不同口令数"计算。
- **修复**：新增 `distinctKeyCount`（去重后的钥匙口令数），K 的钳制（`_enforceKConstraint`）与设置校验（`updateConfig`）全部按它计算；设置页显示"X 种口令 / Y 个"。
- **测试**：`test/vault_session_test.dart`（同口令 K 钳到 1、updateConfig 拒绝 K 超限两用例）。

### 17.4 严重：编辑页关闭最后一把钥匙时崩溃（2026-08-31）

- **缺陷**：编辑条目时把"作为钥匙"从开→关且为最后一把钥匙，`setEntryKey` 抛出的 `StateError` 在 try 块外 → 未处理异常（红屏）。
- **修复**：`_save` 内改为安全调用（`_trySetKey`），守卫拒绝时显示提示文案而非崩溃（`entry_edit_screen.dart`）。

### 17.5 一般：添加条目后列表不刷新 / 设置页钥匙开关不刷新（2026-08-31）

- **缺陷**：`VaultScreen` / `SettingsScreen` 只监听 `AppState`，而增删改通知的是 `VaultSession`，返回后列表不重绘。
- **修复**：编辑页返回后 `setState` 重绘；设置页切换钥匙后 `setState`（`vault_screen.dart` / `settings_screen.dart`）。

### 17.6 一般：保存路径无异常处理（2026-08-31）

- **缺陷**：`session.save()` 在编辑/设置页既未 `await` 也无 `try/catch`，失败会触发未处理异步异常。
- **修复**：全部改为 `await + try/catch`，失败提示"保存失败"（`entry_edit_screen.dart` / `settings_screen.dart`）。

### 17.7 规范：UI 硬编码收敛为 token（2026-08-31）

- **缺陷**：`height: 56`、`letterSpacing: 4`、`size: 18`、`FontWeight.w600/w400` 散落各页面。
- **修复**：新增 token `AppSizes.heroButtonHeight`、`AppFontSizes.titleSpacing`、`AppSizes.iconSize`、`AppFontWeights.strong/normal`，UI 全部引用 token，实现零裸硬编码（规则见 9.7）。

### 17.8 规范：覆盖遮罩/阴影/顶栏尺寸硬编码收敛为 token + 高度算式去重（2026-08-31）

- **缺陷**：主页顶部/底部遮罩裸写 `Color(0xE6/59/000D0D0D)`；横幅 `Duration(milliseconds: 240/200/2600)`、`blurRadius: 12`、`maxWidth: 480` 硬编码；顶栏/编辑页图标 `size: 24`、占位 `SizedBox(width: 48)`、按钮 `height: 34`；设置/备份/编辑/主页四处重复拼装锁定条高度算式。
- **修复**：
  1. `tokens.dart` 新增遮罩渐变 `AppGradients.topScrim / topBarScrim / bottomScrim`、时长 `AppDurations.bannerIn/Out/Hold`、阴影 `AppShadows.banner`、尺寸 `AppSizes.navButtonHeight / topBarHeight / topBarIconSize / topBarLeadingWidth / scrimFade / bannerMaxWidth`；
  2. 新增 `VaultLockBar.totalHeight(mq)`、`VaultTopBar.totalHeight(mq)` 静态方法，四处页面统一复用；
  3. 设置页重复的 `_label`/`_note` 方法合并。
- **审查**：9.7 审查命令扩充（`width/height/size/blurRadius/Duration`），`lib/ui` 零命中。

### 17.9 严重：修改钥匙口令无验证导致用户被永久锁死（2026-08-31）

- **缺陷**：编辑钥匙条目的加密密钥后保存，份额立即用新值重新切分、**旧口令当场失效**，且 UI 无任何警告或旧口令验证。用户误改后忘记新值 → 保险柜永久锁死，无恢复路径。
- **修复**：`entry_edit_screen` 的 `_save` 增加钥匙口令修改确认：若条目是钥匙且加密密钥被改动，弹窗要求**先输入当前密钥验证**，并警告"修改后旧密钥立即失效"；验证失败或取消则回填旧值不保存（规则见 8.4）。
- **用户须知**：忘记解锁口令 = 数据永久丢失（Argon2id 单向、份额仅存密文，无人可恢复）。恢复路径：解锁只需 K 个不同正确值，有其他钥匙就输入其他钥匙口令；若只有一把钥匙且遗忘，无法恢复，只能重建保险柜。
- **测试**：`test/vault_session_test.dart`（改钥匙口令触发重切分已有覆盖；UI 确认流程待补 widget 测试）。

### 17.10 一般：首页顶部遮罩透明区拦截列表点击（2026-08-31）

- **缺陷**：主页顶部面板 `Container` 高度含淡出区，虽然渐变视觉透明，但该区域仍拦截点击，列表前几条点不到（条目进不去、钥匙切不了）。
- **修复**：面板拆为两层——渐变遮罩层用 `IgnorePointer`（仅视觉），内容层（搜索框 + 按钮）正常可交互（`vault_screen.dart`）。

### 17.11 功能：可选二次加密（真实加密）+ 文案/交互调整（2026-08-31）

- **可选二次加密（DEVELOPMENT 8.5b）**：条目可单独开启二次加密——正文（secret/note）不再落盘明文，整体 AES-GCM 加密进 `doubleCipher`（独立盐 `doubleSalt` 派生 KEK）；查看需输入该条目的加密密钥真实解密；明文密钥只缓存会话内存、锁定清空。可同时作为解锁钥匙（份额 KEK 从该密钥派生，解锁输入它即命中）。入口：查看页"开启二次加密 / 修改密钥 / 关闭二次加密"。
- **实现**：`Entry.doubleLocked/doubleCipher/doubleSalt`（骨架已埋，本次补全）；`VaultSession.setDoubleLock / clearDoubleLock / changeDoubleKey / unlockDoubleLock / updateDoubleEntry`；`Keychain.splitSecret` 增加 `keyFor` 回调以支持二次加密钥匙口令；份额重切对无缓存密钥的二次加密钥匙抛 `VaultKeyMissingException` 引导输入；`distinctKeyCount` 对未知口令保守不计（K 只钳低不锁死）。
- **文案**：第二行"加密内容"→"加密密钥"；页面标题"编辑"→"查看"；底部主按钮"锁定保险柜"→"上锁"。
- **解锁按钮**：新增 `UnlockEngine.hitsToOpen`（还差几个可打开），最后一步（差 1 个）按钮只显示"解锁"并金色粗边框高亮（`VaultButton.highlighted`）。
- **横幅**：支持向上滑动手动消失（`vault_banner`）。
- **列表钥匙图标**：移出卡片成独立列，方形点击反馈、与卡片同高（`AppSizes.tileKeyWidth`）。
- **测试**：`vault_session_test.dart` 新增二次加密组（开启落盘无明文、查看正确/错误密钥、编辑重加密、作为钥匙份额兼容、修改/关闭、无缓存重切抛错后输入密钥恢复），15 项全过。

### 17.12 规范：底部渐变对齐 SoWhat 全屏浮层模式（2026-09-01）

- **缺陷**：主页底部"检索框 + 设置/备份/添加"承载在一个固定高遮罩容器里，列表底部 padding 恰好等于遮罩高——条目滚动到底**顶在遮罩边缘硬切**，底部渐隐几乎不生效；顶部/底部渐变是"实心 → 最后一段才淡出"的两档，过渡偏硬。
- **修复**：
  1. `VaultBottomScrim` 拆为**纯视觉遮罩**（`IgnorePointer`，不拦截点击），交互内容由页面在遮罩之上单独浮层承载（`vault_screen.dart`）；
  2. 列表底部留白改用 `AppSizes.homeListBottomInset(128)`（略高于检索浮层顶），条目可滑入遮罩下方渐隐淡出；
  3. `topScrim / bottomScrim` 改为四档平滑渐隐（`bg 1 → 0.90 → 0.48 → 0`，对齐 SoWhat 全屏页）；
  4. 新增 `AppSizes.bottomMaskHeight(180) / bottomChromeHeight(110) / homeListBottomInset(128)`；`VaultBottomScrim.height = safeBottom + bottomMaskHeight`。
- **审查**：`tool/analyze` 全绿；9.7 审查命令无新增命中。

### 17.13 严重：添加/查看页无返回按钮 + 二次加密关闭失败状态被破坏（2026-09-01）

- **缺陷**：① `VaultTopBar` 在 `showBack: false` 时**完全忽略 `leading`**，只渲染占位 `SizedBox`——添加/查看页顶栏实际没有任何返回按钮，用户进入后无法返回；② 二次加密门禁表单在 `SingleChildScrollView` 内用 `Center`，垂直方向不居中（滚动容器高度无限）；③ 关闭/开启/修改二次加密时若存在**其他未查看的二次加密钥匙条目**，`save()` 重切份额抛 `VaultKeyMissingException`（非 `StateError`）→ 界面显示"关闭失败"，但内存状态已改 → 再次操作报"未开启二次加密"，状态错乱；④ 主页切换钥匙开关遇到缺密钥只弹横幅，无输入入口，用户无法继续。
- **根因**：`vault_top_bar.dart` 前置按钮渲染条件写反（`leading` 仅在 `showBack` 时生效）；`_buildGate` 未用 `LayoutBuilder + ConstrainedBox(minHeight)` 居中范式；`clearDoubleLock` 等先改内存后 `save()`，失败无回滚；`_toggleKey` 对 `VaultKeyMissingException` 只提示不引导。
- **修复**：
  1. `vault_top_bar.dart`：`leading` 优先于 `showBack` 渲染，自定义前置按钮不再被丢弃；
  2. `entry_edit_screen.dart`：添加/查看页顶栏统一返回箭头（`VaultTopBar` 默认左箭头）；门禁改用 `LayoutBuilder + ConstrainedBox(minHeight: viewport.maxHeight)` 垂直居中；
  3. `vault_session.dart`：`setDoubleLock / changeDoubleKey / clearDoubleLock` 操作前预检（`_missingDoubleKeyNames`）——若本条目为钥匙且存在其他未缓存密钥的二次加密钥匙条目，先抛 `VaultKeyMissingException` 指名缺失条目，**不改内存状态**；
  4. `vault_screen.dart`：`_toggleKey` 遇 `VaultKeyMissingException` 改为弹窗输入缺失条目密钥（`_promptMissingDoubleKey`，验证缓存后自动重试，最多 8 轮）。
- **测试**：`vault_session_test.dart` 新增"关闭二次加密预检"用例（缺他钥时先报错且状态不变）；`tool/analyze` 全绿。
