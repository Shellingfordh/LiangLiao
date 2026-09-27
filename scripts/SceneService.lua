-- ============================================================================
-- SceneService.lua — 场景状态包与 2.5D 生活痕迹的唯一声明处（M4 §5/§6）
-- 四城 × {居所 / 工作场所 / 公共停留处 / 街区或通勤过渡处} = 16 个原创 4:3 场景包；
-- 每个包一次声明背景、色温、主光方向、人物站位、接地阴影、无骨骼微动、
-- 生活痕迹锚点与未来 3D 锚点（future3D 只预留，不改变事件或存档语义）。
-- 状态窗、档案页与回复事实共用 StateFor 产出的同一份 SceneState；
-- 场景缺包必须显式回退（missing-package），绝不沿用旧图假称已切换。
-- 骨骼动作不是本模块的前置条件：microMotion 全部是无骨骼程序化微动
-- （呼吸 / 重心 / 朝向 / 镜头），接入骨骼要等 GLB→MDL→真机播放三道门全过。
-- ============================================================================

local SceneService = {}

-- 资源路径与 docs/asset-provenance.md 的登记一一对应；全部为 Maker 生成的原创 4:3 静帧。
-- Maker 生成器对 aspect_ratio=4:3/target_size=1152x864 实际交付了 1296x864（3:2），已按画面中心
-- 裁左右各 72px 转成精确 4:3；本文件所有归一化 x/scale 已按 x'=(x*1296-72)/1152 同步重映射。
local BG = {
    la_apartment = "image/la-apartment-night_20260924155332.png",
    la_studio = "image/la-studio-day_20260924155332.png",
    la_cafe = "image/la-cafe-night_20260924155332.png",
    la_commute = "image/la-street-dusk_20260924155332.png",
    sha_apartment = "image/sha-apartment-morning_20260924155332.png",
    sha_office = "image/sha-office-day_20260924155332.png",
    sha_bookstore = "image/sha-bookstore-night_20260924155332.png",
    sha_commute = "image/sha-street-morning_20260924155332.png",
    cdu_apartment = "image/cdu-apartment-day_20260924155606.png",
    cdu_studio = "image/cdu-studio-day_20260924155606.png",
    cdu_cafe = "image/cdu-teahouse-day_20260924155606.png",
    cdu_commute = "image/cdu-nightmarket-street_20260924155606.png",
    lon_apartment = "image/lon-apartment-rain-night_20260924155606.png",
    lon_studio = "image/lon-studio-recording_20260924155606.png",
    lon_recordshop = "image/lon-recordshop-interior_20260924155606.png",
    lon_commute = "image/lon-street-rain-dusk_20260924155606.png",
}

---@class SceneGroundShadow
---@field anchorX number 归一化画面坐标（接地阴影中心）
---@field anchorY number
---@field rx number 横向半径（画面宽的比例）
---@field ry number 纵向半径（画面高的比例）
---@field alpha integer 0-255，两层叠加的峰值不透明度

---@class SceneTraceAnchor
---@field x number 归一化横坐标（痕迹中心）
---@field y number 归一化纵坐标
---@field scale number 痕迹宽度占画面宽的比例
---@field layer integer 叠放层级（越大越靠上）

---@class ScenePackage
---@field id string sceneId（= TimeState 前缀_place）
---@field cityId string
---@field type string home|work|public|transit
---@field label string 档案页可读的场景名
---@field backgroundKey string
---@field backgroundPath string
---@field colorTemperature integer 开尔文，主光色温
---@field keyLightDirection { x: number, y: number, z: number } 光源相对人物的位置向量（主光来向）
---@field characterPlacement { x: number, y: number, z: number, side: string } RT 场景内站位；side 决定相机让位方向
---@field groundShadow SceneGroundShadow
---@field microMotion string breathe|sway|turn|dolly（全部为无骨骼程序化微动）
---@field traceAnchor SceneTraceAnchor
---@field future3D { sceneRef: string, anchorId: string } 未来 3D 场景复用同一锚点，不改事件/存档语义

--- 16 个包的站位与阴影中心必须和静帧的留白侧一致：
--- 全部留白在右侧（side=right、站位 x=+0.55），唯一例外是唱片行——柜台动线在左，
--- 人物与阴影一起走左侧（side=left）。
--- 两格锚点不是一回事，别一起调：**anchorY 对齐静帧里画出来的地板线**，所以逐张不同
--- （0.86/0.87/0.88），取景反过来要按它解算相机高度（见 StatusWindow.frameFixedCamera）；
--- **anchorX 是她脚底的投影 x**，与美术无关。原来那对 0.68/0.32 把阴影往画面中心拉了
--- 0.029~0.030 画面宽（约阴影半宽的 30%），她的脚落在阴影外侧，读起来仍是「没踩上」。
--- 现值由 `.tmp/poc/m4_ground_contact.lua` 逐张量出（16 张只有 0.709/0.290 两个数：
--- 取景位移是常量 viewW*0.21*side，站位 x 也只有 0.55/−0.5 两种），同支探针 K4 带符号
--- 盯着这条，改取景或改站位就会红。
---@type table<string, ScenePackage>
local PACKAGES = {
    la_apartment = {
        id = "la_apartment", cityId = "los_angeles", type = "home", label = "洛杉矶的公寓",
        backgroundKey = "la_apartment", backgroundPath = BG.la_apartment,
        colorTemperature = 3000, keyLightDirection = { x = -1.2, y = 1.6, z = 1.0 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.86, rx = 0.0956, ry = 0.028, alpha = 167 },
        microMotion = "breathe",
        traceAnchor = { x = 0.1175, y = 0.79, scale = 0.1575, layer = 2 },
        future3D = { sceneRef = "scene/la_apartment", anchorId = "la_apartment_desk_01" },
    },
    la_studio = {
        id = "la_studio", cityId = "los_angeles", type = "work", label = "洛杉矶的工作室",
        backgroundKey = "la_studio", backgroundPath = BG.la_studio,
        colorTemperature = 5600, keyLightDirection = { x = 1.4, y = 1.5, z = 0.8 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.87, rx = 0.0956, ry = 0.026, alpha = 133 },
        microMotion = "sway",
        traceAnchor = { x = 0.1625, y = 0.75, scale = 0.1687, layer = 2 },
        future3D = { sceneRef = "scene/la_studio", anchorId = "la_studio_table_01" },
    },
    la_cafe = {
        id = "la_cafe", cityId = "los_angeles", type = "public", label = "「塞法尔东非」咖啡馆",
        backgroundKey = "la_cafe", backgroundPath = BG.la_cafe,
        colorTemperature = 2900, keyLightDirection = { x = -0.8, y = 1.8, z = 0.9 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.86, rx = 0.0956, ry = 0.028, alpha = 182 },
        microMotion = "breathe",
        traceAnchor = { x = 0.14, y = 0.78, scale = 0.1462, layer = 2 },
        future3D = { sceneRef = "scene/la_cafe", anchorId = "la_cafe_counter_01" },
    },
    la_commute = {
        id = "la_commute", cityId = "los_angeles", type = "transit", label = "洛杉矶的街区",
        backgroundKey = "la_commute", backgroundPath = BG.la_commute,
        colorTemperature = 3500, keyLightDirection = { x = -1.6, y = 0.9, z = 0.6 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.88, rx = 0.1012, ry = 0.024, alpha = 148 },
        microMotion = "turn",
        traceAnchor = { x = 0.1625, y = 0.82, scale = 0.1575, layer = 2 },
        future3D = { sceneRef = "scene/la_commute", anchorId = "la_commute_busstop_01" },
    },
    sha_apartment = {
        id = "sha_apartment", cityId = "shanghai", type = "home", label = "上海的公寓",
        backgroundKey = "sha_apartment", backgroundPath = BG.sha_apartment,
        colorTemperature = 3400, keyLightDirection = { x = -1.3, y = 1.4, z = 0.9 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.86, rx = 0.0956, ry = 0.028, alpha = 160 },
        microMotion = "breathe",
        traceAnchor = { x = 0.1288, y = 0.77, scale = 0.1575, layer = 2 },
        future3D = { sceneRef = "scene/sha_apartment", anchorId = "sha_apartment_balcony_01" },
    },
    sha_office = {
        id = "sha_office", cityId = "shanghai", type = "work", label = "报社的版房",
        backgroundKey = "sha_office", backgroundPath = BG.sha_office,
        colorTemperature = 5000, keyLightDirection = { x = 0.2, y = 2.0, z = 0.7 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.87, rx = 0.0956, ry = 0.026, alpha = 125 },
        microMotion = "sway",
        traceAnchor = { x = 0.1625, y = 0.75, scale = 0.1687, layer = 2 },
        future3D = { sceneRef = "scene/sha_office", anchorId = "sha_office_typesetting_01" },
    },
    sha_bookstore = {
        id = "sha_bookstore", cityId = "shanghai", type = "public", label = "街角的旧书店",
        backgroundKey = "sha_bookstore", backgroundPath = BG.sha_bookstore,
        colorTemperature = 2800, keyLightDirection = { x = 1.2, y = 1.3, z = 0.8 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.86, rx = 0.0956, ry = 0.028, alpha = 182 },
        microMotion = "breathe",
        traceAnchor = { x = 0.14, y = 0.78, scale = 0.1575, layer = 2 },
        future3D = { sceneRef = "scene/sha_bookstore", anchorId = "sha_bookstore_counter_01" },
    },
    sha_commute = {
        id = "sha_commute", cityId = "shanghai", type = "transit", label = "上海的街区",
        backgroundKey = "sha_commute", backgroundPath = BG.sha_commute,
        colorTemperature = 4500, keyLightDirection = { x = -1.5, y = 1.0, z = 0.7 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.88, rx = 0.1012, ry = 0.024, alpha = 137 },
        microMotion = "turn",
        traceAnchor = { x = 0.1625, y = 0.83, scale = 0.1687, layer = 2 },
        future3D = { sceneRef = "scene/sha_commute", anchorId = "sha_commute_station_01" },
    },
    cdu_apartment = {
        id = "cdu_apartment", cityId = "chengdu", type = "home", label = "成都的公寓",
        backgroundKey = "cdu_apartment", backgroundPath = BG.cdu_apartment,
        colorTemperature = 4000, keyLightDirection = { x = 1.3, y = 1.5, z = 0.9 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.86, rx = 0.0956, ry = 0.028, alpha = 152 },
        microMotion = "breathe",
        traceAnchor = { x = 0.14, y = 0.77, scale = 0.1575, layer = 2 },
        future3D = { sceneRef = "scene/cdu_apartment", anchorId = "cdu_apartment_desk_01" },
    },
    cdu_studio = {
        id = "cdu_studio", cityId = "chengdu", type = "work", label = "成都的画室",
        backgroundKey = "cdu_studio", backgroundPath = BG.cdu_studio,
        colorTemperature = 4800, keyLightDirection = { x = 1.4, y = 1.6, z = 0.8 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.87, rx = 0.0956, ry = 0.026, alpha = 133 },
        microMotion = "sway",
        traceAnchor = { x = 0.1625, y = 0.75, scale = 0.1575, layer = 2 },
        future3D = { sceneRef = "scene/cdu_studio", anchorId = "cdu_studio_easel_01" },
    },
    cdu_cafe = {
        id = "cdu_cafe", cityId = "chengdu", type = "public", label = "老式茶馆",
        backgroundKey = "cdu_cafe", backgroundPath = BG.cdu_cafe,
        colorTemperature = 3600, keyLightDirection = { x = -1.2, y = 1.7, z = 0.7 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.87, rx = 0.0956, ry = 0.027, alpha = 156 },
        microMotion = "breathe",
        traceAnchor = { x = 0.1625, y = 0.79, scale = 0.1462, layer = 2 },
        future3D = { sceneRef = "scene/cdu_cafe", anchorId = "cdu_cafe_bamboo_table_01" },
    },
    cdu_commute = {
        id = "cdu_commute", cityId = "chengdu", type = "transit", label = "夜市街口",
        backgroundKey = "cdu_commute", backgroundPath = BG.cdu_commute,
        colorTemperature = 2700, keyLightDirection = { x = -1.5, y = 1.1, z = 0.8 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.88, rx = 0.1012, ry = 0.024, alpha = 182 },
        microMotion = "turn",
        traceAnchor = { x = 0.1625, y = 0.8, scale = 0.1575, layer = 2 },
        future3D = { sceneRef = "scene/cdu_commute", anchorId = "cdu_commute_stall_01" },
    },
    lon_apartment = {
        id = "lon_apartment", cityId = "london", type = "home", label = "伦敦的公寓",
        backgroundKey = "lon_apartment", backgroundPath = BG.lon_apartment,
        colorTemperature = 2900, keyLightDirection = { x = -1.2, y = 1.4, z = 0.9 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.86, rx = 0.0956, ry = 0.028, alpha = 175 },
        microMotion = "breathe",
        traceAnchor = { x = 0.14, y = 0.76, scale = 0.1575, layer = 2 },
        future3D = { sceneRef = "scene/lon_apartment", anchorId = "lon_apartment_desk_01" },
    },
    lon_studio = {
        id = "lon_studio", cityId = "london", type = "work", label = "学院的录音棚",
        backgroundKey = "lon_studio", backgroundPath = BG.lon_studio,
        colorTemperature = 6500, keyLightDirection = { x = 0.1, y = 2.0, z = 0.7 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.87, rx = 0.0956, ry = 0.026, alpha = 122 },
        microMotion = "sway",
        traceAnchor = { x = 0.1625, y = 0.77, scale = 0.1575, layer = 2 },
        future3D = { sceneRef = "scene/lon_studio", anchorId = "lon_studio_console_01" },
    },
    -- 唱片行的留白与柜台上在左侧：人物站位、接地阴影、相机让位三处必须一起翻到左边，
    -- 否则人就会像贴在右侧的独立贴图（M4 验收 3 点名的缺陷形态）。
    lon_recordshop = {
        id = "lon_recordshop", cityId = "london", type = "public", label = "老唱片行",
        backgroundKey = "lon_recordshop", backgroundPath = BG.lon_recordshop,
        colorTemperature = 3200, keyLightDirection = { x = 1.1, y = 1.6, z = 0.8 },
        characterPlacement = { x = -0.5, y = 0.0, z = 0.0, side = "left" },
        groundShadow = { anchorX = 0.29, anchorY = 0.86, rx = 0.0956, ry = 0.028, alpha = 171 },
        microMotion = "breathe",
        traceAnchor = { x = 0.815, y = 0.76, scale = 0.1575, layer = 2 },
        future3D = { sceneRef = "scene/lon_recordshop", anchorId = "lon_recordshop_turntable_01" },
    },
    lon_commute = {
        id = "lon_commute", cityId = "london", type = "transit", label = "雨中的伦敦街区",
        backgroundKey = "lon_commute", backgroundPath = BG.lon_commute,
        colorTemperature = 3000, keyLightDirection = { x = 1.5, y = 1.2, z = 0.7 },
        characterPlacement = { x = 0.55, y = 0.0, z = 0.0, side = "right" },
        groundShadow = { anchorX = 0.71, anchorY = 0.88, rx = 0.1012, ry = 0.024, alpha = 179 },
        microMotion = "turn",
        traceAnchor = { x = 0.14, y = 0.8, scale = 0.1687, layer = 2 },
        future3D = { sceneRef = "scene/lon_commute", anchorId = "lon_commute_booth_01" },
    },
}

-- ============================================================================
-- 生活痕迹：不可点击的 2D 覆盖物，绑定最近确定的关键事件，下一关键事件后替换。
-- label 同时是档案页那句短文本——状态窗画面、档案页文字与事件事实说的是同一条痕迹。
-- ============================================================================

---@class TraceItem
---@field id string
---@field label string 档案页/日志用的短文本（不暴露原始事件键）
---@field assetPath string 透明底 2D 贴图

---@type table<string, TraceItem>
local TRACES = {
    note = { id = "note", label = "桌上摊开的便签", assetPath = "image/trace-note_20260924155918.png" },
    coffee = { id = "coffee", label = "喝了一半的咖啡", assetPath = "image/trace-coffee_20260924155918.png" },
    vinyl = { id = "vinyl", label = "没放回架子的唱片", assetPath = "image/trace-vinyl_20260924155918.png" },
    umbrella = { id = "umbrella", label = "门边收着的雨伞", assetPath = "image/trace-umbrella_20260924155918.png" },
    postcard = { id = "postcard", label = "摊开的明信片", assetPath = "image/trace-postcard_20260924155918.png" },
    proofs = { id = "proofs", label = "批注过的校样", assetPath = "image/trace-proofs_20260924155918.png" },
    grocery = { id = "grocery", label = "带回来的那袋菜", assetPath = "image/trace-grocery_20260924155918.png" },
    oldbook = { id = "oldbook", label = "叠着的两本旧书", assetPath = "image/trace-oldbook_20260924155918.png" },
    gaiwan = { id = "gaiwan", label = "还热着的盖碗茶", assetPath = "image/trace-gaiwan_20260924155918.png" },
}

SceneService.SCENE_ORDER = {
    "la_apartment", "la_studio", "la_cafe", "la_commute",
    "sha_apartment", "sha_office", "sha_bookstore", "sha_commute",
    "cdu_apartment", "cdu_studio", "cdu_cafe", "cdu_commute",
    "lon_apartment", "lon_studio", "lon_recordshop", "lon_commute",
}

---@param sceneId string
---@return ScenePackage?
function SceneService.PackageFor(sceneId)
    if type(sceneId) ~= "string" then
        return nil
    end
    return PACKAGES[sceneId]
end

---@return table<string, ScenePackage>
function SceneService.AllPackages()
    return PACKAGES
end

---@param traceKey string?
---@return TraceItem?
function SceneService.TraceFor(traceKey)
    if type(traceKey) ~= "string" then
        return nil
    end
    return TRACES[traceKey]
end

--- 色温 → 主光 RGB（近似 Planck 轨迹，工程够用即可，唯一换算处）。
--- 返回值同时喂给 3D 补光与阴影/环境光的着色，画面与光照不会各说一套。
---@param kelvin integer
---@return number, number, number
function SceneService.TemperatureToRGB(kelvin)
    local t = (kelvin or 3200) / 100
    local r, g, b
    if t <= 66 then
        r = 255
        g = 99.4708025861 * math.log(t) - 161.1195681661
        if t <= 10 then
            b = 0
        else
            b = 138.5177312231 * math.log(t - 10) - 305.0447927307
        end
    else
        r = 329.698727446 * (t - 60) ^ -0.1332047592
        g = 288.1221695283 * (t - 60) ^ -0.0755148492
        b = 255
    end
    local function clamp(v)
        if v < 0 then return 0 end
        if v > 255 then return 255 end
        return v
    end
    return clamp(r) / 255, clamp(g) / 255, clamp(b) / 255
end

---@class CurrentTrace
---@field traceKey string
---@field occurrenceKey string 绑定的事件实例（同一天同一城永远同一个键）
---@field eventTitle string 档案页短文本用的事件标题
---@field sceneId string 绑定时所在场景（痕迹锚点跟着它走）
---@field isM7KeyEvent? boolean 事后痕迹：普通日程不能在下一次刷新时替换
---@field boundAtUtc? integer 由 LifeService 落槽时补

---@class SceneState
---@field sceneId string
---@field backgroundKey string
---@field backgroundPath string
---@field colorTemperature integer
---@field keyLightDirection { x: number, y: number, z: number }
---@field keyLightRGB { r: number, g: number, b: number }
---@field characterPlacement { x: number, y: number, z: number, side: string }
---@field groundShadow SceneGroundShadow
---@field microMotion string
---@field recentTrace { assetKey: string, assetPath: string, label: string, anchorX: number, anchorY: number, scale: number, layer: integer }?
---@field future3D { sceneRef: string, anchorId: string }

--- 状态窗、档案页与回复事实共用的 SceneState 唯一构造处。
--- sceneId 没有对应包时返回 nil —— 调用方必须显式回退并说明，不得沿用旧包。
---@param sceneId string
---@param currentTrace? CurrentTrace
---@return SceneState?
function SceneService.StateFor(sceneId, currentTrace)
    local pkg = SceneService.PackageFor(sceneId)
    if not pkg then
        return nil
    end
    local r, g, b = SceneService.TemperatureToRGB(pkg.colorTemperature)
    ---@type SceneState
    local state = {
        sceneId = pkg.id,
        backgroundKey = pkg.backgroundKey,
        backgroundPath = pkg.backgroundPath,
        colorTemperature = pkg.colorTemperature,
        keyLightDirection = pkg.keyLightDirection,
        keyLightRGB = { r = r, g = g, b = b },
        characterPlacement = pkg.characterPlacement,
        groundShadow = pkg.groundShadow,
        microMotion = pkg.microMotion,
        future3D = pkg.future3D,
    }
    if currentTrace and currentTrace.traceKey then
        local trace = SceneService.TraceFor(currentTrace.traceKey)
        -- 痕迹只在它绑定的那个场景里出现：换城/换景后旧痕迹绝不跟到新画面上（验收 4）。
        if trace and currentTrace.sceneId == pkg.id then
            state.recentTrace = {
                assetKey = trace.id,
                assetPath = trace.assetPath,
                label = trace.label,
                anchorX = pkg.traceAnchor.x,
                anchorY = pkg.traceAnchor.y,
                scale = pkg.traceAnchor.scale,
                layer = pkg.traceAnchor.layer,
            }
        end
    end
    return state
end

return SceneService
