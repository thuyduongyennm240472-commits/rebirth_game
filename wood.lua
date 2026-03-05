--[[
    WOOD.LUA v3.3 - USER BASE VERSION
    - Logic: Theo bản v1.0 của người dùng (Siêu ổn định)
    - Reconnect: Tự động kết nối lại khi bị Kick/Crash
    - Optimize: Tốc độ chặt cực nhanh (0.05s)
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

-- REMOTE INTERFACES
local ri            = ReplicatedStorage:WaitForChild("remoteInterface")
local intRemotes    = ri:WaitForChild("interactions")
local charRemotes   = ri:WaitForChild("character")
local toolRemotes   = ri:WaitForChild("Tools", 5)

local chopRemote    = intRemotes:WaitForChild("chop")
local resetRemote   = charRemotes:WaitForChild("reset")
local respawnRemote = charRemotes:WaitForChild("respawn")
local toolCheck     = toolRemotes and toolRemotes:WaitForChild("CheckToolSetup", 3)

local settings = {
    enabled       = true,
    delay         = 0.05, -- Tốc độ chặt nhanh (v3.0)
    toolSlot      = 4,
    scanRange     = 5000,
    isTeleporting = false,
    targetCF      = nil,
    targetTree    = nil,
    spawnPos      = CFrame.new(96, 22.0625, 52), -- Tọa độ chuẩn của bạn
    respawnArgs   = {15382674, 12, 2, 17, 15382674, 15382674, false}
}

-- AUTO RECONNECT (Tự động kết nối lại khi Kick)
task.spawn(function()
    while true do
        pcall(function()
            local prompt = CoreGui:FindFirstChild("RobloxPromptGui")
            if prompt then
                local overlay = prompt:FindFirstChild("promptOverlay")
                if overlay then
                    local err = overlay:FindFirstChild("ErrorPrompt")
                    if err then
                        print("[RECONNECT] Phat hien bi Kick. Dang quay lai...")
                        TeleportService:Teleport(game.PlaceId, lp)
                    end
                end
            end
        end)
        task.wait(2)
    end
end)

-- HELPERS
local function liteUIWipe()
    local targets = {"Avatar", "AvatarUI", "SpawnUI", "Menu", "Intro", "MainGui", "Announcements", "News", "Loading"}
    for _, name in ipairs(targets) do
        local ui = lp.PlayerGui:FindFirstChild(name)
        if ui then pcall(function() ui:Destroy() end) end
    end
    -- Dọn dẹp GUI cũ của script
    for _, gui in ipairs(lp.PlayerGui:GetChildren()) do
        if gui.Name == "WoodFarmStatus" or gui.Name == "AutoChopGui" then
            pcall(function() gui:Destroy() end)
        end
    end
end

local function getHRP()
    return lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
end

-- HÀM TÌM CÂY GẦN NHẤT
local function getNearestTree()
    local choppable = workspace:FindFirstChild("worldResources") and workspace.worldResources:FindFirstChild("choppable")
    if not choppable then return nil, nil end

    local hrp = getHRP()
    if not hrp then return nil, nil end

    local nearest, minDist = nil, settings.scanRange
    for _, segment in ipairs(choppable:GetChildren()) do
        for _, tree in ipairs(segment:GetChildren()) do
            local n = tree.Name:lower()
            -- Blacklist rác
            if not n:find("mushroom") and not n:find("bush") and not n:find("shrub") then
                local health = tree:GetAttribute("health")
                if health == nil or health > 0 then
                    local pos = tree:IsA("PVInstance") and tree:GetPivot().Position
                    if pos then
                        local d = (hrp.Position - pos).Magnitude
                        if d < minDist then
                            minDist = d
                            nearest = tree
                        end
                    end
                end
            end
        end
    end
    return nearest, minDist
end

-- VÒNG LẶP CHOP CHÍNH
local function startChopping(tree)
    if not tree or not tree.Parent then return end
    
    local tool = (lp.Character and lp.Character:FindFirstChild(tostring(settings.toolSlot)))
               or (lp.Backpack and lp.Backpack:FindFirstChild(tostring(settings.toolSlot)))
    if tool and toolCheck then pcall(function() toolCheck:InvokeServer(tool) end) end

    local startTime = tick()
    while settings.enabled and tree and tree.Parent and (tick() - startTime < 10) do
        local h = tree:GetAttribute("health")
        if h and h <= 0 then break end
        
        pcall(function()
            chopRemote:FireServer(settings.toolSlot, tree, tree:GetPivot())
        end)
        task.wait(settings.delay) -- 0.05s
    end
end

local function smartTeleport(cf, tree)
    settings.isTeleporting = true
    settings.targetCF = cf
    settings.targetTree = tree
    print("=> [RESPAWN TP]: Reset de di chuyen xa...")
    pcall(function() resetRemote:InvokeServer() end)
    task.wait(0.5)
    pcall(function() respawnRemote:InvokeServer(unpack(settings.respawnArgs)) end)
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
                -- INSTANT TP SIÊU TỐC
                print("=> [INSTANT TP]: " .. tree.Name)
                for _ = 1, 3 do
                    hrp.CFrame = targetCF
                    hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    task.wait(0.01)
                end
                startChopping(tree)
                task.spawn(farmLoop)
            else
                print("=> [SMART TP]: " .. tree.Name)
                smartTeleport(targetCF, tree)
            end
        end
    else
        print("=> Hết cây. Đang đợi hoặc đổi server...")
        task.wait(2)
        farmLoop()
    end
end

-- CHARACTER ADDED logic
lp.CharacterAdded:Connect(function(char)
    liteUIWipe()
    task.spawn(function()
        local hrp = char:WaitForChild("HumanoidRootPart", 10)
        if not hrp then return end
        task.wait(0.3)

        if settings.isTeleporting and settings.targetCF then
            -- STICKY TP về cây mục tiêu
            print("=> [STICKY TP] -> Target")
            for _ = 1, 10 do
                if not hrp or not hrp.Parent then break end
                hrp.CFrame = settings.targetCF
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                task.wait(0.05)
            end
            settings.isTeleporting = false
            
            local tree = settings.targetTree
            settings.targetTree = nil
            if tree then startChopping(tree) end
            task.spawn(farmLoop)
        else
            -- SPAWN TP về bãi farm cố định
            print("=> [SPAWN TP] -> Home")
            for _ = 1, 10 do
                if not hrp or not hrp.Parent then break end
                hrp.CFrame = settings.spawnPos
                task.wait(0.05)
            end
            task.spawn(farmLoop)
        end
    end)
end)

-- GUI SETUP
local function setupGUI()
    pcall(function()
        if lp.PlayerGui:FindFirstChild("AutoChopGui") then lp.PlayerGui.AutoChopGui:Destroy() end
        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Name = "AutoChopGui"
        if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = game:GetService("CoreGui") end

        local Main = Instance.new("Frame")
        Main.Size = UDim2.new(0, 200, 0, 150)
        Main.Position = UDim2.new(0, 50, 0, 50) -- Góc trái cho gọn
        Main.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        Main.Draggable = true
        Main.Active = true
        Main.Parent = ScreenGui
        Instance.new("UICorner").Parent = Main

        local Title = Instance.new("TextLabel")
        Title.Size = UDim2.new(1, 0, 0, 35)
        Title.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
        Title.Text = "WOOD v3.3 RECONNECT"
        Title.TextColor3 = Color3.new(1,1,1)
        Title.Font = Enum.Font.GothamBold
        Title.Parent = Main
        Instance.new("UICorner", Title)

        local StartBtn = Instance.new("TextButton")
        StartBtn.Size = UDim2.new(0.9, 0, 0, 50)
        StartBtn.Position = UDim2.new(0.05, 0, 0, 50)
        StartBtn.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
        StartBtn.Text = "DỪNG FARM"
        StartBtn.TextColor3 = Color3.new(1,1,1)
        StartBtn.Font = Enum.Font.GothamBold
        StartBtn.Parent = Main
        Instance.new("UICorner", StartBtn)

        StartBtn.MouseButton1Click:Connect(function()
            settings.enabled = not settings.enabled
            StartBtn.Text = settings.enabled and "DỪNG FARM" or "BẮT ĐẦU FARM"
            StartBtn.BackgroundColor3 = settings.enabled and Color3.fromRGB(150, 0, 0) or Color3.fromRGB(0, 150, 0)
            if settings.enabled then task.spawn(farmLoop) end
        end)
    end)
end

-- INIT
liteUIWipe()
setupGUI()
print("Wood v3.3 Loaded.")

-- Lần đầu chạy: Respawn để về bãi farm
pcall(function() resetRemote:InvokeServer() end)
task.wait(0.3)
pcall(function() respawnRemote:InvokeServer(unpack(settings.respawnArgs)) end)
