# QuickTranslate（en-zh-TR）

macOS 選單列的英 ↔ 繁中快速翻譯器，使用 Apple 內建 Translation framework，**完全離線**、不需要 API key。

## 使用方式

啟動後視窗會常駐在桌面（點別的 App 不會消失），位置可拖曳並會被記住。

| 操作 | 按鍵 |
|---|---|
| 叫出 / 收起視窗 | `⌃⌥T`（或點選單列的 💬 圖示） |
| 翻譯 | 直接打字或貼上，約 0.25 秒後即時顯示 |
| 貼上 | `⌘V`（也支援 `⌃V`） |
| 複製結果 | `Enter`、`⌘⇧C` 或「複製」按鈕 |
| 換行 | `⌥Enter` |
| 收起視窗 | 左上角關閉鈕或 `Esc`（App 仍在選單列，`⌃⌥T` 叫回） |
| 結束 App | 選單列圖示 → 結束，或 `⌘Q` |

方向自動判斷：輸入含漢字就中翻英，否則英翻中。

## 建置

```bash
./build.sh            # 產生 build/QuickTranslate.app
./build.sh --install  # 再複製到 ~/Applications
open ~/Applications/QuickTranslate.app
```

需求：macOS 26+、Xcode（Swift 6.2+）、已下載離線語言「英文」與「中文（台灣）」
（系統設定 → 一般 → 語言與地區 → 翻譯語言）。

開機自動啟動：系統設定 → 一般 → 登入項目 → 加入 QuickTranslate.app。

## 結構

```
Sources/QuickTranslate/
  main.swift             進入點（選單列 accessory app）
  AppDelegate.swift      選單列圖示、全域快捷鍵
  HotKey.swift           Carbon RegisterEventHotKey 包裝
  TranslatorModel.swift  方向判斷、TranslationSession、防抖、複製
  TranslatorPanel.swift  Spotlight 風格浮動視窗 + SwiftUI 介面
```

## 路線圖

- [x] **L1 快速翻譯**：選單列 + 全域快捷鍵 + 離線即時翻譯 + 一鍵複製
- [ ] L1.x 小改進（視需要）：可自訂快捷鍵、翻譯歷史、手動切換方向
- [ ] **L2 練習模式**：先寫中文意思，再寫自己的英文，比較差異並給出修正與更自然的說法
  （離線翻譯做不到糾錯，屆時要評估是否接 LLM API）
- [ ] **L3 情境對話**：選情境（點餐、面試、閒聊），AI 扮演對方來回對話並即時糾正
- [ ] 選配：語音輸入／朗讀、生字複習卡、弱點統計

## 版本紀錄

| 版本 | 日期 | 摘要 |
|---|---|---|
| 0.2.0 | 2026-11-20 | 啟動即顯示並常駐桌面、加關閉鈕、記住位置；修正無法貼上（補 Edit 選單、支援 ⌃V）；Enter 改為只複製 |
| 0.1.0 | 2026-11-20 | L1 MVP：選單列、⌃⌥T、離線中英互譯、Enter 複製 |
