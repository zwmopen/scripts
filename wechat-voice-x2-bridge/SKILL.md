---
name: mouse-voice-typing
description: 本地 Windows 人机协同小技能。用于把鼠标 X2 侧键联动微信输入法语音输入，让用户按鼠标侧键即可触发“左 Ctrl + 左 Alt + O”。适用于配置、启动、停止、开机自启或排查“鼠标快速语音打字”“微信输入法语音输入快捷键”“X2 侧键语音输入”等本机输入效率问题。
---

# 鼠标快速语音打字

## 定位

这是一个人机协同里的本地操作技能：把鼠标 `X2` 侧键变成微信输入法语音输入入口。

它解决的是微信输入法对普通模拟快捷键不稳定识别的问题。脚本监听 Windows 的 `XBUTTON2`，在松开鼠标侧键时发送 `左 Ctrl + 左 Alt + O`，匹配微信输入法“启动语音输入”的快捷键。

## 使用入口

脚本目录：

```text
D:\AICode\AI\skills\技能包\技能\AI协作\鼠标快速语音打字\scripts
```

常用入口：

- `scripts\start.cmd`：启动后台监听。
- `scripts\stop.cmd`：停止后台监听。
- `scripts\install-startup.cmd`：安装当前用户开机自启动。
- `scripts\uninstall-startup.cmd`：取消开机自启动。
- `scripts\watchdog.ps1`：守护脚本，发现后台监听不在时自动拉起。
- `scripts\install-watchdog.ps1`：安装计划任务守护，每 5 分钟检查一次。
- `scripts\uninstall-watchdog.ps1`：取消计划任务守护。
- `scripts\wechat-voice-x2-bridge.ps1`：核心脚本。

## 运行规则

1. 保持微信输入法语音输入快捷键为 `左 Ctrl + 左 Alt + O`。
2. 启动脚本后，按鼠标 `X2` 侧键即可唤起微信输入法语音输入。
3. 默认推荐安装开机自启动和计划任务守护，这样重启、睡眠恢复后仍可直接使用。
4. 如果用户说“X2 没反应”，先检查脚本是否运行、PID 文件是否存在、日志是否记录 `XBUTTON2`。

## 本地运行文件

运行时会生成：

- `scripts\wechat-voice-x2-bridge.log`
- `scripts\wechat-voice-x2-bridge.pid`

这两个文件只代表本机当前运行状态，不是技能源码，不需要提交或同步。

## 排查顺序

1. 确认微信输入法设置里“启动语音输入”为 `左 Ctrl + 左 Alt + O`。
2. 确认后台脚本正在运行。
3. 查看日志是否出现 `Mouse down XBUTTON2`、`Mouse up XBUTTON2`、`keybd_event sent LeftCtrl+LeftAlt+O`。
4. 如果有侧键日志但没有弹窗，优先怀疑微信输入法快捷键设置变化或目标窗口权限层级差异。
5. 如果没有侧键日志，优先怀疑鼠标驱动、侧键映射或脚本未运行。

## 分类

- 所属大类：AI协作 / 人机协同
- 技能类型：本地脚本型技能
- 场景：输入效率、语音转文字、鼠标快捷操作、微信输入法联动
