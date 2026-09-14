# 孤独摇滚角色设定数据核查报告（CHARACTER_DATA_AUDIT）

> 核查日期：2026-09-14
> 范围：`research/game-design-sources/bocchi/` 下后藤一里、山田凉、伊地知虹夏、喜多郁代、结束バンド的设定数据
> 结论：把数据切换到**官方现行版本**（番剧官网 + 日文维基 + 中文维基），补齐了结构化解析版本（`parsed/*.json`），并核查了跨来源冲突。

---

## 一、核心发现

1. **本地权威来源文件几乎全是空壳**。`research/game-design-sources/bocchi/` 下 124 个 JSON 中 **45 个为 `items: []`**，包括全部 `web-*` 权威数据库文件：`web-mal-main.json`、`web-mal-characters.json`、`web-ann-search.json`、`web-bangumi-subject.json`、`web-crunchyroll.json`、`web-fandom-*.json`、`web-wikipedia-*.json`、`web-search-*.json`。完整清单见附录 A。
2. **`bocchi-design-reference.md` 存在悬空引用**。该文档第 3/11/12 节以这些空文件为设定依据，并宣称「11,554 items / 9,411 unique URLs」——但实际这些文件没有可审计内容，设定结论无真实来源支撑。
3. **本地有真实内容的**是 bilibili 视频/专栏、pixiv 图片的 URL 检索条目（79 个文件），属于**粉丝二创/检索产物**，不能作为设定权威，仅作「民间说法」对照。
4. **权威数据已联网补齐**（来源：番剧官网 `bocchi.rocks/character`、日文维基「ぼっち・ざ・ろっく!」、中文维基「孤獨搖滾！」），完整明细见 `parsed/*.json`。

---

## 二、四角色 × 核心字段对照表

权威裁决规则：**番剧官网 > 日文维基 > 中文维基 > 本地二手材料**。日文维基为最详尽源，包含身高体重等中维/官网未收录字段。

### 2.1 後藤ひとり（后藤一里 / Gotoh Hitori）

| 字段 | 官方现行数据 | 本地材料说法 | 是否冲突 | 裁决 |
|---|---|---|---|---|
| 生日 | 2月21日 | （本地无结构数据） | 无冲突 | 官网系谱/维基一致 |
| 血型 | O型 | 无 | — | 维基一致 |
| 班级 | 秀華高中1年2組 | 无 | — | 维基一致 |
| 声优 | 青山吉能（日）/閻麼麼（陆）/邱涵菲（台） | 无 | — | 官网+维基一致 |
| 乐器 | 主音吉他、作词 | 无 | — | 官网 Gt.HITORI 一致 |
| 学校 | 秀華高校（私立） | 无 | — | 维基一致 |
| 家庭 | 父後藤直樹・母美智代・妹ふたり・狗ジミヘン | 无 | — | 维基一致 |
| 昵称 | ぼっちちゃん（小孤獨/小波奇），リョウ取名 | 无 | — | 维基一致 |

**注**：2年級班級表記有**跨卷冲突**（单行本4卷=2年3組、6卷=2年C組），作者2024-05确认为 **2年3組**。这是作品内部资料口径冲突，非来源冲突，已标注。

### 2.2 山田リョウ（山田凉 / Yamada Ryo）

| 字段 | 官方现行数据 | 本地材料说法 | 是否冲突 | 裁决 |
|---|---|---|---|---|
| 生日 | 9月18日 | 无 | — | 官网系谱/维基一致 |
| 血型 | AB型 | 无 | — | 维基一致 |
| 年级 | 下北澤高校2年→3年 | 无 | — | 维基一致 |
| 声优 | 水野朔（日）/張雨曦（陆）/連思宇（台） | 无 | — | 官网+维基一致 |
| 乐器 | 贝斯、作曲（动画版和声） | 无 | — | 官网 Ba.RYO 一致 |
| 性格 | 無口・無表情・好稱怪人・文青・吃草充飢 | 无 | — | 维基一致 |
| 家庭 | 父母经营医院，富裕但钱全买乐器 | 无 | — | 维基一致 |
| 设定演变 | 最初是「不思議ちゃん系可愛」设定 | 无 | — | 维基记录（内部演变） |

### 2.3 伊地知虹夏（Ijichi Nijika）

| 字段 | 官方现行数据 | 本地材料说法 | 是否冲突 | 裁决 |
|---|---|---|---|---|
| 生日 | 5月29日 | 无 | — | 官网系谱/维基一致 |
| 血型 | A型 | 无 | — | 维基一致 |
| 年级 | 下北澤高校2年→3年 | 无 | — | 维基一致 |
| 声优 | 鈴代紗弓（日）/姜英俊（陆）/李昀晴（台） | 无 | — | 官网+维基一致 |
| 乐器 | 鼓手 | 无 | — | 官网 Dr.NIJIKA 一致 |
| 性格 | 開朗・領隊・まとめ役・常識人吐槽役 | 无 | — | 维基一致 |
| 家庭 | 母去世、父在外、與姐星歌兩人生活 | 无 | — | 维基一致 |
| 乐队角色 | 領隊・經理・設計・視頻剪輯 | 无 | — | 维基一致 |

### 2.4 喜多郁代（Kita Ikuyo）

| 字段 | 官方现行数据 | 本地材料说法 | 是否冲突 | 裁决 |
|---|---|---|---|---|
| 生日 | 4月21日 | 无 | — | 官网系谱/维基一致 |
| 血型 | A型 | 无 | — | 维基一致 |
| 班级 | 秀華高中1年5組（2年级后与一里同班） | 无 | — | 维基一致 |
| 声优 | 長谷川育美（日）/閆夜橋（陆）/張乃文（台） | 无 | — | 官网+维基一致 |
| 乐器 | 节奏吉他、主唱 | 无 | — | 官网 Gt.Vo.IKUYO 一致 |
| 性格 | 社交型陽キャ・SNS重度・爱打扮逛街 | 无 | — | 维基一致 |
| 名字情结 | 对「郁代」名字自卑，只报姓 | 无 | — | 维基一致 |

> 四角色 × 7 核心字段 = **28 格全部有官方数据**，无空项。本地 `bocchi/*.json` 无结构性角色描述（均为检索/二创条目），故未发现本地与官方的直接设定冲突；本报告主要揭示的是**「本地权威来源缺失 / 悬空引用」**这一结构性问题。

---

## 三、真正的「冲突」清单（需要修正的）

| # | 冲突/问题 | 现状 | 修正 |
|---|---|---|---|
| C1 | **权威来源空壳** | 45 个 `web-*.json` 为 `items:[]` | 以官方现行数据补齐（见 `parsed/`），原文件保留 |
| C2 | **bocchi-design-reference.md 悬空引用** | 引用空文件、宣称 11,554/9,411 | 标注「原引用文件为空」，改指向 parsed 官方数据 |
| C3 | **设置地点中文译名不一** | 結束バンド 大陆=纽带/结束乐队、台湾=团结Band | 三译名并存，注释说明（非数据错误） |
| C4 | **一里二年级班级跨卷矛盾** | 4卷 2年3組 vs 6卷 2年C組 | 以作者2024-05确认为准=2年3組 |
| C5 | **作品年表易混淆** | 连载开始时间：2017-12-19 客串 vs 2018-03-19 正式连载 | 客串/正式分列，均已标注 |

---

## 四、解析版本交付物

| 文件 | 内容 | 字段数 |
|---|---|---|
| `parsed/hitori.json` | 后藤一里官方设定 | 14 |
| `parsed/ryo.json` | 山田凉官方设定 | 14 |
| `parsed/nijika.json` | 伊地知虹夏官方设定 | 12 |
| `parsed/ikuyo.json` | 喜多郁代官方设定 | 12 |
| `parsed/band.json` | 結束バンド + 作品元数据 | 7+6 |
| `parsed/_raw/characters_official.md` | 权威来源原始摘录 | — |
| `parsed/_inventory.json` | 本地 124 个文件盘点 | — |

每个字段含 `value`、`source`、`source_authority`（high=官网/维基）。

---

## 附录 A：空壳来源文件清单（45 个）

```
bilibili-article-Bocchi_the_Rock_official_art.json
bilibili-article-伊地知虹夏_设定图.json
bilibili-article-後藤一里_壁紙.json
bilibili-article-後藤一里_头像.json
bilibili-article-後藤一里_立绘.json
bilibili-article-喜多郁代_头像.json
bilibili-article-孤独摇滚_角色设定.json
bilibili-article-山田_头像.json
bilibili-bocchi-articles.json
images-bocchi-charart.json
images-bocchi-design-zh.json
images-bocchi-illustration-jp.json
images-bocchi-illustration.json
images-bocchi-keyvisual.json
images-bocchi-layout-zh.json
images-bocchi-material-zh.json
images-bocchi-material.json
images-bocchi-officialart.json
images-hitori-avatar.json
images-ikuyo-avatar.json
images-kessoku-design-jp.json
images-kessoku-illustration-jp.json
images-nijika-avatar.json
images-ryo-avatar.json
reddit-bocchi-extra.json
web-ann-search.json
web-bangumi-subject.json
web-crunchyroll.json
web-fandom-characters.json
web-fandom-collabs.json
web-fandom-episodes.json
web-fandom-merchandise.json
web-fandom-music.json
web-mal-characters.json
web-mal-main.json
web-search-bilibili-article.json
web-search-brands-zh.json
web-search-fanart.json
web-search-fancreation-zh.json
web-search-niconico.json
web-search-opensource-zh.json
web-search-opensource.json
web-search-reddit.json
web-search-twitter-en.json
web-search-twitter-zh.json
```
