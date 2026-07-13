# 资产归档卡：鼠标快速语音打字

## 资产身份

- 名称：鼠标快速语音打字
- 类型：本地 Windows 小技能 / 人机协同脚本
- 分类：AI 协作 / 人机协同 / 输入效率
- 目的：用鼠标 X2 侧键调用微信输入法语音输入，减少键盘操作

## 唯一触发链

```text
鼠标 X2（Windows XBUTTON2）
  -> 释放侧键时发送 左 Ctrl + 左 Alt + O
  -> 微信输入法“启动语音输入”
```

微信输入法中的快捷键必须保持为 `左 Ctrl + 左 Alt + O`。脚本只负责把 X2 转换成这组按键，不修改微信输入法配置。

## 持久化与恢复

本机已安装三个当前用户计划任务：

1. `WeChat Voice X2 Bridge Startup`：登录时启动。
2. `WeChat Voice X2 Bridge Watchdog`：每 5 分钟检查后台监听。
3. `WeChat Voice X2 Bridge Refresh`：用户解锁或系统从睡眠恢复后重启监听。

计划任务通过 `run-hidden.vbs` 隐藏运行，正常使用时不应弹出蓝色 PowerShell 窗口。

## 资产位置

- 本地源：`D:\AICode\AI\skills\技能包\技能\AI协作\鼠标快速语音打字`
- Codex 运行镜像：`C:\Users\z\.codex\skills\mouse-voice-typing`
- Agents 运行镜像：`C:\Users\z\.agents\skills\mouse-voice-typing`
- 云端仓库：`https://github.com/zwmopen/scripts.git`
- 云端分支：`codex/wechat-voice-x2-bridge`
- 云端目录：`wechat-voice-x2-bridge`

## 归档规则

- 源码、`SKILL.md`、`README.md` 和本归档卡属于可沉淀资产。
- `scripts\wechat-voice-x2-bridge.log` 与 `scripts\wechat-voice-x2-bridge.pid` 是本机运行状态，不纳入归档。
- 迁移到新电脑时，先复制资产目录，再运行 `scripts\install-watchdog.ps1`，最后确认微信输入法快捷键仍为 `左 Ctrl + 左 Alt + O`。
- 要彻底移除时，先运行 `scripts\uninstall-watchdog.ps1`，再停止脚本。

## 当前结论

该项目已经从一次性排障脚本沉淀为可复用的小技能资产。云端采用原有 `scripts` 仓库的独立目录和分支保存，不另建仓库；本机采用计划任务保持登录、重启、解锁和睡眠恢复后的可用性。
