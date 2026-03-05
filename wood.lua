--[[
    WOOD.LUA v3.9 - GOD MODE (ULTIMATE KILLAURA)
    - Persistent KillAura: 40-stud radius background task
    - Aggressive Auto-Spawn: UI Clicker for "Spawn/Play"
    - Simplified Navigation: Fast TP to nearest tree
    - Extreme Stability: Non-blocking dynamic remotes
]]

if not game:IsLoaded() then game.Loaded:Wait() end
local lp = game:GetService("Players").LocalPlayer
repeat task.wait() until lp and lp:FindFirstChild("PlayerGui")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local RunService        = game:GetService("RunService")
local CoreGui           = game:GetService("CoreGui")

local function debugLog(msg)
    print("[WOOD v3.9]: " .. tostring(msg))
end

-- [DYNAMIC REMOTES]
local ri = ReplicatedStorage:FindFirstChild("remoteInterface")
local function getRemote(folder, name)
    local f = ri and ri:FindFirstChild(folder)
    return f and f:FindFirstChild(name)
end

local function getChop() return getRemote("interactions", "chop") end
local function getReset() return getRemote("character", "reset") end
local function getRespawn() return getRemote("character", "respawn") end
local function getPickup() 
    return getRemote("interactions", "pickupItem") or (ri and ri:FindFirstChild("inventory") and ri.inventory:FindFirstChild("pickupItem"))
end

local settings = {
    enabled = true,
    delay = 0.04,
    toolSlot = 4,
    scanRange = 5000,
    killAuraRange = 40,
    isTeleporting = false,
    targetCF = nil,
    targetTree = nil,
    spawnPos = CFrame.new(96, 22.0625, 52),
    respawnArgs = {15382674, 12, 2, 17, 15382674, 15382674, false}
}

-- [1] AGGRESSIVE AUTO-SPAWN (UI Clicker)
task.spawn(function()
    while true do
        pcall(function()
            if not lp.Character or not lp.Character:FindFirstChild("HumanoidRootPart") then
                local playerGui = lp:FindFirstChild("PlayerGui")
                if playerGui then
                    for _, g in ipairs(playerGui:GetChildren()) do
                        if g:IsA("ScreenGui") and g.Enabled then
                            for _, b in ipairs(g:GetDescendants()) do
                                if b:IsA("TextButton") or b:IsA("ImageButton") then
                                    local t = (b:IsA("TextButton") and b.Text or ""):lower()
                                    if t:find("spawn") or t:find("play") or t:find("respawn") then
                                        debugLog("Auto Clicking: " .. b.Name .. " (" .. t .. ")")
                                        -- Click simulation
                                        local signals = {"MouseButton1Click", "MouseButton1Down", "Activated"}
                                        for _, s in ipairs(signals) do
                                            if b[s] then
                                                for _, connection in ipairs(getconnections(b[s])) do
                                                    connection:Fire()
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
        task.wait(1)
    end
end)

-- [2] AUTO RECONNECT
task.spawn(function()
    while true do
        pcall(function()
            local prompt = CoreGui:FindFirstChild("RobloxPromptGui")
            if prompt and prompt:FindFirstChild("promptOverlay") then
                local overlay = prompt.promptOverlay
                if overlay:FindFirstChild("ErrorPrompt") then
                    TeleportService:Teleport(game.PlaceId, lp)
                end
            end
        end)
        task.wait(2)
    end
end)

local function getHRP() return lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") end

-- [3] PERSISTENT KILLAURA (Background Task)
task.spawn(function()
    while true do
        local chop = getChop()
        local hrp = getHRP()
        if settings.enabled and chop and hrp then
            pcall(function()
                local choppable = workspace:FindFirstChild("worldResources") and workspace.worldResources:FindFirstChild("choppable")
                if choppable then
                    local charPos = hrp.Position
                    for _, segment in ipairs(choppable:GetChildren()) do
                        for _, tree in ipairs(segment:GetChildren()) do
                            local health = tree:GetAttribute("health")
                            if health == nil or health > 0 then
                                local treePos = tree:GetPivot().Position
                                if (treePos - charPos).Magnitude < settings.killAuraRange then
                                    local cf = tree:GetPivot()
                                    -- High pressure fire
                                    chop:FireServer(settings.toolSlot, tree, cf)
                                    chop:FireServer(settings.toolSlot, tree, cf)
                                end
                            end
                        end
                    end
                end
            end)
        end
        task.wait(0.1) -- 10 times per second
    end
end)

-- [4] FAST PICKUP
task.spawn(function()
    while true do
        local pk = getPickup()
        local hrp = getHRP()
        if settings.enabled and pk and hrp then
            pcall(function()
                local dropped = workspace:FindFirstChild("droppedItems")
                if dropped then
                    local charPos = hrp.Position
                    for _, item in ipairs(dropped:GetChildren()) do
                        if item:IsA("BasePart") and (charPos - item.Position).Magnitude < 100 then
                            pk:FireServer(item)
                        end
                    end
                end
            end)
        end
        task.wait(0.3)
    end
end)

local function liteUIWipe()
    local targets = {"Avatar", "AvatarUI", "SpawnUI", "Menu", "Intro", "MainGui", "Announcements", "News", "Loading"}
    for _, name in ipairs(targets) do
        local ui = lp.PlayerGui:FindFirstChild(name)
        if ui and ui:IsA("ScreenGui") then pcall(function() ui.Enabled = false end) end
    end
end

local function getNearestTree()
    local choppable = workspace:FindFirstChild("worldResources") and workspace.worldResources:FindFirstChild("choppable")
    local hrp = getHRP()
    if not choppable or not hrp then return nil, nil end

    local nearest, minDist = nil, settings.scanRange
    for _, segment in ipairs(choppable:GetChildren()) do
        for _, tree in ipairs(segment:GetChildren()) do
            local health = tree:GetAttribute("health")
            if health == nil or health > 0 then
                local pos = tree:GetPivot().Position
                local d = (hrp.Position - pos).Magnitude
                if d < minDist then minDist = d; nearest = tree end
            end
        end
    end
    return nearest, minDist
end

local function smartTeleport(cf)
    settings.isTeleporting = true
    settings.targetCF = cf
    local rst = getReset()
    local rsp = getRespawn()
    if rst then pcall(function() rst:InvokeServer() end) end
    task.wait(0.3)
    if rsp then pcall(function() rsp:InvokeServer(unpack(settings.respawnArgs)) end) end
end

-- [5] SIMPLIFIED NAVIGATION LOOP
local function farmLoop()
    if not settings.enabled then return end
    
    local tree, dist = getNearestTree()
    if tree then
        local targetPos = tree:GetPivot().Position
        local targetCF = CFrame.new(targetPos + Vector3.new(0, 5, 0))
        local hrp = getHRP()
        if hrp then
            if dist < 50 then
                -- Direct Move
                for _ = 1, 3 do
                    hrp.CFrame = targetCF
                    hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    task.wait()
                end
                -- Let KillAura handle the chopping
                task.wait(0.5) 
                task.spawn(farmLoop)
            else
                smartTeleport(targetCF)
            end
        end
    else
        task.wait(1)
        farmLoop()
    end
end

lp.CharacterAdded:Connect(function(char)
    liteUIWipe()
    task.spawn(function()
        local hrp = char:WaitForChild("HumanoidRootPart", 5)
        if not hrp then return end
        task.wait()

        if settings.isTeleporting and settings.targetCF then
            for i = 1, 10 do
                if not hrp or not hrp.Parent then break end
                hrp.CFrame = settings.targetCF
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                task.wait()
            end
            settings.isTeleporting = false
        else
            for i = 1, 10 do
                if not hrp or not hrp.Parent then break end
                hrp.CFrame = settings.spawnPos
                task.wait()
            end
        end
        task.spawn(farmLoop)
    end)
end)

-- GUI SETUP
local function setupGUI()
    pcall(function()
        if lp.PlayerGui:FindFirstChild("AutoChopGui") then lp.PlayerGui.AutoChopGui:Destroy() end
        local ScreenGui = Instance.new("ScreenGui", CoreGui)
        ScreenGui.Name = "AutoChopGui"
        
        local Main = Instance.new("Frame", ScreenGui)
        Main.Size = UDim2.new(0, 200, 0, 140)
        Main.Position = UDim2.new(0, 10, 0, 50)
        Main.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        Main.Draggable = true; Main.Active = true
        Instance.new("UICorner", Main)

        local Title = Instance.new("TextLabel", Main)
        Title.Size = UDim2.new(1,0,0,35)
        Title.Text = "WOOD v3.9 GOD MODE"
        Title.TextColor3 = Color3.new(1,1,1)
        Title.BackgroundColor3 = Color3.fromRGB(180, 0, 180)
        Title.Font = Enum.Font.GothamBold
        Instance.new("UICorner", Title)

        local Btn = Instance.new("TextButton", Main)
        Btn.Size = UDim2.new(0.9,0,0,50)
        Btn.Position = UDim2.new(0.05,0,0,45)
        Btn.Text = "DỪNG FARM"
        Btn.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
        Btn.TextColor3 = Color3.new(1,1,1)
        Btn.Font = Enum.Font.GothamBold
        Instance.new("UICorner", Btn)

        local Status = Instance.new("TextLabel", Main)
        Status.Size = UDim2.new(1, 0, 0, 35)
        Status.Position = UDim2.new(0, 0, 1, -35)
        Status.BackgroundTransparency = 1
        Status.Text = "KillAura: 40 studs | AoE ON"
        Status.TextColor3 = Color3.new(1, 0.4, 1)
        Status.TextSize = 12
        Status.Parent = Main

        Btn.MouseButton1Click:Connect(function()
            settings.enabled = not settings.enabled
            Btn.Text = settings.enabled and "DỪNG FARM" or "BẮT ĐẦU FARM"
            Btn.BackgroundColor3 = settings.enabled and Color3.fromRGB(180,0,0) or Color3.fromRGB(0,180,0)
            if settings.enabled then task.spawn(farmLoop) end
        end)
    end)
end

setupGUI()
debugLog("WOOD v3.9 GOD MODE Loaded.")
local rst = getReset()
local rsp = getRespawn()
if rst then pcall(function() rst:InvokeServer() end) end
task.wait(0.2)
if rsp then pcall(function() rsp:InvokeServer(unpack(settings.respawnArgs)) end) end
