RS = RS or game:GetService("ReplicatedStorage")
Players = Players or game:GetService("Players")
CollectionService = CollectionService or game:GetService("CollectionService")
HttpService = HttpService or game:GetService("HttpService")
Lighting = Lighting or game:GetService("Lighting")
RunService = RunService or game:GetService("RunService")
player = player or Players.LocalPlayer

local function requireWithRetry(pathFn, name, maxRetry)
    maxRetry = maxRetry or 30
    for i = 1, maxRetry do
        local ok, result = pcall(pathFn)
        if ok and result then return result end
        task.wait(1)
    end
    warn("[requireWithRetry] GAGAL load: " .. name)
    return nil
end

local playerDataMod = requireWithRetry(function()
    return require(RS:WaitForChild("TS", 30):WaitForChild("state", 10):WaitForChild("player-data", 10))
end, "player-data")

local function getData()
    if not playerDataMod then return nil end
    local ok, d = pcall(function() return playerDataMod.getPlayerDataById(tostring(player.UserId)) end)
    return ok and d or nil
end

local TS = RS:WaitForChild("TS", 30)
if not TS then return end
local remotes = require(TS:WaitForChild("remotes")).default
local pdm = require(TS:WaitForChild("state"):WaitForChild("player-data"))
local getPlayerData = pdm.getPlayerData
local srm = require(TS:WaitForChild("state"):WaitForChild("shop-restock"))
local shopRestock, ShopType, personalRestockItems = srm.shopRestock, srm.ShopType, srm.personalRestockItems
local tm = require(TS:WaitForChild("state"):WaitForChild("travelling-merchant"))
local travellingMerchants = tm.travellingMerchants
local craftingUtils = requireWithRetry(function()
    return require(TS:WaitForChild("utils"):WaitForChild("crafting.utils"))
end, "crafting.utils")

local petAgeUtils = requireWithRetry(function()
    return require(TS:WaitForChild("utils"):WaitForChild("pet-age.utils"))
end, "pet-age.utils")

local rc = RS:WaitForChild("rbxts_include"):WaitForChild("node_modules"):WaitForChild("@rbxts"):WaitForChild("remo"):WaitForChild("src"):WaitForChild("container")
local placeRemote       = rc:WaitForChild("ponds.placeBuilding")
local selectCraftRemote = rc:WaitForChild("crafting.selectCraftingItem")
local submitRemote      = rc:WaitForChild("crafting.submitItems")
local startCraftRemote  = rc:WaitForChild("crafting.startCraft")
local collectRemote     = rc:WaitForChild("crafting.collectCraft")
local goldenBuyRemote   = rc:WaitForChild("merchant.purchaseItem")
local purchaseGear      = remotes.shop.purchaseGear
local purchaseBait      = remotes.shop.purchaseBait
local purchaseEgg       = remotes.shop.purchaseEgg

local hwCollectFish = rc:FindFirstChild("bait.collectFish")
local hwFeedAll     = rc:FindFirstChild("instantFeed.feedAll")
local hwClaimPickup = rc:FindFirstChild("pickup.claimPickup")

local PAPER_BITMASK = 1099511627776
pcall(function()
    local bits = require(TS:WaitForChild("lists"):WaitForChild("game"):WaitForChild("mutation-bits")).MUTATION_BITS
    if bits and bits.Paper then PAPER_BITMASK = 2 ^ bits.Paper end
end)

local LOCKED_MUTATIONS = { diamond = true }
local function isLockedMutation(mutName)
    if not mutName or mutName == "" then return false end
    local n = string.lower(string.gsub(tostring(mutName), "^%s*(.-)%s*$", "%1"))
    return LOCKED_MUTATIONS[n] == true
end
local function normalizeMutation(name)
    if not name or name == "" then return "none" end
    return string.lower(string.gsub(tostring(name), "^%s*(.-)%s*$", "%1"))
end

local BCONFIG = {
    TargetAge = 50, HelperMinAge = 100, JumperInterval = 3, WaitAfterPlace = 0.5,
    JumperCooldown = 1.5, MutationCooldown = 2, MainLoadout = 0, ResetLoadout = 1,
    WaitingLoadout = 1, CollectLoadout = 4, LoadoutSwitchDelay = 1.5, MutationCollectSyncDelay = 1.5,
    MaxCyclesBeforeStop = 999, JumperBeforeSwitch = 3, JumperSwitchDelay = 1.5,
    SpeedupPlaceCount = 10, AntiAfkInterval = 60,
    Interval = 5, BuyAll = true, BaitWL = {}, BaitBL = {}, BuyDelay = 0.15, StockTTL = 1.5,
    GoldenInterval = 3, GoldenIdleInterval = 10, GoldenBuyDelay = 0.25,
    GoldenBulkLoopDelay = 0.4, GoldenMaxPass = 8,
    FoodOn = false, FoodInt = 30,
    FoodList = { "SupremeFoodTray", "AdvancedFoodTray", "BasicFoodTray" },
    FoodCat = "booster",
    FoodPos = Vector3.new(10.86, 0.5, -11), -- Naikkan Y dikit biar gak nabrak
    CraftOn = false, CraftItem = "TimeJumper", CraftCat = "gear",
    CraftMats = {{n = "TeleportWand", a = 10}, {n = "MagnifyingGlass", a = 25}, {n = "SupremeAutoFeeder", a = 1}},
}
local ALL_MUTATIONS = { "Diamond", "Silver", "Radiant", "Huge", "Lightning", "Guardian", "Gold", "Tiny", "Aquatic", "Tamed" }
local GEAR_LIST = {"NetMover","FoodScoop","MagnifyingGlass","TeleportWand","StarLock","TradingTicket","BasicAutoFeeder","AdvancedAutoFeeder","SupremeAutoFeeder","ExtremeAutoFeeder","GodlyAutoFeeder","BasicFoodTray","AdvancedFoodTray","SupremeFoodTray","XpCookie","PetToy","PetWhistle","GoldenCookie","EggHatcher","EggIncubator","MutationBeacon","StormHorn"}
local EGG_WL = {"Tropical", "Exotic"}

local COOKIE_DIAMOND = "DiamondCookie"
local COOKIE_XP      = "XpCookie"
local GEAR_PET_TOY   = "PetToy"
local COOKIE_REFRESH_TIME = 600
local PET_TOY_REFRESH_TIME = 300

local SPECIES_FILTER = {
    leveling = { "pegazeus", "darkphoenix" },
    speedup  = { "darkphoenix", "eviltrex" },
    collect  = { "darkphoenix", "werewolf" },
}

local B = {
    isRunning = false, currentWave = {}, wavePhase = "idle",
    placedPets = {}, pickedUpPets = {}, selectedMutations = {},
    mutationInProgress = {}, processedMutation = {},
    lastMutationAction = 0, currentLoadout = nil, lastLoadoutSwitch = 0,
    totalBoosted = 0, totalMutated = 0, cycleCount = 0,
    jumperCounter = 0, lastJumperFire = 0,
    boostJumperCount = 0, boostLoadoutSwitching = false,
    selectedPets = {}, petList = {}, petById = {},
    levelingPets = {}, speedupPets = {}, targetPets = {}, collectPets = {},
    placedLeveling = {}, placedSpeedup = {},
    maxPlacePerWave = 0, lastJumperEmptyNotify = 0,
    useAutoPetToy = false, useAutoCookie = false,
    collectSetupDone = false,
}

local S = {
    gOn = false, gTot = 0, bOn = false, bTot = 0, eOn = false, eTot = 0,
    gdOn = false, gdTot = 0, gdActive = false,
    nextGear = 0, nextBait = 0, nextEgg = 0,
    nextGolden = 0, _stockCache = {},
    pRun = false, pCnt = 0, pCd = 0, nextPlace = 0,
    cRun = false, cAtt = 0, cOk = 0, cFail = 0, cCd = 0, cPhase = "idle",
    hwCollect = false, hwFeedPickup = false,
    hwCollectThread = nil, hwFeedPickupThread = nil,
    minimized = false,
}

local petAgeMod = petAgeUtils

local invStateGear = requireWithRetry(function()
    repeat task.wait(0.5) until player:FindFirstChild("PlayerScripts")
    return require(player.PlayerScripts.TS.ui.features.toolbar["inventory.state"])
end, "inventory.state")

local function getRemote(name)
    local ok, remote = pcall(function()
        return RS:WaitForChild("rbxts_include", 10):WaitForChild("node_modules", 10)
            :WaitForChild("@rbxts", 10):WaitForChild("remo", 10)
            :WaitForChild("src", 10):WaitForChild("container", 10):WaitForChild(name, 10)
    end)
    return ok and remote or nil
end

local useTimeWatch          = getRemote("gear.useTimeWatch")
local equipTool             = getRemote("tools.equipTool")
local placePetFromInventory = getRemote("pets.placePetFromInventory")
local requestPosition       = getRemote("pets.requestPosition")
local pickUpPet             = getRemote("pets.pickUpPet")
local switchPetLoadout      = getRemote("pets.switchPetLoadout")
local startMutation         = getRemote("pets.startMutation")
local collectMutation       = getRemote("pets.collectMutation")
local choosePetMutation     = getRemote("pets.choosePetMutation")
local GRADUATED_PETS        = {}
local usePetGearOnPet       = getRemote("pets.usePetGearOnPet")

local VIM = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local AntiAfk = { running = false, count = 0, lastFire = 0 }

local function fireAntiAfk()
    pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.Z, false, game) end)
    task.wait(0.05)
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Z, false, game) end)
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
    AntiAfk.lastFire = os.clock()
    AntiAfk.count = AntiAfk.count + 1
end

local function startAntiAfk()
    if AntiAfk.running then return end
    AntiAfk.running = true
    task.spawn(function()
        task.wait(1)
        fireAntiAfk()
        while AntiAfk.running do
            task.wait(BCONFIG.AntiAfkInterval)
            fireAntiAfk()
        end
    end)
end

local function stopAntiAfk()
    AntiAfk.running = false
end

task.spawn(startAntiAfk)

local WEBHOOK = {
    url = "", enabled = true, notifyJumperEmpty = true,
    username = "Farm A Fish - Mutation Log", lastJumperEmptyNotify = 0,
}

local function sendWebhook(payload)
    if not WEBHOOK.enabled or WEBHOOK.url == "" then return end
    task.spawn(function()
        pcall(function()
            local body = HttpService:JSONEncode(payload)
            local req = (syn and syn.request) or (http and http.request) or http_request or request
            if req then
                req({ Url = WEBHOOK.url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
            end
        end)
    end)
end

local function getPlayerDisplayName()
    return player.DisplayName or player.Name or "Unknown"
end

local function getFormattedPetWeight(pd)
    if not petAgeUtils or not petAgeUtils.calculatePetWeight then return "0.0kg" end
    local ok, weight = pcall(petAgeUtils.calculatePetWeight, pd)
    if not ok or not weight then return "0.0kg" end
    if petAgeUtils.formatPetWeight then
        local ok2, formatted = pcall(petAgeUtils.formatPetWeight, weight)
        if ok2 and formatted then return formatted end
    end
    if weight >= 1000 then return string.format("%.2ft", weight / 1000)
    else return string.format("%.2fkg", weight) end
end

local function getJumperCount()
    local data = getData()
    if not data or not data.inventory or not data.inventory.gears then return 0 end
    local tj = data.inventory.gears.TimeJumper
    return tj and (tj.amount or 0) or 0
end

local function getGearAmount(gearName)
    local data = getData()
    if not data or not data.inventory or not data.inventory.gears then return 0 end
    local g = data.inventory.gears[gearName]
    return g and (g.amount or 0) or 0
end

local function sendMutationWebhook(petName, petWeightStr, mutationName, jumperLeft)
    local isTarget = false
    local nMut = normalizeMutation(mutationName)
    for target in pairs(B.selectedMutations) do
        if normalizeMutation(target) == nMut then isTarget = true break end
    end
    if not isTarget then return end

    local embed = {
        title = "🧬 Mutation Result (Target Achieved)",
        color = 0x9B59B6,
        fields = {
            { name = "👤 Player", value = tostring(getPlayerDisplayName()), inline = true },
            { name = "🐾 Pet", value = tostring(petName), inline = true },
            { name = "⚖️ Pet Weight", value = tostring(petWeightStr), inline = true },
            { name = "✨ Acquired Mutation", value = tostring(mutationName or "None"), inline = true },
            { name = "⏱️ TimeJumper Remainder", value = tostring(jumperLeft), inline = true },
        },
        footer = { text = "Farm A fish | by bang iqi" },
        timestamp = DateTime.now():ToIsoDate(),
    }
    sendWebhook({ username = WEBHOOK.username, embeds = { embed } })
end

local function sendJumperEmptyWebhook(jumperLeft)
    local embed = {
        title = "⚠️ TIMEJUMPER SOLD!",
        description = "You have run out of TimeJumpers in your inventory. Auto-mutation will stop until you craft or restock them.",
        color = 0xE74C3C,
        fields = {
            { name = "👤 Player", value = tostring(getPlayerDisplayName()), inline = true },
            { name = "⏱️ TimeJumper Remnant", value = tostring(jumperLeft or 0), inline = true },
        },
        footer = { text = "Farm A fish | by bang iqi" },
        timestamp = DateTime.now():ToIsoDate(),
    }
    sendWebhook({ username = WEBHOOK.username, embeds = { embed } })
end

local function getPetAge(pd)
    if not petAgeMod or not pd then return 0 end
    local ok, age = pcall(petAgeMod.getPetAgeFromData, pd)
    return ok and (age or 0) or 0
end

local function getPetMutation(pd)
    if not pd then return "None" end
    local c = { pd.mutation, pd.mutations, pd.mutationType, pd.mutationName, pd.attributes and pd.attributes.mutation }
    for _, m in ipairs(c) do
        if m and m ~= "" and m ~= "None" then
            if type(m) == "table" then
                for _, v in pairs(m) do
                    if v and v ~= "" and v ~= "None" then return tostring(v) end
                end
            else return tostring(m) end
        end
    end
    return "None"
end

local function stockKey(s, t) return s .. "|" .. t end
local function invalidateStock(s, t) S._stockCache[stockKey(s, t)] = nil end

local function getStock(shopType, itemType)
    local k = stockKey(shopType, itemType)
    local now = os.clock()
    local c = S._stockCache[k]
    if c and (now - c.t) < BCONFIG.StockTTL then return c.v end
    local val = 0
    local ok, rs, pi, data = pcall(function()
        return shopRestock(), personalRestockItems(), getPlayerData(player)
    end)
    if ok and rs and data then
        local nowT = os.time()
        local pr = data.personalRestocks and data.personalRestocks[shopType]
        local active = pr and pr.endTime and nowT < pr.endTime
        local uid = tostring(player.UserId)
        local avail
        if active then
            avail = pi[uid] and pi[uid][shopType] and pi[uid][shopType][itemType] or 0
        else
            avail = rs.availableItems and rs.availableItems[shopType] and rs.availableItems[shopType][itemType] or 0
        end
        local bought = 0
        local pur = data.shopPurchases and data.shopPurchases[shopType]
        if pur and pur.purchases then
            if active and pur.currentTimeSlot == pr.timeSlot then
                bought = pur.purchases[itemType] or 0
            elseif not active and pur.currentTimeSlot == rs.currentTimeSlot then
                bought = pur.purchases[itemType] or 0
            end
        end
        val = math.max(0, avail - bought)
    end
    S._stockCache[k] = {v = val, t = now}
    return val
end

local function getAvail(shopType, wl, bl)
    local list = {}
    local rs = shopRestock()
    if not rs then return list end
    local shop = rs.availableItems and rs.availableItems[shopType]
    if not shop then return list end
    local wlSet, blSet
    if wl and #wl > 0 then wlSet = {} for _, v in ipairs(wl) do wlSet[v] = true end end
    if bl and #bl > 0 then blSet = {} for _, v in ipairs(bl) do blSet[v] = true end end
    for t, s in pairs(shop) do
        local inc = true
        if wlSet and not wlSet[t] then inc = false end
        if inc and blSet and blSet[t] then inc = false end
        if inc then list[#list + 1] = {type = t, stock = s} end
    end
    return list
end

local function buyGearSafe(t) local ok = pcall(purchaseGear, t) if ok then invalidateStock(ShopType.Gear, t) end return ok end
local function buyBaitSafe(t) local ok = pcall(purchaseBait, t) if ok then invalidateStock(ShopType.Bait, t) end return ok end
local function buyEggSafe(t) local ok = pcall(purchaseEgg, t) if ok then invalidateStock(ShopType.Eggs, t) end return ok end

local function bulkGear()
    for _, t in ipairs(GEAR_LIST) do
        if not S.gOn then return end
        local rem = getStock(ShopType.Gear, t)
        if rem > 0 then
            local max = BCONFIG.BuyAll and (rem + 2) or 1
            for a = 1, max do
                if not S.gOn then return end
                if not buyGearSafe(t) then break end
                S.gTot += 1
                if a < max then task.wait(BCONFIG.BuyDelay) end
            end
        end
    end
end

local function bulkBait()
    local list = getAvail(ShopType.Bait, BCONFIG.BaitWL, BCONFIG.BaitBL)
    if #list == 0 then return end
    for _, it in ipairs(list) do
        if not S.bOn then return end
        local rem = getStock(ShopType.Bait, it.type)
        if rem > 0 then
            local max = BCONFIG.BuyAll and (rem + 2) or 1
            for a = 1, max do
                if not S.bOn then return end
                if not buyBaitSafe(it.type) then break end
                S.bTot += 1
                if a < max then task.wait(BCONFIG.BuyDelay) end
            end
        end
    end
end

local function bulkEgg()
    local list = getAvail(ShopType.Eggs, EGG_WL, nil)
    if #list == 0 then return end
    for _, it in ipairs(list) do
        if not S.eOn then return end
        local rem = getStock(ShopType.Eggs, it.type)
        if rem > 0 then
            local max = BCONFIG.BuyAll and (rem + 2) or 1
            for a = 1, max do
                if not S.eOn then return end
                if not buyEggSafe(it.type) then break end
                S.eTot += 1
                if a < max then task.wait(BCONFIG.BuyDelay) end
            end
        end
    end
end

local function getGoldenData()
    local d = travellingMerchants()
    if not d then return nil end
    return d.golden
end

local function getGoldenStock()
    local md = getGoldenData()
    if not md or not md.isActive or not md.availableStock then return {}, false end
    local map = {}
    for k, v in pairs(md.availableStock) do map[k] = v end
    return map, true
end

local function goldenBuyOne(itemName)
    return pcall(function() goldenBuyRemote:FireServer("golden", itemName) end)
end

local function goldenBulkBuy()
    local total, pass = 0, 0
    while S.gdOn and pass < BCONFIG.GoldenMaxPass do
        pass += 1
        local map, active = getGoldenStock()
        if not active then break end
        local targets = {}
        for itemName, stock in pairs(map) do
            if stock > 0 then table.insert(targets, itemName) end
        end
        if #targets == 0 then break end
        for _, itemName in ipairs(targets) do
            if not S.gdOn then break end
            if goldenBuyOne(itemName) then
                total += 1
                S.gdTot += 1
            end
            task.wait(BCONFIG.GoldenBuyDelay)
        end
        task.wait(BCONFIG.GoldenBulkLoopDelay)
    end
    return total
end

local function doFood()
    if not playerDataMod then return end 
    S.pCnt += 1
    local chosen = nil
    for _, foodName in ipairs(BCONFIG.FoodList) do
        if getGearAmount(foodName) > 0 then
            chosen = foodName
            break
        end
    end
    
    if not chosen then return end 

    -- LANGSUNG TARUH MAKANAN (Tanpa ganti slot sama sekali)
    pcall(function()
        placeRemote:InvokeServer(BCONFIG.FoodCat, chosen, BCONFIG.FoodPos)
    end)
end

local CRAFT_TIME_FALLBACK = {DiamondCookie = 300, YolkBreaker = 600, TimeJumper = 600, ShieldLock = 1500, NetRetractor = 1500}

local function getCraftTime(id, cat)
    if craftingUtils and craftingUtils.getCraftingTime then
        local ok, r = pcall(craftingUtils.getCraftingTime, id, cat)
        if ok and r then return r end
    end
    return CRAFT_TIME_FALLBACK[id] or 600
end

local function getCraftData()
    local data = getPlayerData(player)
    if not data or not data.crafting then return nil end
    local c = data.crafting[BCONFIG.CraftCat]
    if not c or not c.id then return nil end
    return c
end

local function getCraftRem()
    local c = getCraftData()
    if not c or not c.timeStarted then return nil end
    local now = os.time()
    local tt = getCraftTime(c.id, BCONFIG.CraftCat)
    local acc = c.accumulatedProgress or 0
    local lu = c.lastProgressUpdate or c.timeStarted
    local dr = c.depletionRate or 1
    return math.max(0, tt - (acc + (now - lu) * dr))
end

local function isCraftActive()
    local c = getCraftData()
    return c and c.timeStarted ~= nil
end

local function doCraftOnce()
    S.cAtt += 1
    S.cPhase = "submitting"
    local ok = pcall(function() selectCraftRemote:FireServer(BCONFIG.CraftItem, BCONFIG.CraftCat) end)
    task.wait(0.3)
    if ok then
        local mats, idx = {}, 1
        for _, m in ipairs(BCONFIG.CraftMats) do
            for _ = 1, m.a do mats[idx] = m.n idx += 1 end
        end
        ok = pcall(function() submitRemote:FireServer(mats, BCONFIG.CraftCat) end)
        task.wait(0.3)
    end
    if ok then
        ok = pcall(function() startCraftRemote:FireServer(BCONFIG.CraftCat) end)
        task.wait(0.3)
    end
    if not ok then S.cFail += 1 S.cPhase = "idle" return false end
    S.cPhase = "crafting"
    return true
end

local function collectCraft()
    S.cPhase = "collecting"
    local ok = pcall(function() collectRemote:FireServer(BCONFIG.CraftCat) end)
    if ok then S.cOk += 1 end
    S.cPhase = "idle"
    return ok
end

local antiSpamCollect = {}
local antiSpamFeed = 0

local function isPaper(mut)
    if not mut then return false end
    if typeof(mut) == "number" then
        return math.floor(mut / PAPER_BITMASK) % 2 == 1
    end
    if type(mut) == "table" then
        for _, v in pairs(mut) do
            if typeof(v) == "string" and v:lower() == "paper" then return true end
        end
    end
    return false
end

local function halloweenCollectOnce()
    if not hwCollectFish then return 0 end
    local pd = getPlayerData(player)
    if not pd or not pd.ponds then return 0 end
    local currentPondId = pd.currentPond
    if not currentPondId then return 0 end
    local count = 0
    local pondData = pd.ponds[currentPondId]
    if type(pondData) == "table" and pondData.baits then
        for baitId, baitData in pairs(pondData.baits) do
            if type(baitData) == "table" and baitData.fishes then
                for fishId, fishData in pairs(baitData.fishes) do
                    if type(fishData) == "table" and isPaper(fishData.mutations) then
                        pcall(function() hwCollectFish:FireServer(baitId, fishId) end)
                        count += 1
                        task.wait(0.05)
                    end
                end
            end
        end
    end
    return count
end

local function halloweenFeedAll()
    if not hwFeedAll then return false end
    local now = os.time()
    if (now - antiSpamFeed) >= 5 then
        antiSpamFeed = now
        return pcall(function() hwFeedAll:FireServer() end)
    end
    return false
end

local function halloweenPickupAll()
    if not hwClaimPickup then return 0 end
    local count = 0
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("BasePart") and obj.Name:sub(1, 7) == "Pickup_" then
            local uuid = obj.Name:sub(8)
            if #uuid > 0 then
                pcall(function() hwClaimPickup:FireServer(uuid) end)
                count += 1
                task.wait(0.05)
            end
        end
    end
    return count
end

local function startHWCollect()
    if S.hwCollectThread then pcall(function() task.cancel(S.hwCollectThread) end) end
    S.hwCollectThread = task.spawn(function()
        while S.hwCollect do
            pcall(halloweenCollectOnce)
            task.wait(1)
        end
    end)
end

local function stopHWCollect()
    S.hwCollect = false
    if S.hwCollectThread then
        pcall(function() task.cancel(S.hwCollectThread) end)
        S.hwCollectThread = nil
    end
end

local function startHWFeedPickup()
    if S.hwFeedPickupThread then pcall(function() task.cancel(S.hwFeedPickupThread) end) end
    S.hwFeedPickupThread = task.spawn(function()
        while S.hwFeedPickup do
            pcall(halloweenFeedAll)
            task.wait(1)
            pcall(halloweenPickupAll)
            task.wait(1)
        end
    end)
end

local function stopHWFeedPickup()
    S.hwFeedPickup = false
    if S.hwFeedPickupThread then
        pcall(function() task.cancel(S.hwFeedPickupThread) end)
        S.hwFeedPickupThread = nil
    end
end

local function tickScheduler()
    local now = os.clock()

    if S.gOn and now >= S.nextGear then S.nextGear = now + BCONFIG.Interval; task.spawn(bulkGear) end
    if S.bOn and now >= S.nextBait then S.nextBait = now + BCONFIG.Interval; task.spawn(bulkBait) end
    if S.eOn and now >= S.nextEgg then S.nextEgg = now + BCONFIG.Interval; task.spawn(bulkEgg) end
    if S.gdOn and now >= S.nextGolden then
        local interval = S.gdActive and BCONFIG.GoldenInterval or BCONFIG.GoldenIdleInterval
        S.nextGolden = now + interval
        task.spawn(function()
            local _, active = getGoldenStock()
            S.gdActive = active
            if active then goldenBulkBuy() end
        end)
    end

    if BCONFIG.FoodOn and now >= S.nextPlace then
        S.nextPlace = now + BCONFIG.FoodInt
        task.spawn(function()
            local success, err = pcall(doFood)
            if not success then warn("[AutoFood ERROR]", err) end
        end)
    end

    if BCONFIG.CraftOn then
        if isCraftActive() then
            local rem = getCraftRem()
            if rem then
                S.cCd = rem
                S.cPhase = "crafting"
                if rem <= 0 then task.spawn(collectCraft) end
            else
                S.cPhase = "idle"
                S.cCd = 0
            end
        else
            if not S._nextCraftTry or now >= S._nextCraftTry then
                S._nextCraftTry = now + 2
                task.spawn(doCraftOnce)
            end
        end
    else
        S.cCd = 0
    end
end

local function buildNameMap()
    local map = {}
    if not invStateGear then return map end
    local ok, stacked = pcall(function() return invStateGear.inventoryStackedData() end)
    if not ok or not stacked then return map end
    for _, item in pairs(stacked) do
        local tt = tostring(item.toolType):lower()
        if tt:find("pet") and item.items and item.items[1] then
            local pid = item.items[1].id
            if pid then map[pid] = item.displayName or item.itemName or tostring(pid) end
        end
    end
    return map
end

local function switchLoadout(idx)
    if B.currentLoadout == idx then return true end
    if not switchPetLoadout then return false end
    local now = os.clock()
    local elapsed = now - B.lastLoadoutSwitch
    if elapsed < BCONFIG.LoadoutSwitchDelay then task.wait(BCONFIG.LoadoutSwitchDelay - elapsed) end
    local ok = pcall(function() switchPetLoadout:InvokeServer(idx) end)
    if ok then
        B.currentLoadout = idx; B.lastLoadoutSwitch = os.clock()
        task.wait(BCONFIG.LoadoutSwitchDelay)
        return true
    end
    return false
end

local function ensureLoadout(idx)
    if B.currentLoadout == idx then return true end
    return switchLoadout(idx)
end

local function hasSelected()
    for _ in pairs(B.selectedMutations) do return true end
    return false
end

local function isDesired(m)
    if not hasSelected() then return false end
    local n = normalizeMutation(m)
    if n == "none" or n == "" then return false end
    for t in pairs(B.selectedMutations) do
        if normalizeMutation(t) == n then return true end
    end
    return false
end

local function getMachineState()
    local labels = CollectionService:GetTagged("petMutationLabel")
    if #labels == 0 then return "Unknown" end
    local text = labels[1].Text
    if text == "MUTATION" or text == "" then return "Idle"
    elseif text == "READY!" then return "Ready"
    else return "InProgress" end
end

local lastTimerText = "-"
local lastTimerCheck = 0

local function getLiveMachineTimer()
    local now = os.clock()
    if now - lastTimerCheck < 1 then
        return lastTimerText
    end
    lastTimerCheck = now

    local ok, foundText = pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                local txt = obj.Text
                if txt and string.match(txt, "^%d+:%d+$") then
                    local parentName = obj.Parent and obj.Parent.Name:lower() or ""
                    local objName = obj.Name:lower()
                    if parentName:find("mutation") or parentName:find("machine") or objName:find("time") or objName:find("label") then
                        return txt
                    end
                end
            end
        end
        return nil
    end)
    
    if ok and foundText then
        lastTimerText = foundText
    end
    return lastTimerText
end

local function gearPetLabel(p, idx)
    local mut = (p.mutation and p.mutation ~= "" and p.mutation ~= "None") and p.mutation or "No Mutation"
    local ageStr = string.format("%.1f", p.age or 0)
    local suffix = idx and string.format("  #%d", idx) or ""
    return string.format("%s | %s | Age %s%s", p.displayName, mut, ageStr, suffix)
end

local function getCookieTimeLeft(petId, pd, cookieName)
    if not pd or not pd.activeGearBuffs then return false, 0 end
    local expireTime = pd.activeGearBuffs[cookieName]
    if expireTime then
        local timeLeft = expireTime - os.time()
        if timeLeft > 0 then return true, timeLeft else return false, 0 end
    end
    return false, 0
end

local function needsCookie(petId, cookieName)
    local data = getData()
    if not data or not data.inventory or not data.inventory.pets[petId] then return false end
    local pd = data.inventory.pets[petId]
    local has, timeLeft = getCookieTimeLeft(petId, pd, cookieName)
    return not has or timeLeft <= COOKIE_REFRESH_TIME
end

local function giveCookie(petId, cookieName)
    local data = getData()
    if not data or not data.inventory or not data.inventory.gears then return false end
    local inv = data.inventory.gears[cookieName]
    if not inv or (inv.amount or 0) <= 0 then return false end
    if equipTool then pcall(function() equipTool:FireServer(cookieName, "gear") end) end
    task.wait(0.5)
    local success = false
    if usePetGearOnPet then success = pcall(function() usePetGearOnPet:FireServer(petId) end) end
    task.wait(0.5)
    return success
end

local function getPetToyTimeLeft(pd)
    if not pd or not pd.activeGearBuffs then return false, 0 end
    local expireTime = pd.activeGearBuffs[GEAR_PET_TOY]
    if expireTime then
        local timeLeft = expireTime - os.time()
        if timeLeft > 0 then return true, timeLeft else return false, 0 end
    end
    return false, 0
end

local function needsPetToy(petId, minTime)
    local data = getData()
    if not data or not data.inventory or not data.inventory.pets[petId] then return false end
    local pd = data.inventory.pets[petId]
    local has, timeLeft = getPetToyTimeLeft(pd)
    return not has or timeLeft <= (minTime or PET_TOY_REFRESH_TIME)
end

local function givePetToy(petId)
    local data = getData()
    if not data or not data.inventory or not data.inventory.gears then return false end
    local inv = data.inventory.gears[GEAR_PET_TOY]
    if not inv or (inv.amount or 0) <= 0 then return false end
    if equipTool then pcall(function() equipTool:FireServer(GEAR_PET_TOY, "gear") end) end
    task.wait(0.5)
    local success = false
    if usePetGearOnPet then success = pcall(function() usePetGearOnPet:FireServer(petId) end) end
    task.wait(0.5)
    return success
end

local function refreshToysInList(petTable, label)
    if not B.useAutoPetToy then return end
    for id in pairs(petTable) do
        if needsPetToy(id, PET_TOY_REFRESH_TIME) then
            givePetToy(id)
        end
    end
end

local function makePetEntry(id, pd, nameMap)
    local age = getPetAge(pd)
    local m = getPetMutation(pd)
    local petType = pd.petType or pd.type or pd.species or pd.model or "Unknown"
    local nick = pd.nickname or pd.name or pd.displayName or pd.petName
    local name = nameMap[id]
    if not name or name == "" or name == tostring(id) then
        if nick and nick ~= "" and string.lower(tostring(nick)) ~= string.lower(tostring(petType)) then
            name = string.format("%s (%s)", tostring(petType), tostring(nick))
        else
            name = tostring(petType)
        end
    end
    return {id=id, age=age, mutation=m, displayName=tostring(name)}
end

local function scanAllPetsForList()
    local data = getData(); if not data then return {} end
    if not data.inventory or not data.inventory.pets then return {} end
    local nameMap = buildNameMap()
    local list = {}
    for id, pd in pairs(data.inventory.pets) do
        if not isLockedMutation(getPetMutation(pd)) then
            table.insert(list, makePetEntry(id, pd, nameMap))
        end
    end
    table.sort(list, function(a, b)
        if a.displayName ~= b.displayName then return a.displayName < b.displayName end
        return a.age < b.age
    end)
    for i, p in ipairs(list) do p.label = gearPetLabel(p, i) end
    return list
end

local function scanPetsForHelper()
    local data = getData(); if not data then return {} end
    if not data.inventory or not data.inventory.pets then return {} end
    local nameMap = buildNameMap()
    local list = {}
    for id, pd in pairs(data.inventory.pets) do
        local age = getPetAge(pd)
        if age >= BCONFIG.HelperMinAge then
            table.insert(list, makePetEntry(id, pd, nameMap))
        end
    end
    table.sort(list, function(a, b)
        if a.displayName ~= b.displayName then return a.displayName < b.displayName end
        return a.age < b.age
    end)
    for i, p in ipairs(list) do p.label = gearPetLabel(p, i) end
    return list
end

local function matchesSpeciesFilter(petType, filterList)
    if not petType then return false end
    local n = string.lower(tostring(petType))
    for _, key in ipairs(filterList) do
        if n:find(key, 1, true) then return true end
    end
    return false
end

local function scanPetsFiltered(filterList)
    local data = getData(); if not data then return {} end
    if not data.inventory or not data.inventory.pets then return {} end
    local nameMap = buildNameMap()
    local list = {}
    for id, pd in pairs(data.inventory.pets) do
        local age = getPetAge(pd)
        if age >= BCONFIG.HelperMinAge then
            local petType = pd.petType or pd.type or pd.species or pd.model or ""
            if matchesSpeciesFilter(petType, filterList) then
                table.insert(list, makePetEntry(id, pd, nameMap))
            end
        end
    end
    table.sort(list, function(a, b)
        if a.displayName ~= b.displayName then return a.displayName < b.displayName end
        return a.age < b.age
    end)
    for i, p in ipairs(list) do p.label = gearPetLabel(p, i) end
    return list
end

local function scanTargetLowAge()
    local data = getData(); if not data or not data.inventory then return {} end
    local list = {}
    for id, pd in pairs(data.inventory.pets) do
        if B.targetPets[id] and not GRADUATED_PETS[id] then
            local m = getPetMutation(pd)
            if not isLockedMutation(m) and not isDesired(m) then
                local age = getPetAge(pd)
                if age < BCONFIG.TargetAge then
                    table.insert(list, { id = id, age = age })
                end
            end
        end
    end
    table.sort(list, function(a,b) return a.age < b.age end)
    return list
end

local function scanForMutation()
    local data = getData(); if not data or not data.inventory then return {} end
    local list = {}
    for id, pd in pairs(data.inventory.pets) do
        if B.targetPets[id] and not GRADUATED_PETS[id] then
            local m = getPetMutation(pd)
            if not isLockedMutation(m) and not isDesired(m)
                and not B.processedMutation[id] and not B.mutationInProgress[id] then
                local age = getPetAge(pd)
                if age >= BCONFIG.TargetAge then
                    table.insert(list, { id = id, age = age })
                end
            end
        end
    end
    table.sort(list, function(a,b) return a.age > b.age end)
    return list
end

local function scanLevelingPets()
    local data = getData(); if not data or not data.inventory then return {} end
    local list = {}
    for id, pd in pairs(data.inventory.pets) do
        if B.levelingPets[id] and not B.placedLeveling[id] then
            if getPetAge(pd) >= BCONFIG.HelperMinAge then
                table.insert(list, { id = id, age = getPetAge(pd) })
            end
        end
    end
    table.sort(list, function(a,b) return a.age < b.age end)
    return list
end

local function scanSpeedupPets()
    local data = getData(); if not data or not data.inventory then return {} end
    local list = {}
    for id, pd in pairs(data.inventory.pets) do
        if B.speedupPets[id] and not B.placedSpeedup[id] then
            if getPetAge(pd) >= BCONFIG.HelperMinAge then
                table.insert(list, { id = id, age = getPetAge(pd) })
            end
        end
    end
    return list
end

local function allTargetsMaxed()
    local data = getData(); if not data or not data.inventory then return false end
    local t, maxed = 0, 0
    for id, pd in pairs(data.inventory.pets) do
        if B.targetPets[id] then
            local m = getPetMutation(pd)
            if not isLockedMutation(m) and not isDesired(m) then
                t = t + 1
                if getPetAge(pd) >= BCONFIG.TargetAge then maxed = maxed + 1 end
            end
        end
    end
    return t > 0 and maxed >= t
end

local function allTargetAchieved()
    local data = getData(); if not data or not data.inventory then return false end
    local t, ok = 0, 0
    for id, pd in pairs(data.inventory.pets) do
        if B.targetPets[id] then
            local m = getPetMutation(pd)
            if not isLockedMutation(m) then
                t = t + 1
                if isDesired(m) then ok = ok + 1 end
            end
        end
    end
    return t > 0 and ok >= t
end

local function hasMoreBoost() return #scanTargetLowAge() > 0 end
local function hasMutationReady() return #scanForMutation() > 0 end

local function countWave()
    local c, t = 0, 0
    local data = getData(); if not data or not data.inventory then return 0, 0 end
    for id in pairs(B.currentWave) do
        t = t + 1
        local pd = data.inventory.pets[id]
        if pd and getPetAge(pd) >= BCONFIG.TargetAge then c = c + 1 end
    end
    return c, t
end

local function placePet(id, force)
    if not force and B.placedPets[id] then return true end
    local data = getData()
    if not data or not data.inventory or not data.inventory.pets[id] then 
        B.placedPets[id] = true
        return true 
    end
    if equipTool then pcall(function() equipTool:FireServer(id, "pet") end) end
    task.wait(BCONFIG.WaitAfterPlace)
    local ok = false
    if placePetFromInventory then ok = pcall(function() placePetFromInventory:InvokeServer(id) end) end
    task.wait(BCONFIG.WaitAfterPlace)
    if ok and requestPosition then pcall(function() requestPosition:InvokeServer(id) end) end
    task.wait(0.3)
    B.placedPets[id] = true; B.pickedUpPets[id] = nil
    return ok
end

local function pickUp(id)
    if B.pickedUpPets[id] then return true end
    if not pickUpPet then return false end
    local ok = pcall(function() pickUpPet:InvokeServer(id) end)
    if not ok then return false end
    B.pickedUpPets[id] = true; B.placedPets[id] = nil
    return true
end

local function fireJumper(force)
    local now = os.clock()
    if not force and (now - B.lastJumperFire) < BCONFIG.JumperCooldown then return "cooldown" end
    if B.currentLoadout ~= BCONFIG.MainLoadout then ensureLoadout(BCONFIG.MainLoadout) end

    local data = getData()
    if not data or not data.inventory or not data.inventory.gears then return "error" end
    local tj = data.inventory.gears.TimeJumper
    local amount = tj and (tj.amount or 0) or 0

    if amount <= 0 then
        if WEBHOOK.notifyJumperEmpty then
            local now2 = os.time()
            if now2 - (WEBHOOK.lastJumperEmptyNotify or 0) > 120 then
                WEBHOOK.lastJumperEmptyNotify = now2
                sendJumperEmptyWebhook(0)
            end
        end
        return "empty"
    end

    if not useTimeWatch then return "error" end
    local ok = pcall(function() useTimeWatch:FireServer("TimeJumper") end)
    if ok then
        B.lastJumperFire = now
        B.jumperCounter = B.jumperCounter + 1
        B.boostJumperCount = B.boostJumperCount + 1

        local data2 = getData()
        local left = 0
        if data2 and data2.inventory and data2.inventory.gears and data2.inventory.gears.TimeJumper then
            left = data2.inventory.gears.TimeJumper.amount or 0
        end
        if left <= 0 and WEBHOOK.notifyJumperEmpty then
            local now2 = os.time()
            if now2 - (WEBHOOK.lastJumperEmptyNotify or 0) > 120 then
                WEBHOOK.lastJumperEmptyNotify = now2
                sendJumperEmptyWebhook(left)
            end
        end
        return "ok"
    end
    return "error"
end

local function doLoadoutCycle()
    if B.boostLoadoutSwitching then return end
    B.boostLoadoutSwitching = true
    ensureLoadout(BCONFIG.ResetLoadout); task.wait(BCONFIG.JumperSwitchDelay)
    ensureLoadout(BCONFIG.MainLoadout);  task.wait(BCONFIG.JumperSwitchDelay)
    B.boostJumperCount = 0
    refreshToysInList(B.levelingPets, "Leveling")
    B.boostLoadoutSwitching = false
end

local function resetWave() B.currentWave = {}; B.wavePhase = "idle" end

local function placeBoostWave()
    ensureLoadout(BCONFIG.MainLoadout)
    local lvlCands = scanLevelingPets()
    for _, p in ipairs(lvlCands) do
        local needToy = B.useAutoPetToy and needsPetToy(p.id, PET_TOY_REFRESH_TIME)
        if placePet(p.id, true) then
            B.placedLeveling[p.id] = true
            if needToy then
                task.wait(0.5)
                givePetToy(p.id)
            end
        end
        task.wait(0.2)
    end

    local tgtCands = scanTargetLowAge()
    if #tgtCands == 0 then B.wavePhase = "done"; return false end
    local limit = #tgtCands
    if B.maxPlacePerWave > 0 then limit = math.min(B.maxPlacePerWave, #tgtCands) end

    B.currentWave = {}; B.wavePhase = "placing"
    local sc = 0
    for i = 1, limit do
        local petId = tgtCands[i].id
        local needDiamond = B.useAutoCookie and needsCookie(petId, COOKIE_DIAMOND)
        local needXP = B.useAutoCookie and needsCookie(petId, COOKIE_XP)
        local ok = placePet(petId)
        if ok ~= false then
            B.currentWave[petId] = true
            sc = sc + 1
            if needDiamond or needXP then
                task.wait(0.5)
                if needDiamond then giveCookie(petId, COOKIE_DIAMOND) end
                if needXP then giveCookie(petId, COOKIE_XP) end
            end
        end
        task.wait(0.2)
    end
    if sc == 0 then B.wavePhase = "done"; return false end
    B.boostJumperCount = 0; B.wavePhase = "boosting"
    return true
end

local function placeSpeedupPets()
    ensureLoadout(BCONFIG.MainLoadout)
    local cands = scanSpeedupPets()
    local placed = 0
    for _, p in ipairs(cands) do
        if placed >= BCONFIG.SpeedupPlaceCount then break end
        local needToy = B.useAutoPetToy and needsPetToy(p.id, PET_TOY_REFRESH_TIME)
        if placePet(p.id, true) then
            B.placedSpeedup[p.id] = true
            placed = placed + 1
            if needToy then
                task.wait(0.5)
                givePetToy(p.id)
            end
        end
        task.wait(0.2)
    end
    return placed
end

local function pickUpSpeedupPets()
    for id in pairs(B.placedSpeedup) do
        pickUp(id); task.wait(0.2)
    end
    B.placedSpeedup = {}
end

local function insertPet(id)
    local data = getData()
    if not data or not data.inventory or not data.inventory.pets[id] then return false end
    if isLockedMutation(getPetMutation(data.inventory.pets[id])) then return false end
    if equipTool then pcall(function() equipTool:FireServer(id, "pet") end) end
    task.wait(0.5)
    if not startMutation then return false end
    local ok = pcall(function() startMutation:InvokeServer(id) end)
    if ok then
        B.mutationInProgress[id] = true; B.processedMutation[id] = true
        return true
    end
    return false
end

local function setupCollectLoadout()
    if B.collectSetupDone then return true end
    if next(B.collectPets) == nil then
        B.collectSetupDone = true
        return true
    end
    if not ensureLoadout(BCONFIG.CollectLoadout) then return false end
    local placedAny = false
    for id in pairs(B.collectPets) do
        local data = getData()
        if data and data.inventory and data.inventory.pets[id] then
            local needToy = B.useAutoPetToy and needsPetToy(id, PET_TOY_REFRESH_TIME)
            if placePet(id, true) then
                placedAny = true
                if needToy then
                    task.wait(0.5)
                    givePetToy(id)
                end
            end
        end
        task.wait(0.2)
    end
    task.wait(0.5)
    B.collectSetupDone = true
    ensureLoadout(BCONFIG.MainLoadout)
    return placedAny
end

local function autoResolveMutationPrompt(newMutFromCollect, petIdInMachine)
    local data = getData()
    if not data or not data.petMutation then return false end

    local oldMut = data.petMutation.petData and data.petMutation.petData.mutation
    local newMut = newMutFromCollect or data.petMutation.rolledMutation

    if not oldMut or not newMut then
        pcall(function() choosePetMutation:InvokeServer(true) end) 
        return false
    end

    local tier = {
        ["None"]      = 0,
        ["Tamed"]     = 1,
        ["Guardian"]  = 2,
        ["Tiny"]      = 3,
        ["Aquatic"]   = 4,
        ["Lightning"] = 5,
        ["Radiant"]   = 6,
        ["Huge"]      = 7,
        ["Silver"]    = 8,  
        ["Gold"]      = 9,  
        ["Diamond"]   = 10  
    }
    
    local oldTier = tier[oldMut] or 0
    local newTier = tier[newMut] or 0
    
    local takeNew = false
    local isTargetSelected = false
    
    for t in pairs(B.selectedMutations) do
        if string.lower(t) == string.lower(newMut) then isTargetSelected = true break end
    end

    if string.lower(tostring(newMut)) == "diamond" then
        takeNew = true
    else
        takeNew = newTier > oldTier
    end

    local args = { not takeNew } 
    local ok = pcall(function() choosePetMutation:InvokeServer(unpack(args)) end)

    if ok and takeNew and (isTargetSelected or string.lower(tostring(newMut)) == "diamond") then
        task.wait(1)
        
        local petName = "Unknown"
        local petWeight = "0.0kg"
        
        local freshData = getData()
        if petIdInMachine and freshData and freshData.inventory and freshData.inventory.pets[petIdInMachine] then
            local pd = freshData.inventory.pets[petIdInMachine]
            petName = pd.petType or pd.type or pd.species or pd.model or "Unknown"
            petWeight = getFormattedPetWeight(pd)
        end
        
        sendMutationWebhook(petName, petWeight, newMut, getJumperCount())
        print("📨 [Webhook] Notification sent:" .. tostring(petName) .. " | " .. tostring(petWeight) .. " | " .. tostring(newMut))
        
        if string.lower(tostring(newMut)) == "diamond" then
            if petIdInMachine and B.targetPets[petIdInMachine] then
                B.targetPets[petIdInMachine] = nil
                GRADUATED_PETS[petIdInMachine] = true
                print("🏆 [GRADUATION] Pet succeeded and earned a Diamond! Removed from targets..")
            end
        end
    end
    
    return ok, takeNew
end

local function doMutation()
    local now = os.clock()
    if (now - B.lastMutationAction) < BCONFIG.MutationCooldown then return end
    local state = getMachineState()

    if state == "Ready" then
        if not ensureLoadout(BCONFIG.CollectLoadout) then return end
        refreshToysInList(B.collectPets, "Collect")
        local col = {}
        for id in pairs(B.mutationInProgress) do table.insert(col, id) end
        if not collectMutation then return end
        
        local ok, ret = pcall(function() return collectMutation:InvokeServer() end)
        if ok and ret then
            task.wait(0.5)
            
            local pm = getData() and getData().petMutation
            local petIdInMachine = pm and pm.petId
            
            autoResolveMutationPrompt(ret, petIdInMachine)
            task.wait(1.5)

            local data = getData()
            if data and data.inventory and data.inventory.pets then
                for _, id in ipairs(col) do
                    local pd = data.inventory.pets[id]
                    if pd then
                        local petName = pd.petType or pd.type or pd.species or pd.model or tostring(id)
                        local mutName = getPetMutation(pd)
                        local petWeightStr = getFormattedPetWeight(pd)
                        local jumperLeft = getJumperCount()
                        if B.targetPets[id] and isDesired(mutName) then
                            sendMutationWebhook(petName, petWeightStr, mutName, jumperLeft)
                        end
                    end
                end
            end
            for _, id in ipairs(col) do
                B.totalMutated = B.totalMutated + 1
                B.processedMutation[id] = nil
            end
            B.mutationInProgress = {}
            B.lastMutationAction = os.clock()
        end
        ensureLoadout(BCONFIG.MainLoadout)
        return
    end

    if state == "InProgress" then
        if not B.collectSetupDone then
            local okSetup = setupCollectLoadout()
            if okSetup then ensureLoadout(BCONFIG.WaitingLoadout) end
            return
        end
        if B.currentLoadout ~= BCONFIG.WaitingLoadout then ensureLoadout(BCONFIG.WaitingLoadout) end
        return
    end

    if state == "Idle" then
        if next(B.mutationInProgress) ~= nil then B.mutationInProgress = {} end
        local cands = scanForMutation()
        if #cands == 0 then return end
        if not ensureLoadout(BCONFIG.MainLoadout) then return end
        refreshToysInList(B.speedupPets, "Speedup")
        if insertPet(cands[1].id) then
            B.lastMutationAction = now
            task.wait(0.5)
            ensureLoadout(BCONFIG.WaitingLoadout)
        end
    end
end

local function pickUpWave()
    for id in pairs(B.currentWave) do
        if pickUp(id) then B.totalBoosted = B.totalBoosted + 1 end
        task.wait(0.3)
    end
    resetWave()
end

local function pickUpAllLeveling()
    for id in pairs(B.placedLeveling) do
        pickUp(id); task.wait(0.3)
    end
    B.placedLeveling = {}
end

local function boostLoop()
    ensureLoadout(BCONFIG.MainLoadout)
    while B.isRunning do
        task.wait(BCONFIG.JumperInterval)
        local data = getData(); if not data then continue end

        if allTargetAchieved() then
            pickUpSpeedupPets(); pickUpAllLeveling()
            B.wavePhase = "stopped"; B.isRunning = false
            break
        end
        if B.cycleCount >= BCONFIG.MaxCyclesBeforeStop then
            B.wavePhase = "stopped"; B.isRunning = false
            break
        end

        if B.wavePhase == "mutating" then
            if #scanForMutation() > 0 or getMachineState() == "Ready" or getMachineState() == "InProgress" then
                doMutation()
            else
                if next(B.placedSpeedup) ~= nil then
                    pickUpSpeedupPets()
                end
                B.wavePhase = "idle"
            end
            continue
        end

        if B.wavePhase == "idle" or B.wavePhase == "done" then
            if hasMoreBoost() then
                placeBoostWave()
            elseif allTargetsMaxed() then
                pickUpWave(); pickUpAllLeveling()
                placeSpeedupPets(); B.wavePhase = "mutating"
            elseif next(B.currentWave) ~= nil then
                local c, t = countWave()
                if t > 0 and c >= t then pickUpWave() end
            end
        elseif B.wavePhase == "placing" then
            B.wavePhase = "boosting"
        elseif B.wavePhase == "boosting" then
            local c, t = countWave()
            if t > 0 and c >= t then
                pickUpWave(); B.boostJumperCount = 0
                if allTargetsMaxed() then
                    pickUpAllLeveling(); placeSpeedupPets(); B.wavePhase = "mutating"
                end
            else
                if B.boostJumperCount >= BCONFIG.JumperBeforeSwitch and not B.boostLoadoutSwitching then
                    doLoadoutCycle()
                else
                    local result = fireJumper(false)
                    if result == "empty" then
                        if hasMutationReady() then
                            pickUpWave(); B.boostJumperCount = 0
                            pickUpAllLeveling(); placeSpeedupPets()
                            B.wavePhase = "mutating"
                        else
                            pickUpSpeedupPets(); pickUpAllLeveling(); pickUpWave()
                            B.wavePhase = "stopped"; B.isRunning = false
                            break
                        end
                    end
                end
            end
        end
    end
end

local FPS_STATE = {
    boosted = false, originalSettings = {}, hiddenObjects = {},
    terrainSettings = {}, fishHidden = false, hiddenFish = {},
    mutedSounds = {}, materialCache = {},
}
local Terrain = workspace:FindFirstChildOfClass("Terrain")
local function safeGetChildren(p) local ok, c = pcall(function() return p:GetChildren() end) if ok and c then return c end return {} end
local function safeGetDescendants(p) local ok, c = pcall(function() return p:GetDescendants() end) if ok and c then return c end return {} end

local function saveOriginalSettings()
    FPS_STATE.originalSettings = {
        GlobalShadows = Lighting.GlobalShadows, ShadowSoftness = Lighting.ShadowSoftness,
        Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient, FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart, FogColor = Lighting.FogColor,
        EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
        EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
        ExposureCompensation = Lighting.ExposureCompensation,
        ClockTime = Lighting.ClockTime,
        QualityLevel = UserSettings().GameSettings.SavedQualityLevel.Value,
    }
    if Terrain then
        pcall(function()
            FPS_STATE.terrainSettings = {
                WaterWaveSize = Terrain.WaterWaveSize, WaterWaveSpeed = Terrain.WaterWaveSpeed,
                WaterReflectance = Terrain.WaterReflectance, WaterTransparency = Terrain.WaterTransparency,
                Decoration = Terrain.Decoration,
            }
        end)
    end
end

local function hideHeavyObject(o, char)
    if not o or not o.Parent then return end
    if char and (o == char or o:IsDescendantOf(char)) then return end
    local cls = o.ClassName
    if cls == "ParticleEmitter" or cls == "Trail" or cls == "Beam"
       or cls == "Fire" or cls == "Smoke" or cls == "Sparkles"
       or cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight"
       or cls == "Explosion" or cls == "Atmosphere" or cls == "Sky" then
        pcall(function()
            if o.Enabled then
                o.Enabled = false
                table.insert(FPS_STATE.hiddenObjects, {obj = o, prop = "Enabled", val = true})
            end
        end)
    elseif cls == "Decal" or cls == "Texture" then
        pcall(function()
            if o.Transparency < 1 then
                table.insert(FPS_STATE.hiddenObjects, {obj = o, prop = "Transparency", val = o.Transparency})
                o.Transparency = 1
            end
        end)
    elseif cls == "MeshPart" then
        pcall(function()
            if o.TextureID ~= "" then
                table.insert(FPS_STATE.hiddenObjects, {obj = o, prop = "TextureID", val = o.TextureID})
                o.TextureID = ""
            end
            if o.Material ~= Enum.Material.SmoothPlastic then
                table.insert(FPS_STATE.materialCache, {obj = o, prop = "Material", val = o.Material})
                o.Material = Enum.Material.SmoothPlastic
            end
        end)
    elseif cls == "SurfaceAppearance" then
        pcall(function()
            if o.Enabled then
                table.insert(FPS_STATE.hiddenObjects, {obj = o, prop = "Enabled", val = true})
                o.Enabled = false
            end
        end)
    elseif cls == "BasePart" then
        pcall(function()
            if o.Material ~= Enum.Material.SmoothPlastic then
                table.insert(FPS_STATE.materialCache, {obj = o, prop = "Material", val = o.Material})
                o.Material = Enum.Material.SmoothPlastic
            end
            if o.CastShadow then
                table.insert(FPS_STATE.hiddenObjects, {obj = o, prop = "CastShadow", val = true})
                o.CastShadow = false
            end
        end)
    end
end

local function boostFPS()
    if FPS_STATE.boosted then return false end
    local ok = pcall(function()
        saveOriginalSettings()
        FPS_STATE.boosted = true
        FPS_STATE.hiddenObjects = {} FPS_STATE.mutedSounds = {} FPS_STATE.materialCache = {}
        Lighting.GlobalShadows = false
        Lighting.ShadowSoftness = 0
        Lighting.Brightness = 1
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.FogEnd = 1e6
        Lighting.FogStart = 1e6
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.ExposureCompensation = 0
        Lighting.ClockTime = 14
        for _, e in ipairs(safeGetChildren(Lighting)) do
            pcall(function()
                if e:IsA("PostEffect") or e:IsA("Atmosphere") or e:IsA("Sky") then
                    if e.Enabled ~= nil then
                        e.Enabled = false
                        table.insert(FPS_STATE.hiddenObjects, {obj = e, prop = "Enabled", val = true})
                    end
                end
            end)
        end
        if Terrain then
            pcall(function()
                Terrain.WaterWaveSize = 0
                Terrain.WaterWaveSpeed = 0
                Terrain.WaterReflectance = 0
                Terrain.WaterTransparency = 1
                Terrain.Decoration = false
            end)
        end
        pcall(function()
            UserSettings().GameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
        end)
        local char = player.Character
        for _, o in ipairs(safeGetDescendants(workspace)) do hideHeavyObject(o, char) end
        for _, s in ipairs(safeGetDescendants(workspace)) do
            pcall(function()
                if s:IsA("Sound") and s.Playing then
                    s.Playing = false
                    table.insert(FPS_STATE.mutedSounds, s)
                end
            end)
        end
    end)
    if not ok then FPS_STATE.boosted = false return false end
    return true
end

local function unboostFPS()
    if not FPS_STATE.boosted then return false end
    FPS_STATE.boosted = false
    pcall(function()
        local o = FPS_STATE.originalSettings or {}
        Lighting.GlobalShadows = o.GlobalShadows ~= false
        Lighting.ShadowSoftness = o.ShadowSoftness or 0.2
        Lighting.Brightness = o.Brightness or 2
        Lighting.Ambient = o.Ambient or Color3.fromRGB(70, 70, 70)
        Lighting.OutdoorAmbient = o.OutdoorAmbient or Color3.fromRGB(128, 128, 128)
        Lighting.FogEnd = o.FogEnd or 100000
        Lighting.FogStart = o.FogStart or 0
        Lighting.FogColor = o.FogColor or Color3.fromRGB(192, 192, 192)
        Lighting.EnvironmentDiffuseScale = o.EnvironmentDiffuseScale or 1
        Lighting.EnvironmentSpecularScale = o.EnvironmentSpecularScale or 1
        Lighting.ExposureCompensation = o.ExposureCompensation or 0
        Lighting.ClockTime = o.ClockTime or 14
        if Terrain and FPS_STATE.terrainSettings then
            local t = FPS_STATE.terrainSettings
            Terrain.WaterWaveSize = t.WaterWaveSize or 0.15
            Terrain.WaterWaveSpeed = t.WaterWaveSpeed or 10
            Terrain.WaterReflectance = t.WaterReflectance or 0.1
            Terrain.WaterTransparency = t.WaterTransparency or 0.3
            Terrain.Decoration = t.Decoration ~= false
        end
        for _, e in ipairs(FPS_STATE.hiddenObjects) do
            pcall(function() if e.obj and e.obj.Parent then e.obj[e.prop] = e.val end end)
        end
        FPS_STATE.hiddenObjects = {}
        for _, m in ipairs(FPS_STATE.materialCache) do
            pcall(function() if m.obj and m.obj.Parent then m.obj[m.prop] = m.val end end)
        end
        FPS_STATE.materialCache = {}
        for _, s in ipairs(FPS_STATE.mutedSounds) do
            pcall(function() if s and s.Parent then s.Playing = true end end)
        end
        FPS_STATE.mutedSounds = {}
        pcall(function() UserSettings().GameSettings.SavedQualityLevel = o.QualityLevel or Enum.SavedQualitySetting.QualityLevel5 end)
    end)
    return true
end

local function hideFish()
    if FPS_STATE.fishHidden then return 0 end
    FPS_STATE.hiddenFish = {}
    local count = 0
    local gameFolder = workspace:FindFirstChild("Game")
    if gameFolder then
        table.insert(FPS_STATE.hiddenFish, {obj = gameFolder, parent = gameFolder.Parent, type = "folder"})
        pcall(function() gameFolder.Parent = nil end)
        count += 1
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Parent then
            if obj.Parent.Name:lower():find("pond") then
                local n = obj.Name:lower()
                if n == "sardine" or n == "cod" or n == "salmon" or n:find("_gold") or n:find("_silver") then
                    table.insert(FPS_STATE.hiddenFish, {obj = obj, parent = obj.Parent, type = "model"})
                    pcall(function() obj.Parent = nil end)
                    count += 1
                end
            end
        end
    end
    FPS_STATE.fishHidden = true
    return count
end

local function showFish()
    if not FPS_STATE.fishHidden then return 0 end
    local count = 0
    for _, entry in ipairs(FPS_STATE.hiddenFish) do
        if entry.obj then
            pcall(function() entry.obj.Parent = entry.parent or workspace; count += 1 end)
        end
    end
    FPS_STATE.hiddenFish = {}
    FPS_STATE.fishHidden = false
    return count
end

-- =====================================================================
--  BAGIAN 2 : GLOBAL FARM (sama seperti script lama)
-- =====================================================================
AutoFarmRunning = false
AutoFarmFeederRunning = false
AutoFarmThread, AutoFarmFeederThread = nil, nil

ReplicatedStorageFarm = game:GetService("ReplicatedStorage")
getPlayerDataByIdFarm = require(ReplicatedStorageFarm.TS.state["player-data"]).getPlayerDataById
remoFarm = ReplicatedStorageFarm.rbxts_include.node_modules["@rbxts"].remo.src.container
collectAllFishRemote = remoFarm:WaitForChild("bait.collectAllFish")
sellRemote = remoFarm:WaitForChild("sellFish.sellAllFish")
SwitchPetLoadout = remoFarm:WaitForChild("pets.switchPetLoadout")

AutoCollectRunning = false
AutoSellRunning = false
SellInterval = 3
AutoFarmInterval = 300
AutoFarmDelay = 0

FeederInputValues = {}
Feeders = {"BasicAutoFeeder","AdvancedAutoFeeder","SupremeAutoFeeder","ExtremeAutoFeeder","GodlyAutoFeeder","GoldenAutoFeeder"}

-- =====================================================================
--  BAGIAN 3 : GUI BARU
-- =====================================================================
local function BuildGUI()
    local TweenService = game:GetService("TweenService")
    local UserInputService = game:GetService("UserInputService")
    local CoreGui = game:GetService("CoreGui")
    local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

    for _, n in ipairs({"CustomAutoMutasiUI", "CleanGUI"}) do
        local old = CoreGui:FindFirstChild(n)
        if old then old:Destroy() end
    end

    -- ------------------------------------------------------------
    -- THEME
    -- ------------------------------------------------------------
    local C = {
        Bg        = Color3.fromRGB(11, 11, 18),
        Panel     = Color3.fromRGB(22, 22, 34),
        Element   = Color3.fromRGB(32, 32, 50),
        Accent    = Color3.fromRGB(140, 110, 255),
        Accent2   = Color3.fromRGB(90, 210, 255),
        Glow      = Color3.fromRGB(150, 120, 255),
        Text      = Color3.fromRGB(255, 255, 255),
        Sub       = Color3.fromRGB(185, 185, 215),
        Stroke    = Color3.fromRGB(70, 70, 100),
        Danger    = Color3.fromRGB(255, 100, 120),
        Success   = Color3.fromRGB(100, 240, 160),
        Warn      = Color3.fromRGB(255, 180, 80),
        TextShadow= Color3.fromRGB(0, 0, 0),
    }

    local CloseHooks = {}
    local Conns = {}
    local function track(conn) table.insert(Conns, conn) return conn end

    local function applyCrispText(label, size, font, shadow)
        label.TextSize = size or 13
        label.Font = font or Enum.Font.GothamBold
        if shadow ~= false then
            local stroke = Instance.new("UIStroke", label)
            stroke.Color = C.TextShadow
            stroke.Thickness = 1
            stroke.Transparency = 0.65
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
        end
        return label
    end

    local orderCounter = setmetatable({}, { __mode = "k" })
    local function nextOrder(p)
        orderCounter[p] = (orderCounter[p] or 0) + 1
        return orderCounter[p]
    end

    -- ------------------------------------------------------------
    -- ROOT + MAIN
    -- ------------------------------------------------------------
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local FULL_W = math.clamp(vp.X - 24, 380, 660)
    local FULL_H = math.clamp(vp.Y - 24, 300, 460)
    local SIDE_W = FULL_W >= 560 and 176 or 120
    local MINI_W, MINI_H = 260, 56

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "CleanGUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.IgnoreGuiInset = false
    ScreenGui.DisplayOrder = 999
    ScreenGui.Parent = player:WaitForChild("PlayerGui")

    local Main = Instance.new("Frame")
    Main.Name = "Main"
    Main.Size = UDim2.new(0, 0, 0, 0)
    Main.Position = UDim2.new(0.5, 0, 0.5, 0)
    Main.BackgroundColor3 = C.Bg
    Main.BackgroundTransparency = 0.02
    Main.BorderSizePixel = 0
    Main.ClipsDescendants = true
    Main.ZIndex = 5
    Main.Parent = ScreenGui
    Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 16)

    local MainStroke = Instance.new("UIStroke", Main)
    MainStroke.Color = C.Stroke
    MainStroke.Thickness = 1.5
    MainStroke.Transparency = 0.3
    MainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    -- TOP BAR
    local TopBar = Instance.new("Frame")
    TopBar.Name = "TopBar"
    TopBar.Size = UDim2.new(1, 0, 0, 56)
    TopBar.BackgroundColor3 = C.Panel
    TopBar.BackgroundTransparency = 0.1
    TopBar.BorderSizePixel = 0
    TopBar.ZIndex = 10
    TopBar.Parent = Main
    Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 16)

    local sep = Instance.new("Frame", TopBar)
    sep.Size = UDim2.new(1, -20, 0, 1)
    sep.Position = UDim2.new(0, 10, 1, 0)
    sep.BackgroundColor3 = C.Stroke
    sep.BackgroundTransparency = 0.2
    sep.BorderSizePixel = 0

    local AvatarFrame = Instance.new("Frame")
    AvatarFrame.Size = UDim2.new(0, 34, 0, 34)
    AvatarFrame.Position = UDim2.new(0, 14, 0.5, -17)
    AvatarFrame.BackgroundColor3 = C.Element
    AvatarFrame.BorderSizePixel = 0
    AvatarFrame.ZIndex = 11
    AvatarFrame.Parent = TopBar
    Instance.new("UICorner", AvatarFrame).CornerRadius = UDim.new(0, 10)

    local AvatarImage = Instance.new("ImageLabel")
    AvatarImage.Size = UDim2.new(1, 0, 1, 0)
    AvatarImage.BackgroundTransparency = 1
    AvatarImage.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
    AvatarImage.ZIndex = 12
    AvatarImage.Parent = AvatarFrame
    Instance.new("UICorner", AvatarImage).CornerRadius = UDim.new(0, 10)

    local AvatarStroke = Instance.new("UIStroke", AvatarFrame)
    AvatarStroke.Color = C.Accent
    AvatarStroke.Thickness = 1.5
    AvatarStroke.Transparency = 0.5

    local TitleGroup = Instance.new("Frame")
    TitleGroup.Size = UDim2.new(0, 190, 1, 0)
    TitleGroup.Position = UDim2.new(0, 58, 0, 0)
    TitleGroup.BackgroundTransparency = 1
    TitleGroup.ZIndex = 11
    TitleGroup.Parent = TopBar

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 24)
    Title.Position = UDim2.new(0, 0, 0, 9)
    Title.BackgroundTransparency = 1
    Title.Text = "FARM A FISH"
    Title.TextColor3 = C.Text
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.ZIndex = 12
    Title.Parent = TitleGroup
    applyCrispText(Title, 16, Enum.Font.GothamBlack)

    local Subtitle = Instance.new("TextLabel")
    Subtitle.Size = UDim2.new(1, 0, 0, 14)
    Subtitle.Position = UDim2.new(0, 0, 0, 33)
    Subtitle.BackgroundTransparency = 1
    Subtitle.Text = "👤 " .. player.Name .. "  •  by IQI"
    Subtitle.TextColor3 = C.Sub
    Subtitle.TextXAlignment = Enum.TextXAlignment.Left
    Subtitle.TextTruncate = Enum.TextTruncate.AtEnd
    Subtitle.ZIndex = 12
    Subtitle.Parent = TitleGroup
    applyCrispText(Subtitle, 11, Enum.Font.GothamBold)

    local FpsLabel = Instance.new("TextLabel")
    FpsLabel.Size = UDim2.new(0, 44, 0, 24)
    FpsLabel.Position = UDim2.new(1, -126, 0.5, -12)
    FpsLabel.BackgroundColor3 = C.Element
    FpsLabel.BackgroundTransparency = 0.3
    FpsLabel.Text = "--"
    FpsLabel.TextColor3 = C.Success
    FpsLabel.Font = Enum.Font.GothamBold
    FpsLabel.TextSize = 11
    FpsLabel.BorderSizePixel = 0
    FpsLabel.ZIndex = 11
    FpsLabel.Parent = TopBar
    Instance.new("UICorner", FpsLabel).CornerRadius = UDim.new(0, 6)

    local function makeCtrl(icon, posX, color, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 32, 0, 32)
        b.Position = UDim2.new(1, posX, 0.5, -16)
        b.BackgroundColor3 = color
        b.BackgroundTransparency = 0.88
        b.Text = icon
        b.TextColor3 = color
        b.TextSize = 16
        b.Font = Enum.Font.GothamBold
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.ZIndex = 11
        b.Parent = TopBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
        b.MouseEnter:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.15), {BackgroundTransparency = 0.55, Size = UDim2.new(0, 34, 0, 34), Position = UDim2.new(1, posX - 1, 0.5, -17)}):Play()
        end)
        b.MouseLeave:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.15), {BackgroundTransparency = 0.88, Size = UDim2.new(0, 32, 0, 32), Position = UDim2.new(1, posX, 0.5, -16)}):Play()
        end)
        b.MouseButton1Click:Connect(function() cb() end)
        return b
    end

    -- BODY / SIDEBAR / CONTENT
    local Body = Instance.new("Frame")
    Body.Name = "Body"
    Body.Size = UDim2.new(1, -16, 1, -76)
    Body.Position = UDim2.new(0, 8, 0, 64)
    Body.BackgroundTransparency = 1
    Body.ZIndex = 6
    Body.Parent = Main

    local Sidebar = Instance.new("Frame")
    Sidebar.Name = "Sidebar"
    Sidebar.Size = UDim2.new(0, SIDE_W, 1, 0)
    Sidebar.BackgroundColor3 = C.Panel
    Sidebar.BackgroundTransparency = 0.15
    Sidebar.BorderSizePixel = 0
    Sidebar.ZIndex = 7
    Sidebar.Parent = Body
    Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 12)
    local SideStroke = Instance.new("UIStroke", Sidebar)
    SideStroke.Color = C.Stroke
    SideStroke.Thickness = 1
    SideStroke.Transparency = 0.4
    local SidePad = Instance.new("UIPadding", Sidebar)
    SidePad.PaddingTop = UDim.new(0, 8)
    SidePad.PaddingLeft = UDim.new(0, 6)
    SidePad.PaddingRight = UDim.new(0, 6)
    SidePad.PaddingBottom = UDim.new(0, 8)

    local SideScroll = Instance.new("ScrollingFrame")
    SideScroll.Size = UDim2.new(1, 0, 1, 0)
    SideScroll.BackgroundTransparency = 1
    SideScroll.BorderSizePixel = 0
    SideScroll.ScrollBarThickness = 2
    SideScroll.ScrollBarImageColor3 = C.Accent
    SideScroll.ScrollBarImageTransparency = 0.5
    SideScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    SideScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    SideScroll.ZIndex = 8
    SideScroll.Parent = Sidebar
    local SideLayout = Instance.new("UIListLayout", SideScroll)
    SideLayout.Padding = UDim.new(0, 3)
    SideLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local Content = Instance.new("Frame")
    Content.Name = "Content"
    Content.Size = UDim2.new(1, -(SIDE_W + 16), 1, 0)
    Content.Position = UDim2.new(0, SIDE_W + 8, 0, 0)
    Content.BackgroundColor3 = C.Panel
    Content.BackgroundTransparency = 0.15
    Content.BorderSizePixel = 0
    Content.ZIndex = 7
    Content.Parent = Body
    Instance.new("UICorner", Content).CornerRadius = UDim.new(0, 12)
    local ContentStroke = Instance.new("UIStroke", Content)
    ContentStroke.Color = C.Stroke
    ContentStroke.Thickness = 1
    ContentStroke.Transparency = 0.4
    local ContentPad = Instance.new("UIPadding", Content)
    ContentPad.PaddingTop = UDim.new(0, 12)
    ContentPad.PaddingBottom = UDim.new(0, 12)
    ContentPad.PaddingLeft = UDim.new(0, 14)
    ContentPad.PaddingRight = UDim.new(0, 14)

    -- ------------------------------------------------------------
    -- TAB SYSTEM (tiap tab punya ScrollingFrame sendiri)
    -- ------------------------------------------------------------
    local Tabs = {}
    local ActiveTab = nil
    local ALL_DROPDOWNS = {}

    local function SelectTab(name)
        if not Tabs[name] then return end
        for _, dd in ipairs(ALL_DROPDOWNS) do dd.Close() end
        for _, data in pairs(Tabs) do
            data.Content.Visible = false
            TweenService:Create(data.Btn, TweenInfo.new(0.2), {BackgroundColor3 = C.Element, BackgroundTransparency = 1}):Play()
            TweenService:Create(data.Label, TweenInfo.new(0.2), {TextColor3 = C.Sub}):Play()
            TweenService:Create(data.Icon, TweenInfo.new(0.2), {TextColor3 = C.Sub}):Play()
            TweenService:Create(data.Indicator, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = UDim2.new(0, 3, 0, 0)}):Play()
        end
        local d = Tabs[name]
        d.Content.Visible = true
        ActiveTab = name
        TweenService:Create(d.Btn, TweenInfo.new(0.2), {BackgroundColor3 = C.Accent, BackgroundTransparency = 0.85}):Play()
        TweenService:Create(d.Label, TweenInfo.new(0.2), {TextColor3 = C.Text}):Play()
        TweenService:Create(d.Icon, TweenInfo.new(0.2), {TextColor3 = C.Accent2}):Play()
        TweenService:Create(d.Indicator, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = UDim2.new(0, 3, 0, 22)}):Play()
    end

    local function CreateSidebarBtn(name, icon, layoutOrder)
        local Btn = Instance.new("TextButton")
        Btn.Name = name .. "Btn"
        Btn.Size = UDim2.new(1, 0, 0, 38)
        Btn.BackgroundColor3 = C.Element
        Btn.BackgroundTransparency = 1
        Btn.Text = ""
        Btn.AutoButtonColor = false
        Btn.BorderSizePixel = 0
        Btn.ClipsDescendants = true
        Btn.LayoutOrder = layoutOrder
        Btn.ZIndex = 8
        Btn.Parent = SideScroll
        Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 8)

        local Icon = Instance.new("TextLabel")
        Icon.Size = UDim2.new(0, 22, 0, 22)
        Icon.Position = UDim2.new(0, 8, 0.5, -11)
        Icon.BackgroundTransparency = 1
        Icon.Text = icon or "•"
        Icon.TextColor3 = C.Sub
        Icon.TextSize = 15
        Icon.Font = Enum.Font.GothamBold
        Icon.ZIndex = 9
        Icon.Parent = Btn

        local Label = Instance.new("TextLabel")
        Label.Size = UDim2.new(1, -38, 1, 0)
        Label.Position = UDim2.new(0, 34, 0, 0)
        Label.BackgroundTransparency = 1
        Label.Text = name
        Label.TextColor3 = C.Sub
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.TextWrapped = true
        Label.ZIndex = 9
        Label.Parent = Btn
        applyCrispText(Label, SIDE_W >= 160 and 12 or 11, Enum.Font.GothamBold)

        local Indicator = Instance.new("Frame")
        Indicator.Size = UDim2.new(0, 3, 0, 0)
        Indicator.Position = UDim2.new(0, 0, 0.5, 0)
        Indicator.AnchorPoint = Vector2.new(0, 0.5)
        Indicator.BackgroundColor3 = C.Accent2
        Indicator.BorderSizePixel = 0
        Indicator.ZIndex = 10
        Indicator.Parent = Btn
        Instance.new("UICorner", Indicator).CornerRadius = UDim.new(1, 0)

        local TabScroll = Instance.new("ScrollingFrame")
        TabScroll.Name = name .. "Content"
        TabScroll.Size = UDim2.new(1, 0, 1, 0)
        TabScroll.BackgroundTransparency = 1
        TabScroll.BorderSizePixel = 0
        TabScroll.ScrollBarThickness = 3
        TabScroll.ScrollBarImageColor3 = C.Accent
        TabScroll.ScrollBarImageTransparency = 0.3
        TabScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        TabScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        TabScroll.ScrollingDirection = Enum.ScrollingDirection.Y
        TabScroll.Visible = false
        TabScroll.ZIndex = 8
        TabScroll.Parent = Content
        local L = Instance.new("UIListLayout", TabScroll)
        L.Padding = UDim.new(0, 8)
        L.SortOrder = Enum.SortOrder.LayoutOrder
        local P = Instance.new("UIPadding", TabScroll)
        P.PaddingLeft = UDim.new(0, 8)
        P.PaddingRight = UDim.new(0, 8)
        P.PaddingBottom = UDim.new(0, 8)

        Tabs[name] = { Btn = Btn, Content = TabScroll, Indicator = Indicator, Icon = Icon, Label = Label }

        Btn.MouseEnter:Connect(function()
            if ActiveTab ~= name then
                TweenService:Create(Btn, TweenInfo.new(0.15), {BackgroundTransparency = 0.93}):Play()
                TweenService:Create(Label, TweenInfo.new(0.15), {TextColor3 = C.Text}):Play()
                TweenService:Create(Icon, TweenInfo.new(0.15), {TextColor3 = C.Accent2}):Play()
            end
        end)
        Btn.MouseLeave:Connect(function()
            if ActiveTab ~= name then
                TweenService:Create(Btn, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
                TweenService:Create(Label, TweenInfo.new(0.15), {TextColor3 = C.Sub}):Play()
                TweenService:Create(Icon, TweenInfo.new(0.15), {TextColor3 = C.Sub}):Play()
            end
        end)
        Btn.MouseButton1Click:Connect(function()
            local ripple = Instance.new("Frame", Btn)
            ripple.Size = UDim2.new(0, 0, 0, 0)
            ripple.Position = UDim2.new(0.5, 0, 0.5, 0)
            ripple.AnchorPoint = Vector2.new(0.5, 0.5)
            ripple.BackgroundColor3 = C.Accent
            ripple.BackgroundTransparency = 0.4
            ripple.BorderSizePixel = 0
            ripple.ZIndex = 11
            Instance.new("UICorner", ripple).CornerRadius = UDim.new(1, 0)
            TweenService:Create(ripple, TweenInfo.new(0.5, Enum.EasingStyle.Quart), {
                Size = UDim2.new(0, 200, 0, 200), BackgroundTransparency = 1,
            }):Play()
            task.delay(0.5, function() ripple:Destroy() end)
            SelectTab(name)
        end)
        return TabScroll
    end

    -- ------------------------------------------------------------
    -- NOTIFICATION
    -- ------------------------------------------------------------
    local function Notify(title, message, color)
        color = color or C.Accent
        local n = Instance.new("Frame")
        n.Size = UDim2.new(0, 300, 0, 74)
        n.Position = UDim2.new(1, 0, 1, -100)
        n.BackgroundColor3 = C.Panel
        n.BackgroundTransparency = 0.02
        n.BorderSizePixel = 0
        n.ZIndex = 100
        n.Parent = ScreenGui
        Instance.new("UICorner", n).CornerRadius = UDim.new(0, 10)
        local stroke = Instance.new("UIStroke", n)
        stroke.Color = color
        stroke.Thickness = 1.5
        stroke.Transparency = 0.2

        local bar = Instance.new("Frame", n)
        bar.Size = UDim2.new(0, 4, 1, -16)
        bar.Position = UDim2.new(0, 10, 0, 8)
        bar.BackgroundColor3 = color
        bar.BorderSizePixel = 0
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local t = Instance.new("TextLabel", n)
        t.Size = UDim2.new(1, -34, 0, 26)
        t.Position = UDim2.new(0, 24, 0, 10)
        t.BackgroundTransparency = 1
        t.Text = title
        t.TextColor3 = C.Text
        t.TextXAlignment = Enum.TextXAlignment.Left
        applyCrispText(t, 14, Enum.Font.GothamBlack)

        local m = Instance.new("TextLabel", n)
        m.Size = UDim2.new(1, -34, 0, 24)
        m.Position = UDim2.new(0, 24, 0, 36)
        m.BackgroundTransparency = 1
        m.Text = message
        m.TextColor3 = C.Sub
        m.TextXAlignment = Enum.TextXAlignment.Left
        m.TextTruncate = Enum.TextTruncate.AtEnd
        applyCrispText(m, 12, Enum.Font.GothamBold)

        TweenService:Create(n, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Position = UDim2.new(1, -320, 1, -100),
        }):Play()
        task.delay(3, function()
            TweenService:Create(n, TweenInfo.new(0.3), {Position = UDim2.new(1, 0, 1, -100)}):Play()
            task.delay(0.3, function() n:Destroy() end)
        end)
    end

    -- ------------------------------------------------------------
    -- ANTI SALAH-KLIK SAAT SCROLL
    -- ------------------------------------------------------------
    local function makeAntiScrollClick(button, scrollFrame)
        local MOVE_THRESHOLD   = IS_TOUCH and 18 or 8
        local TIME_THRESHOLD   = IS_TOUCH and 0.60 or 0.35
        local CANVAS_THRESHOLD = 2
        local DEBOUNCE         = IS_TOUCH and 0.20 or 0.15

        local pressPos       = nil
        local pressTime      = 0
        local canvasAtDown   = nil
        local lastFire       = 0
        local touchMovedTooMuch = false
        local lastTouchMove = 0

        button.MouseButton1Down:Connect(function()
            if IS_TOUCH then return end
            pressPos = UserInputService:GetMouseLocation()
            pressTime = os.clock()
            if scrollFrame then canvasAtDown = scrollFrame.CanvasPosition end
        end)

        local function onTouchBegan(input)
            if not IS_TOUCH then return end
            if input.UserInputType ~= Enum.UserInputType.Touch then return end
            pressPos = input.Position
            pressTime = os.clock()
            touchMovedTooMuch = false
            if scrollFrame then canvasAtDown = scrollFrame.CanvasPosition end
        end

        local function onTouchMoved(input)
            if not IS_TOUCH then return end
            if input.UserInputType ~= Enum.UserInputType.Touch then return end
            if not pressPos then return end
            local delta = (Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(pressPos.X, pressPos.Y)).Magnitude
            if delta > MOVE_THRESHOLD then touchMovedTooMuch = true end
            lastTouchMove = os.clock()
        end

        button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then onTouchBegan(input) end
        end)

        button.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then onTouchMoved(input) end
        end)

        track(UserInputService.TouchMoved:Connect(function(input)
            if not pressPos then return end
            local delta = (Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(pressPos.X, pressPos.Y)).Magnitude
            if delta > MOVE_THRESHOLD then touchMovedTooMuch = true end
            lastTouchMove = os.clock()
        end))

        return function()
            local now = os.clock()
            if IS_TOUCH then
                if touchMovedTooMuch then pressPos = nil; canvasAtDown = nil; touchMovedTooMuch = false; return false end
                if scrollFrame and canvasAtDown then
                    local cd = (scrollFrame.CanvasPosition - canvasAtDown).Magnitude
                    if cd > CANVAS_THRESHOLD then pressPos = nil; canvasAtDown = nil; touchMovedTooMuch = false; return false end
                end
                if pressPos and (now - pressTime) > TIME_THRESHOLD then pressPos = nil; canvasAtDown = nil; touchMovedTooMuch = false; return false end
                if now - lastFire < DEBOUNCE then pressPos = nil; canvasAtDown = nil; touchMovedTooMuch = false; return false end
                lastFire = now
                pressPos = nil; canvasAtDown = nil; touchMovedTooMuch = false
                return true
            end
            local pos = UserInputService:GetMouseLocation()
            if pressPos and (now - pressTime) > TIME_THRESHOLD then pressPos = nil; canvasAtDown = nil; return false end
            if pressPos then
                local delta = (pos - pressPos).Magnitude
                if delta > MOVE_THRESHOLD then pressPos = nil; canvasAtDown = nil; return false end
            end
            if scrollFrame and canvasAtDown then
                local cd = (scrollFrame.CanvasPosition - canvasAtDown).Magnitude
                if cd > CANVAS_THRESHOLD then pressPos = nil; canvasAtDown = nil; return false end
            end
            if now - lastFire < DEBOUNCE then pressPos = nil; canvasAtDown = nil; return false end
            lastFire = now
            pressPos = nil; canvasAtDown = nil
            return true
        end
    end

    -- ------------------------------------------------------------
    -- ELEMENT LIBRARY
    -- ------------------------------------------------------------
    local function CreateSection(parent, text)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 28)
        f.BackgroundTransparency = 1
        f.LayoutOrder = nextOrder(parent)
        f.Parent = parent
        local accent = Instance.new("Frame")
        accent.Size = UDim2.new(0, 3, 0, 16)
        accent.Position = UDim2.new(0, 0, 0.5, -8)
        accent.BackgroundColor3 = C.Accent
        accent.BorderSizePixel = 0
        accent.Parent = f
        Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -12, 1, 0)
        l.Position = UDim2.new(0, 12, 0, 0)
        l.BackgroundTransparency = 1
        l.Text = text:upper()
        l.TextColor3 = C.Sub
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = f
        applyCrispText(l, 12, Enum.Font.GothamBlack)
    end

    local function CreateInfo(parent, text)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 0)
        l.AutomaticSize = Enum.AutomaticSize.Y
        l.BackgroundColor3 = C.Element
        l.BackgroundTransparency = 0.45
        l.BorderSizePixel = 0
        l.Text = text
        l.TextColor3 = C.Sub
        l.Font = Enum.Font.Gotham
        l.TextSize = 11
        l.TextWrapped = true
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.LayoutOrder = nextOrder(parent)
        l.Parent = parent
        Instance.new("UICorner", l).CornerRadius = UDim.new(0, 9)
        local pad = Instance.new("UIPadding", l)
        pad.PaddingLeft = UDim.new(0, 12)
        pad.PaddingRight = UDim.new(0, 12)
        pad.PaddingTop = UDim.new(0, 8)
        pad.PaddingBottom = UDim.new(0, 8)
        return l
    end

    local function CreateStatus(parent, text)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 0)
        l.AutomaticSize = Enum.AutomaticSize.Y
        l.BackgroundTransparency = 1
        l.Text = text
        l.TextColor3 = C.Success
        l.Font = Enum.Font.Gotham
        l.TextSize = 11
        l.TextWrapped = true
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.LayoutOrder = nextOrder(parent)
        l.Parent = parent
        return l
    end

    local function CreateToggle(parent, text, default, callback)
        local toggled = default and true or false

        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 44)
        f.BackgroundColor3 = C.Element
        f.BackgroundTransparency = 0.25
        f.BorderSizePixel = 0
        f.LayoutOrder = nextOrder(parent)
        f.Parent = parent
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 9)

        local stroke = Instance.new("UIStroke", f)
        stroke.Color = C.Stroke
        stroke.Thickness = 1
        stroke.Transparency = 0.5

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -76, 1, 0)
        lbl.Position = UDim2.new(0, 16, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = C.Text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextWrapped = true
        lbl.Parent = f
        applyCrispText(lbl, 12, Enum.Font.GothamBold)

        local tb = Instance.new("TextButton")
        tb.Size = UDim2.new(0, 46, 0, 24)
        tb.Position = UDim2.new(1, -60, 0.5, -12)
        tb.BackgroundColor3 = C.Stroke
        tb.Text = ""
        tb.BorderSizePixel = 0
        tb.AutoButtonColor = false
        tb.Parent = f
        Instance.new("UICorner", tb).CornerRadius = UDim.new(1, 0)

        local circle = Instance.new("Frame")
        circle.Size = UDim2.new(0, 18, 0, 18)
        circle.Position = UDim2.new(0, 3, 0.5, -9)
        circle.BackgroundColor3 = Color3.new(1, 1, 1)
        circle.BorderSizePixel = 0
        circle.Parent = tb
        Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)

        local function visual(animate)
            local pos = toggled and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
            local col = toggled and C.Accent or C.Stroke
            local sCol = toggled and C.Accent or C.Stroke
            local sTr = toggled and 0.3 or 0.5
            if animate then
                TweenService:Create(circle, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = pos}):Play()
                TweenService:Create(tb, TweenInfo.new(0.2), {BackgroundColor3 = col}):Play()
                TweenService:Create(stroke, TweenInfo.new(0.2), {Color = sCol, Transparency = sTr}):Play()
            else
                circle.Position = pos
                tb.BackgroundColor3 = col
                stroke.Color = sCol
                stroke.Transparency = sTr
            end
        end
        visual(false)

        tb.MouseButton1Click:Connect(function()
            toggled = not toggled
            visual(true)
            if toggled then
                local glow = Instance.new("UIStroke", tb)
                glow.Color = C.Glow
                glow.Thickness = 2
                glow.Transparency = 0.5
                TweenService:Create(glow, TweenInfo.new(0.5), {Transparency = 1}):Play()
                task.delay(0.5, function() glow:Destroy() end)
            end
            if callback then callback(toggled) end
        end)

        return {
            Set = function(v) toggled = v and true or false; visual(true) end,
            Get = function() return toggled end,
        }
    end

    local function CreateButton(parent, text, callback, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 40)
        b.BackgroundColor3 = color or C.Accent
        b.BackgroundTransparency = 0.05
        b.Text = text
        b.TextColor3 = Color3.new(1, 1, 1)
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.ClipsDescendants = true
        b.LayoutOrder = nextOrder(parent)
        b.Parent = parent
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)
        applyCrispText(b, 13, Enum.Font.GothamBold)

        if not color then
            local bg = Instance.new("UIGradient", b)
            bg.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, C.Accent),
                ColorSequenceKeypoint.new(1, C.Accent2),
            })
        end

        local shine = Instance.new("Frame", b)
        shine.Size = UDim2.new(0, 60, 1, 0)
        shine.Position = UDim2.new(-0.3, 0, 0, 0)
        shine.BackgroundColor3 = Color3.new(1, 1, 1)
        shine.BackgroundTransparency = 0.85
        shine.BorderSizePixel = 0
        shine.ZIndex = 2
        local shineGrad = Instance.new("UIGradient", shine)
        shineGrad.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0.3),
            NumberSequenceKeypoint.new(1, 1),
        })
        shineGrad.Rotation = 15

        b.MouseEnter:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.15), {BackgroundTransparency = 0}):Play()
            TweenService:Create(shine, TweenInfo.new(0.6, Enum.EasingStyle.Quart), {Position = UDim2.new(1.1, 0, 0, 0)}):Play()
        end)
        b.MouseLeave:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.15), {BackgroundTransparency = 0.05}):Play()
            shine.Position = UDim2.new(-0.3, 0, 0, 0)
        end)
        b.MouseButton1Click:Connect(function()
            if callback then callback() end
        end)
        return b
    end

    local function CreateButtonRow(parent, items)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 36)
        row.BackgroundTransparency = 1
        row.LayoutOrder = nextOrder(parent)
        row.Parent = parent
        local layout = Instance.new("UIListLayout", row)
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.Padding = UDim.new(0, 6)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        local n = #items
        for i, it in ipairs(items) do
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1 / n, -6 * (n - 1) / n, 1, 0)
            b.BackgroundColor3 = it.color or C.Accent
            b.BackgroundTransparency = 0.1
            b.Text = it.text
            b.TextColor3 = Color3.new(1, 1, 1)
            b.Font = Enum.Font.GothamBold
            b.TextSize = 11
            b.BorderSizePixel = 0
            b.AutoButtonColor = true
            b.LayoutOrder = i
            b.Parent = row
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
            b.MouseButton1Click:Connect(function()
                if it.callback then it.callback() end
            end)
        end
        return row
    end

    local function CreateTextBox(parent, placeholder, callback, initialText)
        local b = Instance.new("TextBox")
        b.Size = UDim2.new(1, 0, 0, 40)
        b.BackgroundColor3 = C.Element
        b.BackgroundTransparency = 0.25
        b.PlaceholderText = placeholder
        b.PlaceholderColor3 = C.Sub
        b.Text = initialText or ""
        b.TextColor3 = C.Text
        b.TextSize = 12
        b.Font = Enum.Font.GothamBold
        b.BorderSizePixel = 0
        b.ClearTextOnFocus = false
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.ClipsDescendants = true
        b.LayoutOrder = nextOrder(parent)
        b.Parent = parent
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)
        local pad = Instance.new("UIPadding", b)
        pad.PaddingLeft = UDim.new(0, 14)
        pad.PaddingRight = UDim.new(0, 14)

        local stroke = Instance.new("UIStroke", b)
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color = C.Stroke
        stroke.Thickness = 1
        stroke.Transparency = 0.5

        b.Focused:Connect(function()
            TweenService:Create(stroke, TweenInfo.new(0.2), {Color = C.Accent, Transparency = 0}):Play()
        end)
        b.FocusLost:Connect(function()
            TweenService:Create(stroke, TweenInfo.new(0.2), {Color = C.Stroke, Transparency = 0.5}):Play()
            if callback then callback(b.Text) end
        end)
        return b
    end

    local function CreateInput(parent, text, default, callback)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 44)
        f.BackgroundColor3 = C.Element
        f.BackgroundTransparency = 0.25
        f.BorderSizePixel = 0
        f.LayoutOrder = nextOrder(parent)
        f.Parent = parent
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 9)
        local fs = Instance.new("UIStroke", f)
        fs.Color = C.Stroke
        fs.Thickness = 1
        fs.Transparency = 0.5

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.5, -16, 1, 0)
        lbl.Position = UDim2.new(0, 16, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = C.Text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextWrapped = true
        lbl.Parent = f
        applyCrispText(lbl, 12, Enum.Font.GothamBold)

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0.5, -16, 0, 28)
        box.Position = UDim2.new(0.5, 0, 0.5, -14)
        box.BackgroundColor3 = C.Bg
        box.BackgroundTransparency = 0.2
        box.Text = tostring(default)
        box.TextColor3 = C.Accent2
        box.Font = Enum.Font.GothamBold
        box.TextSize = 12
        box.BorderSizePixel = 0
        box.ClearTextOnFocus = false
        box.ClipsDescendants = true
        box.Parent = f
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)

        local stroke = Instance.new("UIStroke", box)
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color = C.Stroke
        stroke.Thickness = 1
        stroke.Transparency = 0.5
        box.Focused:Connect(function()
            TweenService:Create(stroke, TweenInfo.new(0.2), {Color = C.Accent, Transparency = 0}):Play()
        end)
        box.FocusLost:Connect(function()
            TweenService:Create(stroke, TweenInfo.new(0.2), {Color = C.Stroke, Transparency = 0.5}):Play()
            if callback then callback(box.Text) end
        end)
        return box
    end

    local function CreateCollapsible(parent, title, bodyHeight)
        local Container = Instance.new("Frame")
        Container.Size = UDim2.new(1, 0, 0, 42)
        Container.BackgroundColor3 = C.Element
        Container.BackgroundTransparency = 0.25
        Container.BorderSizePixel = 0
        Container.ClipsDescendants = true
        Container.LayoutOrder = nextOrder(parent)
        Container.Parent = parent
        Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 9)
        local cStroke = Instance.new("UIStroke", Container)
        cStroke.Color = C.Stroke
        cStroke.Thickness = 1
        cStroke.Transparency = 0.5

        local Header = Instance.new("TextButton")
        Header.Size = UDim2.new(1, 0, 0, 42)
        Header.BackgroundTransparency = 1
        Header.Text = ""
        Header.AutoButtonColor = false
        Header.Parent = Container

        local HeaderLabel = Instance.new("TextLabel")
        HeaderLabel.Size = UDim2.new(1, -50, 1, 0)
        HeaderLabel.Position = UDim2.new(0, 16, 0, 0)
        HeaderLabel.BackgroundTransparency = 1
        HeaderLabel.Text = title
        HeaderLabel.TextColor3 = C.Text
        HeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
        HeaderLabel.TextTruncate = Enum.TextTruncate.AtEnd
        HeaderLabel.Parent = Header
        applyCrispText(HeaderLabel, 12, Enum.Font.GothamBold)

        local Arrow = Instance.new("TextLabel")
        Arrow.Size = UDim2.new(0, 26, 1, 0)
        Arrow.Position = UDim2.new(1, -32, 0, 0)
        Arrow.BackgroundTransparency = 1
        Arrow.Text = "▼"
        Arrow.TextColor3 = C.Accent2
        Arrow.Font = Enum.Font.GothamBold
        Arrow.TextSize = 12
        Arrow.Parent = Header

        local BodyF = Instance.new("Frame")
        BodyF.Size = UDim2.new(1, 0, 0, bodyHeight)
        BodyF.Position = UDim2.new(0, 0, 0, 42)
        BodyF.BackgroundColor3 = C.Bg
        BodyF.BackgroundTransparency = 0.35
        BodyF.BorderSizePixel = 0
        BodyF.Visible = false
        BodyF.Parent = Container

        local self = { Frame = Container, Body = BodyF, IsOpen = false }
        function self.Close()
            self.IsOpen = false
            BodyF.Visible = false
            Container.Size = UDim2.new(1, 0, 0, 42)
            Arrow.Text = "▼"
        end
        function self.Open()
            for _, dd in ipairs(ALL_DROPDOWNS) do
                if dd ~= self then dd.Close() end
            end
            self.IsOpen = true
            BodyF.Visible = true
            Container.Size = UDim2.new(1, 0, 0, 42 + bodyHeight)
            Arrow.Text = "▲"
        end
        table.insert(ALL_DROPDOWNS, self)

        local check = makeAntiScrollClick(Header, parent:IsA("ScrollingFrame") and parent or nil)
        Header.MouseButton1Click:Connect(function()
            if not check() then return end
            if self.IsOpen then self.Close() else self.Open() end
        end)
        return self
    end

    local function CreateDropdown(parent, title, callback, showSelectAll)
        local LIST_HEIGHT = 160
        local TOP_OFFSET = showSelectAll and 38 or 6
        local box = CreateCollapsible(parent, title, TOP_OFFSET + LIST_HEIGHT + 8)
        local BodyF = box.Body

        local selectedValues = {}
        local currentItems = {}

        local ListFrame = Instance.new("ScrollingFrame")
        ListFrame.Size = UDim2.new(1, -8, 0, LIST_HEIGHT)
        ListFrame.Position = UDim2.new(0, 4, 0, TOP_OFFSET)
        ListFrame.BackgroundTransparency = 1
        ListFrame.BorderSizePixel = 0
        ListFrame.ScrollBarThickness = 4
        ListFrame.ScrollBarImageColor3 = C.Accent
        ListFrame.ElasticBehavior = Enum.ElasticBehavior.Never
        ListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        ListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
        ListFrame.ScrollingDirection = Enum.ScrollingDirection.Y
        ListFrame.Parent = BodyF
        local ListLayout = Instance.new("UIListLayout", ListFrame)
        ListLayout.Padding = UDim.new(0, 3)
        ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        local lp = Instance.new("UIPadding", ListFrame)
        lp.PaddingLeft = UDim.new(0, 4)
        lp.PaddingRight = UDim.new(0, 6)
        lp.PaddingTop = UDim.new(0, 2)
        lp.PaddingBottom = UDim.new(0, 2)

        local function fireCallback()
            local sel = {}
            for k in pairs(selectedValues) do table.insert(sel, k) end
            callback(sel)
        end

        local function setItemVisual(btn, item)
            if selectedValues[item] then
                btn.BackgroundColor3 = C.Accent
                btn.BackgroundTransparency = 0.55
                btn.TextColor3 = C.Text
            else
                btn.BackgroundColor3 = C.Element
                btn.BackgroundTransparency = 0.3
                btn.TextColor3 = C.Sub
            end
        end

        local function refreshVisuals()
            for _, c in ipairs(ListFrame:GetChildren()) do
                if c:IsA("TextButton") then
                    local k = c:GetAttribute("ItemKey")
                    if k then setItemVisual(c, k) end
                end
            end
        end

        if showSelectAll then
            local ActionRow = Instance.new("Frame")
            ActionRow.Size = UDim2.new(1, -12, 0, 26)
            ActionRow.Position = UDim2.new(0, 6, 0, 6)
            ActionRow.BackgroundTransparency = 1
            ActionRow.Parent = BodyF

            local SelectAllBtn = Instance.new("TextButton")
            SelectAllBtn.Size = UDim2.new(0.48, 0, 1, 0)
            SelectAllBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 90)
            SelectAllBtn.Text = "✅ Select All"
            SelectAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            SelectAllBtn.Font = Enum.Font.GothamBold
            SelectAllBtn.TextSize = 11
            SelectAllBtn.Parent = ActionRow
            Instance.new("UICorner", SelectAllBtn).CornerRadius = UDim.new(0, 6)

            local ClearAllBtn = Instance.new("TextButton")
            ClearAllBtn.Size = UDim2.new(0.48, 0, 1, 0)
            ClearAllBtn.Position = UDim2.new(0.52, 0, 0, 0)
            ClearAllBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
            ClearAllBtn.Text = "✖ Clear"
            ClearAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            ClearAllBtn.Font = Enum.Font.GothamBold
            ClearAllBtn.TextSize = 11
            ClearAllBtn.Parent = ActionRow
            Instance.new("UICorner", ClearAllBtn).CornerRadius = UDim.new(0, 6)

            local checkSelectAll = makeAntiScrollClick(SelectAllBtn, ListFrame)
            SelectAllBtn.MouseButton1Click:Connect(function()
                if not checkSelectAll() then return end
                for _, item in ipairs(currentItems) do selectedValues[item] = true end
                refreshVisuals()
                fireCallback()
            end)
            local checkClearAll = makeAntiScrollClick(ClearAllBtn, ListFrame)
            ClearAllBtn.MouseButton1Click:Connect(function()
                if not checkClearAll() then return end
                selectedValues = {}
                refreshVisuals()
                fireCallback()
            end)
        end

        function box.Update(items)
            currentItems = items
            for _, c in ipairs(ListFrame:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end
            local order = 0
            for _, item in ipairs(items) do
                order += 1
                local ItemBtn = Instance.new("TextButton")
                ItemBtn.Size = UDim2.new(1, 0, 0, 32)
                ItemBtn.Text = item
                ItemBtn.TextXAlignment = Enum.TextXAlignment.Left
                ItemBtn.Font = Enum.Font.GothamBold
                ItemBtn.TextSize = 12
                ItemBtn.BorderSizePixel = 0
                ItemBtn.AutoButtonColor = false
                ItemBtn.LayoutOrder = order
                ItemBtn.Parent = ListFrame
                Instance.new("UICorner", ItemBtn).CornerRadius = UDim.new(0, 7)
                Instance.new("UIPadding", ItemBtn).PaddingLeft = UDim.new(0, 10)
                ItemBtn:SetAttribute("ItemKey", item)
                setItemVisual(ItemBtn, item)

                local checkItem = makeAntiScrollClick(ItemBtn, ListFrame)
                ItemBtn.MouseButton1Click:Connect(function()
                    if not checkItem() then return end
                    if selectedValues[item] then selectedValues[item] = nil else selectedValues[item] = true end
                    setItemVisual(ItemBtn, item)
                    fireCallback()
                end)
            end
        end
        return box
    end

    -- ------------------------------------------------------------
    -- SIDEBAR
    -- ------------------------------------------------------------
    local T_AUTO, T_SHOP, T_CRAFT, T_EVENT, T_COLLECT, T_SCOOP, T_BOOST =
        "Auto Mutation", "Shop", "Craft & Food", "Event", "Auto Collect Fish", "Food Scoop", "Setting"

    local tabAuto    = CreateSidebarBtn(T_AUTO,    "🧬", 1)
    local tabShop    = CreateSidebarBtn(T_SHOP,    "🛒", 2)
    local tabCraft   = CreateSidebarBtn(T_CRAFT,   "⚒️", 3)
    local tabEvent   = CreateSidebarBtn(T_EVENT,   "🎉", 4)
    local tabCollect = CreateSidebarBtn(T_COLLECT, "🐟", 5)
    local tabScoop   = CreateSidebarBtn(T_SCOOP,   "🍱", 6)
    local tabBoost   = CreateSidebarBtn(T_BOOST,   "⚙️", 7)

    -- =============================================================
    --  TAB : AUTO MUTATION
    -- =============================================================
    local function CreatePetSelectionUI(parent)
        local AllPetsCache = { leveling = {}, speedup = {}, target = {}, collect = {} }
        local ActiveTabPet = "leveling"
        local SelectedPetsByCat = { leveling = {}, speedup = {}, target = {}, collect = {} }
        local CatLabels = { leveling = "Leveling", speedup = "Boost", target = "Target", collect = "Collect" }
        local ListFrameRef

        local box = CreateCollapsible(parent, "🐾 Pet Selection", 290)
        local BodyF = box.Body

        local function RenderList()
            if not ListFrameRef then return end
            for _, c in ipairs(ListFrameRef:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end
            local list = AllPetsCache[ActiveTabPet]
            if not list or #list == 0 then return end
            local sel = SelectedPetsByCat[ActiveTabPet]

            for i, pet in ipairs(list) do
                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, -4, 0, 30)
                btn.Position = UDim2.new(0, 2, 0, (i - 1) * 32)
                btn.BackgroundColor3 = sel[pet.id] and C.Accent or C.Element
                btn.BackgroundTransparency = sel[pet.id] and 0.45 or 0.3
                btn.Text = (sel[pet.id] and "  ✔ " or "  ") .. pet.label
                btn.TextColor3 = C.Text
                btn.TextXAlignment = Enum.TextXAlignment.Left
                btn.Font = Enum.Font.GothamBold
                btn.TextSize = 11
                btn.BorderSizePixel = 0
                btn.AutoButtonColor = false
                btn.Active = true
                btn.Selectable = true
                btn.Parent = ListFrameRef
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)

                btn.MouseButton1Click:Connect(function()
                    if B.isRunning then return end
                    if sel[pet.id] then
                        sel[pet.id] = nil
                        btn.BackgroundColor3 = C.Element
                        btn.BackgroundTransparency = 0.3
                        btn.Text = "  " .. pet.label
                    else
                        sel[pet.id] = true
                        btn.BackgroundColor3 = C.Accent
                        btn.BackgroundTransparency = 0.45
                        btn.Text = "  ✔ " .. pet.label
                    end

                    if ActiveTabPet == "leveling" then
                        B.levelingPets = {} for id in pairs(SelectedPetsByCat.leveling) do B.levelingPets[id] = true end
                    elseif ActiveTabPet == "speedup" then
                        B.speedupPets = {} for id in pairs(SelectedPetsByCat.speedup) do B.speedupPets[id] = true end
                    elseif ActiveTabPet == "target" then
                        B.targetPets = {} for id in pairs(SelectedPetsByCat.target) do B.targetPets[id] = true end
                    elseif ActiveTabPet == "collect" then
                        B.collectPets = {} for id in pairs(SelectedPetsByCat.collect) do B.collectPets[id] = true end
                    end
                end)
            end
            ListFrameRef.CanvasSize = UDim2.new(0, 0, 0, #list * 32 + 10)
        end

        local ActionRow = Instance.new("Frame")
        ActionRow.Size = UDim2.new(1, -12, 0, 28)
        ActionRow.Position = UDim2.new(0, 6, 0, 6)
        ActionRow.BackgroundTransparency = 1
        ActionRow.Parent = BodyF

        local function smallBtn(text, color, size, pos)
            local b = Instance.new("TextButton")
            b.Size = size
            b.Position = pos or UDim2.new(0, 0, 0, 0)
            b.BackgroundColor3 = color
            b.BackgroundTransparency = 0.1
            b.Text = text
            b.TextColor3 = Color3.fromRGB(255, 255, 255)
            b.Font = Enum.Font.GothamBold
            b.TextSize = 10
            b.BorderSizePixel = 0
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
            return b
        end

        local ScanBtn = smallBtn("🔄 Scan", Color3.fromRGB(0, 130, 90), UDim2.new(0.32, -4, 1, 0))
        ScanBtn.Parent = ActionRow
        local SelectAllTargetBtn = smallBtn("✅ Select", Color3.fromRGB(50, 100, 200), UDim2.new(0.32, -4, 1, 0), UDim2.new(0.33, 2, 0, 0))
        SelectAllTargetBtn.Parent = ActionRow
        local ClearBtn = smallBtn("🧹 Clear", Color3.fromRGB(160, 50, 50), UDim2.new(0.32, -4, 1, 0), UDim2.new(0.66, 4, 0, 0))
        ClearBtn.Parent = ActionRow

        local TabRow = Instance.new("Frame")
        TabRow.Size = UDim2.new(1, -12, 0, 24)
        TabRow.Position = UDim2.new(0, 6, 0, 40)
        TabRow.BackgroundTransparency = 1
        TabRow.Parent = BodyF
        local TabLayout = Instance.new("UIListLayout", TabRow)
        TabLayout.FillDirection = Enum.FillDirection.Horizontal
        TabLayout.Padding = UDim.new(0, 2)
        TabLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local CategoryButtons = {}
        local tabKeys = {"leveling", "speedup", "target", "collect"}
        for i, key in ipairs(tabKeys) do
            local tBtn = smallBtn(CatLabels[key], key == ActiveTabPet and C.Accent or C.Element, UDim2.new(0.24, -2, 1, 0))
            tBtn.BackgroundTransparency = key == ActiveTabPet and 0.1 or 0.3
            tBtn.LayoutOrder = i
            tBtn.Parent = TabRow
            CategoryButtons[key] = tBtn

            tBtn.MouseButton1Click:Connect(function()
                for k, btn in pairs(CategoryButtons) do
                    btn.BackgroundColor3 = k == key and C.Accent or C.Element
                    btn.BackgroundTransparency = k == key and 0.1 or 0.3
                end
                ActiveTabPet = key
                RenderList()
            end)
        end

        ListFrameRef = Instance.new("ScrollingFrame")
        ListFrameRef.Size = UDim2.new(1, -8, 0, 200)
        ListFrameRef.Position = UDim2.new(0, 4, 0, 70)
        ListFrameRef.BackgroundTransparency = 1
        ListFrameRef.BorderSizePixel = 0
        ListFrameRef.ScrollBarThickness = 4
        ListFrameRef.ScrollBarImageColor3 = C.Accent
        ListFrameRef.CanvasSize = UDim2.new(0, 0, 0, 0)
        ListFrameRef.ClipsDescendants = true
        ListFrameRef.Parent = BodyF

        local isScanning = false
        ScanBtn.MouseButton1Click:Connect(function()
            if isScanning or B.isRunning then return end
            isScanning = true
            local allPets = scanAllPetsForList()
            local lvlPets = scanPetsFiltered(SPECIES_FILTER.leveling)
            local spdPets = scanPetsFiltered(SPECIES_FILTER.speedup)
            local colPets = scanPetsFiltered(SPECIES_FILTER.collect)
            AllPetsCache.leveling = lvlPets
            AllPetsCache.speedup = spdPets
            AllPetsCache.target = allPets
            AllPetsCache.collect = colPets
            RenderList()
            task.wait(0.5)
            isScanning = false
        end)

        SelectAllTargetBtn.MouseButton1Click:Connect(function()
            if B.isRunning or ActiveTabPet ~= "target" then return end
            local list = AllPetsCache.target
            if not list or #list == 0 then return end
            for _, pet in ipairs(list) do
                SelectedPetsByCat.target[pet.id] = true
            end
            B.targetPets = {}
            for id in pairs(SelectedPetsByCat.target) do
                B.targetPets[id] = true
            end
            RenderList()
        end)

        ClearBtn.MouseButton1Click:Connect(function()
            if B.isRunning then return end
            SelectedPetsByCat = { leveling = {}, speedup = {}, target = {}, collect = {} }
            B.levelingPets = {}; B.speedupPets = {}; B.targetPets = {}; B.collectPets = {}
            RenderList()
        end)

        task.spawn(function()
            task.wait(2)
            local allPets = scanAllPetsForList()
            local lvlPets = scanPetsFiltered(SPECIES_FILTER.leveling)
            local spdPets = scanPetsFiltered(SPECIES_FILTER.speedup)
            local colPets = scanPetsFiltered(SPECIES_FILTER.collect)
            AllPetsCache.leveling = lvlPets
            AllPetsCache.speedup = spdPets
            AllPetsCache.target = allPets
            AllPetsCache.collect = colPets
            RenderList()
        end)
    end

    local function BuildAutoTab(tab)
        CreateSection(tab, "Control")
        local startToggle
        startToggle = CreateToggle(tab, "Start Auto Mutation", false, function(state)
            isRunning = state
            B.isRunning = state
            if B.isRunning then
                if next(B.targetPets) == nil then
                    Notify("Auto Mutation ", "Sellect Target!", C.Danger)
                    B.isRunning = false; isRunning = false
                    startToggle.Set(false)
                    return
                end
                if not hasSelected() then
                    Notify("Auto Mutation ", "Sellect Target!", C.Danger)
                    B.isRunning = false; isRunning = false
                    startToggle.Set(false)
                    return
                end
                resetWave()
                B.placedPets = {}; B.pickedUpPets = {}
                B.placedLeveling = {}; B.placedSpeedup = {}
                B.mutationInProgress = {}; B.processedMutation = {}
                B.currentLoadout = nil; B.lastLoadoutSwitch = 0
                B.totalBoosted = 0; B.totalMutated = 0; B.cycleCount = 0
                B.jumperCounter = 0; B.lastJumperFire = 0; B.lastMutationAction = 0
                B.boostJumperCount = 0; B.boostLoadoutSwitching = false
                B.lastJumperEmptyNotify = 0
                B.collectSetupDone = false
                task.spawn(boostLoop)
            end
        end)

        local mutDropdown = CreateDropdown(tab, "Mutation Target", function(sel)
            B.selectedMutations = {}
            for _, m in ipairs(sel) do B.selectedMutations[m] = true end
        end)
        mutDropdown.Update(ALL_MUTATIONS)

        CreateInput(tab, "Max Place Target", B.maxPlacePerWave, function(text)
            local n = tonumber(text)
            if n then B.maxPlacePerWave = math.floor(n) end
        end)

        CreatePetSelectionUI(tab)

        CreateSection(tab, "option")
        CreateToggle(tab, "Auto PetToy", false, function(s) B.useAutoPetToy = s end)
        CreateToggle(tab, "Auto Diamond Cookie", false, function(s) B.useAutoCookie = s end)
        return startToggle
    end

    local startToggle = BuildAutoTab(tabAuto)

    -- =============================================================
    --  TAB : SHOP
    -- =============================================================
    CreateSection(tabShop, "Auto Buy")
    CreateToggle(tabShop, "Auto Buy All Stock Gear", false, function(state) S.gOn = state S.nextGear = 0 end)
    CreateToggle(tabShop, "Auto Buy All stock Bait", false, function(state) S.bOn = state S.nextBait = 0 end)
    CreateToggle(tabShop, "Auto Buy All Stock Egg", false, function(state) S.eOn = state S.nextEgg = 0 end)
    CreateToggle(tabShop, "Auto Buy All Stock Golden Merchant", false, function(state) S.gdOn = state S.nextGolden = 0 end)

    -- =============================================================
    --  TAB : CRAFT & FOOD
    -- =============================================================
    CreateSection(tabCraft, "Crafting & Food")
    CreateToggle(tabCraft, "Auto Craft (TimeJumper Only)", false, function(state)
        BCONFIG.CraftOn = state
        S._nextCraftTry = 0
        if not BCONFIG.CraftOn then S.cPhase = "idle" S.cCd = 0 end
    end)
    CreateToggle(tabCraft, "Auto Place FoodTray (Supreme/Advanced/Basic)", false, function(state)
        BCONFIG.FoodOn = state
        S.nextPlace = 0
    end)

        -- =============================================================
    --  AUTO CRAFT (integrasi dari script 1) — Tab Craft & Food
    -- =============================================================
    CreateSection(tabCraft, "Zeus Machine Auto Craft")

    local AC_GEARS = {
        { name = "TimeJumper", items = {
            { id = "TeleportWand", count = 10 },
            { id = "MagnifyingGlass", count = 25 },
            { id = "SupremeAutoFeeder", count = 1 },
        }},
        { name = "DiamondCookie", items = {
            { id = "XpCookie", count = 1 },
            { id = "GoldenCookie", count = 1 },
            { id = "PetToy", count = 1 },
        }},
        { name = "NetRetractor", items = {
            { id = "NetMover", count = 25 },
            { id = "ExtremeAutoFeeder", count = 5 },
        }},
        { name = "YolkBreaker", items = {
            { id = "EggIncubator", count = 1 },
            { id = "EggHatcher", count = 1 },
            { id = "GoldenCookie", count = 1 },
        }},
        { name = "ShieldLock", items = {
            { id = "StarLock", count = 10 },
            { id = "TimeJumper", count = 1 },
            { id = "ExtremeAutoFeeder", count = 1 },
        }},
    }

    local AC_MACHINE_TYPE = "GearAutoCrafter"

    local function acExpandItems(spec, mult)
        local list = {}
        for _, e in ipairs(spec) do
            for _ = 1, e.count * mult do table.insert(list, e.id) end
        end
        return list
    end

    local function acDescribe(spec, mult)
        local parts, total = {}, 0
        for _, e in ipairs(spec) do
            local c = e.count * mult
            total = total + c
            table.insert(parts, c .. "x " .. e.id)
        end
        return table.concat(parts, ", "), total
    end

    local AC_Container = nil
    pcall(function()
        AC_Container = RS:WaitForChild("rbxts_include", 10)
            :WaitForChild("node_modules", 10)
            :WaitForChild("@rbxts", 10):WaitForChild("remo", 10)
            :WaitForChild("src", 10):WaitForChild("container", 10)
    end)

    local AC_State = {
        running = false,
        loopCount = 0,
        multiplier = 1,
        thread = nil,
        selectedGear = AC_GEARS[1],
        uid = nil,
    }

    local function acFire(name, ...)
        if not AC_Container then return false end
        local r = AC_Container:FindFirstChild(name)
        if r and r:IsA("RemoteEvent") then
            local args = { ... }
            pcall(function() r:FireServer(table.unpack(args)) end)
            return true
        end
        return false
    end

    local function acFindAll()
        local found = {}
        if not getPlayerData then return found end
        local ok, data = pcall(getPlayerData, player)
        if not ok or not data or not data.ponds then return found end
        for pondKey, pondData in pairs(data.ponds) do
            if type(pondData) == "table" and type(pondData.machines) == "table" then
                for uid, mData in pairs(pondData.machines) do
                    if type(mData) == "table" and mData.machineType == AC_MACHINE_TYPE then
                        table.insert(found, { pondKey = pondKey, uid = uid })
                    end
                end
            end
        end
        return found
    end

    local function acPickMachine()
        local list = acFindAll()
        if #list == 0 then return nil end
        for _, e in ipairs(list) do
            if tostring(e.pondKey):lower() == "pond2" then return e end
        end
        return list[1]
    end

    local function acRunCraft(gear, mult)
        if not AC_State.uid then return false end
        local uid = AC_State.uid
        acFire("autoCrafting.selectCraftingItem", uid, gear.name, mult)
        task.wait(0.2)
        acFire("autoCrafting.submitItems", uid, acExpandItems(gear.items, mult))
        task.wait(0.3)
        acFire("autoCrafting.startCraft", uid)
        task.wait(1.5)
        acFire("autoCrafting.collectCraft", uid)
        task.wait(0.1)
        acFire("autoCrafting.cancelCraft", uid)
        return true
    end

    local acGearDropdown = CreateDropdown(tabCraft, "Sellect Gear Auto Craft", function(sel)
        if #sel > 0 then
            local name = sel[#sel]
            for _, g in ipairs(AC_GEARS) do
                if g.name == name then AC_State.selectedGear = g break end
            end
        end
    end)

    local acGearNames = {}
    for _, g in ipairs(AC_GEARS) do table.insert(acGearNames, g.name) end
    acGearDropdown.Update(acGearNames)

    local acInfo = CreateInfo(tabCraft, "")
    acInfo.Visible = false

    local acMultFrame = Instance.new("Frame")
    acMultFrame.Size = UDim2.new(1, 0, 0, 34)
    acMultFrame.BackgroundTransparency = 1
    acMultFrame.LayoutOrder = nextOrder(tabCraft)
    acMultFrame.Parent = tabCraft
    local acMultLayout = Instance.new("UIListLayout", acMultFrame)
    acMultLayout.FillDirection = Enum.FillDirection.Horizontal
    acMultLayout.Padding = UDim.new(0, 6)
    acMultLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local acMultBtns = {}
    local function acUpdateMultVisual()
        for m, b in pairs(acMultBtns) do
            b.BackgroundColor3 = (m == AC_State.multiplier) and Color3.fromRGB(60, 180, 100) or C.Element
            b.BackgroundTransparency = (m == AC_State.multiplier) and 0.1 or 0.3
        end
    end

    local function acRefreshInfo()
        local desc, total = acDescribe(AC_State.selectedGear.items, AC_State.multiplier)
        acInfo.Text = "Bahan: " .. desc .. "\nTotal: " .. total .. " item (" .. AC_State.multiplier .. "x)"
    end

    for i, m in ipairs({1, 5, 10}) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.33, -4, 1, 0)
        b.BackgroundColor3 = C.Element
        b.BackgroundTransparency = 0.3
        b.Text = tostring(m) .. "x"
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.BorderSizePixel = 0
        b.LayoutOrder = i
        b.Parent = acMultFrame
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        acMultBtns[m] = b
        b.MouseButton1Click:Connect(function()
            AC_State.multiplier = m
            acUpdateMultVisual()
            acRefreshInfo()
        end)
    end
    acUpdateMultVisual()
    acRefreshInfo()

    local acUidLabel = CreateInfo(tabCraft, "UID: (belum dicari)")
    acUidLabel.Font = Enum.Font.Code
    acUidLabel.TextSize = 10
    acUidLabel.Visible = false

    local function acRefreshUid()
        local chosen = acPickMachine()
        if chosen then
            AC_State.uid = chosen.uid
            acUidLabel.Text = string.format("UID: %s | pond: %s", tostring(chosen.uid), tostring(chosen.pondKey))
            acUidLabel.TextColor3 = Color3.fromRGB(160, 255, 160)
            return true
        else
            AC_State.uid = nil
            acUidLabel.Text = "UID: GearAutoCrafter TIDAK ditemukan"
            acUidLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
            return false
        end
    end
    acRefreshUid()

    local acRefreshBtn = CreateButton(tabCraft, "🔄 Cari UID GearAutoCrafter", function()
        local ok = acRefreshUid()
        Notify("Auto Craft", ok and "Mesin ditemukan!" or "Mesin tidak ditemukan", ok and C.Success or C.Danger)
    end, Color3.fromRGB(70, 110, 180))
    acRefreshBtn.Visible = false

    local acStatus = CreateStatus(tabCraft, "Status: OFF")

    local acToggle
    acToggle = CreateToggle(tabCraft, "Start Auto Craft", false, function(state)
        if state then
            local chosen = acPickMachine()
            if not chosen then
                Notify("Auto Craft", "GearAutoCrafter tidak ditemukan!", C.Danger)
                acToggle.Set(false)
                return
            end
            AC_State.uid = chosen.uid
            acUidLabel.Text = string.format("UID: %s | pond: %s", tostring(chosen.uid), tostring(chosen.pondKey))
            acUidLabel.TextColor3 = Color3.fromRGB(160, 255, 160)

            AC_State.running = true
            AC_State.loopCount = 0
            acStatus.Text = "Status: RUNNING"
            acStatus.TextColor3 = C.Success

            AC_State.thread = task.spawn(function()
                while AC_State.running do
                    local gear = AC_State.selectedGear
                    pcall(acRunCraft, gear, AC_State.multiplier)
                    AC_State.loopCount = AC_State.loopCount + 1
                    acStatus.Text = string.format("Status: RUNNING (%d) - %s (%dx)",
                        AC_State.loopCount, gear.name, AC_State.multiplier)
                    acStatus.TextColor3 = C.Success

                    if AC_State.loopCount % 5 == 0 then
                        pcall(function()
                            local c = acPickMachine()
                            if c then AC_State.uid = c.uid end
                        end)
                    end
                    task.wait(0.5)
                end
            end)
        else
            AC_State.running = false
            if AC_State.thread then pcall(task.cancel, AC_State.thread) AC_State.thread = nil end
            acStatus.Text = "Status: OFF (Total: " .. AC_State.loopCount .. ")"
            acStatus.TextColor3 = C.Sub
        end
    end)

    table.insert(CloseHooks, function()
        AC_State.running = false
        if AC_State.thread then pcall(task.cancel, AC_State.thread) end
    end)

    -- =============================================================
    --  TAB : EVENT
    -- =============================================================
    CreateSection(tabEvent, "Paper Event")
    CreateToggle(tabEvent, "Auto-Collect Mutated Fish (Paper)", false, function(state)
        S.hwCollect = state
        if state then startHWCollect() else stopHWCollect() end
    end)
    CreateToggle(tabEvent, "Auto Feed & Pickup Reward", false, function(state)
        S.hwFeedPickup = state
        if state then startHWFeedPickup() else stopHWFeedPickup() end
    end)

    -- =============================================================
    --  TAB : AUTO COLLECT FISH
    -- =============================================================
    local function CreateFeederList(parent, feedersList)
        local LIST_HEIGHT = 220
        local box = CreateCollapsible(parent, "⚙️ Setting Feeder", LIST_HEIGHT + 12)
        local BodyF = box.Body

        local ListFrame = Instance.new("ScrollingFrame")
        ListFrame.Size = UDim2.new(1, -8, 0, LIST_HEIGHT)
        ListFrame.Position = UDim2.new(0, 4, 0, 6)
        ListFrame.BackgroundTransparency = 1
        ListFrame.BorderSizePixel = 0
        ListFrame.ScrollBarThickness = 4
        ListFrame.ScrollBarImageColor3 = C.Accent
        ListFrame.ElasticBehavior = Enum.ElasticBehavior.Never
        ListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        ListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
        ListFrame.ScrollingDirection = Enum.ScrollingDirection.Y
        ListFrame.Parent = BodyF
        local LL = Instance.new("UIListLayout", ListFrame)
        LL.Padding = UDim.new(0, 4)
        LL.SortOrder = Enum.SortOrder.LayoutOrder
        local lp = Instance.new("UIPadding", ListFrame)
        lp.PaddingTop = UDim.new(0, 4)
        lp.PaddingBottom = UDim.new(0, 4)
        lp.PaddingLeft = UDim.new(0, 4)
        lp.PaddingRight = UDim.new(0, 6)

        for i, fName in ipairs(feedersList) do
            FeederInputValues[fName] = 0

            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 32)
            row.BackgroundColor3 = C.Element
            row.BackgroundTransparency = (i % 2 == 0) and 0.3 or 0.5
            row.BorderSizePixel = 0
            row.LayoutOrder = i
            row.Parent = ListFrame
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size = UDim2.new(1, -70, 1, 0)
            nameLbl.Position = UDim2.new(0, 10, 0, 0)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Text = fName
            nameLbl.TextColor3 = C.Text
            nameLbl.Font = Enum.Font.GothamBold
            nameLbl.TextSize = 12
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            nameLbl.Parent = row

            local cntBox = Instance.new("TextBox")
            cntBox.Size = UDim2.new(0, 50, 0, 22)
            cntBox.Position = UDim2.new(1, -58, 0.5, -11)
            cntBox.BackgroundColor3 = C.Bg
            cntBox.BackgroundTransparency = 0.2
            cntBox.BorderSizePixel = 0
            cntBox.Text = "0"
            cntBox.TextColor3 = C.Accent2
            cntBox.Font = Enum.Font.Code
            cntBox.TextSize = 12
            cntBox.ClearTextOnFocus = false
            cntBox.Parent = row
            Instance.new("UICorner", cntBox).CornerRadius = UDim.new(0, 5)

            cntBox.FocusLost:Connect(function()
                local n = tonumber(cntBox.Text) or 0
                n = math.max(0, math.floor(n))
                FeederInputValues[fName] = n
                cntBox.Text = tostring(n)
            end)
        end
        return box
    end

    local function BuildCollectTab(tab)
        local fishUtils = nil
        pcall(function()
            fishUtils = require(TS:WaitForChild("utils"):WaitForChild("fish.utils"))
        end)

        local collectFishRemoteFarm = remoFarm:FindFirstChild("bait.collectFish")
        local sellAllFishRemoteFarm = remoFarm:FindFirstChild("sellFish.sellAllFish")

        local FC = {
            MaxWeightTon = 1000000,
            CheckInterval = 0,
            AutoOn = false,
            AutoSellOn = false,
            AutoSellInterval = 0.1,
        }

        local collectedCache = {}
        local CACHE_EXPIRY = 10

        local function formatTonText(ton)
            if not ton then return "0" end
            if ton >= 1e12 then return string.format("%.2fT", ton / 1e12)
            elseif ton >= 1e9 then return string.format("%.2fM", ton / 1e9)
            elseif ton >= 1e6 then return string.format("%.2fjt", ton / 1e6)
            elseif ton >= 1e3 then return string.format("%.2frb", ton / 1e3)
            else return string.format("%d", ton) end
        end

        local function parseWeightInput(str)
            if not str or str == "" then return nil end
            str = str:gsub("[%.,%s]", "")
            local num = tonumber(str)
            if not num or num < 0 then return nil end
            return math.floor(num)
        end

        local function getFishWeight(fishData)
            if not fishUtils or not fishUtils.calculateFishWeight then return 0 end
            if not fishData or type(fishData) ~= "table" then return 0 end
            local ok, result = pcall(fishUtils.calculateFishWeight, fishData)
            if ok and type(result) == "number" then return result end
            return 0
        end

        local function isRecentlyCollected(fishId)
            local t = collectedCache[fishId]
            if not t then return false end
            if os.clock() - t > CACHE_EXPIRY then
                collectedCache[fishId] = nil
                return false
            end
            return true
        end

        local function autoCollectBait()
            if not collectFishRemoteFarm then return 0 end
            local pd = getData()
            if not pd or not pd.ponds then return 0 end
            local pondKey = pd.currentPond
            if not pondKey then return 0 end
            local pondData = pd.ponds[pondKey]
            if not pondData or not pondData.baits then return 0 end

            local maxWeightKg = FC.MaxWeightTon * 1000
            local collected = 0

            local toCollect = {}
            for baitId, baitData in pairs(pondData.baits) do
                if type(baitData) == "table" and baitData.fishes then
                    for fishId, fishData in pairs(baitData.fishes) do
                        if type(fishData) == "table" and not isRecentlyCollected(fishId) then
                            local weightKg = getFishWeight(fishData)
                            if weightKg < maxWeightKg then
                                table.insert(toCollect, {baitId = baitId, fishId = fishId})
                            end
                        end
                    end
                end
            end

            for i, data in ipairs(toCollect) do
                if not FC.AutoOn then break end
                pcall(function()
                    collectFishRemoteFarm:FireServer(data.baitId, data.fishId)
                end)
                collectedCache[data.fishId] = os.clock()
                collected += 1
                task.wait(0.01)
            end
            return collected
        end

        local function autoSellAll()
            if not sellAllFishRemoteFarm then return false end
            return pcall(function() sellAllFishRemoteFarm:FireServer() end)
        end

        CreateSection(tab, "Smart Collect")

        local StatusLabel
        local InputBox
        InputBox = CreateInput(tab, "⭐ Max Weight >= (TON)", FC.MaxWeightTon, function(text)
            local parsed = parseWeightInput(text)
            if parsed and parsed >= 0 then
                FC.MaxWeightTon = parsed
                InputBox.Text = tostring(parsed)
                if StatusLabel then
                    StatusLabel.Text = "Status: Collect < " .. formatTonText(parsed) .. " ton"
                end
            else
                InputBox.Text = tostring(FC.MaxWeightTon)
            end
        end)

        StatusLabel = CreateStatus(tab, "Status: Idle")

        local sellIntBox
        sellIntBox = CreateInput(tab, "⏱️ Interval Auto Sell (s)", tostring(FC.AutoSellInterval), function(text)
            local num = tonumber(text)
            if num and num >= 0.1 then
                FC.AutoSellInterval = num
                sellIntBox.Text = tostring(num)
            else
                sellIntBox.Text = tostring(FC.AutoSellInterval)
            end
        end)

        CreateToggle(tab, "🐟 Auto Collect", false, function(state) FC.AutoOn = state end)
        CreateToggle(tab, "💸 Auto Sell", false, function(state) FC.AutoSellOn = state end)
        CreateButton(tab, "💵 SELL NOW", function()
            task.spawn(function()
                StatusLabel.Text = "Status: Selling..."
                local ok = autoSellAll()
                StatusLabel.Text = ok and "Status: Sold all ✅" or "Status: Sell failed ❌"
            end)
        end, Color3.fromRGB(230, 140, 20))

        task.spawn(function()
            while ScreenGui.Parent do
                if FC.AutoOn then
                    pcall(function()
                        local n = autoCollectBait()
                        if StatusLabel and n > 0 then
                            StatusLabel.Text = string.format("Status: Collected %d", n)
                        end
                    end)
                end
                task.wait(FC.CheckInterval)
            end
        end)

        task.spawn(function()
            while ScreenGui.Parent do
                if FC.AutoSellOn then
                    pcall(function()
                        autoSellAll()
                        if StatusLabel then StatusLabel.Text = "Status: Auto sold ✅" end
                    end)
                end
                task.wait(FC.AutoSellInterval)
            end
        end)

        task.spawn(function()
            while ScreenGui.Parent do
                task.wait(30)
                for k in pairs(collectedCache) do collectedCache[k] = nil end
            end
        end)

        table.insert(CloseHooks, function()
            FC.AutoOn = false
            FC.AutoSellOn = false
        end)

        CreateSection(tab, "Auto Feeder")
        CreateInput(tab, "Interval Feeder (s)", "300", function(text)
            local n = tonumber(text)
            if n then AutoFarmInterval = n end
        end)

        CreateFeederList(tab, Feeders)

        CreateToggle(tab, "Auto Place Feeders", false, function(state)
            AutoFarmFeederRunning = state
            if AutoFarmFeederRunning then
                AutoFarmFeederThread = task.spawn(function()
                    while AutoFarmFeederRunning do
                        local totalAll = 0
                        for _, fName in ipairs(Feeders) do
                            totalAll += (FeederInputValues[fName] or 0)
                        end

                        if totalAll > 0 then
                            SwitchPetLoadout:InvokeServer(1)
                            task.wait(0.5)

                            for _, fName in ipairs(Feeders) do
                                local n = FeederInputValues[fName] or 0
                                if n > 0 then
                                    for i = 1, n do
                                        if not AutoFarmFeederRunning then break end
                                        placeRemote:InvokeServer("booster", fName, Vector3.new(24.86, -0.01, -23))
                                        task.wait(0)
                                    end
                                end
                            end
                            SwitchPetLoadout:InvokeServer(0)
                        end

                        local waited = 0
                        while waited < AutoFarmInterval and AutoFarmFeederRunning do
                            task.wait(1)
                            waited += 1
                        end
                    end
                end)
            else
                if AutoFarmFeederThread then pcall(task.cancel, AutoFarmFeederThread) end
            end
        end)

        table.insert(CloseHooks, function()
            AutoFarmFeederRunning = false
            if AutoFarmFeederThread then pcall(task.cancel, AutoFarmFeederThread) end
        end)
    end

    BuildCollectTab(tabCollect)

    -- =============================================================
    --  TAB : FOOD SCOOP (Bait Scanner)
    -- =============================================================
    local function BuildScoopTab(tab)
        local RS = game:GetService("ReplicatedStorage")
        local Players = game:GetService("Players")

        local getPlayerDataById = require(RS.TS.state["player-data"]).getPlayerDataById
        local gearUseFishFeeder = RS.rbxts_include.node_modules["@rbxts"].remo.src.container["gear.useFishFeeder"]
        local DEFAULT_DELAY = 0
        local DEFAULT_CAPACITY = 10

        local NET_SIZE_CAPACITY = {
            ["10x10"] = 5, ["15x15"] = 6, ["20x20"] = 7,
            ["25x25"] = 8, ["30x30"] = 9, ["35x35"] = 10, ["40x40"] = 10,
        }

        local BAITS_CONFIG = nil
        pcall(function()
            BAITS_CONFIG = require(RS.TS.lists.game.bait).Baits
        end)

        local scanned, queue, active, threads = {}, {}, {}, {}
        local sent, failed, skipped = 0, 0, 0
        local autoScan, query = true, ""
        local delay = DEFAULT_DELAY
        local scanThread = nil
        local rowCache = {}
        local isScoopRunning = false
        local selectedScoop = "GoldenFoodScoop"

        local function baitName(b)
            if type(b) ~= "table" then return "?" end
            if type(b.bait) == "table" and type(b.bait.baitType) == "string" then
                return b.bait.baitType
            end
            for _, k in ipairs({"baitType","type","baitId","id","name"}) do
                if type(b[k]) == "string" then return b[k] end
            end
            return "?"
        end

        local function getCurrentAmount(b)
            if type(b) ~= "table" then return 0 end
            if type(b.fishes) == "table" then
                local n = 0
                for _ in pairs(b.fishes) do n = n + 1 end
                return n
            end
            if type(b.bait) == "table" and type(b.bait.amount) == "number" then
                return b.bait.amount
            end
            return 0
        end

        local function getMaxCapacity(b)
            if type(b) ~= "table" then return DEFAULT_CAPACITY end
            local bt = type(b.bait) == "table" and b.bait.baitType or nil
            if not bt then return DEFAULT_CAPACITY end
            if BAITS_CONFIG and BAITS_CONFIG[bt] then
                local netSize = BAITS_CONFIG[bt].netSize
                if netSize and NET_SIZE_CAPACITY[netSize] then
                    return NET_SIZE_CAPACITY[netSize]
                end
            end
            for _, k in ipairs({"maxFishes","maxAmount","capacity","maxCapacity","slots","maxSlots"}) do
                if type(b[k]) == "number" and b[k] > 0 then return b[k] end
                if type(b.bait) == "table" and type(b.bait[k]) == "number" and b.bait[k] > 0 then
                    return b.bait[k]
                end
            end
            return DEFAULT_CAPACITY
        end

        local function isBaitFull(b)
            return getCurrentAmount(b) >= getMaxCapacity(b)
        end

        local function scan()
            local out = {}
            for _, p in ipairs(Players:GetPlayers()) do
                local ok, d = pcall(getPlayerDataById, tostring(p.UserId))
                if ok and d and d.ponds then
                    local pond = d.ponds[d.currentPond]
                    if pond and pond.baits then
                        local list = {}
                        for uid, b in pairs(pond.baits) do
                            local cur = getCurrentAmount(b)
                            local max = getMaxCapacity(b)
                            table.insert(list, {
                                uid = tostring(uid),
                                type = baitName(b),
                                amount = cur,
                                maxAmount = max,
                                isFull = (cur >= max),
                                owner = p.Name,
                                pond = tostring(d.currentPond),
                            })
                        end
                        out[p.Name] = { pond = tostring(d.currentPond), baits = list }
                    end
                end
            end
            return out
        end

        local function countTable(t)
            local n = 0
            for _ in pairs(t) do n = n + 1 end
            return n
        end

        local SC = {
            alt     = C.Element,
            accent  = C.Accent2,
            text    = C.Text,
            dim     = C.Sub,
            ok      = C.Success,
            sel     = Color3.fromRGB(180, 130, 240),
            full    = Color3.fromRGB(255, 180, 80),
        }

        local status, list, listBox
        local startUID, stopUID, stopAll, render, startScanLoop, stopScanLoop, updateRowState, createRow

        CreateSection(tab, "Bait Scoop")

        local scoopToggle
        scoopToggle = CreateToggle(tab, "Start Bait Scoop", false, function(state)
            if not state then
                isScoopRunning = false
                stopAll()
                status.Text = "Auto Scoop: STOPPED"
            else
                if countTable(queue) == 0 then
                    status.Text = "⚠️ Queue kosong! Pilih bait dulu di list."
                    scoopToggle.Set(false)
                    return
                end
                isScoopRunning = true
                for uid in pairs(queue) do startUID(uid) end
                status.Text = "Auto Scoop: STARTED"
            end
        end)

        local scoopDropdown = CreateDropdown(tab, "Scoop Type", function(sel)
            if #sel > 0 then
                selectedScoop = sel[#sel]
            end
        end)
        scoopDropdown.Update({"GoldenFoodScoop", "FoodScoop"})

        local boxDelay
        boxDelay = CreateInput(tab, "Delay (s)", "0", function(text)
            local n = tonumber(text)
            if n and n >= 0 then delay = n
            else boxDelay.Text = tostring(delay) end
        end)

        local search = CreateTextBox(tab, "🔎 Search for Verse / Player...")
        search:GetPropertyChangedSignal("Text"):Connect(function()
            query = search.Text
            render()
        end)

        CreateButtonRow(tab, {
            { text = "🔄 Scan Manual", color = Color3.fromRGB(60, 110, 200), callback = function()
                scanned = scan()
                render()
                status.Text = "Scan manual selesai."
            end },
            { text = "🧹 Clear Queue", color = Color3.fromRGB(180, 60, 70), callback = function()
                stopAll()
                for uid in pairs(queue) do queue[uid] = nil end
                render()
                status.Text = "Queue dibersihkan."
            end },
        })

        CreateToggle(tab, "⚡ Auto Scan", false, function(state)
            autoScan = state
            if autoScan then startScanLoop() else stopScanLoop() end
        end)

        status = CreateStatus(tab, "Status: Ready.")
        status.TextColor3 = C.Sub

        listBox = CreateCollapsible(tab, "📋 List Bait", 300)
        list = Instance.new("ScrollingFrame")
        list.Size = UDim2.new(1, -16, 1, -16)
        list.Position = UDim2.new(0, 8, 0, 8)
        list.BackgroundTransparency = 1
        list.BorderSizePixel = 0
        list.ScrollBarThickness = 4
        list.ScrollBarImageColor3 = C.Accent
        list.CanvasSize = UDim2.new(0, 0, 0, 0)
        list.AutomaticCanvasSize = Enum.AutomaticSize.Y
        list.Parent = listBox.Body
        local listLayout = Instance.new("UIListLayout", list)
        listLayout.Padding = UDim.new(0, 2)
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        local listPad = Instance.new("UIPadding", list)
        listPad.PaddingRight = UDim.new(0, 6)

        stopUID = function(uid)
            active[uid] = nil
            if threads[uid] then
                pcall(task.cancel, threads[uid])
                threads[uid] = nil
            end
        end

        local function isBaitFullLive(uid)
            for _, p in ipairs(Players:GetPlayers()) do
                local ok, d = pcall(getPlayerDataById, tostring(p.UserId))
                if ok and d and d.ponds then
                    local pond = d.ponds[d.currentPond]
                    if pond and pond.baits and pond.baits[uid] then
                        return isBaitFull(pond.baits[uid])
                    end
                end
            end
            return false
        end

        startUID = function(uid)
            if active[uid] or not queue[uid] then return end
            active[uid] = true
            threads[uid] = task.spawn(function()
                while active[uid] and queue[uid] and isScoopRunning and listBox.Frame.Parent do
                    if isBaitFullLive(uid) then
                        skipped = skipped + 1
                        status.Text = "⏭ SKIP (FULL): " .. queue[uid].owner .. " " .. uid:sub(1, 6)
                        task.wait(0)
                    else
                        local ok = pcall(function()
                            gearUseFishFeeder:FireServer(selectedScoop, uid, 1)
                        end)
                        if ok then
                            sent = sent + 1
                            status.Text = "✔ Mengambil: " .. queue[uid].owner .. " " .. uid:sub(1, 6)
                        else
                            failed = failed + 1
                        end
                        task.wait(delay)
                    end
                end
                active[uid] = nil
                threads[uid] = nil
            end)
        end

        stopAll = function()
            for uid in pairs(active) do stopUID(uid) end
        end

        createRow = function(order, name, b)
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 28)
            row.BackgroundColor3 = SC.alt
            row.BackgroundTransparency = 0.3
            row.BorderSizePixel = 0
            row.LayoutOrder = order
            row.Active = true
            row.Parent = list
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

            local ind = Instance.new("Frame")
            ind.Size = UDim2.new(0, 3, 1, 0)
            ind.BackgroundColor3 = SC.accent
            ind.BorderSizePixel = 0
            ind.Visible = false
            ind.ZIndex = 2
            ind.Parent = row
            Instance.new("UICorner", ind).CornerRadius = UDim.new(0, 3)

            local n1 = Instance.new("TextLabel")
            n1.Size = UDim2.new(0, 90, 1, 0)
            n1.Position = UDim2.new(0, 8, 0, 0)
            n1.BackgroundTransparency = 1
            n1.Text = name
            n1.TextColor3 = SC.accent
            n1.Font = Enum.Font.GothamBold
            n1.TextSize = 10
            n1.TextXAlignment = Enum.TextXAlignment.Left
            n1.TextTruncate = Enum.TextTruncate.AtEnd
            n1.ZIndex = 2
            n1.Parent = row

            local n2 = Instance.new("TextLabel")
            n2.Size = UDim2.new(0, 100, 1, 0)
            n2.Position = UDim2.new(0, 100, 0, 0)
            n2.BackgroundTransparency = 1
            n2.Text = b.type
            n2.TextColor3 = SC.text
            n2.Font = Enum.Font.GothamMedium
            n2.TextSize = 10
            n2.TextXAlignment = Enum.TextXAlignment.Left
            n2.TextTruncate = Enum.TextTruncate.AtEnd
            n2.ZIndex = 2
            n2.Parent = row

            local n3 = Instance.new("TextLabel")
            n3.Size = UDim2.new(0, 80, 1, 0)
            n3.Position = UDim2.new(0, 202, 0, 0)
            n3.BackgroundTransparency = 1
            n3.Text = b.uid:sub(1, 8)
            n3.TextColor3 = SC.dim
            n3.Font = Enum.Font.Code
            n3.TextSize = 9
            n3.TextXAlignment = Enum.TextXAlignment.Left
            n3.ZIndex = 2
            n3.Parent = row

            local n4 = Instance.new("TextLabel")
            n4.Size = UDim2.new(0, 50, 1, 0)
            n4.Position = UDim2.new(1, -90, 0, 0)
            n4.BackgroundTransparency = 1
            n4.Text = ""
            n4.TextColor3 = SC.dim
            n4.Font = Enum.Font.Code
            n4.TextSize = 9
            n4.TextXAlignment = Enum.TextXAlignment.Left
            n4.ZIndex = 2
            n4.Parent = row

            local st = Instance.new("TextLabel")
            st.Size = UDim2.new(0, 40, 1, 0)
            st.Position = UDim2.new(1, -40, 0, 0)
            st.BackgroundTransparency = 1
            st.Text = ""
            st.Font = Enum.Font.GothamBold
            st.TextSize = 11
            st.TextXAlignment = Enum.TextXAlignment.Right
            st.ZIndex = 2
            st.Parent = row

            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 1, 0)
            btn.BackgroundTransparency = 1
            btn.Text = ""
            btn.ZIndex = 5
            btn.AutoButtonColor = false
            btn.Parent = row

            btn.MouseButton1Click:Connect(function()
                if queue[b.uid] then
                    stopUID(b.uid)
                    queue[b.uid] = nil
                else
                    queue[b.uid] = { uid = b.uid, owner = name }
                    if isScoopRunning then startUID(b.uid) end
                end
                updateRowState(b.uid)
            end)

            return {
                row = row, ind = ind, btn = btn,
                n1 = n1, n2 = n2, n3 = n3, n4 = n4, st = st,
            }
        end

        updateRowState = function(uid)
            local cache = rowCache[uid]
            if not cache then return end
            local b = nil
            for _, info in pairs(scanned) do
                for _, bait in ipairs(info.baits) do
                    if bait.uid == uid then b = bait; break end
                end
                if b then break end
            end
            cache.row.BackgroundColor3 = SC.alt
            cache.row.BackgroundTransparency = 0.3
            cache.ind.Visible = false
            cache.st.Text = ""
            cache.st.TextSize = 11
            if not b then return end
            cache.n4.Text = tostring(b.amount) .. "/" .. tostring(b.maxAmount)
            cache.n4.TextColor3 = b.isFull and SC.full or SC.dim
            if b.isFull then
                cache.row.BackgroundColor3 = SC.full:Lerp(SC.alt, 0.75)
                cache.ind.BackgroundColor3 = SC.full
                cache.ind.Visible = true
                cache.st.Text = "FULL"
                cache.st.TextColor3 = SC.full
                cache.st.TextSize = 9
            end
            if active[uid] then
                cache.row.BackgroundColor3 = SC.ok:Lerp(SC.alt, 0.75)
                cache.ind.BackgroundColor3 = SC.ok
                cache.ind.Visible = true
                cache.st.Text = "▶"
                cache.st.TextColor3 = SC.ok
                cache.st.TextSize = 11
            elseif queue[uid] then
                cache.row.BackgroundColor3 = SC.sel:Lerp(SC.alt, 0.7)
                cache.ind.BackgroundColor3 = SC.sel
                cache.ind.Visible = true
                cache.st.Text = "✓"
                cache.st.TextColor3 = SC.sel
                cache.st.TextSize = 11
            end
        end

        render = function()
            local q = string.lower(query)
            local order = 0
            local seen = {}
            local total, players = 0, 0
            local names = {}
            for n in pairs(scanned) do table.insert(names, n) end
            table.sort(names)

            for _, name in ipairs(names) do
                local info = scanned[name]
                local shown = 0
                for _, b in ipairs(info.baits) do
                    local match = (q == "")
                        or string.find(string.lower(name), q, 1, true)
                        or string.find(string.lower(b.type), q, 1, true)
                        or string.find(string.lower(b.uid), q, 1, true)
                    if match then
                        shown = shown + 1
                        order = order + 1
                        total = total + 1
                        seen[b.uid] = true
                        if not rowCache[b.uid] then
                            rowCache[b.uid] = createRow(order, name, b)
                        end
                        rowCache[b.uid].row.LayoutOrder = order
                        updateRowState(b.uid)
                    end
                end
                if shown > 0 then players = players + 1 end
            end
            for uid, cache in pairs(rowCache) do
                if not seen[uid] then
                    cache.row:Destroy()
                    rowCache[uid] = nil
                end
            end
            status.Text = string.format("Total: %d Bait | Player: %d | Queue: %d | Skipped: %d",
                total, players, countTable(queue), skipped)
        end

        startScanLoop = function()
            if scanThread then return end
            scanThread = task.spawn(function()
                while autoScan do
                    scanned = scan()
                    render()
                    task.wait(0)
                end
                scanThread = nil
            end)
        end

        stopScanLoop = function()
            if scanThread then
                pcall(task.cancel, scanThread)
                scanThread = nil
            end
        end

        table.insert(CloseHooks, function()
            isScoopRunning = false
            autoScan = false
            stopAll()
            stopScanLoop()
        end)

        scanned = scan()
        render()
    end

    BuildScoopTab(tabScoop)

    -- =============================================================
    --  TAB : BOOST & WEBHOOK
    -- =============================================================
    local function BuildBoostTab(tab)
        CreateSection(tab, "Performance")
        CreateToggle(tab, "Super FPS Boost", false, function(v)
            task.spawn(function()
                if v and not FPS_STATE.boosted then boostFPS()
                elseif not v and FPS_STATE.boosted then unboostFPS() end
            end)
        end)

        CreateToggle(tab, "Hide Fish", false, function(v)
            task.spawn(function()
                if v and not FPS_STATE.fishHidden then hideFish()
                elseif not v and FPS_STATE.fishHidden then showFish() end
            end)
        end)

        CreateSection(tab, "Discord Webhook")
        local WebhookInput = CreateTextBox(tab, "https://discord.com/api/webhooks/...", nil, WEBHOOK.url)
        WebhookInput.FocusLost:Connect(function()
            WEBHOOK.url = WebhookInput.Text
            if WebhookInput.Text:find("https://discord.com/api/webhooks/") then
                Notify("Webhook", "URL valid disimpan.", C.Success)
            else
                Notify("Webhook", "URL tidak valid!", C.Danger)
            end
        end)

        CreateToggle(tab, "Enable Webhook", true, function(v) WEBHOOK.enabled = v end)
        CreateToggle(tab, "TimeJumper Expiration Notification", true, function(v) WEBHOOK.notifyJumperEmpty = v end)

        CreateButton(tab, "🧪 Test Webhook", function()
            WEBHOOK.url = WebhookInput.Text
            if WEBHOOK.url == "" then
                Notify("Webhook", "URL is empty. Please paste the link first..", C.Danger)
                return
            end
            local embed = {
                title = "🧪 Webhook Test Successful",
                description = "The connection from Farm A fish is working well!",
                color = 0x00FF00,
                fields = {
                    { name = "👤 Player", value = tostring(getPlayerDisplayName()), inline = true },
                    { name = "⏱️ TimeJumper Remainder", value = tostring(getJumperCount()), inline = true },
                },
                footer = { text = "Farm A fish | by bang iqi" },
                timestamp = DateTime.now():ToIsoDate(),
            }
            sendWebhook({ username = WEBHOOK.username, embeds = { embed } })
            Notify("Webhook", "Test sent.", C.Accent)
        end)
    end

    BuildBoostTab(tabBoost)

    -- ------------------------------------------------------------
    -- MINIMIZE / CLOSE / DRAG
    -- ------------------------------------------------------------
    local origSize = UDim2.new(0, FULL_W, 0, FULL_H)
    local minimized = false
    local lastPos = UDim2.new(0.5, -FULL_W / 2, 0.5, -FULL_H / 2)
    local fpsConn

    local function doMinimize()
        minimized = true
        lastPos = Main.Position
        FpsLabel.Visible = false
        Body.Visible = false
        TweenService:Create(Main, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, MINI_W, 0, MINI_H),
            Position = UDim2.new(0, 16, 0, 16),
        }):Play()
        S.minimized = true
    end

    local function doRestore()
        minimized = false
        S.minimized = false
        Body.Visible = true
        FpsLabel.Visible = true
        TweenService:Create(Main, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = origSize,
            Position = lastPos,
        }):Play()
    end

    makeCtrl("-", -76, C.Sub, function()
        if minimized then doRestore() else doMinimize() end
    end)

    makeCtrl("X", -38, C.Danger, function()
        S.gOn, S.bOn, S.eOn, S.gdOn = false, false, false, false
        BCONFIG.FoodOn, BCONFIG.CraftOn = false, false
        B.isRunning = false
        stopAntiAfk()
        stopHWCollect()
        stopHWFeedPickup()
        for _, h in ipairs(CloseHooks) do pcall(h) end
        for _, c in ipairs(Conns) do pcall(function() c:Disconnect() end) end
        if fpsConn then pcall(function() fpsConn:Disconnect() end) end
        TweenService:Create(Main, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
            Size = UDim2.new(0, 0, 0, 0),
            Position = UDim2.new(0.5, 0, 0.5, 0),
        }):Play()
        task.delay(0.3, function() ScreenGui:Destroy() end)
    end)

    local dragging, dragStart, startPos
    local function isPress(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end
    local function isMove(i)
        return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
    end
    TopBar.InputBegan:Connect(function(i)
        if isPress(i) and not minimized then
            dragging = true
            dragStart = i.Position
            startPos = Main.Position
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and isMove(i) then
            local d = i.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(i)
        if isPress(i) then dragging = false end
    end))

    local frameCount, fpsAccum, lastFpsUpdate = 0, 0, os.clock()
    fpsConn = RunService.RenderStepped:Connect(function(dt)
        frameCount += 1
        fpsAccum += dt
        local now = os.clock()
        if now - lastFpsUpdate >= 0.5 then
            local fps = math.floor(frameCount / fpsAccum + 0.5)
            local col
            if fps >= 50 then col = Color3.fromRGB(120, 255, 120)
            elseif fps >= 30 then col = Color3.fromRGB(255, 220, 100)
            else col = Color3.fromRGB(255, 100, 100) end

            pcall(function()
                FpsLabel.Text = tostring(fps)
                FpsLabel.TextColor3 = col
            end)

            frameCount = 0
            fpsAccum = 0
            lastFpsUpdate = now
        end
    end)

    task.spawn(function()
        while ScreenGui.Parent do
            task.wait(1)
            tickScheduler()

            if startToggle.Get() and not B.isRunning then
                startToggle.Set(false)
            end
        end
    end)

    TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = origSize,
        Position = UDim2.new(0.5, -FULL_W / 2, 0.5, -FULL_H / 2),
    }):Play()

    SelectTab(T_AUTO)
    task.delay(0.6, function()
        Notify("Welcome!", "Farm A Fish loaded ✨", C.Success)
    end)
end

BuildGUI()