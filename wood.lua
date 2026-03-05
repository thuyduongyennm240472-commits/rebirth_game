--[[
    WOOD.LUA v3.0 - MAX SPEED + FULL PROTECTION
    - Respawn TP cố định về (96, 22.0625, 52) khi vào game
    - Tốc độ chặt tối đa (0.05s delay)
    - Dưới 50 studs: Instant TP → Chặt
    - Trên 50 studs: Respawn TP → Sticky → Chặt
    - Không tìm thấy cây → Hop Server ngay
    - Loot Blacklist: Carrot, Pepper, Seaweed, Cabbage
    - Bảo vệ: Anti-Kill, Anti-Kick, Hunger Check, Remove Water
]]

if not game:IsLoaded() then game.Loaded:Wait() end
local lp = game:GetService("Players").LocalPlayer
repeat task.wait() until lp and lp:FindFirstChild("PlayerGui")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local CoreGui           = game:GetService("CoreGui")
local Lighting          = game:GetService("Lighting")

-- ==================== REMOTES ====================
local ri            = ReplicatedStorage:WaitForChild("remoteInterface")
local intRemotes    = ri:WaitForChild("interactions")
local invRemotes    = ri:WaitForChild("inventory")
local charRemotes   = ri:WaitForChild("character")
local toolRemotes   = ri:WaitForChild("Tools", 5)

local chopRemote    = intRemotes:WaitForChild("chop")
local resetRemote   = charRemotes:WaitForChild("reset")
local respawnRemote = charRemotes:WaitForChild("respawn")
local pickupRemote  = intRemotes:WaitForChild("pickupItem", 2) or invRemotes:WaitForChild("pickupItem", 2)
local toolCheck     = toolRemotes and toolRemotes:WaitForChild("CheckToolSetup", 3)

-- ==================== CONFIG ====================
-- ★ Tọa độ spawn cố định (khu vực nhiều cây gỗ)
local SPAWN_POS = CFrame.new(
    -104.706573, 24.2193909, 206.016602,
     0.769942045, 0, -0.638113856,
     0,           1,  0,
     0.638113856, 0,  0.769942045
)
local TOOL_SLOT     = 4
local SCAN_RANGE    = 5000
local LOOT_RANGE    = 80
local HOP_COOLDOWN  = 30
local RESPAWN_ARGS  = {15382674, 12, 2, 17, 15382674, 15382674, false}

local state = {
    enabled       = true,
    isTeleporting = false,
    targetCF      = nil,
    targetTree    = nil,
    lastSuccess   = tick(),
    stuckCount    = 0,
    lastTargetPos = nil,
}

local function log(msg) print("[WOOD] " .. tostring(msg)) end

-- ==================== REMOVE WATER ====================
local function nukeScan()
    for _, n in ipairs({"Ocean","Waves","OceanZones","ClientFX","UnderwaterDecor"}) do
        local o = workspace:FindFirstChild(n)
        if o then pcall(function() o.Parent = nil end) end
    end
end
local function removeWater()
    pcall(function()
        for _, e in ipairs(Lighting:GetChildren()) do
            if e:IsA("PostProcessEffect") or e:IsA("Atmosphere") or e:IsA("Clouds") or e:IsA("Sky") then e.Parent = nil end
        end
        Lighting.Brightness = 2; Lighting.FogEnd = 100000; Lighting.GlobalShadows = false
    end)
    nukeScan()
    pcall(function()
        local ps = lp:FindFirstChild("PlayerScripts")
        if ps then for _, s in ipairs(ps:GetChildren()) do if s.Name:lower():find("swim") then s.Disabled = true end end end
    end)
    RunService.Heartbeat:Connect(function() nukeScan(); Lighting.FogEnd = 100000 end)
    log("Remove Water: ON")
end

-- ==================== HELPERS ====================
local function getHRP() return lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") end

local function liteUIWipe()
    pcall(function()
        for _, n in ipairs({"menuScreen","intro","Intro","Loading","introGui","Announcements","News"}) do
            local ui = lp.PlayerGui:FindFirstChild(n); if ui then ui:Destroy() end
        end
        for _, n in ipairs({"AvatarUI","SpawnUI","Menu","Avatar","MainGui","Skills","Inventory","Stats","IndicatorGui"}) do
            local ui = lp.PlayerGui:FindFirstChild(n)
            if ui and ui:IsA("ScreenGui") then ui.Enabled = false end
        end
    end)
end

local function checkHunger()
    pcall(function()
        local hunger = lp.PlayerGui:FindFirstChild("hunger", true)
        if hunger then
            local stat = hunger:FindFirstChild("stat", true)
            if stat and stat:IsA("TextLabel") then
                local val = tonumber(stat.Text:gsub("%D+",""))
                if val and val < 200 then
                    log("Đói! Auto reset...")
                    respawnRemote:InvokeServer(unpack(RESPAWN_ARGS))
                    task.wait(5)
                end
            end
        end
    end)
end

-- ==================== SERVER HOP ====================
local isHopping   = false
local lastHopTime = 0

local function serverHop(reason)
    if isHopping or (tick() - lastHopTime < HOP_COOLDOWN) then return end
    isHopping   = true
    lastHopTime = tick()
    log("Hop: " .. (reason or "?"))
    local ok, raw = pcall(game.HttpGet, game, "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
    if ok and raw then
        local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok2 and data and data.data then
            for _, s in ipairs(data.data) do
                if s.id ~= game.JobId and tonumber(s.playing) < tonumber(s.maxPlayers) then
                    pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id) end)
                    task.wait(3)
                end
            end
        end
    end
    pcall(function() TeleportService:Teleport(game.PlaceId) end)
    task.wait(10)
    isHopping = false
end

-- ==================== PROTECTION LOOPS ====================
-- Anti-Kick
task.spawn(function()
    while true do
        pcall(function()
            local p = CoreGui:FindFirstChild("RobloxPromptGui")
            if p and p:FindFirstChild("promptOverlay") and p.promptOverlay:FindFirstChild("ErrorPrompt") then
                serverHop("Kick/Error detected")
            end
        end)
        task.wait(2)
    end
end)

-- Anti-Kill
task.spawn(function()
    while true do
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            local lastHp = hum.Health
            local conn
            conn = hum.HealthChanged:Connect(function(hp)
                if hp < lastHp - 5 then
                    conn:Disconnect()
                    serverHop("Bị tấn công!")
                end
                lastHp = hp
            end)
            while hum and hum.Parent do task.wait(1) end
            pcall(function() conn:Disconnect() end)
        end
        task.wait(1)
    end
end)

-- Instant Loot
task.spawn(function()
    while true do
        pcall(function()
            local dropped = workspace:FindFirstChild("droppedItems")
            local hrp = getHRP()
            if dropped and hrp then
                for _, obj in ipairs(dropped:GetChildren()) do
                    local n = obj.Name:lower()
                    if not n:find("carrot") and not n:find("pepper") and
                       not n:find("seaweed") and not n:find("cabbage") then
                        local bp = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
                        if bp and (bp.Position - hrp.Position).Magnitude < LOOT_RANGE then
                            bp.CanCollide = false
                            bp.CFrame = hrp.CFrame
                            pcall(function() pickupRemote:FireServer(obj) end)
                        end
                    end
                end
            end
        end)
        task.wait(0.1)
    end
end)

-- ==================== TREE SCANNER ====================
local function getNearestTree()
    local choppable = workspace:FindFirstChild("worldResources") and workspace.worldResources:FindFirstChild("choppable")
    if not choppable then return nil, nil end
    local hrp = getHRP()
    if not hrp then return nil, nil end

    local nearest, minDist = nil, SCAN_RANGE
    for _, seg in ipairs(choppable:GetChildren()) do
        for _, tree in ipairs(seg:GetChildren()) do
            local n = tree.Name:lower()
            -- Blacklist đầy đủ: loại trừ tất cả thứ không phải cây gỗ
            local isBlacklisted = n:find("mushroom") or n:find("deathwish") or
                                  n:find("bush")     or n:find("shrub")     or
                                  n:find("wheat")    or n:find("seaweed")   or
                                  n:find("carrot")   or n:find("pepper")    or
                                  n:find("cabbage")
            if not isBlacklisted then
                local hp = tree:GetAttribute("health")
                if hp == nil or hp > 0 then
                    local pos = tree:IsA("PVInstance") and tree:GetPivot().Position
                    if pos then
                        local d = (hrp.Position - pos).Magnitude
                        if d < minDist then minDist = d; nearest = tree end
                    end
                end
            end
        end
    end
    return nearest, minDist
end

-- ==================== CHOP (MAX SPEED) ====================
local function startChopping(tree)
    if not tree or not tree.Parent then return end
    local tool = (lp.Character and lp.Character:FindFirstChild(tostring(TOOL_SLOT)))
               or (lp.Backpack and lp.Backpack:FindFirstChild(tostring(TOOL_SLOT)))
    if tool and toolCheck then pcall(function() toolCheck:InvokeServer(tool) end) end

    local t0 = tick()
    while state.enabled and tree and tree.Parent and (tick() - t0 < 5) do
        local hp = tree:GetAttribute("health")
        if hp and hp <= 0 then break end
        pcall(function() chopRemote:FireServer(TOOL_SLOT, tree, tree:GetPivot()) end)
        task.wait(0.05) -- MAX SPEED
    end
end

-- ==================== TELEPORT ====================
local function respawnTP(cf, tree)
    state.isTeleporting = true
    state.targetCF      = cf
    state.targetTree    = tree
    
    log("[RESPAWN] Bắt đầu chu trình Reset...")
    pcall(function() resetRemote:InvokeServer() end)
    task.wait(0.5)
    
    -- Thử hồi sinh qua Remote
    pcall(function() respawnRemote:InvokeServer(unpack(RESPAWN_ARGS)) end)
    
    -- Watchdog: Nếu sau 3 giây vẫn chưa hồi sinh, thử dùng forceSpawn (Menu Skip)
    task.delay(3, function()
        if state.isTeleporting and not getHRP() then
            log("[WATCHDOG] Cảnh báo: Respawn chậm, đang dùng forceSpawn...")
            if _G.forceSpawn then 
                _G.forceSpawn() 
            else
                autoClickSpawn()
            end
        end
    end)
end

local function instantTP(cf)
    local hrp = getHRP()
    if not hrp then return end
    for _ = 1, 8 do
        if not hrp.Parent then break end
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
        task.wait(0.03)
    end
end

-- ==================== FARM LOOP ====================
local function farmLoop()
    if not state.enabled then return end
    checkHunger()

    local tree, dist = getNearestTree()
    if not tree then
        log("Không thấy cây → Hop Server!")
        serverHop("Hết cây")
        return
    end

    local targetPos = tree:GetPivot().Position
    local targetCF  = CFrame.new(targetPos + Vector3.new(0, 5, 0))
    local hrp = getHRP()
    if not hrp then task.spawn(farmLoop); return end

    -- Stuck detection
    if state.lastTargetPos and (targetPos - state.lastTargetPos).Magnitude < 1 then
        state.stuckCount = state.stuckCount + 1
        if state.stuckCount >= 8 then
            serverHop("Bị kẹt cây")
            return
        end
    else
        state.stuckCount = 0
    end
    state.lastTargetPos = targetPos

    if dist < 50 then
        -- ★ INSTANT TP (< 50 studs)
        instantTP(targetCF)
        startChopping(tree)
        state.lastSuccess = tick()
    else
        -- ★ RESPAWN TP (> 50 studs)
        log("[RESPAWN TP] " .. tree.Name .. " - " .. math.floor(dist) .. "s")
        respawnTP(targetCF, tree)
        return -- farmLoop sẽ tiếp tục từ CharacterAdded
    end

    task.spawn(farmLoop)
end

-- ==================== CHARACTER ADDED ====================
lp.CharacterAdded:Connect(function(char)
    liteUIWipe()
    task.spawn(function()
        local hrp = char:WaitForChild("HumanoidRootPart", 10)
        if not hrp then return end
        task.wait(0.3)

        if state.isTeleporting and state.targetCF then
            -- Đến đúng cây đang chặt
            log("[STICKY TP] → Cây mục tiêu")
            for _ = 1, 20 do
                if not hrp.Parent then break end
                hrp.CFrame = state.targetCF
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                task.wait(0.08)
            end
            state.isTeleporting = false
            state.lastSuccess = tick()
            local tree = state.targetTree
            state.targetTree = nil
            if tree then startChopping(tree) end
        else
            -- ★ SPAWN BÌNH THƯỜNG → TP VỀ ĐIỂM FARM CỐ ĐỊNH
            log("[SPAWN TP] → (96, 22, 52)")
            for _ = 1, 20 do
                if not hrp.Parent then break end
                hrp.CFrame = SPAWN_POS
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                task.wait(0.08)
            end
            state.lastSuccess = tick()
        end

        task.spawn(farmLoop)
    end)
end)

-- ==================== GUI SETUP (From User v1.0) ====================
local function setupGUI()
    pcall(function()
        local sg = Instance.new("ScreenGui")
        sg.Name = "WoodFarmStatus"
        if gethui then sg.Parent = gethui() else sg.Parent = game:GetService("CoreGui") end

        local m = Instance.new("Frame")
        m.Size = UDim2.new(0, 200, 0, 100)
        m.Position = UDim2.new(0, 50, 0, 50)
        m.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        m.Draggable = true
        m.Active = true
        m.Parent = sg
        Instance.new("UICorner").Parent = m

        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, 0, 0, 30)
        t.Text = "WOOD FARM v3.0"
        t.TextColor3 = Color3.new(1, 1, 1)
        t.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
        t.Parent = m
        Instance.new("UICorner").Parent = t

        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.9, 0, 0, 40)
        b.Position = UDim2.new(0.05, 0, 0, 45)
        b.Text = state.enabled and "DỪNG FARM" or "BẮT ĐẦU"
        b.BackgroundColor3 = state.enabled and Color3.fromRGB(150, 0, 0) or Color3.fromRGB(50, 50, 50)
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Parent = m
        Instance.new("UICorner").Parent = b

        b.MouseButton1Click:Connect(function()
            state.enabled = not state.enabled
            b.Text = state.enabled and "DỪNG FARM" or "BẮT ĐẦU"
            b.BackgroundColor3 = state.enabled and Color3.fromRGB(150, 0, 0) or Color3.fromRGB(50, 50, 50)
            if state.enabled then task.spawn(farmLoop) end
        end)
    end)
end

-- ==================== INIT ====================
removeWater()
state.enabled = true
setupGUI()
log("=== WOOD MAX SPEED v3.0 LOADED ===")
log("Farm point: (96, 22.0625, 52)")

-- Respawn ngay lập tức để TP về điểm farm
log("Đang respawn về điểm farm...")
pcall(function() resetRemote:InvokeServer() end)
task.wait(0.4)
pcall(function() respawnRemote:InvokeServer(unpack(RESPAWN_ARGS)) end)
-- farmLoop sẽ tự chạy từ CharacterAdded sau khi respawn xong
