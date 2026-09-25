-- ============================================================================
-- StatusWindow.lua — M0-0 若夕 3D 状态窗（M4：场景状态包驱动）
-- 固定镜头、无交互。将独立预览场景渲染到 Texture2D，再由 UI 绘制。
-- M4 起背景、色温、主光、站位、接地阴影与无骨骼微动全部来自 SceneService 的
-- 16 个场景状态包（同一份 SceneState 也供档案页与回复事实使用）；
-- 骨骼动画未通过「GLB→MDL→真机」三道验证门前不接入，微动一律程序化、无骨骼。
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")

local StatusWindow = {}

local TAG = "[M0-0]"

-- 资源候选路径（相对 assets/，cache 不带 assets/ 前缀）
local MODEL_CANDIDATES = {
    "Meshes/lin-ruoxi.mdl",
    "models/characters/lin-ruoxi/lin-ruoxi.mdl",
    "Models/lin-ruoxi.mdl",
}

local PREFAB_CANDIDATES = {
    "Prefabs/lin-ruoxi.prefab",
    "models/characters/lin-ruoxi/lin-ruoxi.prefab",
}

local GLB_PATH = "models/characters/lin-ruoxi/lin-ruoxi.glb"
local MATERIAL_PATH = "Materials/lin-ruoxi_00_tripo_mat_8ae16fc0-7a3a-402e-9a6e-1180f6c269f7.xml"
-- M4：背景不再写死。16 张 4:3 静帧由 SceneService 的场景状态包给出
-- （ApplySceneState 是唯一入口），路径都在 .project/resources.json 的 image/** 白名单内。
-- 角色漫反射贴图：DWP 资源，设备冷启动时材质内引用可能是占位，需异步补载
local CHARACTER_DIFFUSE_TEXTURE = "Textures/lin-ruoxi_00_D.jpg"

---@type integer
local RT_WIDTH = 960
---@type integer
local RT_HEIGHT = 720
local CAMERA_FOV = 32.0
local CHARACTER_TARGET_HEIGHT = 1.68

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
---@type Node|nil
local characterRoot_ = nil
---@type Texture2D|nil
local texture_ = nil
---@type RenderSurface|nil
local surface_ = nil
---@type Viewport|nil
local viewport_ = nil
---@type integer
local nvgImage_ = 0
---@type NVGContextWrapper|nil
local nvgImageCtx_ = nil
local nvgCreateFailed_ = false

local modelLoaded_ = false
local usingPlaceholderCharacter_ = false

---@type string
local modelError_ = ""
---@type string
local backgroundError_ = ""
--- 当前生效的场景状态（SceneService.StateFor 的产物）：光照、站位、阴影、微动都读它。
---@type SceneState?
local sceneState_ = nil
---@type Zone|nil
local zone_ = nil
---@type Node|nil
local sunNode_ = nil
---@type Light|nil
local coolLight_ = nil
---@type Light|nil
local warmLight_ = nil
---@type Node|nil
local warmLightNode_ = nil
---@type Node|nil
local coolLightNode_ = nil
-- 无骨骼微动的基准与相位：只记录「上一帧施加了多少」，每帧先撤销再施加新偏移，
-- 基准姿态永远是 framing 那一刻的原值，不会累积漂移。
---@type Vector3|nil
local baseCharPos_ = nil
---@type number
local baseCamY_ = 0
---@type number
local microTime_ = 0
---@type number
local microPrev_ = 0
--- 角色漫反射贴图单独一个槽位：bindCharacterMaterial 是在 tryLoadPrefab/tryLoadModelFile
--- 里调的，那两条路随后都会把 modelError_ 清空，写进去会被覆盖；贴图失败要单独上屏。
---@type string
local characterTextureError_ = ""

---@type fun()|nil
local noticesChanged_ = nil

local function logInfo(msg)
    print(TAG .. " " .. msg)
    log:Write(LOG_INFO, TAG .. " " .. msg)
end

local function logError(msg)
    print(TAG .. " ERROR: " .. msg)
    log:Write(LOG_ERROR, TAG .. " " .. msg)
end

local function logWarn(msg)
    print(TAG .. " WARN: " .. msg)
    log:Write(LOG_WARNING, TAG .. " " .. msg)
end

--- 开机那一瞬的整批日志会被日志管道丢掉（2026-09-22 实测：自检只上来 PASS A0…A6，
--- 同批的尾巴连同 StatusWindow.Init 的资源检查/模型加载/光照分支全部没落盘）。
--- 这里把初始化事实额外缓冲一份，由本模块自己订阅 Update 在之后几个真实帧里原样重发，
--- 与 main.lua 里自检结论的重发是同一套办法。异步贴图回填的落点也走这个槽位，
--- 所以每次重发都要重读，不能缓存成定值。
---@type string[]
local bootTrace_ = {}
---@type string
local textureState_ = "未开始"
---@type table|nil
local bootEcho_ = nil

---@param msg string
---@param level number|nil
local function trace(msg, level)
    bootTrace_[#bootTrace_ + 1] = msg
    if (level or LOG_INFO) == LOG_ERROR then
        print(TAG .. " ERROR: " .. msg)
    elseif level == LOG_WARNING then
        print(TAG .. " WARN: " .. msg)
    else
        print(TAG .. " " .. msg)
    end
    log:Write(level or LOG_INFO, TAG .. " " .. msg)
end

--- 状态窗开机 trace + 漫反射贴图当前落点。日志整批丢时靠它读数。
---@return string
function StatusWindow.GetBootTrace()
    return table.concat(bootTrace_, " | ") .. " | 漫反射=" .. textureState_
end

--- 开机 trace 重发：每 4 秒一条，把开机那一瞬被日志管道整批丢掉的那份读数补回来。
---@param dt number 本帧步长（秒）
local function stepBootEcho(dt)
    -- dt 一并兜住：这是每帧调用，取不到步长就会每帧抛一次 nil 索引，把正要救回来的日志又淹掉。
    if not bootEcho_ or bootEcho_.left <= 0 or not dt then
        return
    end
    bootEcho_.elapsed = bootEcho_.elapsed + dt
    if bootEcho_.elapsed < 4 then
        return
    end
    bootEcho_.elapsed = 0
    bootEcho_.left = bootEcho_.left - 1
    logInfo("[状态窗开机] " .. StatusWindow.GetBootTrace()
        .. string.format(" 重发%d/3", 3 - bootEcho_.left))
    if bootEcho_.left <= 0 then
        bootEcho_ = nil
    end
end

--- 启动开机 trace 重发。由 StatusWindow.Init 末尾调用。
--- 只摆一个计数器，不订阅任何事件：逐帧推进统一由 main.lua 那条按全局名订阅的 Update
--- 经 StatusWindow.Tick 转进来（本运行时按函数订阅的 Update 一次都没派发过，见 Tick 的注释）；
--- 到点自己退休（left 归零后 bootEcho_ 置 nil）。
---@param left number 重发次数
local function startBootEcho(left)
    bootEcho_ = { left = left, elapsed = 0 }
end

--- 取消尚未发完的开机 trace 重发。由 StatusWindow.Shutdown 调用。
local function stopBootEcho()
    bootEcho_ = nil
end

---@param path string
---@return boolean
local function resourceExists(path)
    if not path or path == "" then
        return false
    end
    return cache:Exists(path) == true
end

---@param candidates string[]
---@return string|nil
local function findFirstExisting(candidates)
    for i = 1, #candidates do
        local path = candidates[i]
        if resourceExists(path) then
            return path
        end
    end
    return nil
end

---@param r number
---@param g number
---@param b number
---@param metallic number
---@param roughness number
---@return Material
local function makePbrColor(r, g, b, metallic, roughness)
    local mat = Material:new()
    local tech = cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml")
    if tech then
        mat:SetTechnique(0, tech)
    end
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, 1.0)))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.4, 0.4, 0.4, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(metallic))
    mat:SetShaderParameter("Roughness", Variant(roughness))
    return mat
end

---@param parent Node
---@param name string
---@param modelName string
---@param position Vector3
---@param scale Vector3
---@param material Material
---@return Node
local function addPrimitive(parent, name, modelName, position, scale, material)
    local node = parent:CreateChild(name)
    node.position = position
    node.scale = scale
    local modelComp = node:CreateComponent("StaticModel")
    local mdl = cache:GetResource("Model", modelName)
    if mdl then
        modelComp:SetModel(mdl)
    end
    modelComp:SetMaterial(material)
    modelComp.castShadows = true
    return node
end

--- 遍历子节点（兼容 GetChild 0/1 基索引）
---@param node Node
---@param visitor fun(child: Node)
local function forEachChild(node, visitor)
    local count = node:GetNumChildren(false)
    if count <= 0 then
        return
    end
    local first = node:GetChild(0)
    local startIdx = 0
    local endIdx = count - 1
    if first == nil then
        startIdx = 1
        endIdx = count
    end
    for i = startIdx, endIdx do
        local child = node:GetChild(i)
        if child then
            visitor(child)
        end
    end
end

--- 在树里找「真正那盏主光」并认领下来。
--- 为什么必须找而不能按名字取：出厂走的是 LightGroup 预设那一支（runtime log 里
--- 「光照=LightGroup 预设」为证），预设里那盏叫 "Directional Light"，而 sunNode_ 过去只在
--- 「预设不存在」的兜底分支里赋值——于是 16 个场景包声明的主光方向与色温一条都落不到画面上
--- （2026-09-25 逐张取证：方向光 16 张同一朝向同一颜色，命中 0/16）。
--- 判据用「投影的那盏」而不是 lightType：这台绑定层读出来的 lightType 是数字
--- （预设那盏 0.0、我们自己造的两盏点光 2.0），跟枚举名对不上，拿它当唯一判据会赌错；
--- 两盏补光是显式 castShadows=false 的，主光才投影，这一条比枚举稳。
---@param node Node
---@param depth integer
---@return Node?
local function searchKeyLight(node, depth)
    if depth > 8 then
        return nil
    end
    local name = node.name
    if name ~= "WarmFillLight" and name ~= "CoolFillLight" then
        local light = node:GetComponent("Light")
        if light and light.castShadows then
            return node
        end
    end
    local hit = nil
    forEachChild(node, function(child)
        if hit == nil then
            hit = searchKeyLight(child, depth + 1)
        end
    end)
    return hit
end

---@param node Node
---@param out Drawable[]
local function collectDrawables(node, out)    local animated = node:GetComponent("AnimatedModel")
    if animated then
        out[#out + 1] = animated
    else
        local staticModel = node:GetComponent("StaticModel")
        if staticModel then
            out[#out + 1] = staticModel
        end
    end
    forEachChild(node, function(child)
        collectDrawables(child, out)
    end)
end

---@param node Node
---@return BoundingBox|nil
local function computeWorldBounds(node)
    ---@type Drawable[]
    local drawables = {}
    collectDrawables(node, drawables)
    if #drawables == 0 then
        logWarn("角色节点没有可渲染模型，无法计算包围盒")
        return nil
    end
    local first = drawables[1]
    if not first then
        return nil
    end
    local box = first.worldBoundingBox
    local merged = BoundingBox(box.min, box.max)
    for i = 2, #drawables do
        local drawable = drawables[i]
        if drawable then
            merged:Merge(drawable.worldBoundingBox)
        end
    end
    return merged
end

---@param scene Scene
local function createLighting(scene)
    local lightFile = cache:GetResource("XMLFile", "LightGroup/Dusk.xml")
    if not lightFile then
        lightFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    end
    if lightFile then
        local lightGroup = scene:CreateChild("LightGroup")
        lightGroup:LoadXML(lightFile:GetRoot())
        local zone = lightGroup:GetComponent("Zone", true)
        if zone then
            -- 近景状态窗：拉开雾距，避免角色被雾吃掉
            zone.fogStart = 40.0
            zone.fogEnd = 120.0
            zone_ = zone
            -- 把预设实际生效的环境光档位打出来：AMBIENT_PREBAKED 会把 cAmbientColor
            -- 硬清零，那种情况下背光侧只能靠补光救，改 ambientColor 是空操作。
            -- ambientSource 用 tostring 读：不同绑定层可能给枚举名也可能给整数。
            trace(string.format("光照=LightGroup 预设 ambientSource=%s rgb=%.2f,%.2f,%.2f",
                tostring(zone.ambientSource),
                zone.ambientColor.r, zone.ambientColor.g, zone.ambientColor.b))
        else
            trace("光照=LightGroup 预设（无 Zone）")
        end
    else
        trace("光照=备用方向光（LightGroup/Dusk.xml 与 Daytime.xml 都不存在）", LOG_WARNING)
        -- LightGroup 不存在时场景里就没有 Zone，而 Zone 默认 ambientSource 是 AMBIENT_PREBAKED：
        -- 那种模式下着色器会把 cAmbientColor 硬清零（engine-docs/recipes/rendering.md），
        -- zone.ambientColor 是空操作。必须显式切到 AMBIENT_COLOR，环境光才真正进得去。
        -- AMBIENT_COLOR 下漫反射强度固定为 1.0，亮度只由 ambientColor 本身决定。
        -- 没有这一段时全场景只有一盏硬光，背光面直接纯黑——就是真机上「光影不太好」那一项。
        -- 已经有一个 Zone 就改它，别另建一个：新建 Zone 默认 priority=0，
        -- 会顶掉已有那一档（含它的 IBL / SH / Bloom / 雾）。
        ---@type Zone|nil
        local zone = (scene:GetComponent("Zone", true) --[[@as Zone|nil]])
        if not zone then
            local zoneNode = scene:CreateChild("Zone")
            zone = (zoneNode:CreateComponent("Zone") --[[@as Zone]])
            -- boundingBox 必设且要罩住场景，否则这一档照不到角色
            zone:SetBoundingBox(BoundingBox(Vector3(-8.0, -1.0, -8.0), Vector3(8.0, 8.0, 8.0)))
            zone.priority = 0
        end
        zone_ = zone
        zone.ambientSource = AMBIENT_COLOR
        -- 室内暖黄为主、掺一点冷调当天光：背光面有层次而不是死黑
        zone.ambientColor = Color(0.34, 0.31, 0.28)
        zone.fogColor = Color(0.16, 0.15, 0.16)
        -- 近景状态窗：与 LightGroup 分支同一组雾距
        zone.fogStart = 40.0
        zone.fogEnd = 120.0
        -- 实际生效值打出来：真机上如果「光影不太好」仍在，这一行决定是改数值还是改别处
        trace(string.format("环境光=AMBIENT_COLOR rgb=%.2f,%.2f,%.2f 雾=%.0f-%.0f",
            zone.ambientColor.r, zone.ambientColor.g, zone.ambientColor.b,
            zone.fogStart, zone.fogEnd))
        local sunNode = scene:CreateChild("Sun")
        sunNode.direction = Vector3(0.4, -0.7, 0.5)
        local sun = sunNode:CreateComponent("Light")
        sun.lightType = LIGHT_DIRECTIONAL
        sun.color = Color(1.0, 0.82, 0.68)
        sun.brightness = 3.2
        sun.castShadows = true
        sunNode_ = sunNode
    end

    -- 预设那一支里 sunNode_ 一直是 nil，于是 ApplySceneLighting 的主光那段整块跳过：
    -- 16 张场景包声明的主光方向与色温一条都没落到画面上（2026-09-25 逐张取证 0/16，
    -- 那盏方向光 16 张同一朝向、同一颜色、同一亮度）。
    -- 认领只认「这一次 createLighting 手里这棵 scene」里的灯，不写 `if not sunNode_` 那种
    -- 「有没有认领过」的判断：Init 被再走一遍时（本地取证就是两次 Start 两棵树），
    -- 那个判断会把上一棵树那盏灯一直留在引用里，于是主光打在没人看的那棵树上、
    -- 站位写在另一棵上——2026-09-25 第一次实现就是这么错的，实测两棵树各说一半。
    -- 认领不到就保持原样：宁可沿用预设的灯，也不为了「看起来生效」再造一盏去打架。
    local keyNode = searchKeyLight(scene, 0)
    if keyNode then
        sunNode_ = keyNode
        local kd = keyNode.direction
        trace(string.format("主光认领=%s 方向=(%.2f,%.2f,%.2f) 亮度=%.2f（之后按场景包主光改）",
            tostring(keyNode.name), kd.x, kd.y, kd.z,
            (function()
                local l = keyNode:GetComponent("Light")
                return l and l.brightness or 0
            end)()))
    else
        trace("主光认领失败：这棵树里没有投影的灯，主光方向/色温将保持预设值", LOG_WARNING)
    end

    -- 两盏补光两个分支都挂：「背光侧死黑」是共性问题，兜底分支有环境光也仍旧偏硬，
    -- LightGroup 分支若带 AMBIENT_PREBAKED 更是只有灯没有环境光。
    -- 主光只认一盏——兜底分支现造的 Sun 或预设自带的那盏方向光。这里再造一盏方向光
    -- 会跟它打架（两个方向各投一遍阴影，中间反而发灰），所以补光一律用点光、不投影。
    -- 一冷一暖是为了让受光侧与背光侧分得开：全是暖光只会把侧脸糊成一团。
    -- M4：两盏补光的节点与灯都留引用——ApplySceneLighting 按场景包的主光方向/色温改它们，
    -- 人物受光才跟着场景走，不再像独立贴图。
    local coolNode = scene:CreateChild("CoolFillLight")
    coolNode.position = Vector3(-2.2, 1.4, 1.8)
    local cool = coolNode:CreateComponent("Light")
    cool.lightType = LIGHT_POINT
    cool.color = Color(0.60, 0.72, 0.92)
    cool.brightness = 1.55
    cool.range = 9.0
    cool.castShadows = false
    coolLightNode_ = coolNode
    coolLight_ = cool

    -- 右前暖面光：把面部和夹克的细节拉出来，亮度略高于冷补光，
    -- 保持「右前是主受光面」的方向感
    local fillNode = scene:CreateChild("WarmFillLight")
    fillNode.position = Vector3(1.6, 1.8, 2.4)
    local fill = fillNode:CreateComponent("Light")
    fill.lightType = LIGHT_POINT
    fill.color = Color(1.0, 0.90, 0.80)
    fill.brightness = 2.10
    fill.range = 8.0
    fill.castShadows = false
    warmLightNode_ = fillNode
    warmLight_ = fill

    -- 布光结果进 boot trace：真机上要判断「改这几个数够不够」还是「得换 Technique」，
    -- 凭的是这一行，不是截图
    trace(string.format("三点布光 主光=1 冷补=%.2f 暖面=%.2f（均不投影）", 1.55, 2.10))
end

--- 几何占位人（深墨绿夹克 / 米白针织 / 深色牛仔裤 / 白鞋）
---@param parent Node
local function createPlaceholderCharacter(parent)
    usingPlaceholderCharacter_ = true
    local jacket = makePbrColor(0.11, 0.20, 0.16, 0.05, 0.62)
    local knit = makePbrColor(0.90, 0.86, 0.78, 0.0, 0.72)
    local jeans = makePbrColor(0.16, 0.18, 0.22, 0.02, 0.58)
    local shoe = makePbrColor(0.93, 0.93, 0.94, 0.0, 0.45)
    local skin = makePbrColor(0.84, 0.70, 0.60, 0.0, 0.55)
    local hair = makePbrColor(0.10, 0.09, 0.09, 0.0, 0.48)
    local silver = makePbrColor(0.82, 0.84, 0.88, 0.92, 0.18)

    addPrimitive(parent, "Head", "Models/Sphere.mdl", Vector3(0, 1.52, 0.02), Vector3(0.20, 0.24, 0.22), skin)
    addPrimitive(parent, "Hair", "Models/Sphere.mdl", Vector3(0, 1.60, -0.02), Vector3(0.22, 0.16, 0.24), hair)
    addPrimitive(parent, "TorsoKnit", "Models/Box.mdl", Vector3(0, 1.18, 0.0), Vector3(0.30, 0.38, 0.16), knit)
    addPrimitive(parent, "Jacket", "Models/Box.mdl", Vector3(0, 1.16, 0.0), Vector3(0.42, 0.46, 0.22), jacket)
    addPrimitive(parent, "ArmL", "Models/Box.mdl", Vector3(-0.28, 1.10, 0.0), Vector3(0.10, 0.46, 0.10), jacket)
    addPrimitive(parent, "ArmR", "Models/Box.mdl", Vector3(0.28, 1.10, 0.0), Vector3(0.10, 0.46, 0.10), jacket)
    addPrimitive(parent, "HandL", "Models/Sphere.mdl", Vector3(-0.28, 0.84, 0.02), Vector3(0.07, 0.07, 0.07), skin)
    addPrimitive(parent, "HandR", "Models/Sphere.mdl", Vector3(0.28, 0.84, 0.02), Vector3(0.07, 0.07, 0.07), skin)
    addPrimitive(parent, "Hip", "Models/Box.mdl", Vector3(0, 0.88, 0.0), Vector3(0.32, 0.16, 0.18), jeans)
    addPrimitive(parent, "LegL", "Models/Box.mdl", Vector3(-0.10, 0.46, 0.0), Vector3(0.12, 0.72, 0.14), jeans)
    addPrimitive(parent, "LegR", "Models/Box.mdl", Vector3(0.10, 0.46, 0.0), Vector3(0.12, 0.72, 0.14), jeans)
    addPrimitive(parent, "ShoeL", "Models/Box.mdl", Vector3(-0.10, 0.06, 0.04), Vector3(0.13, 0.08, 0.24), shoe)
    addPrimitive(parent, "ShoeR", "Models/Box.mdl", Vector3(0.10, 0.06, 0.04), Vector3(0.13, 0.08, 0.24), shoe)
    addPrimitive(parent, "Earring", "Models/Sphere.mdl", Vector3(0.11, 1.50, 0.02), Vector3(0.025, 0.025, 0.025), silver)

    logInfo("已创建几何占位角色（若夕服装配色）。等待 GLB 导入为 MDL 后替换")
end

---@param node Node
local function bindCharacterMaterial(node)
    local mat = cache:GetResource("Material", MATERIAL_PATH)
    if not mat then
        trace("角色材质加载失败: " .. MATERIAL_PATH, LOG_ERROR)
        return
    end
    local animated = node:GetComponent("AnimatedModel", true)
    local staticModel = node:GetComponent("StaticModel", true)
    local drawable = animated or staticModel
    if not drawable then
        trace("绑定材质时未找到 StaticModel/AnimatedModel", LOG_WARNING)
        return
    end
    drawable:SetMaterial(mat)
    drawable.castShadows = false
    trace("已绑定角色漫反射材质: " .. MATERIAL_PATH)

    ---@param tex Texture2D|nil
    ---@return boolean
    local function applyDiffuse(tex)
        if tex then
            mat:SetTexture(TU_DIFFUSE, tex)
            if surface_ then
                surface_:QueueUpdate()
            end
        end
        -- 失败也照样回调：这一句提示得让主界面的 errorLabel 亮起来，不能只在日志里
        if noticesChanged_ then
            noticesChanged_()
        end
        return tex ~= nil
    end

    -- 与背景的 PrepareBackground 对齐：先走 cache:Exists 快路，文件已在本地就同步取、
    -- 立刻回填，完全不进异步竞态。之前只有异步一条路，且失败只 logWarn 就 return——
    -- 若设备冷启动时 GetResourceAsync 干脆不回调，角色就整会话静默黑着、屏幕上没有任何提示。
    -- 仅涉及“加载”，不改 Technique/法线等 M0-1 内容。
    local syncTex = resourceExists(CHARACTER_DIFFUSE_TEXTURE)
        and (cache:GetResource("Texture2D", CHARACTER_DIFFUSE_TEXTURE) --[[@as Texture2D|nil]])
        or nil
    if applyDiffuse(syncTex) then
        textureState_ = "已回填"
        characterTextureError_ = ""
        trace("角色漫反射贴图已在本地，同步回填: " .. CHARACTER_DIFFUSE_TEXTURE)
        return
    end

    -- 快路没拿到（DWP 里登记了但还没加载完）就退回异步：这里不报错，
    -- 报错只留给异步也失败那一次，避免把“还没加载完”误判成资产缺失。
    textureState_ = "异步等待中"
    cache:GetResourceAsync("Texture2D", CHARACTER_DIFFUSE_TEXTURE, function(resource)
        local tex = resource and (resource --[[@as Texture2D]]) or nil
        if not applyDiffuse(tex) then
            textureState_ = "异步失败"
            characterTextureError_ = "角色贴图 " .. CHARACTER_DIFFUSE_TEXTURE
                .. " 下载失败，人物可能发黑。"
            trace(characterTextureError_, LOG_WARNING)
            return
        end
        textureState_ = "已回填"
        characterTextureError_ = ""
        trace("已回填角色漫反射贴图: " .. CHARACTER_DIFFUSE_TEXTURE)
    end)
end

---@param mdlPath string
---@return boolean
local function tryLoadModelFile(mdlPath)
    if not characterRoot_ then
        return false
    end
    local model = cache:GetResource("Model", mdlPath)
    if not model then
        trace("GetResource(Model) 失败: " .. mdlPath, LOG_ERROR)
        return false
    end

    local skeleton = model:GetSkeleton()
    local boneCount = 0
    if skeleton then
        boneCount = skeleton:GetNumBones()
    end

    ---@type StaticModel|AnimatedModel
    local drawable
    if boneCount > 0 then
        drawable = characterRoot_:CreateComponent("AnimatedModel")
        trace("模型骨骼=" .. tostring(boneCount) .. "，使用 AnimatedModel")
    else
        drawable = characterRoot_:CreateComponent("StaticModel")
        trace("模型骨骼=0，使用 StaticModel")
    end
    drawable:SetModel(model)
    -- 远景移出 3D 场景后场景里没有任何投影接收面，投影贴图白算一遭；真机要帧率
    drawable.castShadows = false
    bindCharacterMaterial(characterRoot_)
    return true
end

---@param prefabPath string
---@return boolean
local function tryLoadPrefab(prefabPath)
    if not characterRoot_ then
        return false
    end
    local prefabFile = cache:GetResource("XMLFile", prefabPath)
    if not prefabFile then
        trace("GetResource(XMLFile) 失败: " .. prefabPath, LOG_ERROR)
        return false
    end
    local ok = characterRoot_:LoadXML(prefabFile:GetRoot())
    if not ok then
        trace("LoadXML 预制体失败: " .. prefabPath, LOG_ERROR)
        return false
    end
    trace("已加载角色预制体: " .. prefabPath)
    bindCharacterMaterial(characterRoot_)
    return true
end

local function normalizeCharacterScale()
    if not characterRoot_ then
        return
    end
    local bbox = computeWorldBounds(characterRoot_)
    if not bbox then
        return
    end
    local height = bbox.size.y
    logInfo(string.format(
        "角色包围盒 size=(%.3f, %.3f, %.3f) center=(%.3f, %.3f, %.3f)",
        bbox.size.x, bbox.size.y, bbox.size.z,
        bbox.center.x, bbox.center.y, bbox.center.z
    ))
    if height < 0.05 then
        logWarn("角色高度过小: " .. tostring(height))
        return
    end
    -- 将角色缩放到约 1.68 米，保证全身入画且脚不裁切
    local scaleFactor = CHARACTER_TARGET_HEIGHT / height
    if math.abs(scaleFactor - 1.0) > 0.02 then
        characterRoot_:SetScale(scaleFactor)
        logInfo(string.format("角色高度 %.3f m，缩放到 %.2f m (x%.3f)", height, CHARACTER_TARGET_HEIGHT, scaleFactor))
    end

    -- 脚底对齐地面 y=0
    bbox = computeWorldBounds(characterRoot_)
    if bbox then
        local minY = bbox.min.y
        if math.abs(minY) > 0.001 then
            local pos = characterRoot_.position
            characterRoot_.position = Vector3(pos.x, pos.y - minY, pos.z)
            logInfo(string.format("脚底对齐地面，Y 偏移 %.3f", -minY))
        end
    end
end

--- 把世界点投影成「top-origin 归一化画面坐标」：y=0 在画面上沿、x=0.5 是画面中线 ——
--- 与接地阴影那套 UI/NanoVG 坐标（`cy = y + h * anchorY`）同一制式，两边才能直接比。
--- 用的是相机刚定好的 basis（direction/up/right），所以必须在摆好相机之后调用。
---@return number? topY  投影失败（点在相机背后）时返回 nil
---@return number  topX
---@return number  z     沿视线方向的距离，给求解的步长用
local function projectToFrame(camNode, p, tanV, tanH)
    local c = camNode.position
    local f = camNode.direction
    local u = camNode.up
    local r = camNode.right
    local vx, vy, vz = p.x - c.x, p.y - c.y, p.z - c.z
    local z = vx * f.x + vy * f.y + vz * f.z
    if z <= 0.001 then
        return nil, 0.5, 0
    end
    local ndcY = (vx * u.x + vy * u.y + vz * u.z) / (z * tanV)
    local ndcX = (vx * r.x + vy * r.y + vz * r.z) / (z * tanH)
    return (1 - ndcY) / 2, (1 + ndcX) / 2, z
end

--- 固定镜头：人物按场景包的站位入画（默认画面右侧约 60% 高度，留头量），背景留白在另一侧。
--- M4：站位与让位方向来自 SceneState.characterPlacement —— 唱片行那种
--- 「留白在左」的场景，人物、相机与阴影一起翻边，不靠改文案凑图。
local function frameFixedCamera()
    if not cameraNode_ or not characterRoot_ then
        return
    end
    local placement = sceneState_ and sceneState_.characterPlacement or nil
    local side = placement and placement.side or "right"
    local bbox = computeWorldBounds(characterRoot_)
    local center = Vector3(placement and placement.x or 0.55, 0.84, 0.0)
    local height = CHARACTER_TARGET_HEIGHT
    if bbox then
        center = bbox.center
        height = math.max(bbox.size.y, 0.5)
    end

    local vfov = CAMERA_FOV * math.pi / 180.0
    -- 角色占画面高度约 1/1.65 ≈ 60%（旧 1.22 太近，人物顶到画框）
    local padding = 1.65
    local dist = (height * 0.5 * padding) / math.tan(vfov * 0.5)
    if dist < 1.8 then
        dist = 1.8
    end
    if dist > 8.0 then
        dist = 8.0
    end

    local aspect = RT_WIDTH / RT_HEIGHT
    local hfov = 2.0 * math.atan(math.tan(vfov * 0.5) * aspect)
    local viewW = 2.0 * dist * math.tan(hfov * 0.5)

    -- 将注视点朝留白的反方向挪，使人物落在画面约 71%（右）或 29%（左）处
    local shift = viewW * 0.21 * (side == "left" and -1 or 1)
    local look = Vector3(center.x - shift, bbox and (bbox.min.y + height * 0.52) or 0.86, center.z)
    local camPos = Vector3(look.x, look.y + height * 0.04, center.z + dist)

    -- 取景锚点求解：把场景包声明的那格「接地阴影」当成她脚底该落的位置来平移相机，
    -- 而不是拿一个固定取景值去对 16 张本来就不在同一格的地面线（home 0.86 / work 0.87
    -- / street 0.88，唱片行还在左半边 0.32）。2026-09-25 投影实测：不 solve 时脚底
    -- 一律落在 y=0.814，比声明的地面线高 4.6~6.6 画面高 —— 这就是「她像浮着」的来源。
    -- **只解竖直方向**：camPos 与 look 一起平移，视线方向不变，所以她不会变成斜视；
    -- 横向那一格实测只差 0.029（画面宽），而按同一条式子解横向会把相机推到人物同一侧
    -- （x 从 -0.23 跑到 +1.22，「相机让位到留白反侧」这条直接破），那 0.029 该由声明调，
    -- 不该由取景凑。
    local tanV = math.tan(vfov * 0.5)
    for _ = 1, 3 do
        cameraNode_.position = camPos
        cameraNode_:LookAt(look, Vector3.UP, TS_WORLD)
        local sh = sceneState_ and sceneState_.groundShadow or nil
        if not (sh and bbox) then
            break
        end
        local feet = Vector3((bbox.min.x + bbox.max.x) * 0.5, bbox.min.y, (bbox.min.z + bbox.max.z) * 0.5)
        local topY, _, z = projectToFrame(cameraNode_, feet, tanV, tanV * aspect)
        if topY == nil then
            break
        end
        -- 相机连着注视点一起抬：她就在画面里往下走（δ 与「锚点-脚底」同号）
        local dy = 2 * (sh.anchorY - topY) * z * tanV
        if math.abs(dy) < 0.0005 then
            break
        end
        look = Vector3(look.x, look.y + dy, look.z)
        camPos = Vector3(camPos.x, camPos.y + dy, camPos.z)
    end

    cameraNode_.position = camPos
    cameraNode_:LookAt(look, Vector3.UP, TS_WORLD)

    -- 角色只绕 Y 转向相机，保持站姿，不引入俯仰。
    -- LookAt 把节点局部 -Z 对准目标，而 lin-ruoxi MDL 正面朝局部 +Z，
    -- 不补这 180° 实机看到的就是后脑勺（2026-09-20 预览截图实测）。
    local charPos = characterRoot_.position
    characterRoot_:LookAt(Vector3(camPos.x, charPos.y, camPos.z), Vector3.UP, TS_WORLD)
    characterRoot_:Rotate(Quaternion(180, Vector3.UP))
    baseCharPos_ = characterRoot_.position
    baseCamY_ = camPos.y
    microPrev_ = 0

    if surface_ then
        surface_:QueueUpdate()
    end

    logInfo(string.format(
        "固定相机 pos=(%.2f,%.2f,%.2f) look=(%.2f,%.2f,%.2f) dist=%.2f side=%s",
        camPos.x, camPos.y, camPos.z, look.x, look.y, look.z, dist, side
    ))
end

local function loadCharacter()
    if not scene_ then
        return
    end
    characterRoot_ = scene_:CreateChild("Ruoxi")

    local prefabPath = findFirstExisting(PREFAB_CANDIDATES)
    local mdlPath = findFirstExisting(MODEL_CANDIDATES)
    local glbExists = resourceExists(GLB_PATH)

    trace("资源检查 GLB=" .. tostring(glbExists) .. " path=" .. GLB_PATH)
    trace("资源检查 prefab=" .. tostring(prefabPath) .. " mdl=" .. tostring(mdlPath))

    local loaded = false
    if prefabPath then
        loaded = tryLoadPrefab(prefabPath)
        if loaded then
            modelError_ = ""
        end
    end
    if (not loaded) and mdlPath then
        loaded = tryLoadModelFile(mdlPath)
        if loaded then
            modelError_ = ""
        end
    end

    -- LoadXML 会写入节点自身变换，必须在加载完成后再设站位
    characterRoot_.position = Vector3(0.55, 0.0, 0.0)

    if loaded then
        modelLoaded_ = true
        usingPlaceholderCharacter_ = false
        normalizeCharacterScale()
        trace("若夕 3D 模型加载成功")
    else
        modelLoaded_ = false
        if glbExists then
            modelError_ = "已找到 lin-ruoxi.glb，但缺少 Meshes/lin-ruoxi.mdl。请用 UrhoXCLI import-gltf 导入后再预览。"
        else
            modelError_ = "未找到角色模型。请将最终 GLB 放到 assets/models/characters/lin-ruoxi/lin-ruoxi.glb，并导入为 Meshes/lin-ruoxi.mdl。"
        end
        trace(modelError_, LOG_ERROR)
        createPlaceholderCharacter(characterRoot_)
    end
end

--- 远景静帧由 UI 层作为状态窗 backgroundImage 绘制（走 3D 平面贴图时 Plane 的 UV
--- 轴向会把静帧镜像，UI 图片路径没有这个问题）。必须先把文件弄到手再交给 UI：
--- UI 的 ImageCache.Get 会把首次失败永久缓存且不再重试
--- （urhox-libs/UI/Core/ImageCache.lua:64），而 DWP 冷启动时纹理尚未下载；
--- 若在首帧就设好 backgroundImage，背景会在整个会话里静默缺失。
--- 失败要打到屏幕上：真机没有 console。
---@param path string
---@param onReady fun(path: string)
---@param onFail fun(path: string)
local function PrepareBackground(path, onReady, onFail)
    if resourceExists(path) then
        logInfo("场景静帧已在本地: " .. path)
        onReady(path)
        return
    end
    cache:GetResourceAsync("Texture2D", path, function(resource)
        if not resource then
            onFail(path)
            return
        end
        logInfo("场景静帧下载就绪: " .. path)
        onReady(path)
    end)
end

--- 把资源先弄到手再交给 UI（ImageCache 会把首次失败永久缓存，DWP 冷启动不能提前挂）。
--- 公开给 main.lua 的生活痕迹覆盖物用：痕迹贴图走与背景完全相同的装载纪律。
---@param path string
---@param onReady fun(path: string)
---@param onFail fun(path: string)
function StatusWindow.PrepareTexture(path, onReady, onFail)
    PrepareBackground(path, onReady, onFail)
end

---@type string
local currentSceneId_ = ""
---@type string
local sceneNotice_ = ""

---@return string
function StatusWindow.GetSceneNotice()
    return sceneNotice_
end

---@return string
function StatusWindow.GetCurrentSceneId()
    return currentSceneId_
end

--- 场景包光照/站位落地：暖面光跟着主光来向与色温走，冷补光在对面，
--- 环境光按色温压暗——人物受光必须与背景光源同一方向同一颜色，
--- 否则就是「独立贴图」（M4 验收 3 点名的缺陷形态）。
---@param state SceneState
local function applySceneLighting(state)
    local k = state.keyLightRGB
    local d = state.keyLightDirection
    local px = (characterRoot_ and characterRoot_.position.x) or 0.55
    if warmLightNode_ and warmLight_ then
        warmLightNode_.position = Vector3(px + d.x, d.y + 0.6, d.z + 1.0)
        warmLight_.color = Color(k.r, k.g, k.b)
    end
    if coolLightNode_ and coolLight_ then
        coolLightNode_.position = Vector3(px - d.x * 1.2, d.y * 0.7 + 0.5, -d.z * 0.4 + 1.6)
    end
    if sunNode_ then
        sunNode_.direction = Vector3(-d.x, -d.y, -d.z)
        local sun = sunNode_:GetComponent("Light")
        if sun then
            sun.color = Color(k.r, k.g, k.b)
        end
    end
    -- 只在 AMBIENT_COLOR 档改环境光：PREBAKED 会把 cAmbientColor 硬清零，写了也是空操作。
    -- 夜晚场景（低色温低亮度）压到 0.16，白天偏冷光抬到 0.34，和静帧的明暗一致。
    if zone_ and tostring(zone_.ambientSource) == "AMBIENT_COLOR" then
        local lift = 0.16 + math.min(state.colorTemperature, 6500) / 6500 * 0.18
        zone_.ambientColor = Color(k.r * lift, k.g * lift, k.b * lift)
    end
    trace(string.format("场景光照 %s 色温=%d 主光=(%.2f,%.2f,%.2f) 站位=%s",
        state.sceneId, state.colorTemperature, d.x, d.y, d.z,
        state.characterPlacement.side))
end

--- 应用一份 SceneState：背景、光照、站位、接地阴影与微动一次换齐。
--- 缺包必须显式回退（保留当前画面 + 上屏说明），绝不沿用旧图假称已切换；
--- 换人生时调用方带 force=true，同 sceneId 也要把光照/阴影/痕迹重挂一遍。
---@param state SceneState?
---@param onApplied fun(path: string)
---@param force? boolean
---@return string result applied-pending | unchanged | missing-package
function StatusWindow.ApplySceneState(state, onApplied, force)
    if not state then
        sceneNotice_ = "当前事件缺少对应场景状态包，状态窗沿用现有画面"
        logWarn("场景包缺失（未切换），沿用当前画面")
        if noticesChanged_ then
            noticesChanged_()
        end
        return "missing-package"
    end
    if state.sceneId == currentSceneId_ and not force then
        return "unchanged"
    end
    currentSceneId_ = state.sceneId
    sceneNotice_ = ""
    logInfo("切换状态窗场景包: " .. state.sceneId .. " → " .. state.backgroundPath)
    PrepareBackground(state.backgroundPath, function(ready)
        sceneState_ = state
        if characterRoot_ then
            -- 站位三个轴都取场景包声明值，不从「当前值」继承 y/z：当前值可能正带着这一帧的微动
            -- 偏移（breathe 每帧改写 position），继承下来会被 frameFixedCamera 里的
            -- `baseCharPos_ = 当前位置` 钉成新基准，于是每次换景都可能把一点偏移永久固化（棘形漂移）。
            -- 16 个包声明的都是 y=0/z=0，而 loadCharacter 落地后本来也是「bbox.minY 归零的 y=0」
            -- （见同文件 pos.y - minY 那条），所以这条改动对当前画面等值，不是调构图。
            local place = state.characterPlacement
            characterRoot_.position = Vector3(place.x, place.y, place.z)
        end
        -- 顺序不能反：applySceneLighting 按 characterRoot_.position.x 摆那两盏补光（光要跟着人），
        -- 写在站位之前就会拿到「上一个场景那一边」的 x。唱片行是 16 张里唯一站左侧的
        -- （x=-0.50，其余 +0.55），进/出它的那两次换景补光会整体偏 1.05，正好落到人物另一侧。
        -- 2026-09-25 逐张取证：15/16 命中「按换景前站位」，0/16 命中「按声明站位」。
        applySceneLighting(state)
        frameFixedCamera()
        onApplied(ready)
        if noticesChanged_ then
            noticesChanged_()
        end
    end, function(failed)
        -- 背景没到手就不切：光照/站位/阴影都保持原场景那一套，
        -- 绝不允许「新光照打在旧背景上」这种半切状态出现在画面上。
        currentSceneId_ = ""
        backgroundError_ = "场景 " .. state.sceneId .. " 的静帧未下载成功，状态窗沿用上一帧画面。"
        logError(backgroundError_ .. " path=" .. failed)
        if noticesChanged_ then
            noticesChanged_()
        end
    end)
    return "applied-pending"
end

-- ---------------------------------------------------------------------------
-- 无骨骼微动（M4 §7）：呼吸 / 重心 / 朝向 / 镜头四种程序化微动。
-- 骨骼动作的三道验证门（源 GLB 骨骼动画 → MDL 保留 → 真机播放）未全过，
-- 这里一行都不许依赖 AnimatedModel 的动画轨道；撤销式增量变换保证不漂移。
-- ---------------------------------------------------------------------------
local function stepMicroMotion(dt)
    if not sceneState_ or not dt then
        return
    end
    microTime_ = microTime_ + dt
    local undo = microPrev_
    local nextv = 0
    local mode = sceneState_.microMotion
    if mode == "breathe" and baseCharPos_ and characterRoot_ then
        nextv = math.sin(microTime_ * 1.7) * 0.006
        -- 位置是**绝对写**（基准 + 目标偏移），不能再减 undo：减了就退化成
        -- `nextv(n) - nextv(n-1)` ≈ A·ω·dt·cos，幅度只有声明值的 1/35（本地逐帧分账实测
        -- ±0.00017 而非 ±0.006，2026-09-25）。撤销式增量只对下面的相对 Rotate 才成立。
        characterRoot_.position = Vector3(baseCharPos_.x, baseCharPos_.y + nextv, baseCharPos_.z)
    elseif mode == "sway" and characterRoot_ then
        nextv = math.sin(microTime_ * 0.55) * 0.9
        characterRoot_:Rotate(Quaternion(-undo, Vector3(0, 0, 1)))
        characterRoot_:Rotate(Quaternion(nextv, Vector3(0, 0, 1)))
    elseif mode == "turn" and characterRoot_ then
        nextv = math.sin(microTime_ * 0.32) * 2.6
        characterRoot_:Rotate(Quaternion(-undo, Vector3(0, 1, 0)))
        characterRoot_:Rotate(Quaternion(nextv, Vector3(0, 1, 0)))
    elseif mode == "dolly" and cameraNode_ then
        nextv = math.sin(microTime_ * 0.25) * 0.012
        local p = cameraNode_.position
        -- 同 breathe：基准 y 是绝对值，减 undo 会把目标值自己抵消掉
        cameraNode_.position = Vector3(p.x, baseCamY_ + nextv, p.z)
    end
    microPrev_ = nextv
end

local function createRenderTarget()
    texture_ = Texture2D:new()
    texture_:SetNumLevels(1)
    local format = Graphics:GetRGBAFormat()
    local ok = texture_:SetSize(RT_WIDTH, RT_HEIGHT, format, TEXTURE_RENDERTARGET)
    if not ok then
        logError("RenderTarget SetSize 失败")
        texture_ = nil
        return
    end
    texture_:SetFilterMode(FILTER_BILINEAR)

    if not scene_ or not camera_ then
        logError("创建 RenderTarget 时场景或相机为空")
        return
    end

    viewport_ = Viewport:new(scene_, camera_)
    local rpFile = cache:GetResource("XMLFile", "RenderPaths/Forward.xml")
    if rpFile then
        viewport_:SetRenderPath(rpFile)
        local path = viewport_:GetRenderPath()
        if path then
            local n = path:GetNumCommands()
            for i = 0, n - 1 do
                local command = path:GetCommand(i)
                if command and command.type == CMD_CLEAR then
                    command.useFogColor = false
                    -- 透明底：4:3 咖啡馆静帧由 UI 画在本层之下，这里只出角色
                    command.clearColor = Color(0, 0, 0, 0)
                end
            end
        end
    else
        logWarn("未找到 RenderPaths/Forward.xml，使用默认 RenderPath")
    end

    surface_ = texture_:GetRenderSurface()
    if not surface_ then
        logError("GetRenderSurface 失败")
        return
    end
    surface_:SetViewport(0, viewport_)
    surface_:SetUpdateMode(SURFACE_UPDATEALWAYS)
    surface_:QueueUpdate()
    logInfo(string.format("状态窗 RenderTarget %dx%d 已创建", RT_WIDTH, RT_HEIGHT))
end

function StatusWindow.Init()
    logInfo("初始化 3D 状态窗场景")
    cache:SetReturnFailedResources(false)
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    createLighting(scene_)
    loadCharacter()

    cameraNode_ = scene_:CreateChild("FixedCamera")
    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.nearClip = 0.1
    camera_.farClip = 50.0
    camera_.fov = CAMERA_FOV
    camera_.autoAspectRatio = false
    camera_:SetAspectRatio(RT_WIDTH / RT_HEIGHT)

    frameFixedCamera()
    createRenderTarget()
    -- 状态窗 RenderTarget 走 NanoVG 采样，关闭 HDR 避免贴图被当成乱码 atlas
    renderer.hdrRendering = false

    -- 微动与开机重发都不在这里自订阅：本运行时只派发**按全局名**订阅的 Update
    -- （main.lua 的 SubscribeToEvent("Update", "HandleUpdate") 每帧都到），
    -- 而按函数订阅的那两条一次都没进来过。逐帧驱动统一由 StatusWindow.Tick 走 main 那条活路。

    startBootEcho(3)
end

--- 逐帧驱动：无骨骼微动 + 开机 trace 重发。由 main.lua 的 HandleUpdate 每帧调一次。
--- 为什么不让本模块自己 SubscribeToEvent("Update", fn)：2026-09-25 本地实测，同一个进程里
--- 按全局名订阅的那条重发了 6 次，按函数订阅的两条（微动、开机 trace）一次都没触发——
--- 微动整块静默不跑、开机突发日志被管道丢掉时也没有重发可救。
---@param dt number TimeStep（秒）
function StatusWindow.Tick(dt)
    if not dt then
        return
    end
    stepMicroMotion(dt)
    stepBootEcho(dt)
end

function StatusWindow.IsModelLoaded()
    return modelLoaded_
end

function StatusWindow.IsUsingPlaceholderCharacter()
    return usingPlaceholderCharacter_
end

---@return string
function StatusWindow.GetModelError()
    -- 贴图失败比“缺模型”更具体：bindCharacterMaterial 只在模型已加载时才会跑，
    -- 两者不会同时成立，所以这里优先返回贴图那一句。
    if characterTextureError_ ~= "" then
        return characterTextureError_
    end
    return modelError_
end

---@return string
function StatusWindow.GetBackgroundError()
    return backgroundError_
end

--- 角色漫反射贴图等异步资源就绪后回调（用于主界面回填资源提示）。
---@param cb fun()
function StatusWindow.SetNoticesChanged(cb)
    noticesChanged_ = cb
end

---@param nvg NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
function StatusWindow.Draw(nvg, x, y, w, h)
    if w <= 1 or h <= 1 or not texture_ then
        return
    end
    if nvgCreateFailed_ then
        return
    end
    if nvgImage_ == 0 then
        nvgImage_ = nvgCreateVideo(nvg, texture_)
        nvgImageCtx_ = nvg
        if nvgImage_ == 0 then
            nvgCreateFailed_ = true
            logError("nvgCreateVideo 失败，状态窗无法绘制 3D 预览")
            return
        end
        logInfo("nvgCreateVideo 成功，句柄=" .. tostring(nvgImage_))
    end

    local radius = 14
    nvgSave(nvg)
    nvgIntersectScissor(nvg, x, y, w, h)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, radius)
    -- RenderSurface 纹理在 nvgCreateVideo 下呈现 180° 翻转（本地 surfaceless 出图实测）；
    -- 将 image pattern 绕矩形中心旋转 180° 修正回正立。
    local cx = x + w * 0.5
    local cy = y + h * 0.5
    nvgTranslate(nvg, cx, cy)
    nvgRotate(nvg, math.pi)
    nvgTranslate(nvg, -cx, -cy)
    nvgFillPaint(nvg, nvgImagePattern(nvg, x, y, w, h, 0, nvgImage_, 1))
    nvgFill(nvg)
    nvgRestore(nvg)
end

--- 接地阴影：径向渐变的椭圆软黑影，画在背景之上、角色 RT 之下。
--- 3D 场景里没有投影接收面（castShadows 全关，真机帧率优先），
--- 接地感由这一格 UI 合成提供，锚点与浓度全部来自场景包。
---@param nvg NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
function StatusWindow.DrawGroundShadow(nvg, x, y, w, h)
    local st = sceneState_
    if not st or not st.groundShadow or w <= 1 or h <= 1 then
        return
    end
    local sh = st.groundShadow
    local cx = x + w * sh.anchorX
    local cy = y + h * sh.anchorY
    local rx = w * sh.rx
    local ry = h * sh.ry
    nvgSave(nvg)
    nvgIntersectScissor(nvg, x, y, w, h)
    local paint = nvgRadialGradient(nvg, cx, cy, math.min(rx, ry) * 0.1, math.max(rx, ry),
        nvgRGBA(0, 0, 0, sh.alpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx, cy, rx, ry)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
    nvgRestore(nvg)
end

function StatusWindow.Shutdown()
    stopBootEcho()
    sceneState_ = nil
    baseCharPos_ = nil
    microTime_ = 0
    microPrev_ = 0
    zone_ = nil
    sunNode_ = nil
    coolLight_ = nil
    warmLight_ = nil
    coolLightNode_ = nil
    warmLightNode_ = nil
    if nvgImage_ ~= 0 and nvgImageCtx_ then
        nvgDeleteVideo(nvgImageCtx_, nvgImage_)
    end
    nvgImage_ = 0
    nvgImageCtx_ = nil
    nvgCreateFailed_ = false
    if surface_ then
        surface_:SetNumViewports(0)
    end
    if texture_ then
        texture_:Dispose()
    end
    surface_ = nil
    viewport_ = nil
    texture_ = nil
    camera_ = nil
    cameraNode_ = nil
    characterRoot_ = nil
    noticesChanged_ = nil
    if scene_ then
        scene_:Dispose()
    end
    scene_ = nil
end

-- ---------------------------------------------------------------------------
-- 自定义 Widget：在 Yoga 布局矩形内绘制 3D 预览
-- ---------------------------------------------------------------------------

---@class StatusPreview : Widget
---@overload fun(props?: WidgetProps): StatusPreview
---@field new fun(self: StatusPreview, props?: WidgetProps): StatusPreview
local StatusPreview = Widget:Extend("StatusPreview")

---@param props WidgetProps?
function StatusPreview:Init(props)
    props = props or {}
    props.pointerEvents = "none"
    props.overflow = props.overflow or "hidden"
    Widget.Init(self, props)
end

---@param nvg NVGContextWrapper
function StatusPreview:Render(nvg)
    self:RenderFullBackground(nvg)
    local l = self:GetAbsoluteLayout()
    StatusWindow.DrawGroundShadow(nvg, l.x, l.y, l.w, l.h)
    StatusWindow.Draw(nvg, l.x, l.y, l.w, l.h)
end

function StatusPreview:IsStateful()
    return false
end

---@param props WidgetProps?
---@return StatusPreview
function StatusWindow.CreatePreviewWidget(props)
    return StatusPreview:new(props)
end

return StatusWindow
