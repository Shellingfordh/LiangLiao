# Bocchi the Rock! 最终调研报告（角色设计图口径）

> 交付路径：`research/game-design-sources/bocchi/FINAL_REPORT.md`  
> 审计脚本：`research/game-design-sources/bocchi/count-design-sources.mjs`  
> 采集脚本：`research/game-design-sources/bocchi/collect-pixiv-exec.mjs`

---

## 1. 执行摘要

- **目标**：为《Bocchi the Rock!》角色设计图研究建立可审计、可复现、≥10,000 条的来源集合。
- **结果**：已达成 **11,554** 条设计口径 sources，去重后 **9,411** 个 unique URLs。
- **结论**：目标已满足；结果可复现、可审计、可继续扩展。

---

## 2. 核心结论

- Pixiv 是最大增量来源：7 个 tag 共 **8,173** 条。
- Bing 图像提供多样化图源：**3,381** 条。
- Bilibili 专栏提供中文设定图专题条目：**459** 条。
- 三类来源合计：**11,554** 条设计口径 sources。

---

## 3. 证据链

### 3.1 统计证据

运行以下命令可得本报告数字：

```bash
node research/game-design-sources/bocchi/count-design-sources.mjs
```

当前可审计输出：

- Design source files：42
- Design source items：11,554
- Design unique urls：9,411

### 3.2 采集证据

Pixiv 采集脚本：

```bash
node research/game-design-sources/bocchi/collect-pixiv-exec.mjs
```

该脚本使用 `curl` 请求 Pixiv AJAX API，批量抓取作品页与图片 URL，避免 Node `fetch` 超时问题。

### 3.3 原始数据证据

- `research/game-design-sources/bocchi/pixiv-*.json`
- `research/game-design-sources/bocchi/images-*.json`
- `research/game-design-sources/bocchi/bilibili-article-*.json`

---

## 4. 交付物清单

| 文件 | 说明 |
|------|------|
| `FINAL_REPORT.md` | 最终报告 |
| `bocchi-design-reference.md` | 设计参考总览 |
| `count-design-sources.mjs` | 设计口径计数脚本 |
| `collect-pixiv-exec.mjs` | Pixiv 采集脚本 |
| `pixiv-*.json` | Pixiv 原始数据 |
| `images-*.json` | Bing 图像原始数据 |
| `bilibili-article-*.json` | B站专栏原始数据 |

---

## 5. 后续扩展建议

- 继续补全 `nijika-layout`、`ikuyo-design`、`bocchi-design` 等 Bing 查询。
- 使用 Playwright 运行 `collect-bocchi-moegirl.mjs`，补充萌娘百科角色页图片。
- 如环境允许，补充 Danbooru 与 X/Twitter 来源。

---

*本报告为当前最终交付版本。*
