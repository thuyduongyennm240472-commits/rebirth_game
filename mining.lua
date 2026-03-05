    -- ============================================================
    -- MINING STANDALONE - FULL SYSTEM (Anti + Teleport + Loot)
    -- Paste vào executor là chạy ngay, không cần file nào khác
    -- ============================================================

    -- ==================== CONFIG ====================-- ==================== CONFIG ====================
    local CFG = {
        miningTool  = 3,        -- Tool slot đào
        auraRange   = 60,       -- Bán kính aura mine quanh người (studs)
        tpThreshold = 40,       -- Xa hơn bao nhiêu studs thì TP tới quặng
        farTpDist   = 1200,     -- Xa hơn thì dùng respawn-TP thay CFrame
        lootRange   = 100,      -- Vacuum loot range (studs)
        stuckLimit  = 5,        -- Bao nhiêu lần cùng quặng thì server hop
        noOreLimit  = 5,        -- Bao nhiêu lần không thấy quặng thì server hop
        hopCooldown = 30,       -- Giây giữa 2 lần server hop
        rbThreshold = 5,        -- Rubber band bao nhiêu lần thì server hop
    }

    local TARGET_ORES = { ["Gold Vein"] = true }

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
            R.mine     = int:WaitForChild("mine", 3)
            R.pickup   = int:WaitForChild("pickupItem", 2)

            local charR   = ri:WaitForChild("character", 5)
            R.reset    = charR:WaitForChild("reset", 3)
            R.respawn  = charR:WaitForChild("respawn", 3)

            local tools   = ri:WaitForChild("Tools", 5)
            R.toolCheck   = tools:WaitForChild("CheckToolSetup", 3)
        end)
        if not ok then warn("[MINE] Remote load loi: " .. tostring(err)) end
        return ok
    end

    -- ==================== LOGGER ====================
    local function log(msg)
        print("[MINE] " .. tostring(msg))
    end

    -- ==================== HELPERS ====================
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

    local function waitForAlive()
        local char = lp.Character or lp.CharacterAdded:Wait()
        local hrp  = char:WaitForChild("HumanoidRootPart", 10)
        local hum  = char:WaitForChild("Humanoid", 10)
        while not hrp or not hum or hum.Health <= 0 do
            task.wait(0.5)
            char = lp.Character
            if char then
                hrp = char:FindFirstChild("HumanoidRootPart")
                hum = char:FindFirstChild("Humanoid")
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
                        log("[SURVIVAL] Hunger thap (" .. val .. "). Auto-Respawn...")
                        R.respawn:InvokeServer(15382674, 12, 2, 17, 15382674, 15382674, false)
                        task.wait(5)
                    end
                end
            end
        end)
    end

    -- ==================== REMOVE WATER ====================
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
            local hum = getHum()
            if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false) end
        end)
        RunService.Heartbeat:Connect(function()
            nuclearScan()
            Lighting.FogEnd = 100000
        end)
        log("Remove Water: ON")
    end

    -- ==================== SERVER HOP ====================
    local lastHopTime  = 0
    local isHopping    = false

    local function serverHop(reason)
        if isHopping then return end
        if (tick() - lastHopTime) < CFG.hopCooldown then return end
        isHopping   = true
        lastHopTime = tick()
        log("Server Hop: " .. (reason or "?"))

        local rawData
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        pcall(function() rawData = game:HttpGet(url) end)
        if not rawData then
            pcall(function()
                local fn = rawget(getfenv(), "request") or rawget(getfenv(), "http_request")
                if fn then
                    local res = fn({Url = url, Method = "GET"})
                    rawData = res and res.Body
                end
            end)
        end

        if rawData then
            local ok, servers = pcall(function() return HttpService:JSONDecode(rawData) end)
            if ok and servers and servers.data then
                for _, s in ipairs(servers.data) do
                    if s.id ~= game.JobId and s.playing < (s.maxPlayers - 1) then
                        local hopOk = pcall(function()
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id)
                        end)
                        if hopOk then return end
                    end
                end
            end
        end

        pcall(function() TeleportService:Teleport(game.PlaceId) end)
        task.wait(5)
        isHopping = false
    end

    -- Auto rejoin khi bị kick
    pcall(function()
        CoreGui.RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" then
                log("Bi kick! Hop server...")
                task.wait(3)
                serverHop("Bi kick")
            end
        end)
    end)
    task.spawn(function()
        while true do
            local kickGui = CoreGui:FindFirstChild("RobloxPromptGui")
            if kickGui and kickGui:FindFirstChild("promptOverlay")
                and kickGui.promptOverlay:FindFirstChild("ErrorPrompt") then
                log("Kick detected (poll). Hop server...")
                serverHop("Bi kick poll")
                task.wait(30)
            end
            task.wait(5)
        end
    end)

    -- ==================== TELEPORT ====================
    local rbCount  = 0
    local rbSkip   = false
    local GS       = { isTeleporting = false, targetCF = nil }

    -- Sticky TP sau khi spawn
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

            -- Anti-swim sau khi spawn
            task.wait(1)
            toggleSwim(true)
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false) end

            -- Sticky TP nếu đang teleporting
            if GS.isTeleporting and GS.targetCF then
                log("Spawn xong. Sticky TP x40...")
                local hrp = char:WaitForChild("HumanoidRootPart", 10)
                local hum2 = char:WaitForChild("Humanoid", 10)
                if hrp and hum2 then
                    for _ = 1, 40 do
                        if not hrp.Parent or hum2.Health <= 0 then break end
                        hrp.CFrame = GS.targetCF
                        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        task.wait(0.05)
                    end
                end
                GS.isTeleporting = false
                log("Sticky TP done.")
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

        -- Rubber band check
        task.wait(0.3)
        if not rbSkip and hrp and hrp.Parent then
            local finalDist = (hrp.Position - targetPos).Magnitude
            if finalDist > 50 then
                rbCount += 1
                log(string.format("⚠️ Giat ve! (%d/%d) dist=%.0f", rbCount, CFG.rbThreshold, finalDist))
                if rbCount >= CFG.rbThreshold then
                    rbCount = 0
                    serverHop("Anti-cheat giat ve " .. CFG.rbThreshold .. " lan")
                end
            else
                rbCount = 0
            end
        end
    end

    local function smartTP(targetCF)
        local hrp = getHRP()
        if not hrp then
            pcall(function() R.respawn:InvokeServer(15382674, 12, 2, 17, 15382674, 15382674, false) end)
            return
        end
        local dist = (hrp.Position - targetCF.Position).Magnitude
        if dist < 50 then
            instantTP(targetCF)
        else
            log("Xa " .. math.floor(dist) .. " studs → respawn-TP...")
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

    -- ==================== VACUUM LOOT ====================
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
                                bp.CFrame     = hrp.CFrame
                                pcall(function() R.pickup:FireServer(obj) end)
                            end
                        end
                    end
                end
            end)
            task.wait(0.1)
        end
    end)

    -- ==================== ORE SCANNER ====================
    local function getNearestOre()
        local wr = workspace:FindFirstChild("worldResources")
        local mineable = wr and wr:FindFirstChild("mineable")
        if not mineable then return nil, nil end
        local hrp = getHRP()
        if not hrp then return nil, nil end

        local nearest, minDist = nil, math.huge
        for _, chunk in ipairs(mineable:GetChildren()) do
            for _, ore in ipairs(chunk:GetChildren()) do
                if TARGET_ORES[ore.Name] then
                    local hp = ore:GetAttribute("health")
                    if hp == nil or hp > 0 then
                        local ok, pos = pcall(function()
                            return ore:IsA("PVInstance") and ore:GetPivot().Position or ore.Position
                        end)
                        if ok and pos then
                            local d = (hrp.Position - pos).Magnitude
                            if d < minDist then minDist, nearest = d, ore end
                        end
                    end
                end
            end
        end
        return nearest, minDist
    end

    -- ==================== MAIN ====================
    if not loadRemotes() then
        warn("[MINE] Khong load duoc remotes!")
        return
    end

    removeWater()
    waitForAlive()
    log("=== MINING STARTED ===")

    local oreNotFoundCount = 0
    local lastOrePos       = nil
    local stuckCount       = 0
    local lastLogTime      = 0

    while true do
        checkHunger()

        local hrp = getHRP()
        if not hrp then task.wait(2) continue end

        local ore, dist = getNearestOre()

        if ore then
            oreNotFoundCount = 0
            local orePos = ore:IsA("PVInstance") and ore:GetPivot().Position or ore.Position

            -- Stuck detection
            if lastOrePos and (orePos - lastOrePos).Magnitude < 1 then
                stuckCount += 1
                log(string.format("[STUCK] Same ore (Strike %d/%d)", stuckCount, CFG.stuckLimit))
                if stuckCount >= CFG.stuckLimit then
                    log("Mining stuck! Hop server...")
                    serverHop("Mining stuck " .. CFG.stuckLimit .. " strikes")
                    stuckCount = 0
                    task.wait(1)
                    continue
                end
            else
                stuckCount = 0
            end
            lastOrePos = orePos

            -- Periodic log
            local now = tick()
            if now - lastLogTime > 10 then
                log(string.format("%s (%.0f studs)", ore.Name, dist))
                lastLogTime = now
            end

            -- TP tới quặng
            if dist > CFG.tpThreshold then
                local tpCF = CFrame.new(orePos + Vector3.new(0, 5, 0))
                if dist > CFG.farTpDist then
                    log("Qua xa (" .. math.floor(dist) .. "). Dung respawn-TP...")
                    smartTP(tpCF)
                    task.wait(1)
                else
                    rbSkip = true
                    instantTP(tpCF)
                    rbSkip = false
                end
                hrp = getHRP()
                if not hrp then task.wait(2) continue end
            end

            -- Gán tool
            local tool = getToolSafely(CFG.miningTool)
            if tool then pcall(function() R.toolCheck:InvokeServer(tool) end) end

            -- Aura mine: spam tất cả quặng trong auraRange
            local deadline = tick() + 10
            while ore and ore.Parent and tick() < deadline do
                local h = ore:GetAttribute("health")
                if h and h <= 0 then break end

                hrp = getHRP()
                if not hrp then break end

                local wr2 = workspace.worldResources
                local mine2 = wr2 and wr2:FindFirstChild("mineable")
                if mine2 then
                    for _, chunk in ipairs(mine2:GetChildren()) do
                        for _, nearOre in ipairs(chunk:GetChildren()) do
                            if TARGET_ORES[nearOre.Name] then
                                local ok, nearPos = pcall(function()
                                    return nearOre:IsA("PVInstance") and nearOre:GetPivot().Position or nearOre.Position
                                end)
                                if ok and nearPos and (hrp.Position - nearPos).Magnitude < CFG.auraRange then
                                    local nh = nearOre:GetAttribute("health")
                                    if nh == nil or nh > 0 then
                                        pcall(function()
                                            R.mine:FireServer(CFG.miningTool, nearOre, nearOre:GetPivot())
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end

                task.wait(0.1)
            end

        else
            oreNotFoundCount += 1
            log("Khong thay Gold Vein (" .. oreNotFoundCount .. "x)")
            if oreNotFoundCount >= CFG.noOreLimit then
                serverHop("Server het quang")
                oreNotFoundCount = 0
            end
            task.wait(1)
        end
    end
