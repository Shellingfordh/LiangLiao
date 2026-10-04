# research/taptap-pages —— TapTap Maker 文档抓取快照（**不可作为 API 依据**）

抓取日期约 2026-09-11。本目录**曾经**是项目的平台文档来源，现已判定无效：

- 原 38 份 HTML 中 **27 份 byte 级完全相同**（md5 `f4f7eb90898b9ca78919e4a7e85a2c4d`，各 345,407 字节），
  内容是 TapTap 登录墙；`_index.json` 里每条的 `title` 都是 `"登录 | TapTap"`，
  而 `status: 200` 具有误导性——HTTP 200 返回的是登录页而不是文档。
- 2026-09-19 已删除其中 26 份重复副本，仅保留 `api.html` 一份作为「登录墙长什么样」的样本。
  `_index.json` / `_index2.json` / `_index3.json` 未改动，仍保留被删条目的抓取记录，
  用于证明当初的抓取失败范围。
- 受影响的 27 份：`api`、`api-engine`、`api-game`、`api-script`、`api-taptap`、`changelog`、
  `examples`、`faq`、`forge-en`、`forge-home`、`forge-zh`、`guide`、`guide-asset`、`guide-deploy`、
  `guide-export`、`guide-monetize`、`guide-multiplayer`、`guide-publish`、`guide-pvp`、`guide-run`、
  `guide-script`、`home`、`intro`、`intro-what`、`quickstart`、`sdk`、`showcase`（均 `.html`）。

## 现在用什么代替

Maker 引擎与 Lua API 的唯一依据是本地 AI Dev Kit：`engine-docs/`、`.emmylua/`、`examples/`、
`templates/`、`urhox-libs/`。逐项验证结论见 `docs/maker-lua-api-verification.md`。

## 仍然有效的部分

剩下 11 份是真实抓到的页面（应用详情页、排行榜、Maker 首页、`doc-27*.html` 等），
仅作历史留存，不用于推导 API 或资产大小限制。
