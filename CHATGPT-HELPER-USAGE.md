# ChatGPT 辅助脚本使用说明

适用脚本：`chatgpt-conversation-tree.user.js`

它会在 ChatGPT 网页中提供最近对话分组、拖动分类、提示词管理、数据导入导出、图片组快捷下载和本地作品包联动等功能。

## 安装与更新

1. 安装 Tampermonkey（油猴）。
2. 打开以下地址并确认安装：
   `https://raw.githubusercontent.com/zwmopen/scripts/master/chatgpt-conversation-tree.user.js`
3. 返回 `https://chatgpt.com/` 并刷新页面。

脚本已经配置 `@updateURL` 和 `@downloadURL`。以后仓库发布更高版本时，Tampermonkey 可以自动检查更新；也可以在 Tampermonkey 管理面板中手动执行“检查更新”。

## Chrome 必须开启“允许用户脚本”

Chrome 138 及以上版本为每个扩展增加了单独的用户脚本权限。即使 Tampermonkey 已启用，如果这个权限关闭，所有油猴脚本仍然不会注入网页。

设置方法：

1. 在 Chrome 地址栏输入 `chrome://extensions`。
2. 找到 Tampermonkey，点击“详细信息”。
3. 开启“允许用户脚本”。
4. 将“网站访问权限”设为“在所有网站上”，或至少允许 `chatgpt.com`。
5. 返回 ChatGPT，按 `Ctrl+Shift+R` 强制刷新。

这是 Chrome 权限，不是本脚本内部开关。Chrome 更新、重装扩展或权限重置后，如果脚本突然完全消失，应首先检查这里。

## Edge 权限

在 Edge 地址栏输入 `edge://extensions`，确认：

- Tampermonkey 已启用；
- 允许扩展访问 `chatgpt.com`；
- 如果扩展详情中出现“允许用户脚本”，也要将它开启。

## 判断脚本是否正常运行

正常情况下，刷新 ChatGPT 后至少能看到以下一个或多个入口：

- “最近”区域中的对话分组；
- 输入框附近的“提示词”按钮；
- 图片回复下方的图片组下载按钮；
- Tampermonkey 图标显示当前页面有脚本运行。

## 脚本突然不显示的排查顺序

1. 检查 Tampermonkey 总开关。
2. Chrome 138+ 检查“允许用户脚本”。
3. 检查 Tampermonkey 对 `chatgpt.com` 的网站访问权限。
4. 在 Tampermonkey 管理面板确认本脚本已启用。
5. 确认脚本匹配地址包含 `https://chatgpt.com/*`。
6. 按 `Ctrl+Shift+R` 强制刷新。
7. 关闭全部 Chrome 窗口后重新打开，避免扩展后台进程卡住。
8. 仍不正常时，重新打开安装地址覆盖安装最新版；分组和提示词数据通常不会因为覆盖安装而删除。

## 数据安全

- 分组与提示词数据主要保存在当前浏览器的油猴存储中。
- 在脚本的数据菜单中定期导出 JSON，便于迁移浏览器或恢复数据。
- 覆盖安装或正常更新脚本不会主动清空数据。
- 卸载 Tampermonkey、清理扩展数据或更换浏览器配置文件前，应先导出数据。

## Chrome 正常、Edge 正常但某个页面不正常

如果只有某个超长对话卡住，而新对话正常，通常是单个标签页负载或页面缓存问题：

1. 先复制尚未发送的内容；
2. 关闭该 ChatGPT 标签页；
3. 从历史记录重新打开对应对话；
4. 必要时完全重启浏览器。

如果同一脚本在 Edge 正常、Chrome 所有 ChatGPT 页面都不生效，优先检查 Chrome 的“允许用户脚本”，不要先删除分组数据或重写脚本。
