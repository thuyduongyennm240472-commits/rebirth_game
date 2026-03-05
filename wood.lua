--[[
    WOOD.LUA v4.1 - REALLY FIXED (REMOTE HANG FIX)
    - Fix: truly dynamic remote detection (no more cached nil ri)
    - Fix: UI Status update logic
    - Version: v4.1
]]

if not game:IsLoaded() then game.Loaded:Wait() end
local lp = game:GetService("Players").LocalPlayer
repeat task.wait() until lp and lp:FindFirstChild("PlayerGui")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local CoreGui           = game:GetService("CoreGui")

local function debugLog(msg)
    print("[WOOD v4.1]: " .. tostring(msg))
end

-- [TRUE DYNAMIC REMOTES]
-- Không bao giờ cache biến ri ở trên đầu để tránh lỗi khi nạp sớm
local function getRemote(folderName, remoteName)
    local ri = ReplicatedStorage:FindFirstChild("remoteInterface")
    if not ri then return nil end
    local folder = ri:FindFirstChild(folderName)
    if not folder then return nil end
    return folder:FindFirstChild(remoteName)
end

local function getChop() return getRemote("interactions", "chop") end
local function getReset() return getRemote("character", "reset") end
local function getRespawn() return getRemote("character", "respawn") end
local function getPickup() 
    local pk = getRemote("interactions", "pickupItem")
    if not pk then
        local ri = ReplicatedStorage:FindFirstChild("remoteInterface")
        local inv = ri and ri:FindFirstChild("inventory")
        pk = inv and inv:FindFirstChild("pickupItem")
    end
    return pk
end

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

local function getHRP()
    local char = lp.Character or workspace:FindFirstChild(lp.Name)
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- [1] AUTO-SPAWN CLICKER
task.spawn(function()
    while true do
        if not getHRP() then
            pcall(function()
                local pg = lp:FindFirstChild("PlayerGui")
                if pg then
                    for _, g in ipairs(pg:GetChildren()) do
                        if g:IsA("ScreenGui") and g.Enabled then
                            for _, b in ipairs(g:GetDescendants()) do
                                if b:IsA("TextButton") and b.Visible then
                                    local t = b.Text:lower()
                                    if t:find("spawn") or t:find("play") or t:find("pick") then
                                        debugLog("Auto Clicking: " .. b.Text)
                                        for _, c in ipairs(getconnections(b.MouseButton1Click)) do c:Fire() end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
        task.wait(1)
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
                    for _, seg in ipairs(choppable:GetChildren()) do
                        for _, tree in ipairs(seg:GetChildren()) do
                            if tree:GetAttribute("health") == nil or tree:GetAttribute("health") > 0 then
                                local tpos = tree:GetPivot().Position
                                if (tpos - hrp.Position).Magnitude < settings.killAuraRange then
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

-- [3] PICKUP
task.spawn(function()
    while true do
        local hrp = getHRP()
        local pk = getPickup()
        if settings.enabled and hrp and pk then
            pcall(function()
                local dropped = workspace:FindFirstChild("droppedItems")
                if dropped then
                    for _, item in ipairs(dropped:GetChildren()) do
                        if item:IsA("BasePart") and (item.Position - hrp.Position).Magnitude < 100 then
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
    local rsp = getRespawn()
    if rst then rst:InvokeServer() end
    task.wait(0.3)
    if rsp then rsp:InvokeServer(unpack(settings.respawnArgs)) end
end

local function getNearestTree()
    local choppable = workspace:FindFirstChild("worldResources") and workspace.worldResources:FindFirstChild("choppable")
    local hrp = getHRP()
    if not choppable or not hrp then return nil, nil end
    local nearest, minDist = nil, settings.scanRange
    for _, seg in ipairs(choppable:GetChildren()) do
        for _, tree in ipairs(seg:GetChildren()) do
            if tree:GetAttribute("health") == nil or tree:GetAttribute("health") > 0 then
                local dist = (tree:GetPivot().Position - hrp.Position).Magnitude
                if dist < minDist then minDist = dist; nearest = tree end
            end
        end
    end
    return nearest, minDist
end

local function farmLoop()
    if not settings.enabled then return end
    local hrp = getHRP()
    if not hrp then 
        task.wait(1)
        return farmLoop()
    end

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
        task.wait(1)
        farmLoop()
    end
end

-- [INIT FLOW]
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
    end
    task.spawn(farmLoop)
end)

-- GUI
local function setupGUI()
    if lp.PlayerGui:FindFirstChild("AutoChopGui") then lp.PlayerGui.AutoChopGui:Destroy() end
    local ScreenGui = Instance.new("ScreenGui", CoreGui)
    ScreenGui.Name = "AutoChopGui"
    local Main = Instance.new("Frame", ScreenGui)
    Main.Size = UDim2.new(0, 200, 0, 100)
    Main.Position = UDim2.new(0, 10, 0, 50)
    Main.BackgroundColor3 = Color3.new(0,0,0)
    Instance.new("UICorner", Main)
    local Title = Instance.new("TextLabel", Main)
    Title.Size = UDim2.new(1,0,0,30)
    Title.Text = "WOOD v4.1 REAL FIX"
    Title.TextColor3 = Color3.new(1,1,1)
    Title.BackgroundColor3 = Color3.new(0,0.5,0)
    local Status = Instance.new("TextLabel", Main)
    Status.Size = UDim2.new(1,0,0,30)
    Status.Position = UDim2.new(0,0,1,-30)
    Status.Text = "Initializing..."
    Status.TextColor3 = Color3.new(1,1,1)
    Status.BackgroundTransparency = 1
    Status.Parent = Main
    
    task.spawn(function()
        while ScreenGui.Parent do
            local ra = ReplicatedStorage:FindFirstChild("remoteInterface")
            if not ra then Status.Text = "WAITING FOR REMOTES..."
            elseif not getHRP() then Status.Text = "WAITING FOR CHARACTER..."
            else Status.Text = "FARMING ACTIVE" end
            task.wait(1)
        end
    end)
end

setupGUI()
debugLog("v4.1 Loaded. Starting...")
task.spawn(farmLoop)
