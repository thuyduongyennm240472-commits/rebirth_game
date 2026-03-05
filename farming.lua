-- ============================================================
-- FARMING STANDALONE - HỆ THỐNG TRỒNG TRỌT ĐỘC LẬP
-- Paste vào executor là chạy ngay, không cần file khác
-- ============================================================

-- ==================== CẤU HÌNH (CONFIG) ====================
local CFG = {
    plantTool    = 9,        -- Slot dụng cụ gieo hạt (Mặc định)
    harvestTool  = 10,       -- Slot dụng cụ gặt (Mặc định)
    plantType    = 210,      -- Loại cây trồng (210 là lúa mì/cà rốt theo game)
    targetLevel  = 999999,    -- Phải để lớn hơn level hiện tại của bạn (bạn đang 1296)
    actionDelay  = 0.1,      -- Độ trễ spam gặt/trồng
    auraRange    = 20,       -- Bán kính nhận diện đất quanh vị trí farm (Tăng lên 20)
    tpThreshold  = 50,       -- Xa hơn bao nhiêu studs thì dùng Respawn-TP
    afkCheckTime = 30,       -- Kiểm tra vị trí mỗi 30 giây
    rbThreshold  = 5,        -- Rubber band quá 5 lần thì hop server
    hopCooldown  = 30,       -- Chờ giữa các lần đổi server
    autoFindTools = true,    -- Tự động tìm kiếm dụng cụ trong túi đồ
}

-- Tọa độ 6 ô đất cố định
local OWN_SLOTS = {
    Vector3.new(88, 22.0625, 68), Vector3.new(80, 22.0625, 68),
    Vector3.new(96, 22.0625, 60), Vector3.new(88, 22.0625, 60),
    Vector3.new(96, 22.0625, 52), Vector3.new(88, 22.0625, 52),
}
local FARM_CENTER = Vector3.new(88, 22.06, 60)

-- ==================== SERVICES ====================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local CoreGui           = game:GetService("CoreGui")
local lp                = Players.LocalPlayer

-- ==================== REMOTES ====================
local R = {}
local function loadRemotes()
    local ok, err = pcall(function()
        local ri  = ReplicatedStorage:WaitForChild("remoteInterface", 10)
        local int = ri:WaitForChild("interactions", 5)
        R.harvest        = int:WaitForChild("harvest", 3)
        R.plant          = int:WaitForChild("plant", 3)
        R.createFarmland = int:WaitForChild("createFarmland", 3)
        R.pickup         = int:WaitForChild("pickupItem", 2)

        local charR   = ri:WaitForChild("character", 5)
        R.reset    = charR:WaitForChild("reset", 3)
        R.respawn  = charR:WaitForChild("respawn", 3)

        local tools   = ri:WaitForChild("Tools", 5)
        R.toolCheck   = tools:WaitForChild("CheckToolSetup", 3)
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
    print("[FARM] Remove Water: ON")
end

-- ==================== LOGGER & HELPERS ====================
local function log(msg)
    print("[FARM] " .. tostring(msg))
end

local function getHRP()
    local char = lp.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local char = lp.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getToolSafely(slot)
    local s  = tostring(slot)
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

local function autoFindTools()
    if not CFG.autoFindTools then return end
    pcall(function()
        local bp = lp:FindFirstChild("Backpack")
        if not bp then return end
        for i = 1, 10 do
            local tool = bp:FindFirstChild(tostring(i))
            if tool then
                local name = tool.Name:lower()
                -- Tìm hạt giống (Seeds / Wheat / Carrot / ...)
                if name:find("seed") or name:find("wheat") or name:find("carrot") or name:find("plant") then
                    if CFG.plantTool ~= i then
                        CFG.plantTool = i
                        log("Tự động nhận diện Hạt giống tại Slot: " .. i)
                    end
                end
                -- Tìm dụng cụ gặt (Sickle / Scythe / Harvest / ...)
                if name:find("sickle") or name:find("scythe") or name:find("harvest") or name:find("gặt") then
                    if CFG.harvestTool ~= i then
                        CFG.harvestTool = i
                        log("Tự động nhận diện Dụng cụ gặt tại Slot: " .. i)
                    end
                end
            end
        end
    end)
end

-- Auto spawning
task.spawn(function()
    while true do
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then
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
        task.wait(2)
    end
end)

local function autoClickSpawn()
    if _G.forceSpawn then return _G.forceSpawn() end
    pcall(function()
        for _, gui in ipairs(lp.PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") then
                for _, btn in ipairs(gui:GetDescendants()) do
                    if btn:IsA("TextButton") and btn.Visible then
                        local t = btn.Text:lower()
                        if t == "spawn" or t == "respawn" or t == "play" then
                            pcall(function() btn.MouseButton1Click:Fire() end)
                        end
                    end
                end
            end
        end
    end)
end

local function waitForAlive()
    local char = lp.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    
    if not hrp or not hum or hum.Health <= 0 then
        log("Nhân vật đang chết hoặc trong Menu. Đang thử Spawn...")
        local t = tick()
        while not hrp or not hum or hum.Health <= 0 do
            autoClickSpawn()
            task.wait(1)
            char = lp.Character
            if char then
                hrp = char:FindFirstChild("HumanoidRootPart")
                hum = char:FindFirstChildOfClass("Humanoid")
            end
            if tick() - t > 15 then break end
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
                    log("Đói quá! Auto-Respawn...")
                    R.respawn:InvokeServer(15382674, 12, 2, 17, 15382674, 15382674, false)
                    task.wait(5)
                end
            end
        end
    end)
end

-- ==================== SERVER HOP & ANTI-KICK ====================
local lastHopTime  = 0
local isHopping    = false

local function serverHop(reason)
    if isHopping then return end
    if (tick() - lastHopTime) < CFG.hopCooldown then return end
    isHopping   = true
    lastHopTime = tick()
    log("Server Hop: " .. (reason or "Yêu cầu đổi"))

    local function getServers()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        local rawData
        pcall(function() rawData = game:HttpGet(url) end)
        if rawData then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(rawData) end)
            if ok and decoded and decoded.data then
                return decoded.data
            end
        end
        return nil
    end

    local serverList = getServers()
    if serverList then
        -- Lọc bỏ server hiện tại và server đầy
        local availableServers = {}
        for _, s in ipairs(serverList) do
            if s.id ~= game.JobId and s.playing < s.maxPlayers then
                table.insert(availableServers, s)
            end
        end

        -- Sắp xếp ngẫu nhiên để không bị dính vào cùng 1 server
        for i = #availableServers, 2, -1 do
            local j = math.random(i)
            availableServers[i], availableServers[j] = availableServers[j], availableServers[i]
        end

        -- Thử kết nối tới từng server
        for _, s in ipairs(availableServers) do
            log("Đang thử vào server: " .. s.id .. " (" .. s.playing .. "/" .. s.maxPlayers .. ")")
            local success = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id)
            end)
            if success then
                task.wait(5) -- Đợi teleport thực hiện
                -- Nếu code vẫn chạy đến đây nghĩa là teleport thất bại (vd: server full đột xuất)
                log("Teleport thất bại, thử server tiếp theo...")
            end
        end
    end

    -- Fallback nếu không tìm thấy server nào hoặc lỗi hết
    log("Không tìm thấy server phù hợp. Dùng Teleport mặc định...")
    pcall(function() TeleportService:Teleport(game.PlaceId) end)
    task.wait(10)
    isHopping = false
end

-- Tự động Rejoin khi bị Kick / Disconnect / Lỗi 267
task.spawn(function()
    while true do
        pcall(function()
            local prompt = CoreGui:FindFirstChild("RobloxPromptGui")
            if prompt then
                local overlay = prompt:FindFirstChild("promptOverlay")
                if overlay then
                    local err = overlay:FindFirstChild("ErrorPrompt")
                    if err then
                        local msg = err:FindFirstChild("MessageArea")
                        local txt = msg and msg:FindFirstChild("ErrorFrame") and msg.ErrorFrame:FindFirstChild("ErrorMessage")
                        local reason = "Bị Kick/Disconnect"
                        if txt and txt.Text then
                            reason = "Lỗi game: " .. txt.Text
                        end
                        log("Phát hiện lỗi: " .. reason .. ". Đang tìm server mới...")
                        serverHop(reason)
                    end
                end
            end
        end)
        task.wait(2)
    end
end)

-- ==================== TELEPORT SYSTEM ====================
local rbCount  = 0
local rbSkip   = false
local GS       = { isTeleporting = false, targetCF = nil }

lp.CharacterAdded:Connect(function(char)
    task.spawn(function()
        -- Wipe spawn UI (Safe version)
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

        if GS.isTeleporting and GS.targetCF then
            log("Spawn xong. Đang bám dính tọa độ (Sticky TP)...")
            local hrp = char:WaitForChild("HumanoidRootPart", 10)
            if hrp then
                for _ = 1, 40 do
                    hrp.CFrame = GS.targetCF
                    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    task.wait(0.05)
                end
            end
            GS.isTeleporting = false
        end
    end)
end)

local function instantTP(cf)
    local hrp = getHRP()
    if not hrp then return end
    local targetPos = cf.Position
    for _ = 1, 12 do
        if not hrp or not hrp.Parent then break end
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        task.wait(0.04)
    end

    task.wait(0.3)
    if not rbSkip and hrp and hrp.Parent then
        if (hrp.Position - targetPos).Magnitude > 50 then
            rbCount = rbCount + 1
            log("Bị giật về (" .. rbCount .. "/" .. CFG.rbThreshold .. ")")
            if rbCount >= CFG.rbThreshold then
                serverHop("Phát hiện bị giật về liên tục")
            end
        else
            rbCount = 0
        end
    end
end

local function smartTP(targetCF)
    local hrp = getHRP()
    local dist = hrp and (hrp.Position - targetCF.Position).Magnitude or 999
    
    if dist < CFG.tpThreshold and hrp then
        instantTP(targetCF)
    else
        log("Ở quá xa (" .. math.floor(dist) .. ") -> Dùng Respawn-TP...")
        GS.isTeleporting = true
        GS.targetCF      = targetCF
        pcall(function()
            R.reset:InvokeServer()
            task.wait(0.5)
            R.respawn:InvokeServer(15382674, 12, 2, 17, 15382674, 15382674, false)
        end)
        local t = tick()
        repeat task.wait(0.5) until not GS.isTeleporting or (tick() - t > 15)
        GS.isTeleporting = false
    end
end

-- ==================== FARMING LOGIC ====================
local function findOwnPlots()
    local plots = {}
    local farmFolder = workspace:FindFirstChild("farmland")
    if not farmFolder then 
        log("LỖI: Không tìm thấy thư mục 'farmland' trong Workspace!")
        return plots 
    end
    for _, obj in ipairs(farmFolder:GetChildren()) do
        if obj:IsA("Model") then
            local ok, pos = pcall(function() return obj:GetPivot().Position end)
            if ok and pos then
                for _, slotPos in ipairs(OWN_SLOTS) do
                    if (pos - slotPos).Magnitude < CFG.auraRange then
                        table.insert(plots, obj)
                        break
                    end
                end
            end
        end
    end
    log("Tìm thấy " .. #plots .. " ô đất của bạn trong phạm vi bãi farm.")
    return plots
end

-- ==================== MAIN LOOP ====================
if not loadRemotes() then
    warn("Không thể tải Remotes! Script dừng.")
    return
end

removeWater()
waitForAlive()
log("=== FARMING STANDALONE BẮT ĐẦU ===")

while true do
    autoFindTools() -- Tự động tìm tool mỗi chu kỳ
    checkHunger()
    
    local hrp = getHRP()
    local hum = getHum()
    if not hrp or not hum or hum.Health <= 0 then
        waitForAlive()
        hrp = getHRP()
    end

    -- 1. Anti-Kill (Đổi server nếu mất máu)
    local damageConn
    local lastHp = hum.Health
    damageConn = hum.HealthChanged:Connect(function(currentHp)
        if currentHp < lastHp - 5 then
            log("CẢNH BÁO: Bị tấn công! Mất " .. math.floor(lastHp - currentHp) .. " máu. Đang đổi server...")
            if damageConn then damageConn:Disconnect() end
            serverHop("Bị player tấn công")
        end
        lastHp = currentHp
    end)

    -- 2. Di chuyển tới khu vực farm
    local dist = (hrp.Position - FARM_CENTER).Magnitude
    if dist > 30 then
        log("Đang tiến tới bãi farm...")
        smartTP(CFrame.new(FARM_CENTER + Vector3.new(0, 3, 0)))
        task.wait(1)
        hrp = getHRP()
    end

    -- 3. Kiểm tra và xây đất
    local plots = findOwnPlots()
    if #plots < 6 then
        log("Đang xây luống đất còn thiếu (" .. #plots .. "/6)...")
        rbSkip = true
        for _, pos in ipairs(OWN_SLOTS) do
            local found = false
            for _, p in ipairs(plots) do
                if (p:GetPivot().Position - pos).Magnitude < 10 then found = true break end
            end
            if not found then
                instantTP(CFrame.new(pos + Vector3.new(0, 5, 0)))
                task.wait(0.5)
                pcall(function() R.createFarmland:FireServer(CFG.plantTool, pos, 0) end)
                task.wait(0.5)
            end
        end
        rbSkip = false
        instantTP(CFrame.new(FARM_CENTER + Vector3.new(0, 3, 0)))
        task.wait(1)
        plots = findOwnPlots()
    end

    -- 4. Trang bị Tools
    local pTool = getToolSafely(CFG.plantTool)
    local hTool = getToolSafely(CFG.harvestTool)
    if pTool then pcall(function() R.toolCheck:InvokeServer(pTool) end) end
    if hTool then pcall(function() R.toolCheck:InvokeServer(hTool) end) end

    -- 5. Vòng lặp AFK Check & Aura Farm (CHẠY VÔ HẠN)
    local lastAfkCheck = tick()
    local pulseCount = 0
    
    log("Bắt đầu chu kỳ Aura Farm...")
    while true do
        hrp = getHRP()
        hum = getHum()
        if not hrp or not hum or hum.Health <= 0 then 
            log("Nhân vật mất tích hoặc chết. Khởi động lại chu kỳ Spawn...")
            break 
        end

        -- AFK / Distance Check (30 giây một lần)
        if tick() - lastAfkCheck > CFG.afkCheckTime then
            lastAfkCheck = tick()
            if (hrp.Position - FARM_CENTER).Magnitude > 50 then
                log("Cảnh báo: Bị dời đi quá xa! Đang quay lại...")
                break 
            end
            checkHunger()
        end

        -- Log Pulse mỗi 100 nhịp để tránh spam console quá mức
        pulseCount = pulseCount + 1
        if pulseCount % 100 == 0 then
            log("Script đang farm... (Nhịp " .. pulseCount .. ")")
        end

        -- Aura Spam
        for _, plot in ipairs(plots) do
            if plot and plot.Parent then
                task.spawn(function()
                    pcall(function() R.harvest:FireServer(CFG.harvestTool, plot) end)
                    pcall(function() R.plant:FireServer(CFG.plantTool, CFG.plantType, plot) end)
                end)
            end
        end

        task.wait(CFG.actionDelay)
    end
    
    if damageConn then damageConn:Disconnect() end
    task.wait(1)
end