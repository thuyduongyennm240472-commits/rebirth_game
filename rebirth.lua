--[[
    AUTO REBIRTH STANDALONE (TỐI GIẢN)
    - Tự động kiểm tra Level 25 (Mining, Food, Wood, Crafting)
    - Tự động Rebirth qua Remote hoặc GUI
]]

if not game:IsLoaded() then game.Loaded:Wait() end
local lp = game:GetService("Players").LocalPlayer
repeat task.wait() until lp and lp:FindFirstChild("PlayerGui")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")

-- HELPER: Lấy level từ GUI
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

-- HELPER: Server Hop
local function serverHop()
    print("[REBIRTH] Đang chuyển server...")
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
        for _, s in ipairs(serverList) do
            if s.id ~= game.JobId and s.playing < s.maxPlayers then
                pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id) end)
                task.wait(5)
            end
        end
    end
    pcall(function() TeleportService:Teleport(game.PlaceId) end)
end

-- LOGIC REBIRTH CHÍNH
local function doRebirth()
    print("[REBIRTH] Đang kiểm tra điều kiện Rebirth...")
    
    -- Kiểm tra 4 kỹ năng chính đạt level 25
    local m = getSkillLevel("Mining")
    local f = getSkillLevel("Food")
    local w = getSkillLevel("Woodcutting")
    local c = getSkillLevel("Crafting")
    
    print(string.format("Levels: Mining:%d, Food:%d, Wood:%d, Crafting:%d", m, f, w, c))
    
    if m >= 25 and f >= 25 and w >= 25 and c >= 25 then
        print("[REBIRTH] Đã đủ điều kiện! Đang thực hiện...")
        
        -- Thử qua Remote trước
        local ri = ReplicatedStorage:FindFirstChild("remoteInterface")
        local rebirthRemote = ri and ri:FindFirstChild("rebirth", true)
        
        if rebirthRemote then
            print("[REBIRTH] Sử dụng Remote: " .. rebirthRemote.Name)
            if rebirthRemote:IsA("RemoteEvent") then rebirthRemote:FireServer() else rebirthRemote:InvokeServer() end
        else
            -- Thử qua GUI nếu không thấy Remote
            local rebirthGui = lp.PlayerGui:FindFirstChild("Rebirth", true)
            if rebirthGui then
                print("[REBIRTH] Sử dụng GUI Rebirth")
                for _, v in ipairs(rebirthGui:GetDescendants()) do
                    if v:IsA("TextButton") and (v.Text == "Rebirth" or v.Name:lower():find("rebirt")) then
                        pcall(function() v.MouseButton1Click:Fire() end)
                        task.wait(1)
                        -- Xác nhận nếu có pop-up
                        for _, g in ipairs(lp.PlayerGui:GetChildren()) do
                            if g:IsA("ScreenGui") and g.Enabled then
                                for _, btn in ipairs(g:GetDescendants()) do
                                    if btn:IsA("TextButton") then
                                        local t = btn.Text:lower()
                                        if t == "yes" or t == "confirm" or t == "xác nhận" or t == "ok" then
                                            pcall(function() btn.MouseButton1Click:Fire() end)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        task.wait(5)
        -- Nếu level đã reset về 1 (Mining < 5) thì coi như thành công
        if getSkillLevel("Mining") < 5 then
            print("[REBIRTH] Thành công! Đổi server...")
            serverHop()
        end
    end
end

print("Auto Rebirth Standalone Loaded.")
while true do
    doRebirth()
    task.wait(10)
end
