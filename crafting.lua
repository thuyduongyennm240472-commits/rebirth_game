-- ============================================================
-- CRAFTING STANDALONE - HỆ THỐNG CHẾ TẠO ĐỘC LẬP (XP FARM)
-- Paste vào executor là chạy ngay, tự động chặt gỗ và spam build
-- ============================================================

-- ==================== CẤU HÌNH (CONFIG) ====================
local CFG = {
    craftId      = 66,       -- ID vật phẩm để spam build/delete (thường là rương hoặc lửa)
    woodId       = 12,       -- ID nguyên liệu gỗ
    chopTool     = 4,        -- Slot dụng cụ chặt cây
    targetLevel  = 999999,   -- Level mục tiêu (vô hạn)
    actionDelay  = 0.1,      -- Độ trễ giữa các lần build
    scanRange    = 5000,     -- Khoảng cách quét cây
    woodPos      = CFrame.new(88, 22.0625, 68), -- Vị trí bãi gỗ mặc định
    targetWood   = {"Big Oak", "Pine", "Oak"},
    excludeWood  = {"Peppers"},
    stuckLimit   = 5,        -- Số lần kẹt cùng 1 cây trước khi hop server
    rbThreshold  = 5,        -- Số lần bị giật teleport (rubber band) trước khi hop server
    lootRange    = 60,       -- Bán kính vặt đồ
    hopCooldown  = 30,       -- Chờ giữa các lần đổi server
}

-- ==================== SERVICES ====================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local CoreGui           = game:GetService("CoreGui")
local Lighting          = game:GetService("Lighting")
local lp = game:GetService("Players").LocalPlayer
while not lp do
    task.wait(0.5)
    lp = game:GetService("Players").LocalPlayer
end

-- ==================== REMOTES ====================
local R = {}
local function loadRemotes()
    local ok, err = pcall(function()
        local ri  = ReplicatedStorage:WaitForChild("remoteInterface", 10)
        local int = ri:WaitForChild("interactions", 5)
        local charR = ri:WaitForChild("character", 5)
        local inv = ri:WaitForChild("inventory", 5)
        local tools = ri:WaitForChild("Tools", 5)

        R.build           = int:WaitForChild("build", 3)
        R.deleteStructure = int:WaitForChild("deleteStructure", 3)
        R.chop            = int:WaitForChild("chop", 3)
        R.reset           = charR:WaitForChild("reset", 3)
        R.respawn         = charR:WaitForChild("respawn", 3)
        R.toolCheck       = tools:WaitForChild("CheckToolSetup", 3)
        R.pickup          = int:WaitForChild("pickupItem", 2) or inv:WaitForChild("pickupItem", 2)
    end)
    return ok
end

-- ==================== REMOVE WATER (OPTIMIZATION) ====================
local function nukeLighting()
    pcall(function()
        for _, e in ipairs(Lighting:GetChildren()) do
            if e:IsA("PostProcessEffect") or e:IsA("Atmosphere") or e:IsA("Clouds") or e:IsA("Sky") then
                e.Parent = nil
            end
        end
        Lighting.Brightness    = 2
        Lighting.FogEnd        = 100000
        Lighting.GlobalShadows = false
        Lighting.Ambient       = Color3.fromRGB(128, 128, 128)
    end)
end

local function liteUIWipe() -- Wipe spawn UI (Safe version)
    local toDestroy = {"menuScreen", "intro", "Intro", "Loading", "introGui", "Announcements", "News"}
    for _, name in ipairs(toDestroy) do
        local ui = lp.PlayerGui:FindFirstChild(name)
        if ui then pcall(function() ui:Destroy() end) end
    end
    local toHide = {"AvatarUI", "SpawnUI", "Menu", "Avatar", "MainGui", "Skills", "Inventory", "Stats", "IndicatorGui"}
    for _, name in ipairs(toHide) do
        local ui = lp.PlayerGui:FindFirstChild(name)
        if ui and ui:IsA("ScreenGui") then pcall(function() ui.Enabled = false end) end
    end
end

local function nuclearScan()
    for _, name in ipairs({"Ocean", "Waves", "OceanZones", "ClientFX", "UnderwaterDecor"}) do
        local obj = workspace:FindFirstChild(name)
        if obj then pcall(function() obj.Parent = nil end) end
    end
end

local function toggleSwim(disable)
    pcall(function()
        local ps = lp:FindFirstChild("PlayerScripts")
        if ps then
            for _, s in ipairs(ps:GetChildren()) do
                if s.Name:lower():find("swim") then s.Disabled = disable end
            end
        end
    end)
end

local function removeWater()
    nukeLighting()
    nuclearScan()
    toggleSwim(true)
    pcall(function()
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false) end
    end)
    RunService.Heartbeat:Connect(function()
        nuclearScan()
        Lighting.FogEnd = 100000
    end)
    print("[CRAFT] Remove Water: ON")
end

-- ==================== LOGGER & HELPERS ====================
local function log(msg) print("[CRAFT] " .. tostring(msg)) end

local function getHRP()
    if not lp then return nil end
    return lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    if not lp then return nil end
    return lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
end

local function getToolSafely(slot)
    local s = tostring(slot)
    local bp = lp:FindFirstChild("Backpack")
    if bp and bp:FindFirstChild(s) then return bp:FindFirstChild(s) end
    return lp.Character and lp.Character:FindFirstChild(s)
end

local function getSkillLevel(skillName)
    local level = 0
    pcall(function()
        for _, gui in ipairs(lp.PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") then
                for _, v in ipairs(gui:GetDescendants()) do
                    if v:IsA("TextLabel") then
                        local txt = v.Text:lower()
                        if txt:find(skillName:lower()) then
                            local lvl = v.Text:match("(%d+)")
                            if lvl then level = math.max(level, tonumber(lvl)) end
                        end
                    end
                end
            end
        end
    end)
    return level
end

local function getItemCount(itemId)
    local count = 0
    local sid = tostring(itemId)
    pcall(function()
        local inv = lp.PlayerGui:FindFirstChild("Inventory") or lp.PlayerGui:FindFirstChild("InventoryUI", true)
        if inv then
            for _, v in ipairs(inv:GetDescendants()) do
                if v.Name == sid and (v:IsA("ImageButton") or v:IsA("Frame")) then
                    local amt = v:FindFirstChild("amount", true)
                    if amt and amt:IsA("TextLabel") then
                        local txt = amt.Text
                        local rawNum = tonumber(txt:match("[%d%.]+"))
                        if rawNum then
                            if txt:find("K") then rawNum = rawNum * 1000
                            elseif txt:find("M") then rawNum = rawNum * 1000000 end
                            count = math.floor(rawNum)
                        end
                        break
                    end
                end
            end
        end
    end)
    return count
end

local function autoClickSpawn()
    if _G.forceSpawn then
        _G.forceSpawn()
    else
        pcall(function()
            local gui = lp.PlayerGui
            local targets = {"SpawnUI", "Menu", "Loading", "Intro", "AvatarUI"}
            for _, name in ipairs(targets) do
                local ui = gui:FindFirstChild(name)
                if ui then
                    for _, btn in ipairs(ui:GetDescendants()) do
                        if btn:IsA("GuiButton") and btn.Visible then
                            local t = btn.Name:lower()
                            local txt = (btn:FindFirstChildOfClass("TextLabel") and btn:FindFirstChildOfClass("TextLabel").Text or btn.Text):lower()
                            if t:find("spawn") or t:find("play") or t:find("start") or 
                               txt:find("spawn") or txt:find("play") or txt:find("start") then
                                local vUser = game:GetService("VirtualUser")
                                vUser:CaptureController()
                                vUser:ClickButton1(Vector2.new(btn.AbsolutePosition.X + (btn.AbsoluteSize.X/2), btn.AbsolutePosition.Y + (btn.AbsoluteSize.Y/2)))
                                task.wait(0.5)
                            end
                        end
                    end
                end
            end
        end)
    end
end

-- Auto spawning loop
task.spawn(function()
    while true do
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then
            autoClickSpawn()
        end
        task.wait(2)
    end
end)

local function waitForAlive()
    if not lp then return nil, nil end
    local char = lp.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then
        log("Đang đợi hồi sinh...")
        while not hrp or not hum or hum.Health <= 0 do
            autoClickSpawn()
            task.wait(1)
            char = lp.Character
            if char then
                hrp = char:FindFirstChild("HumanoidRootPart")
                hum = char:FindFirstChildOfClass("Humanoid")
            end
        end
    end
    return hrp, hum
end

local function checkHunger()
    pcall(function()
        local hunger = lp.PlayerGui:FindFirstChild("hunger", true)
        if hunger then
            local stat = hunger:FindFirstChild("stat", true)
            if stat and stat:IsA("TextLabel") then
                local val = tonumber(stat.Text:gsub("%D+", ""))
                if val and val < 200 then
                    log("Đói quá! Reset để hồi phục...")
                    R.respawn:InvokeServer(15382674, 12, 2, 17, 15382674, 15382674, false)
                    task.wait(5)
                end
            end
        end
    end)
end

-- ==================== INSTANT LOOT ====================
task.spawn(function()
    while true do
        pcall(function()
            local dropped = workspace:FindFirstChild("droppedItems")
            local hrp = getHRP()
            if dropped and hrp then
                for _, obj in ipairs(dropped:GetChildren()) do
                    local name = obj.Name:lower()
                    -- Blacklist: Bỏ qua đồ rác
                    if not name:find("carrot") and not name:find("pepper") and 
                       not name:find("seaweed") and not name:find("cabbage") then
                        local bp = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
                        if bp and (bp.Position - hrp.Position).Magnitude < CFG.lootRange then
                            bp.CanCollide = false
                            bp.CFrame     = hrp.CFrame -- Kéo về phía mình
                            pcall(function() R.pickup:FireServer(obj) end)
                        end
                    end
                end
            end
        end)
        task.wait(0.1)
    end
end)

-- ==================== SERVER HOP & PROTECTION ====================
local isHopping = false
local lastHopTime = 0

local function serverHop(reason)
    if isHopping or (tick() - lastHopTime < CFG.hopCooldown) then return end
    isHopping = true
    lastHopTime = tick()
    log("Server Hop: " .. (reason or "Yêu cầu"))

    local function getServers()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        local rawData
        pcall(function() rawData = game:HttpGet(url) end)
        if rawData then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(rawData) end)
            if ok and decoded and decoded.data then return decoded.data end
        end
        return nil
    end

    local serverList = getServers()
    if serverList then
        local available = {}
        for _, s in ipairs(serverList) do
            if s.id ~= game.JobId and s.playing < s.maxPlayers then table.insert(available, s) end
        end
        for i = #available, 2, -1 do
            local j = math.random(i)
            available[i], available[j] = available[j], available[i]
        end
        for _, s in ipairs(available) do
            log("Vào server: " .. s.id)
            pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id) end)
            task.wait(5)
        end
    end
    pcall(function() TeleportService:Teleport(game.PlaceId) end)
    task.wait(10)
    isHopping = false
end

-- Kick/267 Detection
task.spawn(function()
    while true do
        pcall(function()
            local prompt = CoreGui:FindFirstChild("RobloxPromptGui")
            if prompt and prompt:FindFirstChild("promptOverlay") then
                local err = prompt.promptOverlay:FindFirstChild("ErrorPrompt")
                if err then
                    log("Phát hiện bị Kick/Lỗi! Đang chuyển server...")
                    serverHop("Bị Kick hoặc Lỗi Game")
                end
            end
        end)
        task.wait(2)
    end
end)

-- ==================== TELEPORT ====================
local rbCount = 0
local function instantTP(cf)
    local hrp = getHRP()
    if not hrp then return end
    
    local oldPos = hrp.Position
    for _ = 1, 10 do
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
        task.wait(0.05)
    end
    
    -- Kiểm tra giật (Rubber Band)
    if (hrp.Position - oldPos).Magnitude < 1 then
        rbCount = rbCount + 1
        if rbCount >= CFG.rbThreshold then
            serverHop("Bị giật teleport (Rubber band)")
        end
    else
        rbCount = 0
    end
end

-- ==================== WOODCUTTING LOGIC (FOR RESOURCES) ====================
local function getNearestTree()
    local worldRes = workspace:FindFirstChild("worldResources")
    local choppable = worldRes and worldRes:FindFirstChild("choppable")
    if not choppable then return nil, 0 end
    local hrp = getHRP()
    if not hrp then return nil, 0 end

    local nearest, minDist = nil, CFG.scanRange
    for _, obj in ipairs(choppable:GetDescendants()) do
        local isTarget = false
        for _, name in ipairs(CFG.targetWood) do if obj.Name:find(name) then isTarget = true break end end
        if isTarget then
            for _, ex in ipairs(CFG.excludeWood) do if obj.Name:find(ex) then isTarget = false break end end
        end

        if isTarget then
            local hp = obj:GetAttribute("health")
            if hp == nil or hp > 0 then
                local ok, pos = pcall(function() return obj:GetPivot().Position end)
                if ok and pos then
                    local d = (hrp.Position - pos).Magnitude
                    if d < minDist then minDist, nearest = d, obj end
                end
            end
        end
    end
    return nearest, minDist
end

local function gatherWood()
    log("Thiếu gỗ! Đang đi chặt cây...")
    local startGather = tick()
    local stuckCount = 0
    local lastTreePos = nil

    while getItemCount(CFG.woodId) < 5 and (tick() - startGather < 60) do
        checkHunger()
        local tree, dist = getNearestTree()
        if tree then
            local treePos = tree:GetPivot().Position
            if lastTreePos and (treePos - lastTreePos).Magnitude < 1 then
                stuckCount = stuckCount + 1
                if stuckCount >= CFG.stuckLimit then serverHop("Kẹt cây khi chặt gỗ") return end
            else stuckCount = 0 end
            lastTreePos = treePos

            if dist > 30 then instantTP(CFrame.new(treePos + Vector3.new(0, 5, 0))) end
            
            local tool = getToolSafely(CFG.chopTool)
            if tool then pcall(function() R.toolCheck:InvokeServer(tool) end) end

            local chopStart = tick()
            while tree and tree.Parent and (tick() - chopStart < 10) do
                pcall(function() R.chop:FireServer(CFG.chopTool, tree, tree:GetPivot()) end)
                task.wait(0.2)
                local hp = tree:GetAttribute("health")
                if hp and hp <= 0 then break end
            end
        else
            task.wait(1)
        end
    end
end

-- ==================== CRAFTING LOGIC ====================
local function findAndDestroy(myPos)
    local folders = {
        workspace:FindFirstChild("placedStructures"),
        workspace:FindFirstChild("PlayerStructures"),
        workspace:FindFirstChild("buildings"),
        workspace:FindFirstChild("Structures")
    }
    
    for _, f in ipairs(folders) do
        if f then
            for _, obj in ipairs(f:GetDescendants()) do
                if (obj:IsA("Model") or obj:IsA("BasePart")) and not Players:GetPlayerFromCharacter(obj) and obj ~= lp.Character then
                    local ok, pos = pcall(function() return obj:IsA("Model") and obj:GetPivot().Position or obj.Position end)
                    if ok and pos and (pos - myPos).Magnitude < 40 then
                        pcall(function() R.deleteStructure:FireServer(obj) end)
                        return true
                    end
                end
            end
        end
    end
    
    -- Quét nhanh workspace (chỉ con trực tiếp) nếu không tìm thấy trong folder
    for _, obj in ipairs(workspace:GetChildren()) do
        if (obj:IsA("Model") or obj:IsA("BasePart")) and not Players:GetPlayerFromCharacter(obj) and obj ~= lp.Character then
            local ok, pos = pcall(function() return obj:IsA("Model") and obj:GetPivot().Position or obj.Position end)
            if ok and pos and (pos - myPos).Magnitude < 40 then
                pcall(function() R.deleteStructure:FireServer(obj) end)
                return true
            end
        end
    end
    
    return false
end

-- ==================== MAIN LOOP ====================
if not loadRemotes() then warn("Không load được Remotes!") return end
removeWater()
waitForAlive()
log("=== CRAFTING STANDALONE BẮT ĐẦU ===")

local lastWoodTime   = tick()
local lastActionTime = tick() -- Watchdog timer

while true do
    checkHunger()
    local hrp, hum = waitForAlive()

    -- Anti-Kill
    local lastHp = hum.Health
    local dmgConn = hum.HealthChanged:Connect(function(hp)
        if hp < lastHp - 5 then serverHop("Bị tấn công khi crafting") end
        lastHp = hp
    end)

    -- Check Resources (Trì hoãn 5 giây)
    local woodCount = getItemCount(CFG.woodId)
    if woodCount >= 5 then
        lastWoodTime = tick()
    elseif tick() - lastWoodTime > 5 then
        gatherWood()
        lastWoodTime = tick()
        hrp = getHRP()
    end

    -- Crafting Cycle
    if hrp then
        local myPos = hrp.Position
        local spawnCF = hrp.CFrame * CFrame.new(0, 0, -7)

        -- Build
        task.spawn(function()
            pcall(function() R.build:InvokeServer(CFG.craftId, spawnCF, -1.570796) end)
        end)

        -- Delete (Chờ build xong rồi xóa ngay)
        local start = tick()
        while (tick() - start < 1) do
            if findAndDestroy(myPos) then 
                lastActionTime = tick() -- Cập nhật Watchdog khi xóa thành công
                break 
            end
            task.wait(0.05)
        end
    end

    -- Watchdog: Nếu 15 giây không có hành động thành công (build/destroy bị kẹt)
    if tick() - lastActionTime > 15 then
        log("WATCHDOG: Quá 15 giây không có hành động! Đang thực hiện Ping và Hop Server...")
        pcall(function()
            local args = { Instance.new("Part", nil) }
            game:GetService("ReplicatedStorage"):WaitForChild("remoteInterface"):WaitForChild("inventory"):WaitForChild("pickupItem"):FireServer(unpack(args))
        end)
        task.wait(1)
        serverHop("Kẹt trong chu kỳ Crafting (Watchdog 15s)")
    end

    dmgConn:Disconnect()
    task.wait(CFG.actionDelay)
end
