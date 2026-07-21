# 公共脚本发布仓库

> 项目 ID：`public-scripts`
> 版本：1.0.0
> 状态：维护

这里集中保存适合公开安装、复用或自动更新的轻量脚本。它是发布仓库，也可承载尚未拆成独立产品的小脚本，但不再保存已有独立项目的第二份可编辑源码。

## 当前边界

- 普通轻量脚本：可直接在本仓库维护。
- 已拆出的独立产品：本仓库只保留在线更新所需的受管发布镜像。
- 私人资料、账号凭据、业务数据和运行缓存：禁止进入本仓库。
- 历史抽取副本：进入 `archive/`，只作追溯，不参与运行。

## 受管发布镜像

以下两个文件服务于现有 `zwmopen/scripts` 在线更新地址：

- `chatgpt-conversation-tree.user.js`
- `chatgpt-cloud-prompts.json`

它们的唯一可编辑真源位于 `D:\AICode\工具开发\projects\chatgpt-conversation-tree`。映射关系见 [MIRRORS.md](MIRRORS.md)，同步与检查方法见 [MAINTENANCE.md](MAINTENANCE.md)。禁止直接编辑镜像。

ChatGPT 脚本的安装、使用和云提示词说明已经回到独立项目：

- `chatgpt-conversation-tree\docs\USAGE.md`
- `chatgpt-conversation-tree\docs\CLOUD-PROMPTS.md`

## 历史内容

- `archive/codexradar-monitor/`：已停止维护的实验。
- `archive/extracted-products/window-layout-launcher-legacy/`：从集合仓抽离的旧窗口布局快照；当前真源是独立项目 `window-layout-launcher`。

## 安全规则

- 批量移动、覆盖或删除默认只预览；写入模式必须显式开启。
- 配置只提交示例和安全默认值，不提交令牌、Cookie、账号和个人绝对路径。
- 发布前校验代码、版本、文档和受管镜像一致。
- 运行日志、缓存和临时文件不作为源码提交。

## 当前状态

- 可见范围：公开。
- 单一事实源：独立项目负责开发，本仓库负责必要的公开分发。
