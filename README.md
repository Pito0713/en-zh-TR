# QuickTranslate（en-zh-TR）

macOS 選單列的英 ↔ 繁中快速翻譯器，**完全離線**、不需要 API key。
翻譯引擎為本機 [Ollama](https://ollama.com) 上的 `qwen3.5:9b`（慣用語、口語、台灣用詞明顯較準）；Ollama 沒開時自動退回 Apple 內建 Translation framework。

## 使用方式

啟動後視窗會常駐在桌面（點別的 App 不會消失），位置可拖曳並會被記住。
背景為 Liquid Glass 玻璃透明效果，透明度由 `TranslatorPanel.swift` 的 `glassOpacity`（目前 0.95）調整。

| 操作 | 按鍵 |
|---|---|
| 叫出 / 收起視窗 | `⌃⌥T`（或點選單列的 💬 圖示） |
| 翻譯 | 打字或貼上後按 `Enter`（或「翻譯」鈕、`⌘Enter`）；打字時只自動偵測語言、不翻譯 |
| 貼上 | `⌘V`（也支援 `⌃V`） |
| 複製結果 | 翻譯完再按一次 `Enter`、`⌘⇧C` 或「複製」按鈕 |
| 切換方向 | 上方「自動／中 → 英／英 → 中」，或 `⌘1` `⌘2` `⌘3` |
| 結果換到輸入框反向翻譯 | ⇄ 按鈕或 `⌘⇧X`（可回譯檢查） |
| 朗讀 | 結果：`⌘⇧S` 或結果區 🔊；原文：`⌘⇧I` 或輸入框 🔊（朗讀中再按一次停止） |
| 換行 | `⌥Enter` |
| 收起視窗 | 左上角關閉鈕或 `Esc`（App 仍在選單列，`⌃⌥T` 叫回） |
| 結束 App | 選單列圖示 → 結束，或 `⌘Q` |

方向預設自動判斷：輸入含漢字就中翻英，否則英翻中；也可手動固定方向。

## 建置

```bash
./build.sh            # 產生 build/QuickTranslate.app
./build.sh --install  # 再複製到 ~/Applications
open ~/Applications/QuickTranslate.app
```

需求：macOS 26+、Xcode 或 Command Line Tools（Swift 6.2+）、Ollama 並下載模型：

```bash
ollama pull qwen3.5:9b   # 約 7.6 GB；翻譯時佔約 7.7 GB 記憶體，閒置 5 分鐘自動釋放
```

換模型：`defaults write local.quicktranslate ollamaModel "模型名稱"`。
備援用的 Apple 翻譯需下載離線語言「英文」與「中文（台灣）」（系統設定 → 一般 → 語言與地區 → 翻譯語言）。

翻譯品質對照腳本：`scripts/fm-eval.swift`（Apple Translation / Foundation Models / Ollama 模型並排比較，用法見檔頭）。

開機自動啟動：第一次啟動時會自動註冊為登入項目（macOS 可能跳出「已加入登入項目」通知）。
要關閉可在選單列圖示 → 取消勾選「登入時自動啟動」，或到系統設定 → 一般 → 登入項目。
請從 `~/Applications` 或 `/Applications` 執行 App，登入項目才會指向正確位置。

## 結構

```
Sources/QuickTranslate/
  main.swift             進入點（選單列 accessory app）
  AppDelegate.swift      選單列圖示、全域快捷鍵
  HotKey.swift           Carbon RegisterEventHotKey 包裝
  LaunchAtLogin.swift    SMAppService 登入項目（開機自動啟動）
  TranslatorModel.swift  方向判斷、按鍵觸發翻譯（Ollama → Apple 備援）、複製
  OllamaClient.swift     本機 Ollama /api/chat 翻譯（qwen3.5:9b）
  TranslatorPanel.swift  Spotlight 風格浮動視窗 + SwiftUI 介面
  Speaker.swift          AVSpeechSynthesizer 朗讀原文與翻譯結果
```

## 路線圖

- [x] **L1 快速翻譯**：選單列 + 全域快捷鍵 + 離線即時翻譯 + 一鍵複製
- [ ] L1.x 小改進（視需要）：可自訂快捷鍵、翻譯歷史
- [ ] **L2 練習模式**：先寫中文意思，再寫自己的英文，比較差異並給出修正與更自然的說法
  （離線翻譯做不到糾錯，屆時要評估是否接 LLM API）
- [ ] **L3 情境對話**：選情境（點餐、面試、閒聊），AI 扮演對方來回對話並即時糾正
- [x] 朗讀翻譯結果（🔊）
- [ ] 選配：語音輸入、生字複習卡、弱點統計

## 版本紀錄

| 版本 | 日期 | 摘要 |
|---|---|---|
| 0.5.0 | 2026-11-27 | 翻譯改用本機 Ollama `qwen3.5:9b`（Ollama 未啟動自動退回 Apple 翻譯）；改為按 Enter／翻譯鈕才翻、再按 Enter 複製，打字時只自動偵測語言；輸入框加 🔊 朗讀原文（⌘⇧I）；修正新 SDK safe area 造成版面下移、底部提示被切；新增 `scripts/fm-eval.swift` 翻譯品質對照腳本 |
| 0.4.0 | 2026-11-20 | 新增 🔊 朗讀按鈕（⌘⇧S，en-US / zh-TW 離線語音）；手動切換方向（自動／中→英／英→中，⌘1-3）；⇄ 結果換到輸入框反向翻譯（⌘⇧X） |
| 0.3.0 | 2026-11-20 | Liquid Glass 玻璃透明背景（95%）；開機自動啟動（首次啟動自動註冊，選單可切換） |
| 0.2.0 | 2026-11-20 | 啟動即顯示並常駐桌面、加關閉鈕、記住位置；修正無法貼上（補 Edit 選單、支援 ⌃V）；Enter 改為只複製 |
| 0.1.0 | 2026-11-20 | L1 MVP：選單列、⌃⌥T、離線中英互譯、Enter 複製 |
