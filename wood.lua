--[[
    WOOD.LUA v3.6 - MERGED STABLE
    - Logic: Custom User Base (v1.0)
    - Stability: Non-Blocking Remotes (Zero-Hang)
    - Features: Reconnect, Turbo Chop, Fast Pickup
]]

if not game:IsLoaded() then game.Loaded:Wait() end
local lp = game:GetService("Players").LocalPlayer
repeat task.wait() until lp and lp:FindFirstChild("PlayerGui")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local RunService        = game:GetService("RunService")
local CoreGui           = game:GetService("CoreGui")

-- [DYNAMIC REMOTES] Tránh treo tuyệt đối
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
    isTeleporting = false,
    targetCF = nil,
    targetTree = nil,
    spawnPos = CFrame.new(96, 22.0625, 52),
    respawnArgs = {15382674, 12, 2, 17, 15382674, 15382674, false}
}

-- [1] AUTO RECONNECT
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

-- [2] FAST PICKUP (Hút gỗ nền)
task.spawn(function()
    while true do
        local pk = getPickup()
        if settings.enabled and pk then
            pcall(function()
                local dropped = workspace:FindFirstChild("droppedItems")
                if dropped then
                    for _, item in ipairs(dropped:GetChildren()) do
                        if item:IsA("BasePart") then
                            local d = (lp.Character and lp.Character:GetPivot().Position - item.Position).Magnitude
                            if d < 100 then pk:FireServer(item) end
                        end
                    end
                end
            end)
        end
        task.wait(0.2)
    end
end)

-- HELPERS
local function liteUIWipe()
    local targets = {"Avatar", "AvatarUI", "SpawnUI", "Menu", "Intro", "MainGui", "Announcements", "News", "Loading"}
    for _, name in ipairs(targets) do
        local ui = lp.PlayerGui:FindFirstChild(name)
        if ui and ui:IsA("ScreenGui") then pcall(function() ui.Enabled = false end) end
    end
end

local function getHRP() return lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") end

-- TÌM CÂY (User Segment Logic)
local function getNearestTree()
    local choppable = workspace:FindFirstChild("worldResources") and workspace.worldResources:FindFirstChild("choppable")
    if not choppable then return nil, nil end
    local hrp = getHRP()
    if not hrp then return nil, nil end

    local nearest, minDist = nil, settings.scanRange
    for _, segment in ipairs(choppable:GetChildren()) do
        for _, tree in ipairs(segment:GetChildren()) do
            local health = tree:GetAttribute("health")
            if health == nil or health > 0 then
                local pos = tree:IsA("PVInstance") and tree:GetPivot().Position
                if pos then
                    local d = (hrp.Position - pos).Magnitude
                    if d < minDist then minDist = d; nearest = tree end
                end
            end
        end
    end
    return nearest, minDist
end

-- CHẶT TURBO (3 nhịp/vòng)
local function startChopping(tree)
    local chop = getChop()
    if not tree or not tree.Parent or not chop then return end
    
    local startTime = tick()
    while settings.enabled and tree and tree.Parent and (tick() - startTime < 8) do
        local h = tree:GetAttribute("health")
        if h and h <= 0 then break end
        pcall(function()
            local cf = tree:GetPivot()
            chop:FireServer(settings.toolSlot, tree, cf)
            chop:FireServer(settings.toolSlot, tree, cf)
            chop:FireServer(settings.toolSlot, tree, cf)
        end)
        task.wait(settings.delay)
    end
end

local function smartTeleport(cf, tree)
    settings.isTeleporting = true
    settings.targetCF = cf
    settings.targetTree = tree
    local rst = getReset()
    local rsp = getRespawn()
    if rst then pcall(function() rst:InvokeServer() end) end
    task.wait(0.3)
    if rsp then pcall(function() rsp:InvokeServer(unpack(settings.respawnArgs)) end) end
end

local function farmLoop()
    if not settings.enabled then return end
    local tree, dist = getNearestTree()
    if tree then
        local targetPos = tree:GetPivot().Position
        local targetCF = CFrame.new(targetPos + Vector3.new(0, 5, 0))
        local hrp = getHRP()
        if hrp then
            if dist < 50 then
                for _ = 1, 3 do
                    hrp.CFrame = targetCF
                    hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    task.wait()
                end
                startChopping(tree)
                task.spawn(farmLoop)
            else
                smartTeleport(targetCF, tree)
            end
        end
    else
        task.wait(1)
        farmLoop()
    end
end

-- CHARACTER ADDED (Fast)
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
            if settings.targetTree then
                local tree = settings.targetTree
                settings.targetTree = nil
                startChopping(tree)
            end
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

-- GUI SETUP (Merged Style)
local function setupGUI()
    pcall(function()
        if lp.PlayerGui:FindFirstChild("AutoChopGui") then lp.PlayerGui.AutoChopGui:Destroy() end
        local ScreenGui = Instance.new("ScreenGui", CoreGui)
        ScreenGui.Name = "AutoChopGui"
        
        local Main = Instance.new("Frame", ScreenGui)
        Main.Size = UDim2.new(0, 200, 0, 130)
        Main.Position = UDim2.new(0, 10, 0, 50)
        Main.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        Main.Draggable = true; Main.Active = true
        Instance.new("UICorner", Main)

        local Title = Instance.new("TextLabel", Main)
        Title.Size = UDim2.new(1,0,0,35)
        Title.Text = "WOOD v3.6 STABLE"
        Title.TextColor3 = Color3.new(1,1,1)
        Title.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
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
        Status.Size = UDim2.new(1, 0, 0, 30)
        Status.Position = UDim2.new(0, 0, 1, -30)
        Status.BackgroundTransparency = 1
        Status.Text = "Slots 4 | Turbo Enabled"
        Status.TextColor3 = Color3.new(0.8, 1, 0.8)
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
print("Wood v3.6 Stable Loaded.")
local rst = getReset()
local rsp = getRespawn()
if rst then pcall(function() rst:InvokeServer() end) end
task.wait(0.2)
if rsp then pcall(function() rsp:InvokeServer(unpack(settings.respawnArgs)) end) end
