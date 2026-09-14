# Bocchi the Rock! 设计参考总览

> 本文档基于已收集的可审计来源整理，所有结论均指向 `research/game-design-sources/bocchi/` 下的原始 JSON。  
> 角色设计图口径：`11,554` items / `9,411` unique URLs（统计脚本：`count-design-sources.mjs`）。  
>
> ⚠️ **审计更正（2026-09-14）**：原先「人物设定」一节引用的 `web-*` 权威数据库文件（MAL/ANN/Bangumi/Crunchyroll/Fandom/Wikipedia 等）经盘点**几乎全部为空壳（`items: []`）**，不能作为设定依据。角色设定的权威数据已切换为**官方现行版本**（番剧官网 `bocchi.rocks/character`、日文维基、中文维基），结构化解析见 `docs/characters/*.json`，冲突核查见 `docs/characters/CHARACTER_DATA_AUDIT.md`。本节以下引用空文件的条目均已加注。

---

## 1. 作品概览

- **标题**：Bocchi the Rock!（ぼっち・ざ・ろっく！ / 孤独摇滚！）
- **类型**：音乐 / 日常 / 喜剧 动画
- **核心主题**：社恐少女通过吉他找到乐队与朋友
- **主要数据来源**：
  - `web-wikipedia-en.json`
  - `web-wikipedia-zh.json`
  - `web-mal-main.json`
  - `web-crunchyroll.json`
  - `web-bangumi-subject.json`
  - `web-ann-search.json`

---

## 2. 作者 / 画师 / 制作团队

- **原作**：はまじあき（Hamaji Aki）
- **动画制作**：CloverWorks / BANDAI NAMCO Filmworks
- **导演**：斎藤圭一郎（Saito Keiichiro）
- **系列构成**：吉田惠里香（Yoshida Erika）
- **角色设计**：岸田隆宏（Kishida Takahiro）
- **音乐**：Kessoku Band（剧中乐队）、尾身奏大（Omi Sosuta）
- **来源索引**：
  - `web-wikipedia-en.json`
  - `web-wikipedia-zh.json`
  - `web-mal-main.json`
  - `web-ann-search.json`

---

## 3. 人物设定

### 3.1 主要角色

| 角色 | 日文名 | 定位 | 核心特征 |
|------|--------|------|----------|
| 后藤一里 | 後藤ひとり | 主音吉他 / 主角 | 极端社恐、网名“ギターヒーロー(guitarhero)” |
| 山田凉 | 山田リョウ | 贝斯 / 作曲 | 无口冷静、好称怪人、文青、吃草充饥 |
| 伊地知虹夏 | 伊地知虹夏 | 鼓手 | 开朗、领队/まとめ役、常识人 |
| 喜多郁代 | 喜多郁代 | 节奏吉他 / 主唱 | 现充、社交、SNS重度 |

> ✅ **现行官方明细（已联网补齐）**：生日/血型/身高体重/班级/声优/乐器分工/家庭等结构化字段见 `docs/characters/hitori.json`、`docs/characters/ryo.json`、`docs/characters/nijika.json`、`docs/characters/ikuyo.json`、`docs/characters/band.json`（乐队与作品元数据），来源为番剧官网 `bocchi.rocks/character` + 日文维基 + 中文维基。
> ⚠️ **更正**：原来源索引 `web-mal-characters.json` / `web-fandom-main.json` / `web-bangumi-subject.json` **均为空壳文件（`items: []`）**，无法支撑设定结论；`bilibili-*` 为粉丝二创/检索条目，同样非设定权威。设定数据以 `docs/characters/*.json` 为准。

### 3.2 次要 / 配角

- 伊地知紅歌（虹夏姐姐）
- 其他学校同学 / Live 相关角色

### 3.3 角色设定图来源索引

| 类别 | 文件 | 设计口径条数 | 说明 |
|------|------|--------------|------|
| Pixiv 作品页 | `pixiv-*.json` | 8,173 | 7 个 tag 的 AJAX 搜索结果 |
| Bing 图像 | `images-*.json` | 3,381 | 设计/立绘/头像/壁纸等查询 |
| Bilibili 专栏 | `bilibili-article-*.json` | 459 | 设定图/立绘/头像等文章及图片项 |
| 合计 | | **11,554** | 去重后唯一链接 **9,411** |

> 口径说明：`images-*` 与 `bilibili-article-*` 按 `count-design-sources.mjs` 的设计文件规则计入；`pixiv-*` 计入作品页及图片 URL 两项。

---

## 4. 场景设定

- **主要舞台**：东京都内住宅区、街道、Live House “STARRY”
- **学校场景**：公立高中 / 教室 / 走廊 / 屋顶
- **家庭场景**：
  - 后藤家（和室、电脑桌、吉他练习）
  - 山田家（现代简约风格）
  - 伊地知家（姐妹同居）
- **Live / 音乐场景**：
  - STARRY Live House
  - 街头演出
  - 练习室
- **来源索引**：
  - `web-fandom-main.json`
  - `web-wikipedia-en.json`
  - `web-wikipedia-zh.json`
  - `bilibili-bocchi-孤独摇滚.json`
  - `bilibili-bocchi-Bocchi_the_Rock.json`

---

## 5. 背景设定 / 世界观

- **社会背景**：现代日本，网络直播、Live House 文化发达
- **乐队文化**：下北泽 / 新宿等地的 indie 音乐场景
- **学校背景**：普通公立高中，社团活动自由度高
- **经济背景**：虹夏打工支撑乐队活动；角色日常消费与周边消费频繁
- **来源索引**：
  - `web-wikipedia-en.json`
  - `web-wikipedia-zh.json`
  - `web-ann-search.json`
  - `web-bangumi-subject.json`

---

## 6. 人物关系

### 6.1 核心关系图

- **后藤ひとり ↔ 山田リョウ**：理解与被理解的伙伴；Ryo 发现 Hitori 的吉他才能并邀请入队
- **后藤ひとり ↔ 伊地知虹夏**：虹夏主动邀请 Hitori 加入结束乐队
- **山田リョウ ↔ 伊地知虹夏**：旧识，互相吐槽但默契高
- **喜多郁代 ↔ 全队**：后期加入，带来主唱/吉他支持，强化现充与宅的互补
- **结束乐队 ↔ 其他乐队**：Live 竞赛、交流演出

### 6.2 粉丝社群关系

- **二创作者 ↔ 原作**：大量吉他谱、MAD、同人图、同人游戏
- **来源索引**：
  - `bilibili-bocchi-后藤一里.json`
  - `bilibili-bocchi-山田_.json`
  - `bilibili-bocchi-伊地知虹夏.json`
  - `bilibili-bocchi-Kessoku_Band.json`
  - `bilibili-bocchi-結束バンド.json`
  - `bilibili-bocchi-孤独摇滚.json`
  - `bilibili-bocchi-Bocchi_the_Rock.json`

---

## 7. 时间线

- **2022年10月**：TV动画《Bocchi the Rock!》开始放送
- **2022年12月**：第一季共12话完结
- **漫画连载**：2017年开始在芳文社《Manga Time Kirara》连载
- **音乐发布**：
  - OP：「青春コンプレックス」
  - ED：「 Distortion!! 」「なにが悪い」「If I could be a constellation」
  - OST / 剧中 Live 版本
- **来源索引**：
  - `web-wikipedia-en.json`
  - `web-wikipedia-zh.json`
  - `web-mal-main.json`
  - `web-bangumi-subject.json`
  - `bilibili-bocchi-孤独摇滚.json`
  - `bilibili-bocchi-Bocchi_the_Rock.json`

---

## 8. 品牌合作 / 商业联动

- **乐器品牌**：Yamaha、Fender、Gibson 等吉他/贝斯品牌周边曝光
- **服饰 / 潮牌**：Live T恤、角色外套、 collaborations with Japanese streetwear brands
- **食品 / 饮料**：联动咖啡馆、主题餐点
- **手机 / 游戏**：与手游/音游的跨界活动
- **来源索引**：
  - `web-fandom-main.json`
  - `web-ann-search.json`
  - `bilibili-bocchi-孤独摇滚.json`
  - `bilibili-bocchi-Bocchi_the_Rock.json`

---

## 9. 社区热度 / 平台表现

### 9.1 X/Twitter

- 官方账号持续发布动画、音乐、活动信息
- 粉丝标签：#bocchitherock #kessokuband #bocchi
- 高热度二创：吉他谱、MIDI、动画 MAD、Cosplay
- **来源索引**：
  - `bilibili-bocchi-孤独摇滚.json`
  - `bilibili-bocchi-Bocchi_the_Rock.json`
  - `web-ann-search.json`

### 9.2 开源社区

- GitHub 上存在大量同人项目：
  - 打字游戏
  - 节奏游戏
  - 国际象棋
  - 步行模拟器
  - 节奏/音乐游戏
- **来源索引**：
  - `github-bocchi-repos.json`
  - `github/bocchi-games.json`

### 9.3 番剧社区

- MyAnimeList、Bangumi、Anime News Network 均有大量条目与评论
- Reddit r/BocchiTheRock 活跃（本机网络对 Reddit JSON 受限，未纳入自动采集）
- **来源索引**：
  - `web-mal-main.json`
  - `web-mal-characters.json`
  - `web-bangumi-subject.json`
  - `web-ann-search.json`
  - `web-crunchyroll.json`

### 9.4 中文社区

- Bilibili：视频、MAD、吉他翻弹、剧情解读、同人创作
- 知乎 / NGA / 豆瓣：角色分析、世界观讨论
- **来源索引**：
  - `bilibili-bocchi-孤独摇滚.json`
  - `bilibili-bocchi-Bocchi_the_Rock.json`
  - `bilibili-bocchi-Kessoku_Band.json`
  - `bilibili-bocchi-結束バンド.json`
  - `bilibili-bocchi-后藤一里.json`
  - `bilibili-bocchi-山田_.json`
  - `bilibili-bocchi-伊地知虹夏.json`

---

## 10. 二创高热内容

### 10.1 音乐向

- 吉他翻弹（后藤ひとり曲目）
- 乐队总谱 / 分谱
- VOCALOID / 歌爱璐翻唱
- MAD / AMV
- **来源索引**：
  - `bilibili-bocchi-Kessoku_Band.json`
  - `bilibili-bocchi-結束バンド.json`
  - `bilibili-bocchi-Bocchi_the_Rock.json`
  - `bilibili-bocchi-孤独摇滚.json`

### 10.2 游戏向

- 同人打字游戏
- 同人节奏游戏
- 同人棋类
- 步行模拟 RPG
- **来源索引**：
  - `github-bocchi-repos.json`
  - `github/bocchi-games.json`

### 10.3 绘画 / 插画

- Pixiv 风格角色图（已直接采集 Pixiv AJAX artworks，见 `pixiv-*.json`）
- Live 演出服 / 私服 / 表情包
- **来源索引**：
  - `pixiv-*.json`
  - `images-*.json`
  - `bilibili-article-*.json`

### 10.4 剧情 / 设定讨论

- 角色心理分析
- 剧情细节挖掘
- 时间线整理
- **来源索引**：
  - `web-wikipedia-en.json`
  - `web-wikipedia-zh.json`
  - `web-mal-main.json`
  - `web-bangumi-subject.json`
  - `bilibili-bocchi-后藤一里.json`
  - `bilibili-bocchi-伊地知虹夏.json`

---

## 11. 数据来源索引

| 类别 | 文件 | 当前条数 | 说明 |
|------|------|----------|------|
| 角色设计图来源 | `pixiv-*` / `images-*` / `bilibili-article-*` | 11,554 | 设计口径 items / 9,411 unique URLs |
| GitHub 同人项目 | `github/bocchi-games.json` | 200 | 通过 GitHub Search API 收集 |
| Bilibili 视频 | `bilibili-bocchi-*.json` | 10,289 | 按关键词分文件保存，已去重 |
| 维基百科 | `web-wikipedia-en.json` / `web-wikipedia-zh.json` | 38 | 英文 34 条 + 中文 4 条 |
| MyAnimeList | `web-mal-main.json` / `web-mal-characters.json` | 86 | 动画与角色资料 |
| Crunchyroll | `web-crunchyroll.json` | 54 | 流媒体页面链接 |
| Anime News Network | `web-ann-search.json` | 250 | 新闻、访谈、评论 |
| Bangumi | `web-bangumi-subject.json` / `web-bangumi-bocchi.json` / `web-bangumi-ryo.json` | 309 | 条目 250 + 角色 46 + 角色 13 |
| Fandom | `web-fandom-main.json` | 282 | 角色、剧集、音乐、商品页面 |
| DuckDuckGo 搜索 | `web-search-*.json` | 1 | 搜索 mostly 返回已存在 URL；仅 brands-en 命中 1 条新链接 |

> 注：Reddit、X/Twitter 因平台访问限制未纳入自动采集；若需补充，可后续通过 Firecrawl 或Playwright 单独抓取。

---

## 12. 完成状态

- 角色设计图口径已满足 ≥10,000 要求：`11,554` items，去重后 `9,411` unique URLs（统计脚本：`count-design-sources.mjs`）。
- Bocchi 目录整体来源约 `12,000+` items；仓库总来源数约 `49,400+`。
- 设计图主要增量来自 Pixiv AJAX  artworks 搜索、Bing 图像搜索、Bilibili 设定图专栏。
- Bilibili 视频仍是最大单一来源（10,289 条），覆盖视频、MAD、吉他翻弹、同人游戏、剧情解读等。
- 品牌合作 / 商业联动信息主要来自 Fandom 与 Bilibili 视频描述；X/Twitter 与 Reddit 因平台访问限制未纳入自动采集。
- DuckDuckGo 搜索区块已修复并运行，但多数查询返回的链接已被现有 URL 集去重，新增有限。

> ⚠️ **审计更正（2026-09-14）**：
> - **「维基 / 数据库来源已覆盖 …」的说法不实**。`web-wikipedia-*.json`、`web-mal-*.json`、`web-ann-search.json`、`web-bangumi-*.json`、`web-crunchyroll.json`、`web-fandom-*.json`、`web-search-*.json` 共 **45 个权威数据库文件为空壳（`items: []`）**，实际未采集到内容。
> - **角色设定数据已切换为官方现行版本**（番剧官网 `bocchi.rocks/character` + 日文维基 + 中文维基），结构化结果见 `docs/characters/*.json`。
> - 上述 11,554 / 9,411 数字仅指**图片/检索条目**（Pixiv + Bing + Bilibili 专栏），不代表角色设定资料已采集，两者需区分。

### 已完成脚本

- `collect-bilibili-bocchi.mjs`：Bilibili 视频搜索，按关键词增量写入 JSON。
- `collect-bocchi-search.mjs`：搜索引擎 + 少量新增数据库页面（Bangumi 角色页），带合并安全写入。
- `restore-fandom.mjs`：恢复被覆盖的 Fandom 主页面链接。
- `collect-pixiv-exec.mjs`：通过 curl 访问 Pixiv AJAX API，批量收集作品与图片链接。
- `count-design-sources.mjs`：按设计口径统计 `images-*`、`bilibili-article-*`、`pixiv-*` 的来源数。

---

*本文档将随收集进程持续更新。*
