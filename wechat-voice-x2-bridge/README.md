# 鼠标快速语音打字

Windows 小工具：把鼠标 `X2` 侧键绑定到微信输入法语音输入。

它会在后台监听鼠标 `XBUTTON2`，松开侧键时发送 `左 Ctrl + 左 Alt + O`，对应微信输入法里的“启动语音输入”快捷键。

## 文件

- `start.cmd`：启动后台监听。
- `stop.cmd`：停止后台监听。
- `install-startup.cmd`：添加到当前用户的 Windows 开机启动。
- `uninstall-startup.cmd`：取消开机启动。
- `watchdog.ps1`：守护脚本，发现后台监听不在时自动拉起。
- `install-watchdog.ps1`：安装计划任务守护，每 5 分钟检查一次。
- `uninstall-watchdog.ps1`：取消计划任务守护。
- `run-hidden.vbs`：隐藏运行守护脚本，避免弹出蓝色 PowerShell 窗口。
- `wechat-voice-x2-bridge.ps1`：核心脚本。
- `SKILL.md`：技能说明，归类为“AI协作 / 人机协同 / 本地脚本型技能”。

## 使用

1. 保持微信输入法的语音输入快捷键为 `左 Ctrl + 左 Alt + O`。
2. 运行 `start.cmd`。
3. 按鼠标 `X2` 侧键，即可唤起微信输入法语音输入。
4. 运行 `install-startup.cmd` 后，重启电脑也会自动启动。
5. 运行 `install-watchdog.ps1` 后，会每 5 分钟检查一次，并在解锁或睡眠恢复后主动重启监听，避免系统输入层刷新后失效。

运行时会生成 `wechat-voice-x2-bridge.log` 和 `wechat-voice-x2-bridge.pid`，它们只保留在本地，不需要提交到 GitHub。
