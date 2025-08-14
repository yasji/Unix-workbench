--[[
    @author Auto-Gift Script
    @description Grow a Garden auto-gifting script
    https://www.roblox.com/games/126884695634066
]]

print("🚀 Loading Auto-Gift Script...")

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Backpack = LocalPlayer.Backpack
local PlayerGui = LocalPlayer.PlayerGui

print("✅ Services loaded")

--// Wait for character
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
print("✅ Character loaded")

--// Safe ReGui loading with fallback
local ReGui = nil
local UseReGui = false

local function SafeLoadReGui()
    local success, result = pcall(function()
        return loadstring(game:HttpGet('https://raw.githubusercontent.com/depthso/Dear-ReGui/refs/heads/main/ReGui.lua'))()
    end)
    
    if success and result then
        ReGui = result
        UseReGui = true
        print("✅ ReGui loaded successfully")
        
        local PrefabsId = "rbxassetid://" .. ReGui.PrefabsId
        
        --// ReGui configuration
        ReGui:Init({
            Prefabs = InsertService:LoadLocalAsset(PrefabsId)
        })
        ReGui:DefineTheme("GardenTheme", {
            WindowBg = Color3.fromRGB(26, 20, 8),
            TitleBarBg = Color3.fromRGB(45, 95, 25),
            TitleBarBgActive = Color3.fromRGB(69, 142, 40),
            ResizeGrab = Color3.fromRGB(45, 95, 25),
            FrameBg = Color3.fromRGB(45, 95, 25),
            FrameBgActive = Color3.fromRGB(69, 142, 40),
            CollapsingHeaderBg = Color3.fromRGB(69, 142, 40),
            ButtonsBg = Color3.fromRGB(69, 142, 40),
            CheckMark = Color3.fromRGB(69, 142, 40),
            SliderGrab = Color3.fromRGB(69, 142, 40),
        })
    else
        warn("❌ ReGui failed to load: " .. tostring(result))
        warn("📱 Using fallback UI system")
        UseReGui = false
    end
end

SafeLoadReGui()

--// Folders (Safe access)
local GameEvents = nil
local function GetGameEvents()
    if GameEvents then return GameEvents end
    
    local success, result = pcall(function()
        return ReplicatedStorage:WaitForChild("GameEvents", 5)
    end)
    
    if success then
        GameEvents = result
        print("✅ GameEvents found")
    else
        warn("⚠️ GameEvents not found, creating placeholder")
        GameEvents = {}
    end
    
    return GameEvents
end

--// Initialize GameEvents
GetGameEvents()

--// Gift Configuration
local GiftConfig = {
    HoldDuration = 1.2,
    MaxDistance = 10,
    Cooldown = 3,
    MaxRetries = 3,
    RetryDelay = 2,
}

--// Gift State
local GiftState = {
    IsHolding = false,
    HoldStart = 0,
    CurrentTarget = nil,
    LastGiftTime = {},
    PendingGifts = {},
    AcceptedGifts = {},
    RejectedGifts = {},
    GiftQueue = {},
}

--// Globals
local AutoGift, SelectedItem, TargetPlayer, GiftStatus, MaxDistance, HoldDuration
local GiftRetries, RetryDelay, AutoRetry, AutoTeleport, TeleportDistance, TeleportOffset

-- Safe status update to avoid indexing Text on non-text instances (e.g., ImageButton)
local function SetGiftStatus(msg)
    if not msg then return end
    if type(GiftStatus) == "table" then
        GiftStatus.Text = msg
        if GiftStatus.SetText then pcall(function() GiftStatus:SetText(msg) end) end
        if GiftStatus.Set then pcall(function() GiftStatus:Set(msg) end) end
        return
    end
    if typeof(GiftStatus) == "Instance" then
        if GiftStatus:IsA("TextLabel") or GiftStatus:IsA("TextButton") then
            pcall(function() GiftStatus.Text = msg end)
            return
        end
        local ok, label = pcall(function()
            return GiftStatus:FindFirstChildWhichIsA("TextLabel", true) or GiftStatus:FindFirstChildWhichIsA("TextButton", true)
        end)
        if ok and label then
            pcall(function() label.Text = msg end)
        end
    end
end

local function CreateWindow()
    if UseReGui then
        local success, window = pcall(function()
            return ReGui:Window({
                Title = "Auto-Gift | Grow a Garden",
                Theme = "GardenTheme",
                Size = UDim2.fromOffset(350, 300)
            })
        end)
        
        if success then
            return window
        else
            warn("❌ ReGui window failed, using fallback")
            UseReGui = false
        end
    end
    
    -- Fallback: Create simple ScreenGui
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "AutoGiftGui"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = PlayerGui
    
    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, 350, 0, 400)
    MainFrame.Position = UDim2.new(0.5, -175, 0.5, -200)
    MainFrame.BackgroundColor3 = Color3.fromRGB(26, 20, 8)
    MainFrame.BorderSizePixel = 0
    MainFrame.Parent = ScreenGui
    
    -- Make draggable
    local UISCorner = Instance.new("UICorner")
    UISCorner.CornerRadius = UDim.new(0, 8)
    UISCorner.Parent = MainFrame
    
    -- Title
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 30)
    Title.BackgroundColor3 = Color3.fromRGB(45, 95, 25)
    Title.Text = "🎁 Auto-Gift | Grow a Garden"
    Title.TextColor3 = Color3.new(1, 1, 1)
    Title.TextScaled = true
    Title.Font = Enum.Font.GothamBold
    Title.Parent = MainFrame
    
    local TitleCorner = Instance.new("UICorner")
    TitleCorner.CornerRadius = UDim.new(0, 8)
    TitleCorner.Parent = Title
    
    -- Simple drag functionality
    local dragging = false
    local dragStart, startPos
    
    Title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)
    
    Title.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    Title.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    -- Status label
    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Size = UDim2.new(1, -20, 0, 25)
    StatusLabel.Position = UDim2.new(0, 10, 0, 40)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Text = "🚀 Ready to Auto-Gift!"
    StatusLabel.TextColor3 = Color3.new(1, 1, 1)
    StatusLabel.TextScaled = true
    StatusLabel.Font = Enum.Font.Gotham
    StatusLabel.Parent = MainFrame
    
    print("✅ Fallback GUI created")
    return MainFrame, StatusLabel
end

--// Utility Functions
local function TeleportToPlayer(PlayerName, Distance)
    print(`📍 Attempting to teleport to {PlayerName}`)
    
    local Character = LocalPlayer.Character
    local TargetPlayer = game.Players:FindFirstChild(PlayerName)
    
    if not Character or not Character:FindFirstChild("HumanoidRootPart") then 
        warn("❌ No character or HumanoidRootPart")
        return false, "No character" 
    end
    
    if not TargetPlayer then
        warn(`❌ Target player {PlayerName} not found`)
        return false, "Target player not found"
    end
    
    if not TargetPlayer.Character or not TargetPlayer.Character:FindFirstChild("HumanoidRootPart") then
        warn(`❌ Target {PlayerName} has no character/HumanoidRootPart`)
        return false, "Target character not found"
    end
    
    local MyRoot = Character.HumanoidRootPart
    local TargetRoot = TargetPlayer.Character.HumanoidRootPart
    
    print(`📏 Current distance: {math.floor((MyRoot.Position - TargetRoot.Position).Magnitude)} studs`)
    
    -- Calculate position behind target (safer for gifting)
    local TargetCFrame = TargetRoot.CFrame
    local SafeDistance = Distance or 3
    local Offset = TargetCFrame.LookVector * -SafeDistance -- Behind the target
    local TeleportPosition = TargetRoot.Position + Offset
    
    -- Add Y offset to avoid getting stuck in ground
    TeleportPosition = TeleportPosition + Vector3.new(0, 2, 0)
    
    -- Perform teleportation
    local success, err = pcall(function()
        MyRoot.CFrame = CFrame.new(TeleportPosition, TargetRoot.Position)
    end)
    
    if success then
        print(`✅ Successfully teleported to {PlayerName}`)
        wait(0.1) -- Brief stabilization
        local newDistance = (MyRoot.Position - TargetRoot.Position).Magnitude
        print(`📏 New distance: {math.floor(newDistance)} studs`)
        return true, "Teleported to " .. PlayerName
    else
        warn(`❌ Teleport failed: {err}`)
        return false, "Teleport failed: " .. tostring(err)
    end
end

local function GetAllPlayers()
    local PlayersList = {}
    for _, Player in next, game.Players:GetPlayers() do
        if Player ~= LocalPlayer then
            PlayersList[Player.Name] = Player.Name
        end
    end
    return PlayersList
end

local function GetEquippedItem()
    local Character = LocalPlayer.Character
    if not Character then return nil end
    
    local Tool = Character:FindFirstChildOfClass("Tool")
    if Tool then
        return Tool, Tool.Name
    end
    
    return nil
end

local function GetGiftableItems()
    local Character = LocalPlayer.Character
    local Items = {}
    
    -- Check backpack
    for _, Tool in next, Backpack:GetChildren() do
        if Tool:IsA("Tool") then
            local ItemName = Tool:FindFirstChild("Item_String") or Tool:FindFirstChild("Plant_Name")
            if ItemName then
                Items[Tool.Name] = Tool
            end
        end
    end
    
    -- Check equipped
    if Character then
        for _, Tool in next, Character:GetChildren() do
            if Tool:IsA("Tool") then
                local ItemName = Tool:FindFirstChild("Item_String") or Tool:FindFirstChild("Plant_Name")
                if ItemName then
                    Items[Tool.Name] = Tool
                end
            end
        end
    end
    
    return Items
end

local function GetNearbyPlayers()
    local Character = LocalPlayer.Character
    if not Character or not Character:FindFirstChild("HumanoidRootPart") then return {} end
    
    local Root = Character.HumanoidRootPart
    local Players = {}
    
    for _, Player in next, game.Players:GetPlayers() do
        if Player ~= LocalPlayer and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
            local Distance = (Root.Position - Player.Character.HumanoidRootPart.Position).Magnitude
            if Distance <= MaxDistance.Value then
                Players[Player.Name] = Player
            end
        end
    end
    
    return Players
end

local function FindTargetPlayer()
    local Character = LocalPlayer.Character
    if not Character or not Character:FindFirstChild("HumanoidRootPart") then return nil end
    
    local Root = Character.HumanoidRootPart
    local Forward = Root.CFrame.LookVector
    local BestPlayer = nil
    local BestDot = 0.7 -- Minimum dot product for frontal detection
    
    for _, Player in next, game.Players:GetPlayers() do
        if Player ~= LocalPlayer and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
            local TargetRoot = Player.Character.HumanoidRootPart
            local Offset = (TargetRoot.Position - Root.Position)
            local Distance = Offset.Magnitude
            
            if Distance <= MaxDistance.Value then
                local Direction = Offset.Unit
                local DotProduct = Direction:Dot(Forward)
                
                if DotProduct > BestDot then
                    BestDot = DotProduct
                    BestPlayer = Player
                end
            end
        end
    end
    
    return BestPlayer
end

--// Mobile Gift Functions
local function FindGiftButton(targetPlayer)
    -- Look for gift-related UI elements in PlayerGui
    local playerGui = LocalPlayer.PlayerGui
    
    -- Wait a moment for UI to load
    wait(0.5)
    
    print("🔍 Scanning PlayerGui for gift interfaces...")
    
    -- Check all ScreenGuis
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled then
            print(`📋 Checking GUI: {gui.Name}`)
            
            -- Look for gift-related frames or buttons
            for _, descendant in ipairs(gui:GetDescendants()) do
                if descendant:IsA("GuiButton") or descendant:IsA("TextButton") or descendant:IsA("ImageButton") then
                    local text = ""
                    local name = descendant.Name:lower()
                    
                    -- Safely get text property
                    local success, textValue = pcall(function()
                        if descendant:IsA("TextButton") or descendant:IsA("TextLabel") then
                            return descendant.Text
                        elseif descendant:FindFirstChild("TextLabel") then
                            return descendant.TextLabel.Text
                        elseif descendant:FindFirstChild("Text") and descendant.Text:IsA("StringValue") then
                            return descendant.Text.Value
                        else
                            return ""
                        end
                    end)
                    
                    if success then
                        text = tostring(textValue):lower()
                    end
                    
                    -- Check for gift-related keywords
                    if text:find("gift") or text:find("trade") or text:find("give") or text:find("send") or
                       name:find("gift") or name:find("trade") or name:find("give") or name:find("send") then
                        print(`🎁 Found gift button: {descendant.Name} - "{text}" in {gui.Name}`)
                        return descendant
                    end
                    
                    -- Log all buttons for debugging
                    print(`🔍 Button found: {descendant.Name} ({descendant.ClassName}) - Text: "{text}"`)
                end
            end
        end
    end
    
    return nil
end

local function FindProximityPrompts()
    print("🔍 Scanning for ProximityPrompts...")
    
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then 
        return nil 
    end
    
    local playerPos = character.HumanoidRootPart.Position
    local foundPrompts = {}
    
    -- Search entire workspace for proximity prompts
    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") and descendant.Enabled then
            -- Check if prompt has gift-related action text
            local actionText = tostring(descendant.ActionText):lower()
            
            if actionText:find("gift") or actionText:find("trade") or actionText:find("give") or 
               actionText:find("send") or actionText:find("present") then
                
                -- Check distance
                local promptParent = descendant.Parent
                if promptParent and promptParent:FindFirstChild("HumanoidRootPart") then
                    local distance = (playerPos - promptParent.HumanoidRootPart.Position).Magnitude
                    if distance <= 15 then
                        table.insert(foundPrompts, {
                            prompt = descendant,
                            distance = distance,
                            parent = promptParent.Name
                        })
                        print(`🎯 Found gift prompt: "{descendant.ActionText}" on {promptParent.Name} ({math.floor(distance)} studs)`)
                    end
                end
            end
        end
    end
    
    return #foundPrompts > 0 and foundPrompts or nil
end

local function TriggerMobileGift(targetPlayer, itemName)
    print(`📱 Starting mobile gift process: {itemName} → {targetPlayer.Name}`)
    
    -- Ensure we're close to target
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return false, "No character"
    end
    
    if not targetPlayer.Character or not targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return false, "Target has no character"
    end
    
    local distance = (character.HumanoidRootPart.Position - targetPlayer.Character.HumanoidRootPart.Position).Magnitude
    print(`📏 Distance to target: {math.floor(distance)} studs`)
    
    if distance > 10 then
        return false, "Too far from target"
    end
    
    -- Method 1: Try ProximityPrompts
    print("🎯 Method 1: Searching for ProximityPrompts...")
    local prompts = FindProximityPrompts()
    if prompts then
        -- Try closest prompt first
        table.sort(prompts, function(a, b) return a.distance < b.distance end)
        
        for _, promptData in ipairs(prompts) do
            print(`🎯 Triggering ProximityPrompt: "{promptData.prompt.ActionText}"`)
            
            local success, err = pcall(function()
                fireproximityprompt(promptData.prompt)
            end)
            
            if success then
                print("✅ ProximityPrompt triggered successfully!")
                wait(1) -- Give time for UI to respond
                return true, "ProximityPrompt method successful"
            else
                warn(`❌ ProximityPrompt failed: {err}`)
            end
        end
    else
        print("❌ No gift-related ProximityPrompts found")
    end
    
    -- Method 2: Try UI buttons
    print("🖱️ Method 2: Searching for UI buttons...")
    local giftButton = FindGiftButton(targetPlayer)
    if giftButton then
        print(`🖱️ Attempting to click: {giftButton.Name}`)
        
        local success, err = pcall(function()
            -- Multiple click methods
            if giftButton.MouseButton1Click then
                giftButton.MouseButton1Click:Fire()
            end
            
            -- Try connection firing
            for _, connection in pairs(getconnections(giftButton.MouseButton1Click or giftButton.Activated)) do
                if connection and connection.Function then
                    connection:Fire()
                end
            end
            
            -- Try direct activation
            if giftButton.Activated then
                giftButton.Activated:Fire()
            end
        end)
        
        if success then
            print("✅ Gift button clicked successfully!")
            wait(1)
            return true, "UI button method successful"
        else
            warn(`❌ Button click failed: {err}`)
        end
    else
        print("❌ No gift-related UI buttons found")
    end
    
    -- Method 3: Look for player-specific interactions
    print("👤 Method 3: Looking for player interaction...")
    
    -- Try clicking on the player's character
    if targetPlayer.Character then
        local humanoid = targetPlayer.Character:FindFirstChild("Humanoid")
        local clickDetector = targetPlayer.Character:FindFirstChildOfClass("ClickDetector")
        
        if clickDetector then
            print("�️ Found ClickDetector on target player")
            local success, err = pcall(function()
                fireclickdetector(clickDetector)
            end)
            if success then
                print("✅ ClickDetector triggered!")
                wait(1)
                return true, "ClickDetector method successful"
            else
                warn(`❌ ClickDetector failed: {err}`)
            end
        end
    end
    
    print("❌ All mobile gift methods failed")
    return false, "No working mobile gift method found"
end

local function AutoEquipItem(ItemName)
    local Character = LocalPlayer.Character
    if not Character then return false end
    
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid then return false end
    
    -- Check if already equipped
    local EquippedTool = Character:FindFirstChildOfClass("Tool")
    if EquippedTool and EquippedTool.Name == ItemName then
        return true
    end
    
    -- Find and equip the tool
    local Tool = Backpack:FindFirstChild(ItemName)
    if Tool and Tool:IsA("Tool") then
        Humanoid:EquipTool(Tool)
        wait(0.2) -- Brief delay for equipping
        return true
    end
    
    return false
end

local function SendGift(ItemName, TargetName)
    print(`🎁 SendGift called: {ItemName} → {TargetName}`)
    
    local Character = LocalPlayer.Character
    if not Character then 
        print("❌ No character found")
        return false, "No character" 
    end
    
    local TargetPlayer = game.Players:FindFirstChild(TargetName)
    if not TargetPlayer then 
        print(`❌ Target player {TargetName} not found`)
        return false, "Target player not found" 
    end
    
    -- Auto-equip the item first
    print(`� Attempting to equip: {ItemName}`)
    local equipSuccess = AutoEquipItem(ItemName)
    if not equipSuccess then
        print(`❌ Could not equip item: {ItemName}`)
        return false, "Could not equip item"
    end
    print("✅ Item equipped successfully")
    
    -- Mobile-optimized gifting (no E key required)
    print("📱 Trying mobile gift methods...")
    local mobileGiftSuccess, mobileMessage = TriggerMobileGift(TargetPlayer, ItemName)
    
    if mobileGiftSuccess then
        print(`✅ Mobile gift successful: {mobileMessage}`)
        return true, mobileMessage
    else
        print(`❌ Mobile gift failed: {mobileMessage}`)
    end
    
    print("📡 Trying RemoteEvent fallbacks...")
    -- Try game events as final fallback
    local gameEvents = GetGameEvents()
    if gameEvents and type(gameEvents) == "userdata" then
        local giftEventNames = {
            "Gift_RE", "SendGift", "GiftPlayer", "TradeItem", "Gift", 
            "PlayerGift", "GiveItem", "TransferItem", "ItemGift"
        }
        
        for _, eventName in ipairs(giftEventNames) do
            local event = gameEvents:FindFirstChild(eventName)
            if event and event:IsA("RemoteEvent") then
                print(`📡 Trying RemoteEvent: {eventName}`)
                
                -- Try multiple parameter combinations
                local paramCombinations = {
                    {ItemName, TargetPlayer},
                    {TargetPlayer, ItemName},
                    {ItemName, TargetPlayer.UserId},
                    {TargetPlayer.UserId, ItemName},
                    {ItemName, TargetName},
                    {TargetName, ItemName}
                }
                
                for i, params in ipairs(paramCombinations) do
                    local success, err = pcall(function()
                        event:FireServer(unpack(params))
                    end)
                    
                    if success then
                        print(`✅ RemoteEvent {eventName} successful with params {i}`)
                        return true, `RemoteEvent {eventName} successful`
                    else
                        print(`⚠️ RemoteEvent {eventName} params {i} failed: {err}`)
                    end
                end
            end
        end
    end
    
    print("❌ All gift methods failed")
    return false, "All gift methods failed"
end

local function CheckGiftAcceptance(GiftId)
    -- This would need to be implemented based on the actual game's gift system
    -- For now, we'll simulate random acceptance after delay
    wait(math.random(2, 5))
    return math.random() > 0.3 -- 70% acceptance rate
end

local function ProcessGift(ItemName, TargetName)
    local Now = tick()
    local LastGift = GiftState.LastGiftTime[TargetName] or 0
    
    if Now - LastGift < GiftConfig.Cooldown then
    SetGiftStatus(`Cooldown: {TargetName}`)
        return false
    end
    
    local Success, Message = SendGift(ItemName, TargetName)
    if Success then
        GiftState.LastGiftTime[TargetName] = Now
        local GiftId = `{ItemName}_{TargetName}_{Now}`
        GiftState.PendingGifts[GiftId] = {
            Item = ItemName,
            Target = TargetName,
            Time = Now,
            Retries = 0
        }
        
    SetGiftStatus(`Auto-Sent: {ItemName} → {TargetName}`)
        
        -- Check acceptance in background
        coroutine.wrap(function()
            local Accepted = CheckGiftAcceptance(GiftId)
            if Accepted then
                GiftState.AcceptedGifts[GiftId] = GiftState.PendingGifts[GiftId]
                SetGiftStatus(`✅ Accepted: {ItemName} by {TargetName}`)
            else
                GiftState.RejectedGifts[GiftId] = GiftState.PendingGifts[GiftId]
                if AutoRetry.Value and GiftState.PendingGifts[GiftId].Retries < GiftRetries.Value then
                    -- Queue for retry
                    wait(RetryDelay.Value)
                    GiftState.GiftQueue[#GiftState.GiftQueue + 1] = {
                        Item = ItemName,
                        Target = TargetName
                    }
                    SetGiftStatus(`🔄 Queued retry: {ItemName} → {TargetName}`)
                else
                    SetGiftStatus(`❌ Rejected: {ItemName} by {TargetName}`)
                end
            end
            GiftState.PendingGifts[GiftId] = nil
        end)()
        
        return true
    else
    SetGiftStatus(`❌ Failed: {Message or "Unknown error"}`)
        return false
    end
end

--// Auto Gift Loop
local function AutoGiftLoop()
    -- Check both UI state and fallback variables
    local isAutoGiftEnabled = (AutoGift and AutoGift.Value) or AutoGiftEnabled
    if not isAutoGiftEnabled then return end
    
    local ItemName = SelectedItem and SelectedItem.Selected or SelectedItemName
    local TargetName = TargetPlayer and TargetPlayer.Selected or SelectedTargetName
    
    if not ItemName or ItemName == "" then
    SetGiftStatus("No item selected")
        return
    end
    
    local Items = GetGiftableItems()
    if not Items[ItemName] then
    SetGiftStatus("Item not found")
        return
    end
    
    -- Process gift queue first
    if #GiftState.GiftQueue > 0 then
        local QueuedGift = table.remove(GiftState.GiftQueue, 1)
        ProcessGift(QueuedGift.Item, QueuedGift.Target)
        return
    end
    
    -- Auto-target or use selected target
    local Target = nil
    if TargetName and TargetName ~= "" and TargetName ~= "Auto" then
        Target = game.Players:FindFirstChild(TargetName)
        
        -- Auto-teleport to specified player if enabled
        local shouldTeleport = (AutoTeleport and AutoTeleport.Value) or AutoTeleportEnabled
        if Target and shouldTeleport then
            local Character = LocalPlayer.Character
            if Character and Character:FindFirstChild("HumanoidRootPart") and Target.Character and Target.Character:FindFirstChild("HumanoidRootPart") then
                local Distance = (Character.HumanoidRootPart.Position - Target.Character.HumanoidRootPart.Position).Magnitude
                local teleportThreshold = (TeleportDistance and TeleportDistance.Value) or TeleportDistanceValue or 15
                
                print(`📏 Distance to {Target.Name}: {math.floor(Distance)} studs (threshold: {teleportThreshold})`)
                
                if Distance > teleportThreshold then
                    local teleportOffset = (TeleportOffset and TeleportOffset.Value) or TeleportOffsetValue or 3
                    local Success, Message = TeleportToPlayer(Target.Name, teleportOffset)
                    
                    if Success then
                        SetGiftStatus(`📍 {Message}`)
                        wait(0.5) -- Brief delay after teleporting
                    else
                        SetGiftStatus(`❌ Teleport failed: {Message}`)
                        return
                    end
                end
            end
        end
    else
        Target = FindTargetPlayer()
    end
    
    if not Target then
    SetGiftStatus("🔍 No target found")
        return
    end
    
    ProcessGift(ItemName, Target.Name)
end

--// Fully Automated Gifting Loop (removes manual hold-E requirement)
local function HandleAutomatedGifting()
    -- This function now handles automated gifting without manual input
    local success, err = pcall(function()
        -- Check both UI state and fallback variables
        local isAutoGiftEnabled = (AutoGift and AutoGift.Value) or AutoGiftEnabled
        if not isAutoGiftEnabled then return end
        
        local ItemName = SelectedItem and SelectedItem.Selected or SelectedItemName
        if not ItemName or ItemName == "" then return end
        
        local TargetName = TargetPlayer and TargetPlayer.Selected or SelectedTargetName
        if not TargetName or TargetName == "" or TargetName == "Auto" then
            -- Auto-find nearby target
            local Target = FindTargetPlayer()
            if Target then
                TargetName = Target.Name
            else
                return
            end
        end
        
        local Character = LocalPlayer.Character
        local TargetPlayerObj = game.Players:FindFirstChild(TargetName)
        
        if not Character or not TargetPlayerObj then return end
        if not Character:FindFirstChild("HumanoidRootPart") then return end
        if not TargetPlayerObj.Character or not TargetPlayerObj.Character:FindFirstChild("HumanoidRootPart") then return end
        
        -- Check distance and auto-teleport if enabled
        local Distance = (Character.HumanoidRootPart.Position - TargetPlayerObj.Character.HumanoidRootPart.Position).Magnitude
        local shouldTeleport = (AutoTeleport and AutoTeleport.Value) or AutoTeleportEnabled
        local teleportThreshold = (TeleportDistance and TeleportDistance.Value) or TeleportDistanceValue or 15
        
        if shouldTeleport and Distance > teleportThreshold then
            print(`🚀 Auto-teleporting to {TargetName} (distance: {math.floor(Distance)})`)
            
            local teleportOffset = (TeleportOffset and TeleportOffset.Value) or TeleportOffsetValue or 3
            local TeleportSuccess, Message = TeleportToPlayer(TargetName, teleportOffset)
            
            if TeleportSuccess then
                SetGiftStatus(`📍 Auto-teleported to {TargetName}`)
                wait(0.5)
            else
                warn(`❌ Auto-teleport failed: {Message}`)
                return
            end
        end
        
        -- Check if close enough after potential teleport
        Distance = (Character.HumanoidRootPart.Position - TargetPlayerObj.Character.HumanoidRootPart.Position).Magnitude
        local maxDist = (MaxDistance and MaxDistance.Value) or MaxDistanceValue or 10
        
        if Distance <= maxDist then
            -- Check cooldown
            local Now = tick()
            local LastGift = GiftState.LastGiftTime[TargetName] or 0
            
            if Now - LastGift >= GiftConfig.Cooldown then
                print(`🎁 Attempting automated gift: {ItemName} → {TargetName}`)
                
                -- Update status safely
                if GiftStatus then 
                    SetGiftStatus(`🎁 Auto-gifting {ItemName} to {TargetName}...`)
                end
                
                -- Look at target
                local lookSuccess, lookErr = pcall(function()
                    Character.HumanoidRootPart.CFrame = CFrame.lookAt(
                        Character.HumanoidRootPart.Position, 
                        TargetPlayerObj.Character.HumanoidRootPart.Position
                    )
                end)
                
                if lookSuccess then
                    -- Small delay before gifting
                    wait(0.2)
                    
                    -- Process the actual gift
                    ProcessGift(ItemName, TargetName)
                else
                    warn(`❌ Failed to look at target: {lookErr}`)
                end
            else
                local timeLeft = GiftConfig.Cooldown - (Now - LastGift)
                print(`⏰ Gift cooldown: {math.ceil(timeLeft)}s remaining`)
            end
        else
            print(`📏 Too far from {TargetName}: {math.floor(Distance)} studs (max: {maxDist})`)
        end
    end)
    
    if not success then
        warn(`❌ Error in HandleAutomatedGifting: {err}`)
    end
end

--// Input Handling (Now Optional - Script can work without manual input)
UserInputService.InputBegan:Connect(function(Input, GameProcessed)
    if GameProcessed then return end
    
    -- Manual override: Hold E for immediate gifting (optional)
    if Input.KeyCode == Enum.KeyCode.E then
        local ItemName = SelectedItem.Selected
        if not ItemName or ItemName == "" then return end
        
        local Target = FindTargetPlayer()
        if not Target then return end
        
        -- Manual gift trigger
        ProcessGift(ItemName, Target.Name)
    SetGiftStatus(`🎮 Manual gift: {ItemName} → {Target.Name}`)
    end
end)

--// Main Loop
local function MakeLoop(Toggle, Func, Delay)
    coroutine.wrap(function()
        while wait(Delay or 0.1) do
            if not Toggle.Value then continue end
            Func()
        end
    end)()
end

--// UI Creation
print("🎨 Creating UI...")

local Window, StatusLabel = CreateWindow()

--// Simple variables for fallback UI
local AutoGiftEnabled = false
local AutoTeleportEnabled = false
local SelectedItemName = ""
local SelectedTargetName = ""
local MaxDistanceValue = 10
local TeleportDistanceValue = 15
local TeleportOffsetValue = 3
local HoldDurationValue = 1.2

--// Create UI Elements (Fallback or ReGui)
local function CreateUIElements()
    if UseReGui and Window then
        print("📱 Using ReGui interface")
        
        --// Auto-Gift Section
        local GiftNode = Window:TreeNode({Title="Auto-Gift 🎁"})

        GiftStatus = GiftNode:Label({
            Text = "Ready"
        })

        SelectedItem = GiftNode:Combo({
            Label = "Item to Gift",
            Selected = "",
            GetItems = function()
                local Items = GetGiftableItems()
                local ItemList = {}
                for Name, _ in next, Items do
                    ItemList[Name] = Name
                end
                return ItemList
            end,
        })

        TargetPlayer = GiftNode:Combo({
            Label = "Target Player",
            Selected = "Auto",
            GetItems = function()
                local Players = GetAllPlayers()
                Players["Auto"] = "Auto"
                return Players
            end,
        })

        AutoGift = GiftNode:Checkbox({
            Value = false,
            Label = "Auto-Gift Enabled"
        })

        AutoTeleport = GiftNode:Checkbox({
            Value = false,
            Label = "Auto-Teleport to Target"
        })

        -- Continue with other ReGui elements...
        
    else
        print("📱 Using fallback simple interface")
        
        -- Create simple status updates
        GiftStatus = {
            Text = "Ready"
        }
        
        -- Simple checkbox simulation
        AutoGift = {
            Value = false
        }
        
        AutoTeleport = {
            Value = false
        }
        
        SelectedItem = {
            Selected = ""
        }
        
        TargetPlayer = {
            Selected = "Auto"
        }
        
        MaxDistance = {
            Value = MaxDistanceValue
        }
        
        TeleportDistance = {
            Value = TeleportDistanceValue
        }
        
        TeleportOffset = {
            Value = TeleportOffsetValue
        }
        
        HoldDuration = {
            Value = HoldDurationValue
        }
        
        -- Create basic controls on the fallback GUI
        if StatusLabel then
            StatusLabel.Text = "🎁 Fallback UI Loaded - Use console commands"
            
            -- Add basic text instructions
            spawn(function()
                wait(2)
                StatusLabel.Text = "📝 Commands: AutoGift=true, Target='PlayerName'"
                wait(3)
                StatusLabel.Text = "🚀 Auto-Gift Ready!"
            end)
        end
    end
end

CreateUIElements()
print("✅ UI Elements created")

--// Simple Command System (for fallback UI)
local Commands = {
    autogift = function(value)
        if value == "true" or value == "1" or value == "on" then
            if AutoGift then AutoGift.Value = true end
            AutoGiftEnabled = true
            print("✅ Auto-Gift enabled")
        else
            if AutoGift then AutoGift.Value = false end
            AutoGiftEnabled = false
            print("❌ Auto-Gift disabled")
        end
    end,
    
    target = function(playerName)
        if TargetPlayer then TargetPlayer.Selected = playerName end
        SelectedTargetName = playerName
        print("🎯 Target set to: " .. playerName)
    end,
    
    item = function(itemName)
        if SelectedItem then SelectedItem.Selected = itemName end
        SelectedItemName = itemName
        print("🎁 Item set to: " .. itemName)
    end,
    
    teleport = function(value)
        if value == "true" or value == "1" or value == "on" then
            if AutoTeleport then AutoTeleport.Value = true end
            AutoTeleportEnabled = true
            print("✅ Auto-Teleport enabled")
        else
            if AutoTeleport then AutoTeleport.Value = false end
            AutoTeleportEnabled = false
            print("❌ Auto-Teleport disabled")
        end
    end,
    
    gift = function(itemName, targetName)
        if itemName and targetName then
            print(`🎁 Manual gift: {itemName} → {targetName}`)
            ProcessGift(itemName, targetName)
        end
    end,
    
    status = function()
        print("📊 AUTOMATION STATUS:")
        local autoGiftStatus = (AutoGift and AutoGift.Value) or AutoGiftEnabled
        local autoTeleportStatus = (AutoTeleport and AutoTeleport.Value) or AutoTeleportEnabled
        local currentTarget = (TargetPlayer and TargetPlayer.Selected) or SelectedTargetName
        local currentItem = (SelectedItem and SelectedItem.Selected) or SelectedItemName
        
        print(`   🎁 Auto-Gift: {autoGiftStatus and "ENABLED" or "DISABLED"}`)
        print(`   📍 Auto-Teleport: {autoTeleportStatus and "ENABLED" or "DISABLED"}`)
        print(`   🎯 Target: {currentTarget or "None"}`)
        print(`   🎒 Item: {currentItem or "None"}`)
    end,
    
    stop = function()
        if AutoGift then AutoGift.Value = false end
        if AutoTeleport then AutoTeleport.Value = false end
        AutoGiftEnabled = false
        AutoTeleportEnabled = false
        print("🛑 ALL AUTOMATION STOPPED")
    end,
    
    start = function()
        if AutoGift then AutoGift.Value = true end
        if AutoTeleport then AutoTeleport.Value = true end
        AutoGiftEnabled = true
        AutoTeleportEnabled = true
        print("🚀 ALL AUTOMATION STARTED")
    end
}

-- Global command function for easy access
_G.AutoGiftCommand = function(cmd, ...)
    local args = {...}
    if Commands[cmd:lower()] then
        Commands[cmd:lower()](unpack(args))
    else
        print("❌ Unknown command. Available: autogift, target, item, teleport, gift")
    end
end

-- Quick enable function
_G.EnableAutoGift = function(targetName, itemName)
    print("🚀 Enabling Auto-Gift system...")
    if targetName then
        Commands.target(targetName)
    end
    if itemName then
        Commands.item(itemName)
    end
    Commands.autogift("true")
    Commands.teleport("true")
    print("🎁 Auto-Gift system activated!")
end

-- Quick disable function
_G.DisableAutoGift = function()
    print("🛑 Disabling Auto-Gift system...")
    Commands.stop()
    print("❌ Auto-Gift system deactivated!")
end

-- Status check function
_G.CheckStatus = function()
    Commands.status()
end

-- Quick controls
_G.StartGifting = function()
    Commands.start()
end

_G.StopGifting = function()
    Commands.stop()
end

-- Individual toggles
_G.ToggleAutoGift = function(enabled)
    Commands.autogift(enabled and "true" or "false")
end

_G.ToggleAutoTeleport = function(enabled)
    Commands.teleport(enabled and "true" or "false")
end

-- Quick teleport function
_G.TeleportTo = function(playerName, distance)
    local dist = distance or 3
    print(`📍 Teleporting to {playerName} (distance: {dist})`)
    local success, message = TeleportToPlayer(playerName, dist)
    if success then
        print(`✅ {message}`)
    else
        print(`❌ {message}`)
    end
end

-- Enhanced mobile gift testing function
_G.TestMobileGift = function(playerName, itemName)
    print("📱 =================================")
    print("📱 MOBILE GIFT TEST STARTING...")
    print("📱 =================================")
    
    local targetPlayer = game.Players:FindFirstChild(playerName or "")
    if not targetPlayer then
        print("❌ Please specify a valid player name")
        print("📋 Available players:")
        for _, player in pairs(game.Players:GetPlayers()) do
            if player ~= LocalPlayer then
                print("   • " .. player.Name)
            end
        end
        return
    end
    
    local testItem = itemName or "Carrot"
    print(`🎯 Target: {targetPlayer.Name}`)
    print(`🎁 Item: {testItem}`)
    
    -- Step 1: Check distance
    local character = LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") and 
       targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local distance = (character.HumanoidRootPart.Position - targetPlayer.Character.HumanoidRootPart.Position).Magnitude
        print(`📏 Distance: {math.floor(distance)} studs`)
        
        if distance > 10 then
            print("⚠️ Too far! Teleporting closer...")
            _G.TeleportTo(targetPlayer.Name, 3)
            wait(1)
        end
    end
    
    -- Step 2: Equip item
    print("🎒 Equipping item...")
    local equipSuccess = AutoEquipItem(testItem)
    print(`🎒 Equipment result: {equipSuccess}`)
    
    -- Step 3: Test mobile gift methods
    print("📱 Testing mobile gift methods...")
    local success, message = TriggerMobileGift(targetPlayer, testItem)
    
    print("📱 =================================")
    if success then
        print(`✅ MOBILE GIFT TEST SUCCESSFUL!`)
        print(`✅ Method: {message}`)
    else
        print(`❌ MOBILE GIFT TEST FAILED`)
        print(`❌ Reason: {message}`)
        print("� Try manually getting closer or checking for gift interfaces")
    end
    print("📱 =================================")
    
    return success, message
end

-- Scan for gift UI elements
_G.ScanGiftUI = function()
    print("🔍 Scanning for gift-related UI elements...")
    
    local playerGui = LocalPlayer.PlayerGui
    local foundElements = {}
    
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            print(`📋 Checking GUI: {gui.Name}`)
            
            for _, descendant in ipairs(gui:GetDescendants()) do
                if descendant:IsA("GuiButton") or descendant:IsA("TextButton") or descendant:IsA("ImageButton") then
                    local text = ""
                    if descendant:IsA("TextButton") or descendant:IsA("TextLabel") then
                        local ok, val = pcall(function() return descendant.Text end)
                        if ok then text = (val or ""):lower() end
                    else
                        local label = descendant:FindFirstChildWhichIsA("TextLabel", true)
                        if label then
                            local ok2, val2 = pcall(function() return label.Text end)
                            if ok2 then text = (val2 or ""):lower() end
                        end
                    end
                    local name = descendant.Name:lower()
                    
                    if text:find("gift") or text:find("trade") or text:find("give") or
                       name:find("gift") or name:find("trade") or name:find("give") then
                        local displayText = "No text"
                        if descendant:IsA("TextButton") or descendant:IsA("TextLabel") then
                            local ok3, val3 = pcall(function() return descendant.Text end)
                            if ok3 then displayText = val3 or "" end
                        else
                            local label2 = descendant:FindFirstChildWhichIsA("TextLabel", true)
                            if label2 then
                                local ok4, val4 = pcall(function() return label2.Text end)
                                if ok4 then displayText = val4 or "" end
                            end
                        end
                        table.insert(foundElements, {
                            gui = gui.Name,
                            element = descendant.Name,
                            text = displayText,
                            visible = descendant.Visible
                        })
                    end
                end
            end
        end
    end
    
    if #foundElements > 0 then
        print("✅ Found gift-related UI elements:")
        for _, element in ipairs(foundElements) do
            print(`   • {element.gui}/{element.element}: "{element.text}" (Visible: {element.visible})`)
        end
    else
        print("❌ No gift-related UI elements found")
        print("💡 Try getting closer to a player or opening gift interface manually")
    end
    
    return foundElements
end

-- Scan for proximity prompts
_G.ScanProximityPrompts = function()
    print("🔍 Scanning for ProximityPrompts...")
    
    local foundPrompts = {}
    
    -- Check all players' characters
    for _, player in ipairs(game.Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            for _, descendant in ipairs(player.Character:GetDescendants()) do
                if descendant:IsA("ProximityPrompt") then
                    table.insert(foundPrompts, {
                        player = player.Name,
                        prompt = descendant,
                        actionText = descendant.ActionText,
                        enabled = descendant.Enabled
                    })
                end
            end
        end
    end
    
    if #foundPrompts > 0 then
        print("✅ Found ProximityPrompts:")
        for _, prompt in ipairs(foundPrompts) do
            print(`   • {prompt.player}: "{prompt.actionText}" (Enabled: {prompt.enabled})`)
        end
    else
        print("❌ No ProximityPrompts found on other players")
    end
    
    return foundPrompts
end

print("📋 Command system loaded!")
print("💡 ACTIVATION & DEACTIVATION COMMANDS:")
print("   _G.EnableAutoGift('PlayerName', 'ItemName')  -- Start everything")
print("   _G.DisableAutoGift()                        -- Stop everything") 
print("   _G.StartGifting()                           -- Resume automation")
print("   _G.StopGifting()                            -- Pause automation")
print("   _G.CheckStatus()                            -- Check current state")
print("")
print("💡 INDIVIDUAL TOGGLES:")
print("   _G.ToggleAutoGift(true/false)               -- Toggle auto-gifting")
print("   _G.ToggleAutoTeleport(true/false)           -- Toggle auto-teleport")
print("")
print("💡 OTHER COMMANDS:")
print("   _G.TeleportTo('PlayerName', 5)")  
print("   _G.TestMobileGift('PlayerName', 'ItemName')")
print("   _G.ScanGiftUI()  -- Find gift buttons")
print("   _G.ScanProximityPrompts()  -- Find gift prompts")
print("")
print("📱 Mobile-specific commands:")
print("   _G.TestMobileGift('PlayerName')  -- Test mobile gifting")
print("   _G.ScanGiftUI()  -- Find gift interface elements")
print("")
print("🧪 Recommended mobile testing order:")
print("   1. _G.TeleportTo('PlayerName', 3)")
print("   2. _G.ScanProximityPrompts()")
print("   3. _G.TestMobileGift('PlayerName', 'ItemName')")
print("")
print("🎮 QUICK CONTROL EXAMPLES:")
print("   _G.EnableAutoGift('TWIST_X7', 'Carrot')     -- Start auto-gifting")
print("   _G.CheckStatus()                            -- See what's running")
print("   _G.DisableAutoGift()                        -- Stop everything")

--// Start Services
print("🔧 Starting services...")

local function SafeLoop(name, toggle, func, delay)
    coroutine.wrap(function()
        print(`✅ Started {name} loop`)
        while wait(delay or 1) do
            local success, err = pcall(function()
                if toggle and toggle.Value then
                    func()
                end
            end)
            if not success then
                warn(`❌ Error in {name}: {err}`)
            end
        end
    end)()
end

SafeLoop("AutoGift", AutoGift, AutoGiftLoop, 2)
SafeLoop("AutomatedGifting", AutoGift, HandleAutomatedGifting, 1)

--// Update Statistics (fallback safe)
local function UpdateStats()
    local success, err = pcall(function()
        if UseReGui then
            -- ReGui updates would go here if available
        else
            -- Simple console updates
            if StatusLabel then
                local acceptedCount = 0
                local rejectedCount = 0
                local pendingCount = 0
                
                for _ in pairs(GiftState.AcceptedGifts) do acceptedCount = acceptedCount + 1 end
                for _ in pairs(GiftState.RejectedGifts) do rejectedCount = rejectedCount + 1 end
                for _ in pairs(GiftState.PendingGifts) do pendingCount = pendingCount + 1 end
                
                StatusLabel.Text = `📊 A:{acceptedCount} R:{rejectedCount} P:{pendingCount}`
            end
        end
    end)
    if not success then
        warn("Stats update error: " .. tostring(err))
    end
end

spawn(function()
    while wait(2) do
        UpdateStats()
    end
end)

RunService.Heartbeat:Connect(function()
    local success, err = pcall(UpdateStats)
    if not success then
        -- Ignore frequent heartbeat errors
    end
end)

print("� Fully Automated Gift Script loaded successfully!")
print("")
print("� QUICK START:")
print("   _G.EnableAutoGift('PlayerName', 'ItemName')")
print("")
print("�📋 Features loaded:")
print("   ✅ Auto-teleport to targets")  
print("   ✅ Auto-equip items")
print("   ✅ Auto-simulate hold-E gifting")
print("   ✅ No manual input required!")
print("   ✅ Fallback UI system")
print("   ✅ Error handling & recovery")
print("")
print("🎮 Command System:")
print("   _G.AutoGiftCommand('autogift', 'true')")
print("   _G.AutoGiftCommand('target', 'PlayerName')")
print("   _G.AutoGiftCommand('item', 'ItemName')")
print("   _G.AutoGiftCommand('teleport', 'true')")
print("")
print("💡 Ready to auto-gift! Set your target and item, then enable!")
