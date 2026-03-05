--[[
    WOOD.LUA v4.4 - ULTIMATE CHARACTER DETECTION
    - Fix: Character detection (Removed strict parent check)
    - Fix: Status GUI update
    - Version: v4.4
]]

if not game:IsLoaded() then game.Loaded:Wait() end
local lp = game:GetService("Players").LocalPlayer
repeat task.wait() until lp and lp:FindFirstChild("PlayerGui")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")
local CoreGui           = game:GetService("CoreGui")

local function debugLog(msg)
    print("[WOOD v4.4]: " .. tostring(msg))
end

-- [OPTIMIZATION: REMOVE WATER]
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

local function removeWater()
    nukeLighting()
    nuclearScan()
    pcall(function()
        local ps = lp:FindFirstChild("PlayerScripts")
        if ps then
            for _, s in ipairs(ps:GetChildren()) do
                if s.Name:lower():find("swim") then s.Disabled = true end
            end
        end
    end)
    RunService.Heartbeat:Connect(nuclearScan)
    debugLog("Lag Reducer ACTIVE")
end

-- [DEEP REMOTE SEARCH]
local function findRemoteRecursive(parent, name)
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
            return child
        end
        local found = findRemoteRecursive(child, name)
        if found then return found end
    end
    return nil
end

local function getRemote(name)
    local ri = ReplicatedStorage:FindFirstChild("remoteInterface")
    if not ri then return nil end
    return findRemoteRecursive(ri, name)
end

local function getChop() return getRemote("chop") end
local function getReset() return getRemote("reset") end
local function getRespawn() return getRemote("respawn") end
local function getPickup() return getRemote("pickupItem") end

local settings = {
    enabled = true,
    delay = 0.04,
    toolSlot = 4,
    scanRange = 5000,
    killAuraRange = 40,
    isTeleporting = false,
    targetCF = nil,
    spawnPos = CFrame.new(96, 22.0625, 52),
    respawnArgs = {15382674, 12, 2, 17, 15382674, 15382674, false}
}

-- [FIXED HRP CHECK]
local function getHRP()
    local char = lp.Character or workspace:FindFirstChild(lp.Name)
    -- Nếu char nằm trong folder con của Workspace (như worldResources.Players) vẫn cho là đúng
    if char and char:IsDescendantOf(workspace) then
        return char:FindFirstChild("HumanoidRootPart")
    end
    return nil
end

-- [1] UNIVERSAL SPAWNER
local function forceSpawn()
    local rsp = getRespawn()
    if rsp then pcall(function() rsp:InvokeServer(unpack(settings.respawnArgs)) end) end
    
    pcall(function()
        local pg = lp:FindFirstChild("PlayerGui")
        if pg then
            for _, g in ipairs(pg:GetChildren()) do
                if g:IsA("ScreenGui") and g.Enabled then
                    for _, b in ipairs(g:GetDescendants()) do
                        if b:IsA("TextButton") and b.Visible and b.TextSize > 0 then
                            local t = b.Text:lower()
                            if t:find("spawn") or t:find("play") or t:find("pick") then
                                if getconnections then
                                    for _, c in ipairs(getconnections(b.MouseButton1Click)) do c:Fire() end
                                    for _, c in ipairs(getconnections(b.Activated)) do c:Fire() end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

task.spawn(function()
    while true do
        if not getHRP() then forceSpawn() end
        task.wait(3)
    end
end)

-- [2] PERSISTENT KILLAURA
task.spawn(function()
    while true do
        local hrp = getHRP()
        local chop = getChop()
        if settings.enabled and hrp and chop then
            pcall(function()
                local choppable = workspace:FindFirstChild("worldResources") and workspace.worldResources:FindFirstChild("choppable")
                if choppable then
                    local myPos = hrp.Position
                    for _, seg in ipairs(choppable:GetChildren()) do
                        for _, tree in ipairs(seg:GetChildren()) do
                            if tree:GetAttribute("health") == nil or tree:GetAttribute("health") > 0 then
                                if (tree:GetPivot().Position - myPos).Magnitude < settings.killAuraRange then
                                    local cf = tree:GetPivot()
                                    chop:FireServer(settings.toolSlot, tree, cf)
                                    chop:FireServer(settings.toolSlot, tree, cf)
                                end
                            end
                        end
                    end
                end
            end)
        end
        task.wait(0.1)
    end
end)

-- [3] FAST PICKUP
task.spawn(function()
    while true do
        local hrp = getHRP()
        local pk = getPickup()
        if settings.enabled and hrp and pk then
            pcall(function()
                local dropped = workspace:FindFirstChild("droppedItems")
                if dropped then
                    local myPos = hrp.Position
                    for _, item in ipairs(dropped:GetChildren()) do
                        if item:IsA("BasePart") and (item.Position - myPos).Magnitude < 100 then
                            pk:FireServer(item)
                        end
                    end
                end
            end)
        end
        task.wait(0.3)
    end
end)

local function smartTeleport(cf)
    settings.isTeleporting = true
    settings.targetCF = cf
    local rst = getReset()
    if rst then pcall(function() rst:InvokeServer() end) end
    task.wait(0.3)
    forceSpawn()
end

local function getNearestTree()
    local choppable = workspace:FindFirstChild("worldResources") and workspace.worldResources:FindFirstChild("choppable")
    local hrp = getHRP()
    if not choppable or not hrp then return nil, nil end
    local nearest, minDist = nil, settings.scanRange
    for _, seg in ipairs(choppable:GetChildren()) do
        for _, tree in ipairs(seg:GetChildren()) do
            if tree:GetAttribute("health") == nil or tree:GetAttribute("health") > 0 then
                local d = (tree:GetPivot().Position - hrp.Position).Magnitude
                if d < minDist then minDist = d; nearest = tree end
            end
        end
    end
    return nearest, minDist
end

local function farmLoop()
    if not settings.enabled then return end
    local hrp = getHRP()
    if not hrp then task.wait(1); return farmLoop() end

    local tree, dist = getNearestTree()
    if tree then
        local targetCF = tree:GetPivot() + Vector3.new(0, 5, 0)
        if dist < 50 then
            hrp.CFrame = targetCF
            task.wait(0.5)
            farmLoop()
        else
            smartTeleport(targetCF)
        end
    else
        task.wait(1); farmLoop()
    end
end

-- CHARACTER EVENT
lp.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if hrp then
        if settings.isTeleporting and settings.targetCF then
            for i = 1, 5 do hrp.CFrame = settings.targetCF; task.wait() end
            settings.isTeleporting = false
        else
            for i = 1, 5 do hrp.CFrame = settings.spawnPos; task.wait() end
        end
        task.spawn(farmLoop)
    end
end)

-- GUI
local function setupGUI()
    if lp.PlayerGui:FindFirstChild("AutoChopGui") then lp.PlayerGui.AutoChopGui:Destroy() end
    local ScreenGui = Instance.new("ScreenGui", CoreGui); ScreenGui.Name = "AutoChopGui"
    local Main = Instance.new("Frame", ScreenGui); Main.Size = UDim2.new(0, 200, 0, 100); Main.Position = UDim2.new(0, 10, 0, 50); Main.BackgroundColor3 = Color3.new(0,0,0)
    Instance.new("UICorner", Main)
    local Title = Instance.new("TextLabel", Main); Title.Size = UDim2.new(1,0,0,30); Title.Text = "WOOD v4.4 ULTIMATE"; Title.TextColor3 = Color3.new(1,1,1); Title.BackgroundColor3 = Color3.fromRGB(150, 0, 150); Instance.new("UICorner", Title)
    local Status = Instance.new("TextLabel", Main); Status.Size = UDim2.new(1,0,0,30); Status.Position = UDim2.new(0,0,1,-30); Status.Text = "Starting..."; Status.TextColor3 = Color3.new(1,1,1); Status.BackgroundTransparency = 1; Status.Parent = Main
    
    task.spawn(function()
        while ScreenGui.Parent do
            local hrp = getHRP()
            if not hrp then Status.Text = "WAITING FOR CHARACTER..." else Status.Text = "ACTIVE | FPS OPTIMIZED" end
            task.wait(1)
        end
    end)
end

setupGUI()
removeWater()
debugLog("v4.4 Loaded. Character detection fixed.")
if getHRP() then task.spawn(farmLoop) else forceSpawn() end
