---@meta
-- 项目侧类型增补：引擎 .emmylua/__manual_types.d.lua 的 `common` 只声明了 get_map_name，
-- 但 common.get_server_time() 确实存在于运行时（engine-docs/recipes/server-time.md）。
-- 这里只补声明，不改引擎目录。

---@class common
---@field get_server_time fun(): integer 权威 Unix 秒（UTC 基准），用户改系统时间无效
