# ChatGPT 云端提示词库

公开数据文件：`chatgpt-cloud-prompts.json`

ChatGPT 辅助器会每天自动检查一次，也可以在“提示词库”里点击“☁ 同步”立即拉取。同步结果缓存在浏览器本地；GitHub 暂时不可访问时，仍会使用上一次缓存。

## 更新提示词

1. 在 ChatGPT 辅助器里维护本地提示词。
2. 点击“导出云端文件”，得到 `chatgpt-cloud-prompts.json`。
3. 用导出的文件替换仓库同名文件并提交。
4. 其他设备点击“☁ 同步”即可更新。

云端条目是只读映射，不会覆盖或删除浏览器里的本地提示词。公开仓库不要存放账号、密码、令牌或其他隐私信息。

Raw 地址：

`https://raw.githubusercontent.com/zwmopen/scripts/master/chatgpt-cloud-prompts.json`
