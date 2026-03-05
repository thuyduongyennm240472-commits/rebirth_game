--[[
    CORE.LUA - THE BRAIN (BỘ NÃO ĐIỀU PHỐI) - v1.6.8
    - Chống spam Remote Respawn (Cooldown 5s)
    - Fix lỗi cú pháp toàn hệ thống (Farming/Mining/Crafting)
    - Toàn cục hóa _G.forceSpawn (Remote-based)
]]

-- ==================== CONFIG ====================
local CONFIG = {
    webhookUrl = "https://discord.com/api/webhooks/1478859638341636189/fxAzO_rjgjzrUk4KS5f0eD3n8SVJZUU0xkrgveife8jpl2MPXKDmXLoW1nwBWrghggys",
    serverName = "The Survival Game",
    targetLevel = 25,
    rebirthFile = "rebirth_count.txt"
}

-- ==================== GITHUB PRIVATE REPO ====================
local GITHUB = {
    user   = "thuyduongyennm240472-commits",
    repo   = "rebirth_game",
    branch = "main"
}

-- ==================== SERVICES ====================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local CoreGui           = game:GetService("CoreGui")

local lp = Players.LocalPlayer
while not lp do task.wait(0.5) lp = Players.LocalPlayer end

-- ==================== HELPERS ====================
local function log(msg) print("[CORE] " .. tostring(msg)) end

local function getRebirthCount()
    local count = 0
    pcall(function()
        if isfile(CONFIG.rebirthFile) then
            count = tonumber(readfile(CONFIG.rebirthFile)) or 0
        end
    end)
    return count
end

local function addRebirth()
    local count = getRebirthCount() + 1
    pcall(writefile, CONFIG.rebirthFile, tostring(count))
    return count
end

-- ==================== SKILL CACHE SYSTEM ====================
local skillCache = {
    Mining = 0,
    Food = 0,
    Crafting = 0,
    Woodcutting = 0,
    lastUpdate = 0
}

local function updateAllSkills()
    -- Chỉ cập nhật nếu đã qua 5 giây (tránh spam CPU)
    if tick() - skillCache.lastUpdate < 5 then return end
    skillCache.lastUpdate = tick()

    pcall(function()
        local pGui = lp:FindFirstChild("PlayerGui")
        if not pGui then return end

        local tempLevels = { mining = 0, food = 0, crafting = 0, wood = 0 }
        
        -- Một vòng quét duy nhất cho tất cả GUI
        for _, gui in ipairs(pGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Name ~= "StandaloneFarmUI" then
                for _, v in ipairs(gui:GetDescendants()) do
                    if v:IsA("TextLabel") or v:IsA("TextButton") then
                        local txt = v.Text:lower()
                        for key, _ in pairs(tempLevels) do
                            if txt:find(key) then
                                local lvl = v.Text:match("(%d+)")
                                if lvl then 
                                    local val = tonumber(lvl)
                                    if val and val <= 100 then 
                                        tempLevels[key] = math.max(tempLevels[key], val) 
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        -- Cập nhật vào cache chính
        skillCache.Mining = tempLevels.mining
        skillCache.Food = tempLevels.food
        skillCache.Crafting = tempLevels.crafting
        skillCache.Woodcutting = tempLevels.wood
    end)
end

local function getSkillLevel(skillName)
    updateAllSkills() -- Tự động cập nhật nếu cần
    local val = skillCache[skillName] or 0
    return math.min(val, CONFIG.targetLevel)
end

local function getHRP()
    return lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
end

local function getFullStatus()
    -- Sử dụng dữ liệu trực tiếp từ cache mà không quét lại GUI
    return string.format(
        "**Trạng thái Kỹ năng:**\n" ..
        "Mining: `%d/25`\n" ..
        "Food: `%d/25`\n" ..
        "Crafting: `%d/25`\n" ..
        "Woodcutting: `%d/25`\n\n" ..
        "**Tổng số Rebirth:** `%d`",
        skillCache.Mining, skillCache.Food, skillCache.Crafting, skillCache.Woodcutting, getRebirthCount()
    )
end

local function sendWebhook(title, message)
    if not CONFIG.webhookUrl or CONFIG.webhookUrl == "" then return end
    
    local data = {
        ["embeds"] = {{
            ["title"] = title or "🚀 **HOẠT ĐỘNG REBIRTH**",
            ["description"] = message .. "\n\n" .. getFullStatus(),
            ["color"] = 65280,
            ["footer"] = { ["text"] = "Lester Rebirth" },
            ["author"] = { ["name"] = lp.Name .. " (" .. CONFIG.serverName .. ")" }
        }}
    }

    pcall(function()
        local http = game:GetService("HttpService")
        local jsonBody = http:JSONEncode(data)
        local req = (syn and syn.request) or (http_request) or (request)
        if req then
            req({ Url = CONFIG.webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = jsonBody })
        else
            http:PostAsync(CONFIG.webhookUrl, jsonBody)
        end
    end)
end

-- ==================== SYSTEM FUNCTIONS ====================
local R = {}
local function loadRemotes()
    local ok = pcall(function()
        local ri = ReplicatedStorage:WaitForChild("remoteInterface", 10)
        local charR = ri:WaitForChild("character", 5)
        R.reset = charR:WaitForChild("reset", 3)
        R.respawn = charR:WaitForChild("respawn", 3)
    end)
    return ok
end

local function wipeUI()
    log("Làm sạch UI an toàn (Lite Wipe)...")
    pcall(function()
        local toDestroy = {"SpawnUI", "menuScreen", "intro", "Intro", "Loading", "introGui", "Announcements", "News", "Rules", "RulesUI", "PlayGui", "StartGui"}
        for _, name in ipairs(toDestroy) do
            local ui = lp.PlayerGui:FindFirstChild(name)
            if ui then ui:Destroy() end
        end

        local toHide = {"AvatarUI", "Settings", "Bundles", "Codes", "Kingdom", "IndicatorGui", "MainGui", "Skills", "Inventory", "Stats", "Tutorial"}
        for _, name in ipairs(toHide) do
            local ui = lp.PlayerGui:FindFirstChild(name)
            if ui and ui:IsA("ScreenGui") then ui.Enabled = false end
        end
    end)
end

local lastForceSpawn = 0
local function forceSpawn()
    if tick() - lastForceSpawn < 5 then return end -- Cooldown 5s tránh spam
    lastForceSpawn = tick()
    
    if not loadRemotes() then return end
    log("Force Spawn qua Remote...")
    pcall(function()
        R.reset:InvokeServer()
        task.wait(0.3)
        R.respawn:InvokeServer(15382674, 12, 2, 17, 15382674, 15382674, false)
    end)
    local t = tick()
    repeat task.wait(0.5) until getHRP() or (tick() - t > 10)
end
_G.forceSpawn = forceSpawn -- Toàn cục hóa để các script lẻ sử dụng

local function serverHop(reason)
    local msg = "🔄 **Server Hop**: " .. (reason or "Tiếp tục quy trình")
    log(msg)
    sendWebhook("🔄 DANG DOI SERVER", msg)
    task.wait(1.5) -- Đợi 1.5s để Webhook kịp gửi đi trước khi ngắt kết nối
    
    local function getServers()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        local success, rawData = pcall(game.HttpGet, game, url)
        if success and rawData then
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

-- Kick & Attack Detection
local lastHP = 100
task.spawn(function()
    while true do
        pcall(function()
            -- 1. GIÁM SÁT BỊ TẤN CÔNG
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            
            if hum and hum.Health > 0 and hrp then
                local currentHP = hum.Health
                if currentHP < (lastHP - 5) then
                    lastHP = currentHP -- Cập nhật ngay để tránh trigger liên tiếp do Webhook delay
                    local attacker = "Không xác định (Quái hoặc Rơi)"
                    local minDist = 40
                    for _, player in ipairs(Players:GetPlayers()) do
                        if player ~= lp and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                            pcall(function()
                                local d = (player.Character.HumanoidRootPart.Position - hrp.Position).Magnitude
                                if d < minDist then
                                    minDist = d
                                    attacker = player.Name
                                end
                            end)
                        end
                    end
                    log("⚔️ CẢNH BÁO BỊ TẤN CÔNG: " .. attacker)
                    task.spawn(sendWebhook, "⚔️ **CANH BAO: BI TAN CONG**", string.format("Bạn đang bị tấn công!\nHP: `%.1f` -> `%.1f`\nĐối tượng nghi vấn: **%s**", lastHP + 5, currentHP, attacker))
                end
                lastHP = currentHP
            elseif not hum or hum.Health <= 0 then
                lastHP = 100 -- Reset khi chết
            end

            -- 2. GIÁM SÁT KICK/DISCONNECT
            local prompt = CoreGui:FindFirstChild("RobloxPromptGui")
            local err = prompt and prompt:FindFirstChild("promptOverlay") and prompt.promptOverlay:FindFirstChild("ErrorPrompt")
            if err and err.Visible then
                local title = err:FindFirstChild("TitleFrame") and err.TitleFrame:FindFirstChild("ErrorTitle")
                local msgArea = err:FindFirstChild("MessageArea")
                local errorMsg = msgArea and msgArea:FindFirstChild("ErrorFrame") and msgArea.ErrorFrame:FindFirstChild("ErrorMessage")
                
                local reason = errorMsg and errorMsg.Text or "Unknown Reason"
                local header = title and title.Text or "DISCONNECTED"
                
                if not _G.KickedNotified then
                    _G.KickedNotified = true
                    log("⚠️ BI KICK: " .. reason)
                    sendWebhook("⚠️ **" .. header:upper() .. "**", "Chi tiết: " .. reason .. "\n\nScript sẽ tự động đổi server...")
                    task.wait(1)
                    serverHop("Bị Kick/Disc: " .. reason)
                end
            end
        end)
        task.wait(2)
    end
end)

local function runLocalScript(filename)
    local content = nil
    log("Đang tải: " .. filename)

    -- Ưu tiên 1: Tải từ GitHub Public Raw (Không cần token)
    if GITHUB.user ~= "YOUR_GITHUB_USERNAME" then
        local url = string.format(
            "https://raw.githubusercontent.com/%s/%s/%s/%s",
            GITHUB.user, GITHUB.repo, GITHUB.branch, filename
        )
        
        local success, res = pcall(function()
            return game:HttpGet(url)
        end)
        
        if success and res and #res > 0 then
            content = res
            log("Tải thành công từ GitHub: " .. filename)
        else
            log("GitHub: Không thể tải Raw URL (Có thể file chưa public hoặc sai link)")
        end
    end

    -- Ưu tiên 2: Đọc từ file local (nếu GitHub thất bại)
    if not content then
        log("Thử đọc file local: " .. filename)
        pcall(function()
            local c = readfile(filename)
            if c and #c > 0 then 
                content = c 
                log("Sử dụng file local: " .. filename)
            end
        end)
    end

    if content then
        log("Run: " .. filename)
        task.spawn(function()
            local func, err = loadstring(content)
            if func then func() else warn("Lỗi load " .. filename .. ": " .. tostring(err)) end
        end)
        return true
    else
        warn("[CORE] Không thể tải: " .. filename .. " (Kiểm tra token và tên repo)")
        return false
    end
end

-- ==================== MAIN CYCLE ====================
if not game:IsLoaded() then game.Loaded:Wait() end
log("Game Loaded. Khởi động nhanh...")
task.wait(1) -- Giảm từ 5s xuống 1s
local function ensureSpawned()
    if not getHRP() then forceSpawn() end
    local t = tick()
    repeat task.wait(0.5) until getHRP() or (tick() - t > 15)
    
    log("Đợi Stats đồng bộ...")
    local waitStart = tick()
    while (tick() - waitStart < 5) do -- Giảm từ 10s xuống 5s
        if lp.PlayerGui:FindFirstChild("Skills") or lp.PlayerGui:FindFirstChild("MainGui") then break end
        task.wait(0.2)
    end
    task.wait(0.5) -- Giảm từ 2s xuống 0.5s
end

ensureSpawned()
wipeUI()
sendWebhook("✅ **KHOI DONG HE THONG**", "Lester Rebirth đã khởi động thành công.")

while true do
    if not getHRP() then
        ensureSpawned()
        wipeUI()
    end

    local mining   = getSkillLevel("Mining")
    local food     = getSkillLevel("Food")
    local crafting = getSkillLevel("Crafting")
    local wood     = getSkillLevel("Woodcutting")
    
    log(string.format("Skills: Min:%d Food:%d Craf:%d Wood:%d", mining, food, crafting, wood))

    if mining < CONFIG.targetLevel then
        if runLocalScript("mining.lua") then
            repeat task.wait(10) until getSkillLevel("Mining") >= CONFIG.targetLevel
            serverHop("Mining đạt level " .. CONFIG.targetLevel)
        end
    elseif food < CONFIG.targetLevel then
        if runLocalScript("farming.lua") then
            repeat task.wait(10) until getSkillLevel("Food") >= CONFIG.targetLevel
            serverHop("Food đạt level " .. CONFIG.targetLevel)
        end
    elseif crafting < CONFIG.targetLevel then
        if runLocalScript("crafting.lua") then
            repeat task.wait(10) until getSkillLevel("Crafting") >= CONFIG.targetLevel
            serverHop("Crafting đạt level " .. CONFIG.targetLevel)
        end
    elseif wood < CONFIG.targetLevel then
        if runLocalScript("wood.lua") then
            repeat task.wait(10) until getSkillLevel("Woodcutting") >= CONFIG.targetLevel
            serverHop("Woodcutting đạt level " .. CONFIG.targetLevel)
        end
    else
        log("Goal đạt được! Đang Rebirth...")
        addRebirth()
        sendWebhook("🌟 **MUC TIEU DA DAT**", "Chu kỳ hoàn tất. Đang Rebirth...")
        if runLocalScript("rebirth.lua") then
            task.wait(15)
            serverHop("Rebirth completed")
        end
    end
    
    task.wait(10)
end
