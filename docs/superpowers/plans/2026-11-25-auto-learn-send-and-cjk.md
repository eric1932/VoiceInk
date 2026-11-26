# Auto-Learn：发送后仍能学到更正 + 中文按词学习 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户在聊天输入框里改完识别结果、按回车发送后，Auto-Learn 仍能学到更正；中文和中英混排的更正学成"词 → 词"，而不是"整句 → 整句"。

**Architecture:** 两处独立改动。(1) 观察期间每 250ms 读一次输入框，记住最后一版非空文字；输入框被清空时立刻结算，并用这版文字代替空的最终读数。(2) `CorrectionDiffEngine.segments(in:)` 把连续的中日韩文字交给系统 `NLTokenizer` 按词切分，全角标点当作分隔符。纯逻辑放在不依赖 Accessibility 的类型里，用独立的 `swiftc` 脚本测试。

**Tech Stack:** Swift、ApplicationServices (AX)、系统 `NaturalLanguage`；测试用 `swiftc` 直接编译纯逻辑文件（不启动 App）。

**Spec:** 本文件即规格。背景证据：2026-11-25 会话中用真实源码编译跑出的结果（见各 Task 的断言）。

## Global Constraints

- 分支 `fix/auto-learn-send-and-cjk`（从 `ui-polish` 切出，已含上游 2.27）。不动 `ui-polish`。
- 只改 `VoiceInk/Features/Dictionary/AutoLearn/` 下的 4 个现有文件，新增 1 个源文件和测试文件。不改 `AccessibilityTextReader`、UI、设置项、本地化文案，方便以后合并上游。
- 不加第三方依赖。
- 日志里不能出现输入框文字，只记原因和数量（沿用 `privacy: .public` 只用于非文本字段的做法）。
- 不用 XCTest 的 `VoiceInkTests` target：它以 App 为宿主，跑测试会再启动一个 VoiceInk，和正在运行的那个抢全局快捷键。
- 现有常量 `maximumUnspacedCandidateCharacters = 32`、`maximumCandidateSegments = 24` 不改。

## Review Focus

以下情况没有（或无法用纯逻辑）完全覆盖，评审时重点看：

1. **发送后马上在同一个框里打新消息。** 期望：不拿新消息去和旧的粘贴内容比较。由 Task 3 测试 `sampler_blankReadSettlesImmediately` 保证成功读到空文本就立刻结算。
2. **输入法组字中途被采样**（框里有未上屏的拼音），随后 250ms 内上屏并发送。期望：不弹出带拼音的建议。无自动化测试，Task 4 手动验证。
3. **分词器对未改动的上下文切法不一致**，导致差异范围变大。期望：最多丢弃，绝不学成整句。由 Task 2 测试 `cjk_longSentence_learnsWordOnly` 约束。
4. **轮询开销。** Chromium 内核 App 里每秒 4 次 AX 读取、最长 60 秒。期望：Dia 里打字无可感知卡顿。Task 4 手动验证；若单次读取经常超过 50ms，把间隔调到 500ms。
5. **超长输入框文本。** 期望：采样时沿用 `finishSnapshot` 的 `maximumFieldUTF16Length` 上限，超限的读数不保存。代码评审检查。

---

### Task 1: 独立测试脚本

**Files:**
- Create: `scripts/test-auto-learn.sh`
- Create: `Tests/AutoLearn/Stubs.swift`
- Create: `Tests/AutoLearn/main.swift`

**Interfaces:**
- Produces: `./scripts/test-auto-learn.sh` 退出码 0 表示全部通过。`main.swift` 提供两个帮助函数，后续 Task 的测试都用它们：
  - `func check(_ name: String, _ condition: Bool)`：失败时打印 `FAIL: name` 并 `exit(1)`。
  - `func learned(field: String, pasted: String, final: String) -> [String]`（Task 3 再加 `usedFallback: Bool = false` 参数并传给快照）：依次调用 `FinalSnapshotDiffEngine.revision(from:)` → `CorrectionDiffEngine.candidates(from:usesAIReviewer: false)` → `CorrectionDiffEngine.replacementPair(from:)` → `AutoLearnLocalReviewPolicy.accepts`，返回通过的规则，格式 `"源→目标"`。`pastedRange` 取 `pasted` 在 `field` 中的位置。

- [ ] **Step 1:** 写 `scripts/test-auto-learn.sh`：`set -euo pipefail`，从仓库根目录用 `swiftc -O` 把下列文件编译成临时可执行文件并运行：`Tests/AutoLearn/Stubs.swift`、`Tests/AutoLearn/main.swift`、`AutoLearn/AutoLearnTypes.swift`、`AutoLearn/CorrectionDiffEngine.swift`、`AutoLearn/FinalSnapshotDiffEngine.swift`、`AutoLearn/AutoLearnLocalReviewer.swift`、`VoiceInk/Features/Dictionary/Workflows/WordReplacementVariants.swift`。（Task 3 再加 `AutoLearnFieldSampler.swift`。）
- [ ] **Step 2:** `Stubs.swift` 只桩两样：`enum AutoLearnSettings { static var usesAIReviewer = false }`，以及 `enum AutoLearnReviewEligibility { static func accepts(source: String?, destination: String, aiReviewConfigurationID: String?) -> Bool { true } }`。
- [ ] **Step 3:** `main.swift` 先放两条现有行为的回归测试，确认脚本本身能跑通：

```swift
check("en_wordFix", learned(field: "I think voice ink works.", pasted: "I think voice ink works.", final: "I think VoiceInk works.") == ["voice ink→VoiceInk"])
check("en_pluralIgnored", learned(field: "I like the model.", pasted: "I like the model.", final: "I like the models.") == [])
```

- [ ] **Step 4:** Run: `./scripts/test-auto-learn.sh`。Expected: 两条都通过，退出码 0。
- [ ] **Step 5:** Commit：`test: standalone harness for Auto-Learn diff logic`

---

### Task 2: 中文按词切分

**Files:**
- Modify: `VoiceInk/Features/Dictionary/AutoLearn/CorrectionDiffEngine.swift`（`segments(in:)` 约 156 行起；三个标点集合约 39–47 行；`candidates` 里的逗号判断约 123 行；`isCompactScriptScalar` 约 388 行）
- Modify: `VoiceInk/Features/Dictionary/AutoLearn/AutoLearnLocalReviewer.swift`（`fitsLimits`）
- Test: `Tests/AutoLearn/main.swift`

**Interfaces:**
- Produces: `CorrectionDiffEngine.isCompactScriptScalar(_:)` 从 `private` 改为内部可见（`fitsLimits` 要用）。其余公开签名不变。

- [ ] **Step 1: 写失败的测试**（`s` 开头的是整句粘贴，`field == pasted`）：

```swift
let s1 = "今天安排差啥没干，6点半去Kupertino杨国福吃饭。"
check("cjk_mixedLatinWord", learned(field: s1, pasted: s1, final: s1.replacingOccurrences(of: "Kupertino", with: "Cupertino")) == ["Kupertino→Cupertino"])
let s2 = "我们明天去北鲸开会，然后顺便吃个饭。"
check("cjk_wordFix", learned(field: s2, pasted: s2, final: s2.replacingOccurrences(of: "北鲸", with: "北京")) == ["北鲸→北京"])
let s3 = "我觉得这个功能在大多数情况下都挺好用的但是有时候它根本就没有触发我也不知道为什么会这样"
check("cjk_longSentence_learnsWordOnly", learned(field: s3, pasted: s3, final: s3.replacingOccurrences(of: "触发", with: "出发")) == ["触发→出发"])
let s4 = "那那个Waveform CLI是什么呢？"
check("cjk_latinNextToHan", learned(field: s4, pasted: s4, final: "那那个 vphone CLI是什么呢？") == ["Waveform→vphone"])
let s5 = "他高兴的跳了起来"
check("cjk_singleCharNotLearned", learned(field: s5, pasted: s5, final: "他高兴地跳了起来") == [])
```

- [ ] **Step 2:** Run: `./scripts/test-auto-learn.sh`。Expected: `FAIL: cjk_mixedLatinWord`（现在学到的是整句）。
- [ ] **Step 3: 改 `segments(in:)`。** 规则：
  - 字符的标量全部满足 `isCompactScriptScalar` 的算"紧凑文字"。紧凑文字和非紧凑文字相邻时，在交界处断开当前片段（`去Kupertino杨` 切成三段）。
  - 每一段连续的紧凑文字用 `NLTokenizer(unit: .word)` 细分：`tokenizer.string = text`，`enumerateTokens(in: 该段范围)`，每个词一个 `TextSegment`（`range` 直接用返回的范围，`isBoundary: false`）。不调用 `setLanguage`。分词器没覆盖到的字符，每个字符单独成段。
  - 拉丁字母、数字的切法保持不变。
- [ ] **Step 4: 全角标点与半角同等对待。** `structuralSeparators` 加 `，。！？；：、（）【】《》「」『』`；`trailingSentencePunctuation` 加 `，。！？；：、`；`leadingWrappers` 加 `（【《「『`；`candidates` 里 `!pair.source.contains(",")` 同时排除 `，` 和 `、`。
- [ ] **Step 5: 不学单个汉字。** 在 `AutoLearnLocalReviewPolicy.fitsLimits` 里加条件：`source` 不为 nil 时，不能恰好是一个紧凑文字字符。（`的→地`、`张→章` 这类规则会误伤所有出现该字的地方。）
- [ ] **Step 6:** Run: `./scripts/test-auto-learn.sh`。Expected: 全部通过，包括 Task 1 的两条英文回归。
- [ ] **Step 7:** Commit：`fix(auto-learn): diff CJK text by word instead of by whole clause`

---

### Task 3: 发送清空输入框后仍能学到

**Files:**
- Create: `VoiceInk/Features/Dictionary/AutoLearn/AutoLearnFieldSampler.swift`
- Modify: `VoiceInk/Features/Dictionary/AutoLearn/AutoLearnTypes.swift`（`AutoLearnFieldSnapshot`、`AutoLearnLimits`）
- Modify: `VoiceInk/Features/Dictionary/AutoLearn/FinalSnapshotDiffEngine.swift`（`revision(from:)`）
- Modify: `VoiceInk/Features/Dictionary/AutoLearn/AutoLearnAXRuntime.swift`（`Session`、`finishSnapshot`，新增 `sampleField`）
- Modify: `VoiceInk/Features/Dictionary/AutoLearn/AutoLearnService.swift`（`beginObservation`、`resetObservation`，新增采样任务）
- Modify: `scripts/test-auto-learn.sh`（编译列表加 `AutoLearnFieldSampler.swift`）
- Test: `Tests/AutoLearn/main.swift`

**Interfaces:**
- Produces:

```swift
// AutoLearnFieldSampler.swift —— 纯逻辑，只依赖 Foundation
struct AutoLearnFieldSampler {
    enum Event: Equatable { case none, cleared }
    private(set) var lastText: String?          // 最后一次读到的非空白文字
    /// text 为 nil 表示这次没读到（超时或元素失效）。
    mutating func record(_ text: String?) -> Event
}
// AutoLearnTypes.swift
struct AutoLearnFieldSnapshot { /* 现有字段 */ var usedFallback: Bool = false }
enum AutoLearnLimits { /* 现有 */ static let fieldSampleIntervalNanoseconds: UInt64 = 250_000_000 }
// AutoLearnAXRuntime.swift
func sampleField(token: AutoLearnPasteToken) async -> AutoLearnFieldSampler.Event
```

- `record` 的规则：
  - 非空白文字 → 存入 `lastText`，未读到计数清零，返回 `.none`。
  - 成功读到空白文字 → `lastText` 不为 nil 时返回 `.cleared`，否则 `.none`。
  - `nil` → 连续第 2 次且 `lastText` 不为 nil 时返回 `.cleared`，否则 `.none`。

- [ ] **Step 1: 写失败的测试**（先给 `learned` 加上 `usedFallback: Bool = false` 参数）：

```swift
var a = AutoLearnFieldSampler()
check("sampler_blankReadSettlesImmediately", a.record("abc") == .none && a.record("") == .cleared && a.lastText == "abc")
var b = AutoLearnFieldSampler()
check("sampler_oneUnreadableTolerated", b.record("abc") == .none && b.record(nil) == .none && b.record("abd") == .none && b.lastText == "abd")
check("sampler_twoUnreadableSettles", b.record(nil) == .none && b.record(nil) == .cleared)
var c = AutoLearnFieldSampler()
check("sampler_nothingSeenNeverSettles", c.record("") == .none && c.record(nil) == .none && c.record(nil) == .none)
// 发送场景：最终读数为空，用最后一版文字代替
check("send_fallbackLearnsFix", learned(field: s1, pasted: s1, final: s1.replacingOccurrences(of: "Kupertino", with: "Cupertino"), usedFallback: true) == ["Kupertino→Cupertino"])
// 一路退格删到一半时被采样，不能当成更正
check("send_fallbackIgnoresTruncation", learned(field: "Kupertino is nice", pasted: "Kupertino is nice", final: "Kup", usedFallback: true) == [])
```

- [ ] **Step 2:** Run: `./scripts/test-auto-learn.sh`。Expected: 编译失败，`AutoLearnFieldSampler` 未定义。
- [ ] **Step 3:** 实现 `AutoLearnFieldSampler`，加 `usedFallback` 字段和 `fieldSampleIntervalNanoseconds` 常量。
- [ ] **Step 4:** `FinalSnapshotDiffEngine.revision(from:)`：`snapshot.usedFallback` 为 true 且归一化后的更正文本是原文的前缀时，返回 nil。
- [ ] **Step 5:** Run: `./scripts/test-auto-learn.sh`。Expected: 全部通过。
- [ ] **Step 6: 接到运行时（无自动化测试，Task 4 手动验证）。**
  - `AutoLearnAXRuntime.Session` 加 `var sampler = AutoLearnFieldSampler()`。
  - `sampleField(token:)`：token 不匹配返回 `.none`；用 `textReader.textValue(from: targetElement)?.text` 读取；长度超过 `AccessibilityTextReader.maximumFieldUTF16Length` 的读数当作 `nil`；调用 `record` 并写回 session。
  - `finishSnapshot(token:)`：最终读数为 nil 或空白时，改用 `sampler.lastText` 并设 `usedFallback = true`；`lastText` 也没有时照旧返回 nil。保留"与 baseline 完全相同则返回 nil"的判断。
  - `AutoLearnService`：新增 `private var sampleTask: Task<Void, Never>?`。`beginObservation` 在 `activeToken = token` 之后启动循环：睡 `fieldSampleIntervalNanoseconds` → 确认 `activeToken == token && isEnabled` → `sampleField` → 返回 `.cleared` 时调用新的 `finalizeOnClear(token:)`（写法照抄 `finalizeAtDeadline`）并结束循环。`resetObservation()` 里取消并置空 `sampleTask`。
  - `finalizeOnClear` 里加一行日志：`Auto Learn settled reason=field-cleared`。
- [ ] **Step 7:** Commit：`fix(auto-learn): keep the edit when sending clears the field`

---

### Task 4: 构建、安装、手动验证、回馈上游

**Files:** 无代码改动。

- [ ] **Step 1: 构建。** Run: `make local LOCAL_CODESIGN_IDENTITY=-`（保持和现在装的一样的 ad-hoc 签名）。Expected: `Build complete! App saved to: ~/Downloads/VoiceInk.app`。
- [ ] **Step 2: 安装（用户操作）。** 退出 VoiceInk，用 `~/Downloads/VoiceInk.app` 替换 `/Applications/VoiceInk.app`。ad-hoc 签名每次构建都会变，需要在系统设置里重新授予"辅助功能"和麦克风权限。菜单栏图标不见的话，到系统设置 > 菜单栏里重新打开。
- [ ] **Step 3: 手动验证，三个场景都在 Dia 的聊天输入框里做：**
  - 说"6点半去 Cupertino 吃饭"之类的话，把识别错的词改对，**2 秒内按回车**。Expected: 弹出「学习此更正？」，内容是"错词 → 对词"，不是整句；日志有 `reason=field-cleared`。
  - 改完不发送，切到别的窗口。Expected: 同样弹出按词的建议。
  - 不改，直接回车，接着在同一个框里打一条新消息。Expected: 不弹任何建议。
  - 用拼音输入法改字时留意有没有带拼音的建议（Review Focus 第 2 条），以及打字是否卡顿（第 4 条）。
- [ ] **Step 4: 回馈上游（需要用户确认后再发）。** 上游不收 PR，只收 issue：
  - 在 Beingpax/VoiceInk#977 下评论：确认"发送清空输入框导致最终读数为空"这个原因，附本分支的修复提交链接。该 issue 下已有 alexph-dev 的参考补丁（思路相同，改动更大）。
  - 新开一个 issue 报告中文/日文按整句学习的问题：上游目前没有相关报告。附最小复现、原因（`segments(in:)` 只按空格和半角标点切分）和修复提交链接。
  - 发布前用 `gemini-issue-rewrite` skill 过一遍文字。
