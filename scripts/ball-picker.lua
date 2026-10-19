-- Ball Picker: Rayfield Gen2 pickup and basket selling.
-- Run in Real. Re-running replaces the previous GUI and worker.
local env = getgenv()
local previous = env.GolfBallPicker
local resumeRunning = previous and previous.running == true
local resumeAutoUpgrade = previous and previous.autoUpgrade == true
if previous and previous.Stop then previous.Stop() end
local player = game:GetService("Players").LocalPlayer
local controllers = player.PlayerScripts.Client.Controllers
local run = require(controllers:WaitForChild("RunStateController") :: any)
local arrows = require(controllers:WaitForChild("TutorialArrowController") :: any)
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
local window = Rayfield:CreateWindow({
    name = "Golf Ball Picker", subtitle = "Collect & sell", sidebarLayout = true,
})
local app = {running = false, autoSell = true, alive = true, sellRequested = false, autoUpgrade = false,
    upgradeStatus = "Backpack upgrades off",
    status = "Ready", picked = 0, sold = 0, earned = 0, failures = 0}
env.GolfBallPicker = app
local function active()
    return app.alive and not window.unloaded
end
local function rootPart()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then return root end
    return nil
end
local function pause(seconds)
    local deadline = os.clock() + seconds
    repeat task.wait() until not active() or os.clock() >= deadline
end
function app.Stop()
    app.running = false
    app.alive = false
    if not window.unloaded then window:Unload() end
end
local main = window:CreateTab({name = "Collect & sell"})
local pickupToggle = main:CreateToggle({
    name = "Auto pickup", value = false,
    description = "Uses your equipped tool at its server-controlled collection rate.",
    callback = function(value) app.running = value; app.failures = 0 end,
})
main:CreateToggle({
    name = "Auto sell", value = true,
    description = "Visits the basket when full, then resumes. Sells the last bag too.",
    callback = function(value) app.autoSell = value end,
})
local upgradeToggle = main:CreateToggle({
    name = "Auto upgrade backpack", value = false,
    description = "Spends earned coins on Bag Capacity whenever affordable.",
    callback = function(value)
        app.autoUpgrade = value
        app.upgradeStatus = value and "Checking backpack upgrade" or "Backpack upgrades off"
    end,
})
function app.SetAutoUpgrade(value)
    app.autoUpgrade = value
    upgradeToggle:Set(value, true)
    app.upgradeStatus = value and "Checking backpack upgrade" or "Backpack upgrades off"
end
main:CreateButton({name = "Sell bag now", callback = function() app.sellRequested = true end})
main:CreateButton({name = "Stop", callback = function()
    app.running = false; app.sellRequested = false; pickupToggle:Set(false, true)
    app.SetAutoUpgrade(false)
    app.status = "Stopped"
end})
local display = main:CreateConsole({name = "Live status", height = 130, text = "Ready"})
main:CreateButton({name = "Close & stop", callback = function() app.Stop() end})
local blocked = setmetatable({}, {__mode = "k"})
local function nearestBall(root)
    local folder = workspace:FindFirstChild("Balls")
    local best, distance = nil, math.huge
    if not folder then return nil end
    for _, ball in ipairs(folder:GetChildren()) do
        if ball:IsA("BasePart") and typeof(ball:GetAttribute("Id")) == "number"
            and not ball:GetAttribute("FxHeld") and not ball:GetAttribute("SweptBy")
            and (blocked[ball] or 0) < os.clock() then
            local d = (root.Position - ball.Position).Magnitude
            if d < distance then best = ball; distance = d end
        end
    end
    return best
end
local function sell(root)
    if (run.State.held or 0) == 0 then return end
    local basket = arrows.NearestBasket(root.Position)
    local trigger = basket and basket.Parent:FindFirstChild("Trigger")
    if not trigger or not trigger:IsA("BasePart") then
        app.status = "No basket trigger available"
        app.running = false
        pickupToggle:Set(false, true)
        return
    end
    local original = root.CFrame
    app.status = "Selling at basket"
    root.CFrame = trigger.CFrame
    root.AssemblyLinearVelocity = Vector3.zero
    local deadline = os.clock() + 6
    repeat task.wait() until not active() or (run.State.held or 0) == 0 or os.clock() >= deadline
    if active() and root == rootPart() and not app.running then root.CFrame = original end
    if (run.State.held or 0) > 0 then
        app.running = false; pickupToggle:Set(false, true)
        app.status = "Sale not confirmed; stopped"
    else app.status = "Bag sold" end
end
local runService = game:GetService("RunService")
local heartbeat = runService.Heartbeat
local walkDirection = Vector3.zero
local walkBinding = "GolfBallPickerWalk_" .. game:GetService("HttpService"):GenerateGUID(false)
local vehicleControl = {seat = nil, throttle = 0, steer = 0, driving = false, lastSend = -math.huge}
local function stopCart()
    local seat = vehicleControl.seat
    if seat and seat.Parent then
        seat.ThrottleFloat = 0
        seat.SteerFloat = 0
        if vehicleControl.driving and os.clock()-vehicleControl.lastSend>=0.15 then
            remotes.CartInput:FireServer(0,0,false)
            vehicleControl.lastSend=os.clock()
        end
    end
    vehicleControl.driving = false
    vehicleControl.seat = nil
end
runService:BindToRenderStep(walkBinding, Enum.RenderPriority.Last.Value + 1, function()
    if active() and (app.running or app.sellRequested) and vehicleControl.driving then
        local seat = vehicleControl.seat
        if seat and seat.Parent then
            seat.ThrottleFloat = vehicleControl.throttle
            seat.SteerFloat = vehicleControl.steer
            if os.clock()-vehicleControl.lastSend >= 0.15 then
                remotes.CartInput:FireServer(vehicleControl.throttle,vehicleControl.steer,false)
                vehicleControl.lastSend = os.clock()
            end
        end
    end
    if active() and app.running and run.State.toolId == "Sweeper" then
        local root = rootPart()
        local h = root and root.Parent:FindFirstChildOfClass("Humanoid")
        if h then h:Move(walkDirection, false) end
    end
end)
local tuning = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning") :: any)
local economy = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Economy") :: any)
local difficulty = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Difficulty") :: any)

-- Shop prices and ownership come from the game's own catalogue.
local config = game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local store = require(config:WaitForChild("Store") :: any)
local tractor = require(config:WaitForChild("Tractor") :: any)
local unlocks = require(config:WaitForChild("Unlocks") :: any)
local marketplace = game:GetService("MarketplaceService")
local shopTab = window:CreateTab({name = "Tools & vehicles"})
local premiumTab = window:CreateTab({name = "Robux offers"})
local shopDisplay
local premiumDisplay
local shopStatus = shopTab:CreateConsole({name = "Shop status", height = 55, text = "Choose an item below."})
app.shopBusy = false
local premiumIds = {"VoidGun", "VoidGunRun", "CartV12", "Tractor", "TractorRun"}
local robuxPrices = {}
local function numberText(value)
    return (tostring(math.floor(value)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function tellShop(message)
    if active() then
        shopStatus:Set(message)
        window:Notify({title = "Shop", content = message})
    end
end
local function ownsOffer(item)
    if item.unlock and unlocks.owns(run.Profile or {}, item.unlock) then return true end
    if item.runTool and run.State.ownedTools[item.runTool] then return true end
    if item.runTractor then
        return player:GetAttribute("TractorTier") == "Run" or tractor.tier(run.Profile or {}) == "Full"
    end
    return false
end
function app.ShopCatalogue()
    local list = {}
    for _, id in ipairs(economy.ToolOrder) do
        local tool = economy.getTool(id)
        if tool and not tool.robuxOnly then
            list[#list+1] = {id = id, name = tool.displayName,
                price = difficulty.priceAt(run.State.difficultyId, tool.cost),
                currency = "coins", owned = run.State.ownedTools[id] == true}
        end
    end
    list[#list+1] = {id = "RoboVehicle", name = "Robo Vehicle", price = tractor.GEM_PRICE,
        currency = "gems", owned = tractor.tier(run.Profile or {}) ~= nil}
    for _, id in ipairs(premiumIds) do
        local item = store.get(id)
        if item then
            list[#list+1] = {id = id, name = item.displayName, price = robuxPrices[id] or item.robux,
                currency = "Robux", listed = robuxPrices[id] == nil, owned = ownsOffer(item)}
        end
    end
    return list
end
function app.ShopPremium(id)
    local item = store.get(id)
    if not item or not store.isReady(item) then tellShop("This offer is not available yet."); return end
    if ownsOffer(item) then tellShop("You already own " .. item.displayName); return end
    if item.unlock then
        local unlock = unlocks.get(item.unlock)
        if unlock and not unlocks.available(unlock, run.Profile or {}) then
            tellShop("This unlock is not available yet.")
            return
        end
    end
    if item.kind == "Pass" then marketplace:PromptGamePassPurchase(player, item.assetId)
    else marketplace:PromptProductPurchase(player, item.assetId) end
end
local function buyCoin(id, equip)
    local tool = economy.getTool(id)
    if not tool then return false, "Unknown item" end
    if run.State.ownedTools[id] then
        if equip then remotes.ToolEquip:FireServer(id) end
        return true, "Already owned: " .. tool.displayName
    end
    if tool.robuxOnly then return false, "Use the Robux offers tab for " .. tool.displayName end
    local price = difficulty.priceAt(run.State.difficultyId, tool.cost)
    if (run.State.money or 0) < price then
        return false, tool.displayName .. " needs " .. numberText(price) .. " coins"
    end
    local purchased, reason = remotes.BuyTool:InvokeServer(id)
    if not purchased then
        return false, tool.displayName .. ": " .. tostring(reason or purchased or "purchase refused")
    end
    local deadline = os.clock() + 1
    repeat task.wait() until not active() or run.State.ownedTools[id] or os.clock() >= deadline
    if active() and equip then remotes.ToolEquip:FireServer(id) end
    return true, "Bought " .. tool.displayName
end
function app.ShopBuy(id, equip)
    if app.shopBusy then return false, "Another purchase is in progress" end
    app.shopBusy = true
    local ok, bought, message = pcall(buyCoin, id, equip ~= false)
    app.shopBusy = false
    if not ok then message = "Purchase failed: " .. tostring(bought); bought = false end
    tellShop(message)
    return bought, message
end
shopTab:CreateButton({
    name = "Buy all affordable items (coins)",
    description = "Buys missing tools and golf carts, cheapest first. Uses coins only.",
    callback = function()
        if app.shopBusy then return end
        app.shopBusy = true
        task.spawn(function()
            local bought = 0
            local ok, err = pcall(function()
                local items = {}
                for _, id in ipairs(economy.ToolOrder) do
                    local tool = economy.getTool(id)
                    if tool and not tool.robuxOnly and not run.State.ownedTools[id] then
                        items[#items+1] = tool
                    end
                end
                table.sort(items, function(a, b) return a.cost < b.cost end)
                for _, tool in ipairs(items) do
                    if not active() then break end
                    local success = buyCoin(tool.id, false)
                    if success then bought += 1 end
                    pause(0.3)
                end
            end)
            app.shopBusy = false
            if not ok then tellShop("Stopped: " .. tostring(err))
            else tellShop("Bought " .. bought .. " affordable items.") end
        end)
    end,
})
for _, id in ipairs(economy.ToolOrder) do
    local tool = economy.getTool(id)
    if tool and not tool.robuxOnly then
        local itemId = id
        local price = difficulty.priceAt(run.State.difficultyId, tool.cost)
        shopTab:CreateButton({
            name = tool.displayName .. " | " .. numberText(price) .. " coins | Buy / equip",
            description = tool.description,
            callback = function() app.ShopBuy(itemId, true) end,
        })
    end
end
shopTab:CreateButton({
    name = "Robo Vehicle | " .. numberText(tractor.GEM_PRICE) .. " gems | Buy",
    description = "Permanent gem purchase. The Robo Vehicle collects and deposits for you.",
    callback = function()
        if app.shopBusy then return end
        if tractor.tier(run.Profile or {}) then tellShop("You already own the Robo Vehicle."); return end
        if (run.Profile.gems or 0) < tractor.GEM_PRICE then tellShop("Not enough gems for the Robo Vehicle."); return end
        app.shopBusy = true
        local ok, bought, reason = pcall(function() return remotes.TractorBuy:InvokeServer() end)
        app.shopBusy = false
        if ok and bought then tellShop("Bought Robo Vehicle.")
        else tellShop("Robo Vehicle: " .. tostring(reason or bought)) end
    end,
})
shopTab:CreateButton({
    name = "Activate / park owned Robo Vehicle",
    callback = function()
        if tractor.tier(run.Profile or {}) or player:GetAttribute("TractorTier") == "Run" then
            remotes.TractorToggle:FireServer()
        else tellShop("Buy a Robo Vehicle first.") end
    end,
})
for _, id in ipairs(premiumIds) do
    local itemId = id
    local item = store.get(id)
    if item then
        premiumTab:CreateButton({
            name = item.displayName .. " | " .. numberText(item.robux) .. " Robux listed",
            description = item.description .. " Opens Roblox's purchase confirmation.",
            callback = function() app.ShopPremium(itemId) end,
        })
        task.spawn(function()
            local ok, info = pcall(function()
                return marketplace:GetProductInfo(item.assetId,
                    item.kind == "Pass" and Enum.InfoType.GamePass or Enum.InfoType.Product)
            end)
            if ok and info and typeof(info.PriceInRobux) == "number" then robuxPrices[itemId] = info.PriceInRobux end
        end)
    end
end
shopDisplay = shopTab:CreateConsole({name = "Prices & ownership", height = 180})
premiumDisplay = premiumTab:CreateConsole({name = "Live Robux prices", height = 150})
function app.ShowShop(premium)
    if premium then premiumTab:Select() else shopTab:Select() end
end
task.spawn(function()
    while active() do
        local coins = {"Balance: " .. numberText(run.State.money or 0) .. " coins | " ..
            numberText((run.Profile or {}).gems or 0) .. " gems"}
        local premium = {"Current prices (listed if lookup unavailable). Roblox confirms the final price."}
        for _, row in ipairs(app.ShopCatalogue()) do
            local text = row.name .. " | " .. numberText(row.price) .. " " .. row.currency ..
                (row.listed and " listed" or "") .. (row.owned and " | OWNED" or "")
            if row.currency == "Robux" then premium[#premium+1] = text else coins[#coins+1] = text end
        end
        shopDisplay:Set(table.concat(coins, "\n"))
        premiumDisplay:Set(table.concat(premium, "\n"))
        pause(1)
    end
end)

task.spawn(function()
    while active() do
        if app.autoUpgrade and run.State.phase == "Running" then
            local ok, err = pcall(function()
                local s = run.State
                local upgrade = economy.getUpgrade("Capacity")
                local level = s.upgrades.Capacity or 0
                if not economy.isEndless(upgrade) and level >= upgrade.maxLevel then
                    app.upgradeStatus = "Backpack fully upgraded"
                    return
                end
                local price = difficulty.priceAt(s.difficultyId, economy.costAt(upgrade.cost, level))
                app.upgradeStatus = string.format("Backpack Lv.%d | Next: %d coins", level, price)
                if (s.money or 0) < price then return end
                if not active() or not app.autoUpgrade then return end
                local purchased, reason = remotes.BuyUpgrade:InvokeServer("Capacity", 1)
                if not active() then return end
                if purchased then
                    app.upgradeStatus = "Backpack upgraded"
                    local deadline = os.clock() + 2
                    repeat task.wait() until not active() or not app.autoUpgrade
                        or (run.State.upgrades.Capacity or 0) > level or os.clock() >= deadline
                else
                    app.upgradeStatus = "Upgrade waiting: " .. tostring(reason)
                    pause(1)
                end
            end)
            if not ok then
                app.SetAutoUpgrade(false)
                app.upgradeStatus = "Upgrade stopped: " .. tostring(err)
            end
        end
        pause(0.5)
    end
end)
local collection = game:GetService("CollectionService")
local target = nil
local toolMode = nil
local lastHand = -math.huge
local lastVoid = -math.huge
local settleUntil = 0
local targetSince = 0
local toolStarted = nil
local backoff = 0.01
local voidReady = 0
local connections = {}
local lastTotal = run.State.totalBalls or 0
local lastMoney = run.State.money or 0
local lastHeld = run.State.held or 0
local function input(action, point, direction)
    remotes.ToolInput:FireServer(action, point, direction)
end
local function releaseTool()
    stopCart()
    walkDirection = Vector3.zero
    if toolStarted == "Vacuum" then input("VacuumStop")
    elseif toolStarted == "Picker" then input("PickStop")
    elseif toolStarted == "Sweeper" then input("SweepStop") end
    toolStarted = nil
    local root = rootPart()
    if root then
        local h = root.Parent:FindFirstChildOfClass("Humanoid")
        if h then h:Move(Vector3.zero) end
        root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
    end
end
connections[#connections+1] = remotes.VoidFx.OnClientEvent:Connect(function(kind, ready)
    if kind == "cooldown" and typeof(ready) == "number" then voidReady = ready end
end)
connections[#connections+1] = remotes.PickupResult.OnClientEvent:Connect(function(ok, _count, _data, reason)
    if run.State.toolId == "Hand" and app.running then
        if ok then backoff = math.max(0.01, backoff - 0.001)
        elseif typeof(reason) == "string" and string.find(string.lower(reason), "cooldown") then
            backoff = math.min(0.1, backoff + 0.01)
        end
    end
end)
local oldStop = app.Stop
app.Stop = function()
    app.autoUpgrade = false
    runService:UnbindFromRenderStep(walkBinding)
    for _, connection in ipairs(connections) do connection:Disconnect() end
    releaseTool()
    oldStop()
end
function app.SetRunning(value)
    app.running = value
    pickupToggle:Set(value, true)
    if not value then releaseTool() end
end
local function holeNear(position)
    local map = workspace:FindFirstChild("Map")
    local yards = map and map:FindFirstChild("Yards")
    local best, distance = nil, math.huge
    if not yards then return nil end
    for _, model in ipairs(yards:GetDescendants()) do
        if model:IsA("Model") then
            local index = tonumber(string.match(model.Name, "^Yard(%d+)_Hole%d+$"))
            if index and (not run.State.fields[index] or run.State.fields[index].unlocked) then
                local trigger = model:FindFirstChild("Trigger")
                if trigger and trigger:IsA("BasePart") then
                    local d = (trigger.Position - position).Magnitude
                    if d < distance then best = trigger; distance = d end
                end
            end
        end
    end
    return best
end
local function flatDirection(from, to)
    local d = (to - from) * Vector3.new(1, 0, 1)
    return d.Magnitude > 0.05 and d.Unit or Vector3.new(0, 0, -1)
end
local function groundHeight(root, ball)
    local h = root.Parent:FindFirstChildOfClass("Humanoid")
    local height = h and h.HipHeight + root.Size.Y / 2 or 3
    if h and h.RigType == Enum.HumanoidRigType.R6 then height += 2 end
    return ball.Position.Y - tuning.Physics.BALL_RADIUS + height
end
local function moveFront(root, ball, forward)
    local direction = flatDirection(root.Position, ball.Position)
    local p = ball.Position - direction * forward
    p = Vector3.new(p.X, groundHeight(root, ball), p.Z)
    root.CFrame = CFrame.lookAt(p, p + direction)
    return direction
end
local function startTool(id)
    if toolStarted == id then return end
    releaseTool()
    if id == "Vacuum" then input("VacuumStart")
    elseif id == "Picker" then input("PickStart")
    elseif id == "Sweeper" then input("SweepStart") end
    toolStarted = id
end
local gatherBall = nil
local function sweep(root, ball, _dt)
    local swept = {}
    for _, part in ipairs(collection:GetTagged("SweptBall")) do
        if part:IsA("BasePart") and part:GetAttribute("SweptBy") == player.UserId then
            table.insert(swept, part)
        end
    end
    local hole = holeNear(root.Position)
    if not hole then app.status = "Sweeper needs an unlocked money hole"; return end
    if #swept == 0 then
        local direction = flatDirection(ball.Position, hole.Position)
        local p = root.Position
        if gatherBall ~= ball then
            p = ball.Position - direction * (tuning.Tools.SWEEP_FORWARD + 2)
            p = Vector3.new(p.X, groundHeight(root, ball), p.Z)
            gatherBall = ball
        end
        root.CFrame = CFrame.lookAt(p, p + direction)
        local h = root.Parent:FindFirstChildOfClass("Humanoid")
        walkDirection = direction
        if h then h:Move(direction, false) end
        root.AssemblyLinearVelocity = direction * math.min(16, tuning.Tools.SWEEP_MAX_SPEED)
        app.status = "Sweeper: gathering balls"
    else
        gatherBall = nil
        local direction = flatDirection(root.Position, hole.Position)
        -- Stay with the carried balls; sweep physics owns their movement.
        local distance = ((hole.Position - root.Position) * Vector3.new(1,0,1)).Magnitude
        local speed = math.min(16, tuning.Tools.SWEEP_MAX_SPEED)
        local p = root.Position
        root.CFrame = CFrame.lookAt(p, p + direction)
        root.AssemblyLinearVelocity = direction * speed
        local h = root.Parent:FindFirstChildOfClass("Humanoid")
        walkDirection = direction
        if h then h:Move(direction, false) end
        app.status = "Sweeper: taking " .. #swept .. " balls to money hole"
        if distance < tuning.Tools.SWEEP_FORWARD + 0.5 then
            input("SweepStop")
            toolStarted = nil
        end
    end
end

local cartVariants = require(config:WaitForChild("CartVariants") :: any)
app.autoBoard = true
app.fastCartHops = true
app.cartUnloadAt = 0.9
app.autoRobo = true
app.vehicleStatus = "Ready"
local vehicleTab = window:CreateTab({name = "Vehicle controls"})
vehicleTab:CreateToggle({name = "Auto board owned cart", value = true,
    callback = function(v) app.autoBoard = v end})
vehicleTab:CreateToggle({name = "Fast cart hops", value = true,
    description = "Repositions the whole cart for clear collection passes and unloading.",
    callback = function(v) app.fastCartHops = v end})
vehicleTab:CreateSlider({name = "Unload cart at", range = {50,100}, increment = 5, value = 90, suffix = "%",
    callback = function(v) app.cartUnloadAt = v/100 end})
vehicleTab:CreateToggle({name = "Auto deploy owned Robo Vehicle", value = true,
    description = "Uses the Robo Vehicle's own collection and unloading route.",
    callback = function(v) app.autoRobo = v end})
local vehicleDisplay = vehicleTab:CreateConsole({name = "Vehicle status", height = 100})
function app.ShowVehicles() vehicleTab:Select() end
local driveGoal = nil
local driveDirection = nil
local driveStarted = 0
local lastBoard = 0
local lastRecover = -math.huge
local lastHop = -math.huge
local lastMovePosition = nil
local lastMoveAt = 0
local cartUnloadStarted = nil
local lastUnloadHeld = nil
local unloadProgressAt = 0
local cartIgnore = {}
local cartOverlap = OverlapParams.new()
cartOverlap.FilterType = Enum.RaycastFilterType.Include
cartOverlap.MaxParts = 1500
local roadRay = RaycastParams.new()
roadRay.FilterType = Enum.RaycastFilterType.Include
roadRay.RespectCanCollide = true
roadRay.IgnoreWater = true
local function refreshRoadFilter()
    local map = workspace:FindFirstChild("Map")
    roadRay.FilterDescendantsInstances = map and {map, workspace.Terrain} or {workspace.Terrain}
end
refreshRoadFilter()
local function currentCart()
    local character = player.Character
    local h = character and character:FindFirstChildOfClass("Humanoid")
    local seat = h and h.SeatPart
    local folder = workspace:FindFirstChild("Carts")
    if seat and seat:IsA("VehicleSeat") and seat.Parent and seat.Parent.Parent == folder
        and seat.Parent:GetAttribute("Owner") == player.UserId then return seat.Parent, seat end
    return nil, nil
end
local function ownedCart()
    local folder = workspace:FindFirstChild("Carts")
    if not folder then return nil, nil end
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute("Owner") == player.UserId
            and model:GetAttribute("Active") ~= false then
            local seat = model:FindFirstChild("DriverSeat", true)
            if seat and seat:IsA("VehicleSeat") then return model, seat end
        end
    end
    return nil, nil
end
local function collector(model)
    local part = model:FindFirstChild("RollerCore", true)
    if part and part:IsA("BasePart") then return part end
    return model.PrimaryPart
end
local function setDrive(seat, throttle, steer)
    vehicleControl.seat = seat
    vehicleControl.throttle = throttle
    vehicleControl.steer = steer
    vehicleControl.driving = true
end
local function clearPass()
    driveGoal = nil
    driveDirection = nil
end
local function hopCart(model, point, direction, rollerAtPoint)
    local roll = collector(model)
    if not roll then return false end
    local pivot = model:GetPivot()
    local localRoll = pivot:PointToObjectSpace(roll.Position)
    local rotation = CFrame.lookAt(Vector3.zero, direction)
    local rollerPosition = point + Vector3.new(0, math.max(0.5, model:GetAttribute("RollerRadius") or 1.05)-tuning.Physics.BALL_RADIUS, 0)
    if not rollerAtPoint then rollerPosition -= direction*18 end
    local newPivot = CFrame.new(rollerPosition - rotation:VectorToWorldSpace(localRoll))*rotation
    model:PivotTo(newPivot)
    local primary = model.PrimaryPart
    if primary then
        primary.AssemblyLinearVelocity = Vector3.zero
        primary.AssemblyAngularVelocity = Vector3.zero
    end
    lastHop = os.clock()
    lastMovePosition = model:GetPivot().Position
    lastMoveAt = os.clock()
    return true
end
local function rayClearance(origin, direction, distance)
    local hit = workspace:Raycast(origin, direction*distance, roadRay)
    return hit and hit.Distance or distance
end
local function safePassDirection(point, forward, width)
    local best, bestScore, bestLength = nil, -math.huge, 0
    local start = point + Vector3.new(0,2,0)
    for i=0,7 do
        local angle = i*math.pi/4
        local direction = CFrame.Angles(0,angle,0):VectorToWorldSpace(forward)
        local right = direction:Cross(Vector3.yAxis)
        local back, ahead = 22, 42
        for _, side in ipairs({-width/2,0,width/2}) do
            local origin = start + right*side
            back = math.min(back, rayClearance(origin,-direction,22))
            ahead = math.min(ahead, rayClearance(origin,direction,42))
        end
        local score = math.min(back,22)+math.min(ahead,42)+direction:Dot(forward)*3
        if back>20 and ahead>10 and score>bestScore then
            best = direction
            bestScore = score
            bestLength = math.max(8,math.min(32,ahead-8))
        end
    end
    return best,bestLength
end
local function choosePass(model, seat)
    local folder = workspace:FindFirstChild("Balls")
    local roll = collector(model)
    if not folder or not roll then return nil end
    cartOverlap.FilterDescendantsInstances = {folder}
    local candidates = workspace:GetPartBoundsInRadius(roll.Position,130,cartOverlap)
    if #candidates==0 then candidates=folder:GetChildren() end
    local cells = {}
    for _, ball in ipairs(candidates) do
        if ball:IsA("BasePart") and typeof(ball:GetAttribute("Id"))=="number"
            and not ball:GetAttribute("SweptBy") and not ball:GetAttribute("FxHeld") then
            local key = math.floor(ball.Position.X/24)..":"..math.floor(ball.Position.Z/24)
            if (cartIgnore[key] or 0)<os.clock() then
                local cell = cells[key]
                if not cell then cell={count=0,sum=Vector3.zero,key=key}; cells[key]=cell end
                cell.count += 1
                cell.sum += ball.Position
            end
        end
    end
    local ranked = {}
    for _,cell in pairs(cells) do
        cell.point=cell.sum/cell.count
        local distance=(cell.point-roll.Position).Magnitude
        local direction=flatDirection(roll.Position,cell.point)
        cell.score=cell.count/(1+distance/60)*(0.8+0.2*math.max(0,seat.CFrame.LookVector:Dot(direction)))
        ranked[#ranked+1]=cell
    end
    table.sort(ranked,function(a,b) return a.score>b.score end)
    for i=1,math.min(12,#ranked) do
        local cell=ranked[i]
        local direction,length=safePassDirection(cell.point,flatDirection(roll.Position,cell.point),
            math.min(14,model:GetAttribute("RollerWidth") or 12))
        if direction then return cell,direction,length end
        cartIgnore[cell.key]=os.clock()+6
    end
    return nil
end
local function cartSell(model, seat)
    stopCart()
    local roll=collector(model)
    local basket=arrows.NearestBasket(seat.Position)
    if not basket or not roll then
        app.vehicleStatus="No sell basket available"
        return
    end
    if not cartUnloadStarted then
        cartUnloadStarted=os.clock()
        lastUnloadHeld=run.State.held or 0
        unloadProgressAt=os.clock()
        local away=flatDirection(basket.Position,seat.Position)
        local groundPoint=basket.Position+away*12
        local ground=workspace:Raycast(groundPoint+Vector3.new(0,20,0),Vector3.new(0,-60,0),roadRay)
        groundPoint=Vector3.new(groundPoint.X,ground and ground.Position.Y or 0,groundPoint.Z)
        hopCart(model,groundPoint,-away,true)
        clearPass()
    end
    setDrive(seat,0,0)
    app.vehicleStatus="Cart: unloading "..(run.State.held or 0).." balls"
    local held=run.State.held or 0
    if held<lastUnloadHeld then lastUnloadHeld=held; unloadProgressAt=os.clock() end
    if held==0 then
        cartUnloadStarted=nil
        app.sellRequested=false
        clearPass()
        app.vehicleStatus="Cart emptied"
    elseif os.clock()-unloadProgressAt>4 then
        cartUnloadStarted=nil
        app.running=false
        pickupToggle:Set(false,true)
        app.vehicleStatus="Cart sale not confirmed; stopped safely"
    end
end
local function cartStep(root)
    local model,seat=currentCart()
    if not model then
        stopCart()
        clearPass()
        if app.autoBoard and os.clock()-lastBoard>1 then
            model,seat=ownedCart()
            local h=root.Parent:FindFirstChildOfClass("Humanoid")
            if seat and h and not seat.Occupant then
                lastBoard=os.clock()
                root.CFrame=seat.CFrame+Vector3.new(0,2,0)
                seat:Sit(h)
            end
        end
        app.vehicleStatus="Boarding your cart"
        return
    end
    local roll=collector(model)
    if not roll then stopCart(); return end
    local held=run.State.held or 0
    local capacity=run.State.capacity or tuning.Tools.CART_CAPACITY
    if cartUnloadStarted or app.sellRequested or (held>=capacity*app.cartUnloadAt and app.autoSell) then
        cartSell(model,seat)
        return
    end
    if held>=capacity then stopCart(); app.vehicleStatus="Cart full; enable Auto sell"; return end
    local position=roll.Position
    if model:GetPivot().UpVector.Y<0.5 then
        stopCart()
        if os.clock()-lastRecover>3 then remotes.CartRecover:FireServer(); lastRecover=os.clock(); clearPass() end
        app.vehicleStatus="Recovering overturned cart"
        return
    end
    local speed=(seat.AssemblyLinearVelocity*Vector3.new(1,0,1)).Magnitude
    local heading=flatDirection(Vector3.zero,seat.CFrame.LookVector)
    local brakingDistance=math.clamp(speed*speed/(2*math.max(1,tuning.Tools.CART_BRAKE))+8,12,30)
    local front=position+Vector3.new(0,1.2,0)
    local width=math.min(12,model:GetAttribute("RollerWidth") or 12)
    local right=heading:Cross(Vector3.yAxis)
    local ahead=brakingDistance
    for _,side in ipairs({-width/2,0,width/2}) do
        ahead=math.min(ahead,rayClearance(front+right*side,heading,brakingDistance))
    end
    local blockedRoad=ahead<brakingDistance-0.5
    if blockedRoad then
        stopCart()
        clearPass()
        if not app.fastCartHops then
            setDrive(seat,-0.45,1)
            app.vehicleStatus="Wall detected: backing away"
            return
        end
        app.vehicleStatus="Wall detected: choosing a clear pass"
        if os.clock()-lastHop<0.4 then return end
    end
    if lastMovePosition and os.clock()-lastMoveAt>2.5 then
        if (seat.Position-lastMovePosition).Magnitude<3 then
            stopCart()
            clearPass()
            if not app.fastCartHops then setDrive(seat,-0.5,-1); lastMoveAt=os.clock(); return end
        end
        lastMovePosition=seat.Position
        lastMoveAt=os.clock()
    elseif not lastMovePosition then lastMovePosition=seat.Position; lastMoveAt=os.clock() end
    if driveGoal then
        local delta=driveGoal-position
        if delta.Magnitude<8 or delta:Dot(driveDirection)<0 or os.clock()-driveStarted>5 then clearPass() end
    end
    if not driveGoal then
        local cell,direction,length=choosePass(model,seat)
        if not cell then
            stopCart()
            if held>0 and app.autoSell then cartSell(model,seat)
            else app.vehicleStatus="No reachable ball clusters"; pause(0.3) end
            return
        end
        if app.fastCartHops and os.clock()-lastHop>0.35 then
            hopCart(model,cell.point,direction,false)
        end
        driveDirection=direction
        driveGoal=cell.point+direction*length
        driveStarted=os.clock()
        cartIgnore[cell.key]=os.clock()+3
        position=roll.Position
    end
    local direction=flatDirection(position,driveGoal)
    local localDirection=seat.CFrame:VectorToObjectSpace(direction)
    local angle=math.atan2(localDirection.X,-localDirection.Z)
    local steer=math.clamp(angle*1.8,-1,1)
    local throttle=math.abs(angle)>0.9 and 0.35 or 1
    if blockedRoad and not app.fastCartHops then throttle=-0.45 end
    setDrive(seat,throttle,steer)
    app.vehicleStatus=cartVariants.ofModel(model).displayName..": collecting | "..math.floor(speed)..
        " studs/s | "..held.."/"..capacity
end
task.spawn(function()
    local lastRoboTry=-math.huge
    while active() do
        if app.autoRobo and app.running and run.State.phase=="Running" then
            local tier=tractor.tier(run.Profile or {}) or player:GetAttribute("TractorTier")
            if tier then
                local folder=workspace:FindFirstChild("Tractors")
                local robot=folder and folder:FindFirstChild("Tractor_"..player.UserId)
                if not robot and os.clock()-lastRoboTry>10 then
                    remotes.TractorToggle:FireServer()
                    lastRoboTry=os.clock()
                end
            end
        end
        local folder=workspace:FindFirstChild("Tractors")
        local robot=folder and folder:FindFirstChild("Tractor_"..player.UserId)
        local robotText=robot and ("\nRobo Vehicle: "..tostring(robot:GetAttribute("State")).." | "..
            tostring(robot:GetAttribute("Held") or 0).."/"..tostring(robot:GetAttribute("Cap") or 0)) or ""
        vehicleDisplay:Set(app.vehicleStatus..robotText)
        pause(0.5)
    end
end)

task.spawn(function()
    while active() do
        heartbeat:Wait()
        local ok, err = pcall(function()
            local s = run.State
            local total = s.totalBalls or 0
            app.picked += math.max(0, total - lastTotal)
            lastTotal = total
            local held = s.held or 0
            if held < lastHeld and (s.money or 0) > lastMoney then app.sold += lastHeld - held end
            app.earned += math.max(0, (s.money or 0) - lastMoney)
            lastHeld = held
            lastMoney = s.money or 0
            local root = rootPart()
            if not root then releaseTool(); app.status = "Waiting for character"; return end
            if s.phase ~= "Running" then releaseTool(); app.status = "Waiting for a running round"; return end
            if s.toolId ~= toolMode then
                releaseTool()
                toolMode = s.toolId
                target = nil
            end
            if cartVariants.isCart(s.toolId) or currentCart() then
                if app.running or app.sellRequested then cartStep(root) else stopCart() end
                app.status = app.vehicleStatus
                return
            end
            if app.sellRequested then
                app.sellRequested = false
                releaseTool()
                sell(root)
                return
            end
            if not app.running then releaseTool(); return end
            if held >= (s.capacity or 1) then
                releaseTool()
                if app.autoSell then sell(root) else app.status = "Bag full; enable Auto sell" end
                return
            end
            if not target or not target.Parent or target:GetAttribute("FxHeld") or target:GetAttribute("Sinking") or os.clock()-targetSince>4 then
                if target and target.Parent then blocked[target] = os.clock()+2 end
                target = nearestBall(root)
                targetSince = os.clock()
                settleUntil = 0
            end
            if not target then
                releaseTool()
                if app.autoSell and held > 0 then sell(root) else app.status = "All available balls collected" end
                pause(0.25)
                return
            end
            local id = s.toolId
            app.status = id .. ": collecting"
            if id == "Hand" then
                if settleUntil == 0 then
                    moveFront(root, target, 3)
                    root.AssemblyLinearVelocity = Vector3.zero
                    settleUntil = os.clock()
                    return
                end
                if os.clock() < settleUntil then return end
                if os.clock() - lastHand < math.max(1/25, s.cooldown or 0.45) + backoff then return end
                lastHand = os.clock()
                remotes.PickupRequest:FireServer(target:GetAttribute("Id"), target.Position)
                blocked[target] = os.clock() + math.max(0.3, s.cooldown or 0.45)
                target = nil
            elseif id == "Picker" or id == "Roller" then
                startTool(id)
                local forward = id == "Picker" and tuning.Tools.PICK_FORWARD or tuning.Tools.ROLLER_FORWARD
                local direction = moveFront(root, target, forward)
                root.AssemblyLinearVelocity = direction * 8
                app.status = id .. ": continuous collection"
            elseif id == "Vacuum" then
                startTool(id)
                local direction = moveFront(root, target, tuning.Tools.VACUUM_MOUTH)
                root.AssemblyLinearVelocity = Vector3.zero
                if os.clock() - lastHand >= tuning.Tools.VACUUM_AIM_INTERVAL then
                    input("VacuumAim", nil, direction)
                    lastHand = os.clock()
                end
            elseif id == "Sweeper" then
                startTool(id)
                sweep(root, target, 0)
            elseif id == "VoidGun" then
                local config = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("VoidGun") :: any)
                if workspace:GetServerTimeNow() >= voidReady and os.clock() - lastVoid >= config.MIN_RELOAD then
                    moveFront(root, target, 12)
                    input("VoidFire", target.Position, (target.Position-root.Position).Unit)
                    lastVoid = os.clock()
                    voidReady = workspace:GetServerTimeNow() + config.RELOAD
                    blocked[target] = os.clock() + config.RELOAD
                    target = nil
                end
            elseif id == "Cart" or id == "CartV12" then
                cartStep(root)
            else app.status = "Unknown tool: " .. tostring(id) end
        end)
        if not ok then
            app.status = "Stopped: " .. tostring(err)
            app.running = false
            pickupToggle:Set(false, true)
            releaseTool()
        end
    end
    releaseTool()
    runService:UnbindFromRenderStep(walkBinding)
    app.running = false
    app.alive = false
end)
task.spawn(function()
    while active() do
        local s = run.State
        display:Set(string.format("%s\nBag: %d / %d  |  Money: %d\nPicked: %d  |  Sold: %d  |  Earned: %d\n%s",
            app.status, s.held or 0, s.capacity or 0, s.money or 0, app.picked, app.sold, app.earned, app.upgradeStatus))
        pause(0.5)
    end
end)
if resumeRunning then app.SetRunning(true) end
if resumeAutoUpgrade then app.SetAutoUpgrade(true) end
window:Notify({title = "Golf Ball Picker", content = "Ready. Enable Auto pickup to collect and sell."})
return app
