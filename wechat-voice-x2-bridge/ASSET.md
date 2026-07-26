# 资产归档卡：鼠标快速语音打字

## 资产身份

- 名称：鼠标快速语音打字
- 类型：本地 Windows 常驻小软件 / Codex 运维技能
- 分类：AI 协作 / 人机协同 / 输入效率
- 目的：用鼠标 X2 侧键调用微信输入法语音输入，减少键盘操作；通过自动启动、守护恢复和版本维护形成可长期使用的软件资产

## 唯一触发链

```text
鼠标 X2（Windows XBUTTON2）
  -> 释放侧键时通过 Windows SendInput 发送 左 Ctrl + 左 Alt + O
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

当前版本为 `0.4.0`。核心监听采用“低层钩子 + `GetAsyncKeyState` 轮询后备”双通道；守护程序通过 PID、进程启动时间和 15 秒心跳共同判断健康。计划任务直接运行隐藏 PowerShell，不再依赖可能挂起的 VBS 中间层。用户可通过桌面 `鼠标语音输入-启动修复.lnk` 一键重启并检查健康状态。

2026-07-26 已验证：脚本语法、X2 回环、心跳推进、五分钟守护任务和登录启动任务均通过；任务执行结果为 `0x0`。未执行真实重启电脑验收，已完成等价的登录任务手动触发测试。

## 升级路线

1. 产品边界：核心监听、守护恢复、安装任务和配置共同组成一个本地小程序；代码可模块化，但对用户保持一个产品、一个入口。
2. 映射模型：从写死的 X2 单映射升级为配置文件驱动的多映射表，支持鼠标键、键盘键和组合键作为触发源。
3. 动作模型：支持发送快捷键、启动程序、执行受控命令等动作，并为每条映射提供启停开关和应用范围。
4. 管理能力：增加映射冲突检测、配置校验、统一日志、健康状态和托盘管理界面。
5. 兼容原则：现有微信语音输入链作为默认预设保留，升级时自动迁移，不破坏当前 X2 使用习惯。
