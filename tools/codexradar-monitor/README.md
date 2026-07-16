# CodexRadar 最佳模型监控

这个工具定时读取 [CodexRadar](https://codexradar.com/) 的“降智雷达”榜单，并同时维护两套结论：

- **当前轮结论**：当前能力最强、当前综合性价比
- **长期稳定结论**：最近 7 天的能力最强、日常默认

这样既能发现某一时段的临时变化，也不会因为单轮偶然 10/10 就频繁切换长期默认模型。

## 推送入口

- Issue：[`zwmopen/scripts#9`](https://github.com/zwmopen/scripts/issues/9)
- 默认检查时间：北京时间每天约 **09:10、15:10、18:10**
- GitHub Actions 的定时任务可能因平台负载延迟几分钟至更久
- 当前轮推荐变化时才评论；榜单更新但推荐不变时只保存数据

GitHub 网页通知默认可见。是否收到手机 App 推送和邮件，取决于 GitHub 的 Notifications 设置以及是否订阅该 Issue。

## 云端存档

Action 会自动维护：

```text
data/codexradar/
├── README.md       # 当前一轮的可读摘要
├── LONG_TERM.md    # 7 日滚动长期稳定建议
├── latest.json     # 最新结构化快照
├── rolling-7d.json # 长期统计的结构化结果
└── history.jsonl   # 历次新榜单，一行一个 JSON
```

相同榜单不会重复提交，因此不会每次定时检查都制造 commit。

## 当前轮推荐规则

### 当前能力最强

依次比较：

1. 通过数更高
2. IQ 更高
3. 费用更低
4. 耗时更短

### 当前综合性价比

先限制候选范围：

- 距离本轮最高通过数不超过 1 题
- IQ 不低于 90

再优先选择：

1. 每道通过题的成本更低
2. 总费用更低
3. 耗时更短
4. 通过数和 IQ 更高

当前轮结果用于临时切换、疑难任务升级和降智排查，不等于长期默认。

## 长期稳定推荐规则

`long_term.py` 读取 `history.jsonl`，以最近 7 天为滚动窗口。

### 样本门槛

- 少于 4 轮：只展示统计，**不下长期结论**
- 4–7 轮：给出暂定结论
- 8 轮及以上且覆盖率足够：标记为稳定
- 某模型在窗口内覆盖不足 60%：不参与长期冠军判断

### 长期能力最强

依次比较：

1. 中位通过数
2. 平均通过数
3. 通过数标准差，越低越稳定
4. 最差轮次
5. 平均 IQ
6. 平均费用

这会降低单轮异常高分对结果的影响。

### 长期日常默认

先筛选：

- 平均通过数距离最佳不超过 1 题
- 平均 IQ 不低于 90

再优先选择：

1. 平均每道通过题成本更低
2. 波动更小
3. 平均费用更低
4. 平均耗时更短
5. 中位通过数和平均通过数更高

因此长期能力最强和长期日常默认可能不是同一个模型：前者用于疑难任务与最终验收，后者用于普通开发和持续执行。

## Codex 使用原则

- 日常启动任务时，优先读取 `data/codexradar/LONG_TERM.md`
- 单轮榜首只用于临时切换，不永久改默认
- 普通任务使用长期日常默认
- 疑难任务、最终验收使用长期能力最强
- 当前默认连续失败时，再参考当前轮榜单升级
- 模型代际或名称变化后重新累计，不继承上一代结论

## 工作流

文件：`.github/workflows/codexradar-monitor.yml`

支持：

- 定时执行
- GitHub Actions 页面手动执行 `workflow_dispatch`
- 使用仓库自带 `GITHUB_TOKEN` 评论 Issue 和提交数据
- 无需外部 Token、邮箱密码或第三方推送密钥
- 解析失败时直接失败，不发布可能错误的推荐
- 每轮抓取后自动重算 7 日滚动结果

## 本地测试

```bash
python3 tools/codexradar-monitor/test_monitor.py
python3 tools/codexradar-monitor/test_long_term.py
python3 tools/codexradar-monitor/monitor.py
python3 tools/codexradar-monitor/long_term.py
```

也可以用本地 HTML 文件测试当前轮解析：

```bash
python3 tools/codexradar-monitor/monitor.py --html-file page.html
```

## 页面历史数据边界

CodexRadar 页面展示历史曲线时间轴，但网页可读文本不一定完整暴露每个模型的全部历史曲线点。仓库不会根据不完整的图表文本猜测数值，而是从监控启用后自行累计每一轮完整表格。

CodexRadar 当前也没有公开提供完整模型榜单 JSON；公开的 `current.json` 主要用于额度重置雷达。因此本工具解析主页当前指标表格，再用自己的 `history.jsonl` 计算长期稳定结论。

如果站点调整表格字段或名称，监控会失败并在 GitHub Actions 中显示红色，而不是根据残缺数据发表评论。此时应根据新的页面结构更新解析器和测试样例。
