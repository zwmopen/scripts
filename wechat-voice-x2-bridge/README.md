# 鼠标快速语音打字

Windows 小工具：把鼠标 `X2` 侧键绑定到微信输入法语音输入。

它会在后台监听鼠标 `XBUTTON2`，松开侧键时发送 `左 Ctrl + 左 Alt + O`，对应微信输入法里的“启动语音输入”快捷键。

## 文件

- `start.cmd`：启动后台监听。
- `stop.cmd`：停止后台监听。
- `install-startup.cmd`：添加到当前用户的 Windows 开机启动。
- `uninstall-startup.cmd`：取消开机启动。
- `wechat-voice-x2-bridge.ps1`：核心脚本。

## 使用

1. 保持微信输入法的语音输入快捷键为 `左 Ctrl + 左 Alt + O`。
2. 运行 `start.cmd`。
3. 按鼠标 `X2` 侧键，即可唤起微信输入法语音输入。
4. 运行 `install-startup.cmd` 后，重启电脑也会自动启动。

运行时会生成 `wechat-voice-x2-bridge.log` 和 `wechat-voice-x2-bridge.pid`，它们只保留在本地，不需要提交到 GitHub。
