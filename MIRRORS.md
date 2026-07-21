# 受管镜像映射

| 发布镜像 | 唯一可编辑真源 | 保留原因 |
|---|---|---|
| `chatgpt-conversation-tree.user.js` | `..\chatgpt-conversation-tree\src\chatgpt-conversation-tree.user.js` | 现有用户脚本在线更新地址指向本仓库 |
| `chatgpt-cloud-prompts.json` | `..\chatgpt-conversation-tree\data\chatgpt-cloud-prompts.json` | 已安装脚本从本仓库获取公开提示词 |

规则：只允许“真源 → 发布镜像”单向同步。检查发现差异时先判断真源是否已完成，再执行同步；不要把镜像反向复制成源码。
