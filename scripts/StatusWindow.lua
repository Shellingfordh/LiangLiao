-- ============================================================================
-- StatusWindow.lua — M0-0 若夕 3D 状态窗
-- 固定相机、无交互。将独立预览场景渲染到 Texture2D，再由 UI 绘制。
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
-- 唯一背景路径：与 .project/resources.json 的 groups.default 白名单一致。
-- 多候选回退在这里没有意义——不在白名单里的候选在设备上永远取不到，只会误导排查。
local BACKGROUND_PATH = "Textures/backgrounds/la-cafe-4x3.png"
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

---@param node Node
---@param out Drawable[]
local function collectDrawables(node, out)
    local animated = node:GetComponent("AnimatedModel")
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
        end
        logInfo("已加载 LightGroup 预设（黄昏/白天）")
    else
        logWarn("未找到 LightGroup 预设，使用备用方向光")
        local sunNode = scene:CreateChild("Sun")
        sunNode.direction = Vector3(0.4, -0.7, 0.5)
        local sun = sunNode:CreateComponent("Light")
        sun.lightType = LIGHT_DIRECTIONAL
        sun.color = Color(1.0, 0.82, 0.68)
        sun.brightness = 3.2
        sun.castShadows = true
    end

    -- 右前补光，让人物面部和夹克更清晰
    local fillNode = scene:CreateChild("FillLight")
    fillNode.position = Vector3(1.6, 1.8, 2.4)
    local fill = fillNode:CreateComponent("Light")
    fill.lightType = LIGHT_POINT
    fill.color = Color(1.0, 0.92, 0.85)
    fill.brightness = 1.6
    fill.range = 8.0
    fill.castShadows = false
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
        logError("角色材质加载失败: " .. MATERIAL_PATH)
        return
    end
    local animated = node:GetComponent("AnimatedModel", true)
    local staticModel = node:GetComponent("StaticModel", true)
    local drawable = animated or staticModel
    if not drawable then
        logWarn("绑定材质时未找到 StaticModel/AnimatedModel")
        return
    end
    drawable:SetMaterial(mat)
    drawable.castShadows = false
    logInfo("已绑定角色漫反射材质: " .. MATERIAL_PATH)

    -- 角色漫反射贴图是 DWP 资源：设备冷启动时材质内引用可能是占位（角色偏黑）。
    -- 显式异步补载并在就绪后回填到材质贴图槽 + 重渲染，仅涉及“加载”，不改 Technique/法线等 M0-1 内容。
    cache:GetResourceAsync("Texture2D", CHARACTER_DIFFUSE_TEXTURE, function(resource)
        local tex = resource and (resource --[[@as Texture2D]]) or nil
        if not tex then
            logWarn("角色漫反射贴图异步加载失败: " .. CHARACTER_DIFFUSE_TEXTURE)
            return
        end
        mat:SetTexture(TU_DIFFUSE, tex)
        logInfo("已回填角色漫反射贴图: " .. CHARACTER_DIFFUSE_TEXTURE)
        if surface_ then
            surface_:QueueUpdate()
        end
        if noticesChanged_ then
            noticesChanged_()
        end
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
        logError("GetResource(Model) 失败: " .. mdlPath)
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
        logInfo("模型含骨骼 (" .. tostring(boneCount) .. ")，使用 AnimatedModel 静态站姿（M0-0 不播动画）")
    else
        drawable = characterRoot_:CreateComponent("StaticModel")
        logInfo("模型无骨骼，使用 StaticModel")
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
        logError("GetResource(XMLFile) 失败: " .. prefabPath)
        return false
    end
    local ok = characterRoot_:LoadXML(prefabFile:GetRoot())
    if not ok then
        logError("LoadXML 预制体失败: " .. prefabPath)
        return false
    end
    logInfo("已加载角色预制体: " .. prefabPath)
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

--- 固定镜头：人物在画面右侧约占 60% 高度（留头量），背景静帧留在左侧
local function frameFixedCamera()
    if not cameraNode_ or not characterRoot_ then
        return
    end
    local bbox = computeWorldBounds(characterRoot_)
    local center = Vector3(0.55, 0.84, 0.0)
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

    -- 将注视点左移，使人物落在画面右侧约 71% 处；背景留在左侧
    local look = Vector3(center.x - viewW * 0.21, bbox and (bbox.min.y + height * 0.52) or 0.86, center.z)
    local camPos = Vector3(look.x, look.y + height * 0.04, center.z + dist)

    cameraNode_.position = camPos
    cameraNode_:LookAt(look, Vector3.UP, TS_WORLD)

    -- 角色只绕 Y 转向相机，保持站姿，不引入俯仰。
    -- LookAt 把节点局部 -Z 对准目标，而 lin-ruoxi MDL 正面朝局部 +Z，
    -- 不补这 180° 实机看到的就是后脑勺（2026-09-20 预览截图实测）。
    local charPos = characterRoot_.position
    characterRoot_:LookAt(Vector3(camPos.x, charPos.y, camPos.z), Vector3.UP, TS_WORLD)
    characterRoot_:Rotate(Quaternion(180, Vector3.UP))

    if surface_ then
        surface_:QueueUpdate()
    end

    logInfo(string.format(
        "固定相机 pos=(%.2f,%.2f,%.2f) look=(%.2f,%.2f,%.2f) dist=%.2f",
        camPos.x, camPos.y, camPos.z, look.x, look.y, look.z, dist
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

    logInfo("资源检查 GLB=" .. tostring(glbExists) .. " path=" .. GLB_PATH)
    logInfo("资源检查 prefab=" .. tostring(prefabPath) .. " mdl=" .. tostring(mdlPath))

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
        logInfo("若夕 3D 模型加载成功")
    else
        modelLoaded_ = false
        if glbExists then
            modelError_ = "已找到 lin-ruoxi.glb，但缺少 Meshes/lin-ruoxi.mdl。请用 UrhoXCLI import-gltf 导入后再预览。"
        else
            modelError_ = "未找到角色模型。请将最终 GLB 放到 assets/models/characters/lin-ruoxi/lin-ruoxi.glb，并导入为 Meshes/lin-ruoxi.mdl。"
        end
        logError(modelError_)
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

function StatusWindow.WarmUpBackground(onReady)
    PrepareBackground(BACKGROUND_PATH, onReady, function(path)
        backgroundError_ = "4:3 咖啡馆背景未下载成功，当前状态窗只有角色。"
        logError(backgroundError_ .. " path=" .. path)
        if noticesChanged_ then
            noticesChanged_()
        end
    end)
end

-- 场景资产清单：scene_id → 远景静帧。作息表里的 apartment / campus / studio / commute
-- 目前没有原创静帧（见 BLOCKED.md），缺资产就显式留在咖啡馆，不伪称已经切换。
---@type table<string, string>
local SCENE_BACKGROUNDS = {
    la_cafe = BACKGROUND_PATH,
    -- 开发测试用原创占位图；正式资产替换后只需改这里的路径，不改状态机。
    la_apartment = "Textures/backgrounds/la-apartment-dev-placeholder.png",
}

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

--- 按 scene_id 尝试切换远景。无资产时保留当前静帧并留下可上屏的说明。
---@param sceneId string
---@param onApplied fun(path: string)
---@return string result unchanged | pending | missing-asset
function StatusWindow.RequestScene(sceneId, onApplied)
    if sceneId == "" or sceneId == currentSceneId_ then
        return "unchanged"
    end
    local path = SCENE_BACKGROUNDS[sceneId]
    currentSceneId_ = sceneId
    if not path then
        sceneNotice_ = "场景 " .. sceneId .. " 暂无原创静帧，状态窗沿用咖啡馆画面"
        logWarn("场景未切换（缺资产）: " .. sceneId)
        if noticesChanged_ then
            noticesChanged_()
        end
        return "missing-asset"
    end
    sceneNotice_ = ""
    logInfo("切换状态窗场景: " .. sceneId .. " → " .. path)
    PrepareBackground(path, function(ready)
        onApplied(ready)
        if noticesChanged_ then
            noticesChanged_()
        end
    end, function(failed)
        backgroundError_ = "场景 " .. sceneId .. " 的静帧未下载成功，状态窗沿用上一帧画面。"
        logError(backgroundError_ .. " path=" .. failed)
        if noticesChanged_ then
            noticesChanged_()
        end
    end)
    return "pending"
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
end

function StatusWindow.IsModelLoaded()
    return modelLoaded_
end

function StatusWindow.IsUsingPlaceholderCharacter()
    return usingPlaceholderCharacter_
end

function StatusWindow.GetModelError()
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

function StatusWindow.Shutdown()
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
