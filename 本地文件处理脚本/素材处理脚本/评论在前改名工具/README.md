# 评论在前改名工具

用途：把当前文件夹及所有子文件夹里的文件、文件夹名称，从 `赞1评4` 改成 `评4赞1`，方便先看评论数。

## 默认行为：只预览

双击 `一键改名-评论在前.bat` 或直接运行脚本时，默认只列出改名计划，不修改文件。

```powershell
.\swap-like-comment-prefix.ps1 -Mode Preview
```

## 确认执行

确认预览结果后，必须显式使用 Apply 模式和确认令牌：

```powershell
.\swap-like-comment-prefix.ps1 -Mode Apply -ConfirmApplyToken RENAME
```

执行时会：

- 先检查所有目标名称是否冲突；
- 按最深路径优先执行；
- 任一改名失败时，自动反向恢复已完成项目；
- 在 `rename-logs` 中生成 CSV 历史。

## Undo

```powershell
.\swap-like-comment-prefix.ps1 -Mode Undo `
  -HistoryFile ".\rename-logs\rename_like_comment_时间.csv" `
  -ConfirmUndoToken UNDO
```

Undo 会按反向顺序恢复目录和文件。

## 规则

- `赞1评4xxx` → `评4赞1xxx`
- `赞10评080个游戏` → `评0赞10 80个游戏`
- 如果目标名称已经存在，预检会直接停止，不覆盖原文件。
