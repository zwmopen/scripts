# CodexRadar 最佳模型监控

这个工具定时读取 [CodexRadar](https://codexradar.com/) 的“降智雷达”榜单，自动判断：

- 当前能力最强模型
- 当前综合性价比模型
- 榜单数据更新时间
- 各模型的通过数、IQ、费用与耗时

推荐发生变化时，GitHub Action 会在固定 Issue 中发表评论并 `@zwmopen`。

## 推送入口

- Issue：[`zwmopen/scripts#9`](https://github.com/zwmopen/scripts/issues/9)
- 默认检查时间：北京时间每天约 **09:10、15:10、18:10**
- GitHub Actions 的定时任务可能因平台负载延迟几分钟至更久
- 只有推荐变化时才评论；榜单更新但推荐不变时只保存数据

GitHub 网页通知默认可见。是否收到手机 App 推送和邮件，取决于 GitHub 的 Notifications 设置以及是否订阅该 Issue。

## 云端存档

Action 会自动维护：

```text
data/codexradar/
├── README.md       # 当前推荐的可读摘要
├── latest.json     # 最新结构化快照
└── history.jsonl   # 历次新榜单，一行一个 JSON
```

相同榜单不会重复提交，因此不会每次定时检查都制造 commit。

## 推荐规则

### 能力最强

依次比较：

1. 通过数更高
2. IQ 更高
3. 费用更低
4. 耗时更短

### 综合性价比

先限制候选范围：

- 距离本轮最高通过数不超过 1 题
- IQ 不低于 90

再优先选择：

1. 每道通过题的成本更低
2. 总费用更低
3. 耗时更短
4. 通过数和 IQ 更高

这样可以避免只因某个低价模型很便宜，就把明显低通过率的组合推荐为日常默认；也可以避免 `max` / `xhigh` 只因档位名更高就自动获胜。

## 工作流

文件：`.github/workflows/codexradar-monitor.yml`

支持：

- 定时执行
- GitHub Actions 页面手动执行 `workflow_dispatch`
- 使用仓库自带 `GITHUB_TOKEN` 评论 Issue 和提交数据
- 无需外部 Token、邮箱密码或第三方推送密钥
- 解析失败时直接失败，不发布可能错误的推荐

定时工作流只有合并到仓库默认分支后才会自动运行。

## 本地测试

```bash
python3 tools/codexradar-monitor/test_monitor.py
python3 tools/codexradar-monitor/monitor.py
```

也可以用本地 HTML 文件测试解析：

```bash
python3 tools/codexradar-monitor/monitor.py --html-file page.html
```

## 页面变化时

CodexRadar 目前没有公开提供完整模型榜单 JSON；公开的 `current.json` 主要用于额度重置雷达。因此本工具解析主页的公开指标表格。

如果站点调整表格字段或名称，监控会失败并在 GitHub Actions 中显示红色，而不是根据残缺数据发表评论。此时应根据新的页面结构更新解析器和测试样例。
