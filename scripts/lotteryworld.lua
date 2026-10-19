-- LOTTERYWORLD v43. Either Ctrl key shows/hides the draggable window.
-- Only uses inspected live service objects. All automation starts disabled.
if not game:IsLoaded() then game.Loaded:Wait() end
assert(game.PlaceId == 103419356526644, "This script is for LOTTERYWORLD")
local function raiseIdentity()
    local setter=setthreadidentity or setidentity or set_thread_identity
    if type(setter)=="function" then pcall(setter,8) end
end
raiseIdentity()
local function startupError(message)
    local text="Lottery GUI: "..tostring(message)
    warn(text)
    pcall(function()game:GetService("StarterGui"):SetCore("SendNotification",{Title="Lottery GUI failed to start",Text=tostring(message),Duration=15})end)
    error(text,0)
end
local found={}
local targets={
    P={"_poopingInProgress","_remotesReady"},
    L={"_createdTickets","_visibleTickets","_serviceBag"},
    I={"_inventoryData","_initialDataLoaded"},
    Shop={"PurchaseCompleted","_lotteryStoreGuiService","_currencyServiceClient"},
    Items={"PennyPincherScratcher","QuarterQuestScratcher"},
}
local function matches(value,keys)
    if type(value)~="table" then return false end
    for _,key in ipairs(keys) do if rawget(value,key)==nil then return false end end
    return true
end
local function consider(value)
    if type(value)~="table" then return end
    if rawget(value,"__LotteryPoopGuiRuntime") and rawget(value,"alive")==true and type(rawget(value,"Stop"))=="function" then
        found.prior=value
    end
    for name,keys in pairs(targets) do
        if not found[name] and matches(value,keys) then
            local penny=name=="Items" and rawget(value,"PennyPincherScratcher")
            if name~="Items" or (type(penny)=="table" and rawget(penny,"Type")=="Scratchoff") then found[name]=value end
        end
    end
end
local function allFound()
    return found.P and found.L and found.I and found.Shop and found.Items
end
local nativeFilter=filtergc
local deadline=os.clock()+25
repeat
    if type(nativeFilter)=="function" then
        for _,keys in pairs(targets) do
            local ok,values=pcall(nativeFilter,"table",{Keys=keys},false)
            if ok and type(values)=="table" then
                consider(values)
                for _,value in pairs(values) do consider(value) end
            end
        end
        local ok,values=pcall(nativeFilter,"table",{Keys={"__LotteryPoopGuiRuntime","Stop"}},false)
        if ok and type(values)=="table" then consider(values);for _,value in pairs(values) do consider(value) end end
    end
    if allFound() then break end
    if type(nativeFilter)~="function" then
        startupError("This script requires Real or an executor with compatible native filtergc support.")
    end
    task.wait(1)
until os.clock()>=deadline
if not allFound() then
    local missing={}
    for name in pairs(targets) do if not found[name] then table.insert(missing,name) end end
    startupError("Game services unavailable ("..table.concat(missing,", ").."). Wait until the game has loaded and run again. Executor table inspection must be supported.")
end
if found.prior then pcall(found.prior.Stop) end
local P,L,I,Shop,ItemConstants=found.P,found.L,found.I,found.Shop,found.Items
local Sweep={step=function(ticket,state)
    if ticket.IsAutoScratchSuspended and ticket:IsAutoScratchSuspended() then return false end
    local gui=ticket.Gui
    if not gui or gui.AbsoluteSize.Y<=0 then return false end
    ticket:AutoScratchBand(gui.AbsolutePosition.Y-2,gui.AbsolutePosition.Y+gui.AbsoluteSize.Y+2)
    state.progress=1
    return true
end}
local R = {
    __LotteryPoopGuiRuntime = true,
    alive = true,
    poop = false,
    use = false,
    buy = false,
    startedPoop = false,
    wasPooping = false,
    poopBusy = false,
    sweeps = setmetatable({}, { __mode = "k" }),
    scratchSteps = 0,
    uses = 0,
    claims = 0,
    purchases = 0,
    poopStarts = 0,
    poopCompletions = 0,
    errors = 0,
    scratchStatus = "Off",
    poopStatus = "Off",
    useStatus = "Off",
    buyStatus = "Off",
    busy = false,
    buyBusy = false,
    nextBuy = 0,
    buyRetry = 0.25,
    nextUse = 0,
    nextPoop = 0,
    useRetry = 0.25,
    claimRetry = 0.25,
    codesBusy = false,
    codeResults = {},
    codesStatus = "Not started",
    autoRewards = false,
    rewardsBusy = false,
    nextRewards = 0,
    rewardClaims = 0,
    rewardsStatus = "Off",
    moneyFarm = false,
    nextMoneyChoice = 0,
    moneyStatus = "Off",
    autoLuck = false,
    luckBusy = false,
    nextLuck = 0,
    luckStatus = "Off",
    potionBusy = false,
    potionEntries = {},
    potionStatus = "Loading potion shop",
    autoPotions = false,
    potionUseBusy = false,
    nextPotionUse = 0,
    potionUseStatus = "Off",
    potionsUsed = 0,
    autoUpgrades = false,
    upgradesBusy = false,
    nextUpgrade = 0,
    upgradesBought = 0,
    upgradesStatus = "Off",
}
local window, connection, menuConnection, controlledBar
local function releaseBar()
    if controlledBar then pcall(function()controlledBar._holding.Value=false end) end
    controlledBar=nil
end
function R.Stop()
    if not R.alive then return end
    raiseIdentity()
    R.alive=false; R.poop=false; R.use=false; R.buy=false; R.autoRewards=false; R.moneyFarm=false; R.autoLuck=false; R.autoPotions=false; R.autoUpgrades=false
    local obbyAuto=rawget(R,"obbyAuto")
    if obbyAuto then obbyAuto.Stop() end
    if connection then connection:Disconnect() end
    if menuConnection then menuConnection:Disconnect() end
    releaseBar()
    if R.startedPoop and P:IsPooping() then P:StopPooping() end
    if window and not window.unloaded then window:Unload() end
end
-- Re-running this standalone file stops its previous live runtime during discovery.
function R.ControlPressure(bar)
    if bar:GetState()~="Active" then return end
    controlledBar=bar
    local pos, center=bar._indicatorPosition.Value, bar._zoneCenter.Value
    if pos < center-0.012 then bar._holding.Value=true
    elseif pos > center+0.012 then bar._holding.Value=false end
    bar._hasHeld.Value=true
end
if type(loadstring)~="function" then startupError("This executor does not provide loadstring, which the menu needs.") end
local loaded,Rayfield=pcall(function()
    local source=game:HttpGet("https://sirius.menu/gen2")
    local chunk,compileError=loadstring(source)
    if not chunk then error(compileError) end
    return chunk()
end)
if not loaded then startupError("Could not load the menu library: "..tostring(Rayfield)) end
window=Rayfield:CreateWindow({name="Lottery & Poop",subtitle="LOTTERYWORLD",ToggleUIKeybind=Enum.KeyCode.Unknown})
R.window=window
function R.HandleMenuKey(key)
    if R.alive and (key==Enum.KeyCode.LeftControl or key==Enum.KeyCode.RightControl) then
        window:ToggleHide()
    end
end
menuConnection=game:GetService("UserInputService").InputBegan:Connect(function(input)
    R.HandleMenuKey(input.KeyCode)
end)
local tab=window:CreateTab({name="Automation"})
raiseIdentity()
local function getRewardService(name)
    for _,service in pairs(P._serviceBag._services) do
        if type(service)=="table" and service.ServiceName==name then return service end
    end
    return nil
end
function R.SelectLuckOutfit()
    local equipment=getRewardService("EquipmentServiceClient")
    local quality=nativeFilter("table",{Keys={"parseQuality","getStatMultiplier"}},true)
    local definitions=rawget(R,"luckDefinitions")
    if not definitions then
        for _,candidate in pairs(nativeFilter("table",{Keys={"ElvisHat","GoldenHat"}},false)) do
            if type(candidate.GoldenHat)=="table" and candidate.GoldenHat.LuckModification~=nil then definitions=candidate;break end
        end
        R.luckDefinitions=definitions
    end
    if not equipment or not quality or not definitions then error("Luck equipment information is still loading") end
    local current=equipment:GetAllLocalEquipment()
    local slots={Hat={},Shirt={},Pants={}}
    for name in pairs(I._inventoryData._map) do
        local item=ItemConstants[name]
        if item and slots[item.EquipmentType] and I:GetItemCount(name)>0 then
            local stars,base=quality.parseQuality(name)
            if item.EnchantmentName and base:sub(1,#item.EnchantmentName+1)==item.EnchantmentName.."_" then
                base=base:sub(#item.EnchantmentName+2)
            end
            local definition=definitions[base]
            if definition then
                local multiplier=quality.getStatMultiplier(stars)
                local luck=type(definition.LuckModification)=="number" and definition.LuckModification or 0
                table.insert(slots[item.EquipmentType],{name=name,base=base,definition=definition,multiplier=multiplier,
                    luck=luck>0 and luck*multiplier or luck,current=current[item.EquipmentType] and current[item.EquipmentType].itemName==name})
            end
        end
    end
    for _,options in pairs(slots) do
        table.sort(options,function(a,b)return a.name<b.name end)
        if #options==0 then table.insert(options,{name=false,base=false,luck=0}) end
    end
    local best,bestScore,bestKept=nil,-math.huge,-1
    for _,hat in ipairs(slots.Hat) do for _,shirt in ipairs(slots.Shirt) do for _,pants in ipairs(slots.Pants) do
        local outfit={Hat=hat,Shirt=shirt,Pants=pants}
        local bases={};local score,kept=0,0
        for _,entry in pairs(outfit) do
            if entry.base then bases[entry.base]=true end
            score=score+entry.luck
            if entry.current then kept=kept+1 end
        end
        for _,entry in pairs(outfit) do
            for _,effect in ipairs(entry.definition and entry.definition.DynamicEffects or {}) do
                if effect.ClassName=="BonusLuckEffect" and type(effect._baseLuck)=="number" then
                    local active=true
                    for _,required in ipairs(effect:GetRequiredEquipment() or {}) do if not bases[required] then active=false end end
                    if active then score=score+effect._baseLuck*(entry.multiplier or 1) end
                end
            end
        end
        if score>bestScore+0.00001 or (math.abs(score-bestScore)<0.00001 and kept>bestKept) then
            best=outfit;bestScore=score;bestKept=kept
        end
    end end end
    return best,bestScore,equipment
end
function R.EquipBestLuck()
    if not R.alive or not R.autoLuck or R.luckBusy then return false end
    R.luckBusy=true;R.nextLuck=os.clock()+5
    task.spawn(function()
        local ok,err=pcall(function()
            local outfit,score,equipment=R.SelectLuckOutfit()
            R.bestLuckOutfit=outfit;R.bestLuckScore=score
            for _,slot in ipairs({"Hat","Shirt","Pants"}) do
                if not R.alive or not R.autoLuck then return end
                local entry=outfit and outfit[slot]
                local current=equipment:GetAllLocalEquipment()[slot]
                if entry and entry.name and (not current or current.itemName~=entry.name) then
                    local success,result=equipment:EquipItem(entry.name):Yield()
                    if not success or (type(result)=="table" and result.success==false) then
                        error("Cannot equip "..entry.name..": "..tostring(type(result)=="table" and result.error or result))
                    end
                    R.lastEquippedLuckItem=entry.name
                    task.wait(0.25)
                end
            end
            local capabilities=getRewardService("PlayerCapabilitiesServiceClient")
            R.luckStatus=string.format("Best owned base-luck outfit equipped | Current base luck: %.2f",capabilities and capabilities:GetCapability("BaseLuck") or score)
        end)
        if not ok then R.lastLuckError=tostring(err);R.luckStatus="Retrying: "..tostring(err) end
        R.luckBusy=false
        if not R.autoLuck or not R.alive then R.luckStatus="Off" end
    end)
    return true
end
R.luckToggle=tab:CreateToggle({name="Auto Equip Best Luck",description="Equips your highest base-luck hat, shirt and pants, including stars and permanent luck set bonuses. Checks every 5 seconds. Conditional effects and rare-item odds can favor other outfits.",value=false,callback=function(value)
    R.autoLuck=value;R.nextLuck=0;R.luckStatus=value and "Checking owned clothes" or "Off"
end})
tab:CreateButton({name="Show equipped luck",callback=function()
    window:Notify({title="Auto Equip Best Luck",content=R.luckStatus})
end})
function R.CheckRewards()
    if not R.alive or not R.autoRewards or R.rewardsBusy then return false end
    R.rewardsBusy=true
    R.nextRewards=os.clock()+15
    task.spawn(function()
        local ok,err=pcall(function()
            local daily=getRewardService("DailyRewardServiceClient")
            local awards=getRewardService("AwardsServiceClient")
            local definitions=nativeFilter("table",{Keys={"AWARDS","REMOTE_FUNCTION_NAME","Actions"}},true)
            local claimed=0
            if daily then
                local loaded,info=daily:PromiseTrackInfo():Yield()
                if not R.alive or not R.autoRewards then return end
                if loaded and type(info)=="table" and info.claimableNow==true then
                    local success,result=daily:PromiseClaimFree():Yield()
                    if success then
                        claimed=claimed+1;R.rewardClaims=R.rewardClaims+1
                        R.lastDailyReward=result
                    else R.lastRewardError=tostring(result) end
                elseif not loaded then R.lastRewardError=tostring(info) end
            end
            if not R.alive or not R.autoRewards then return end
            if awards and awards._isLoaded.Value and definitions then
                local ready={}
                for id,award in pairs(definitions.AWARDS) do
                    if awards:GetCounter(award.Counter)>=award.Target and not awards._claimed.Value[id] then
                        table.insert(ready,id)
                    end
                end
                table.sort(ready)
                for _,id in ipairs(ready) do
                    if not R.alive or not R.autoRewards then return end
                    local success,result=awards:PromiseClaim(id):Yield()
                    if success and type(result)=="table" and result.success then
                        claimed=claimed+1;R.rewardClaims=R.rewardClaims+1
                        R.lastAwardClaim=id;R.lastAwardReward=result
                    else
                        R.lastRewardError=tostring(type(result)=="table" and (result.error or result.message) or result)
                        break
                    end
                    task.wait(0.5)
                end
            end
            R.rewardsStatus=claimed>0 and "Claimed "..claimed.." rewards; watching for more" or "Waiting for eligible daily and achievement rewards"
            if not daily or not awards or not definitions then R.rewardsStatus="Waiting for reward services to load" end
        end)
        if not ok then R.lastRewardError=tostring(err);R.rewardsStatus="Retrying reward check: "..tostring(err) end
        R.rewardsBusy=false
        if not R.alive or not R.autoRewards then R.rewardsStatus="Off" end
    end)
    return true
end
R.rewardsToggle=tab:CreateToggle({name="Auto Claim Rewards",description="Claims eligible free daily rewards and completed achievement rewards. Checks every 15 seconds.",value=false,callback=function(value)
    R.autoRewards=value;R.nextRewards=0;R.rewardsStatus=value and "Checking rewards" or "Off"
end})
tab:CreateButton({name="Show reward status",callback=function()
    window:Notify({title="Auto Claim Rewards",content=R.rewardsStatus.." | Total claimed: "..R.rewardClaims})
end})
-- Publicly listed codes checked October 18, 2026:
-- https://www.mrguider.org/roblox/lotteryworld-codes/
-- https://twinfinite.net/codes/lotteryworld-codes/
R.knownCodes = {
    "600COMMITS",
    "SORRYFORBROKENOBBYSYSTEM",
    "BLACKMARKET3OBBIES6ENCHANTS",
}
local codesTab=window:CreateTab({name="Reward Codes"})
local function getCodesService()
    for _,service in pairs(P._serviceBag._services) do
        if type(service)=="table" and service.ServiceName=="CodesServiceClient" then return service end
    end
    return nil
end
local function codeResultText(result)
    if type(result)~="table" then return tostring(result) end
    return tostring(result.error or result.message or "Unknown response")
end
function R.ClaimAllCodes()
    if R.codesBusy or not R.alive then return false end
    local service=getCodesService()
    if not service then
        window:Notify({title="Reward codes",content="The game's codes service has not loaded yet. Try again shortly."})
        return false
    end
    R.codesBusy=true
    R.codeResults={}
    R.codesStatus="Checking redemption status"
    task.spawn(function()
        local batchOk,batchError=pcall(function()
            local stateOk,state=service:PromiseGetState():Yield()
            if not R.alive then return end
            if stateOk and type(state)=="table" and (tonumber(state.lockedFor) or 0)>0 then
                R.codesStatus="Wait "..tostring(math.ceil(state.lockedFor)).." seconds before trying again."
                return
            end
            local claimed,already,failed=0,0,0
            for index,code in ipairs(R.knownCodes) do
                if not R.alive then return end
                R.codesStatus="Claiming "..index.."/"..#R.knownCodes..": "..code
                local callOk,redeemed,result=pcall(function()return service:PromiseRedeem(code):Yield()end)
                if not callOk then result=redeemed;redeemed=false end
                local reason=codeResultText(result)
                if not redeemed and (reason=="RateLimited" or reason=="AlreadyProcessing" or reason=="DataNotReady") then
                    R.codesStatus="Waiting before retrying "..code
                    task.wait(2)
                    if not R.alive then return end
                    callOk,redeemed,result=pcall(function()return service:PromiseRedeem(code):Yield()end)
                    if not callOk then result=redeemed;redeemed=false end
                    reason=codeResultText(result)
                end
                if redeemed and type(result)=="table" and result.success then
                    claimed=claimed+1
                    table.insert(R.codeResults,{code=code,status="Claimed",response=result})
                elseif reason=="AlreadyRedeemed" or reason=="GroupAlreadyClaimed" then
                    already=already+1
                    table.insert(R.codeResults,{code=code,status=reason,response=result})
                else
                    failed=failed+1
                    table.insert(R.codeResults,{code=code,status=reason,response=result})
                end
                if reason=="TooManyAttempts" or reason=="CodesDisabled" then break end
                if index<#R.knownCodes then task.wait(1) end
            end
            R.codesStatus=string.format("%d claimed, %d already claimed, %d unavailable",claimed,already,failed)
        end)
        R.codesBusy=false
        if not batchOk then R.codesStatus="Redemption failed: "..tostring(batchError) end
        if R.alive and not window.unloaded then
            window:Notify({title="Reward codes",content=R.codesStatus})
        end
    end)
    return true
end
codesTab:CreateButton({name="Claim All Codes",description="Tries all 3 publicly listed codes. Skips previously claimed codes and reports server results.",callback=R.ClaimAllCodes})
codesTab:CreateButton({name="Show known codes",callback=function()
    window:Notify({title="Known reward codes",content=table.concat(R.knownCodes,"\n")})
end})
codesTab:CreateButton({name="Show code results",callback=function()
    local lines={R.codesStatus}
    for _,entry in ipairs(R.codeResults) do table.insert(lines,entry.code..": "..entry.status) end
    window:Notify({title="Code redemption results",content=table.concat(lines,"\n")})
end})
function R.GetOwnedTickets()
    local owned={}
    for name in pairs(I._inventoryData._map) do
        local definition=ItemConstants[name]
        if definition and definition.Type=="Scratchoff" and I:GetItemCount(name)>0 then
            table.insert(owned,name)
        end
    end
    table.sort(owned)
    return owned
end
R.useToggle=tab:CreateToggle({name="Auto Use Tickets",description="Detects owned tickets, uses them, scratches them, and claims the results. Switches ticket types automatically.",value=false,
    callback=function(v)R.use=v;R.useStatus=v and "Checking inventory" or "Off";R.scratchStatus=v and "Ready" or "Off" end})
local buyTab=window:CreateTab({name="Auto Buy"})
local function formatAmount(n)
    local text=string.format("%.0f",n):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
    return text
end
function R.GetTicketPrice(itemName)
    local parts={}
    for _,charge in ipairs(Shop:GetTicketCharges(itemName)) do
        table.insert(parts,charge.Type=="Money" and ("$"..formatAmount(charge.Value)) or (formatAmount(charge.Value).." "..charge.Type))
    end
    return table.concat(parts," + ")
end
local buyOptions,buyItems={},{}
for _,ticket in ipairs(Shop:GetAvailableTickets()) do
    local definition=ItemConstants[ticket.ItemName]
    if definition and definition.Type=="Scratchoff" then
        local label=ticket.DisplayName.." — "..R.GetTicketPrice(ticket.ItemName)
        table.insert(buyOptions,label);buyItems[label]=ticket.ItemName
    end
end
R.buyItem=buyItems[buyOptions[1]]
R.buyDropdown=buyTab:CreateDropdown({name="Ticket to buy · current shop prices",options=buyOptions,value=buyOptions[1],callback=function(v)
    local label=type(v)=="table" and v[1] or v
    R.buyItem=buyItems[label]
    R.nextBuy=0
end})
R.buyToggle=buyTab:CreateToggle({name="Auto Buy Tickets",description="Spends available ticket currencies on the largest affordable batch, then keeps buying until switched off. Waits for funds and retries server rejections.",value=false,
    callback=function(v)R.buy=v;R.nextBuy=0;R.buyRetry=0.25;R.buyStatus=v and "Checking funds" or "Off" end})
buyTab:CreateButton({name="Show auto-buy status",callback=function()
    window:Notify({title="Auto Buy",content=R.buyStatus})
end})
buyTab:CreateButton({name="Show current selected price",callback=function()
    if not R.buyItem then window:Notify({title="Current shop price",content="No ticket selected"});return end
    window:Notify({title="Current shop price",content=(Shop:GetTicketByItemName(R.buyItem).DisplayName)..": "..R.GetTicketPrice(R.buyItem)})
end})
local potionTab=window:CreateTab({name="Luck Potions"})
local function potionCatalog()
    local constants=nativeFilter("table",{Keys={"RESTOCK_INTERVAL","STORE_ITEMS","ITEMS_PER_RESTOCK"}},true)
    assert(constants,"Potion catalog is still loading")
    local entries={}
    for _,group in ipairs(constants.STORE_ITEMS) do
        for _,variant in ipairs(group.variants or {}) do
            local luck=0
            for _,part in ipairs(variant.effectParts or {}) do
                if part.capabilityName=="BaseLuck" then luck=luck+(tonumber(part.value) or 0) end
            end
            if luck>0 then table.insert(entries,{item=variant.itemName,name=variant.displayName,group=group.groupKey,
                boost=luck,duration=variant.durationMinutes or 0,toxicity=variant.toxicity or 0,basePrice=variant.price,summary=variant.effectSummary}) end
        end
    end
    table.sort(entries,function(a,b)
        if a.boost~=b.boost then return a.boost>b.boost end
        if a.duration~=b.duration then return a.duration>b.duration end
        return a.item<b.item
    end)
    return entries
end
R.potionDropdown=potionTab:CreateDropdown({name="Luck potion · price · stock",options={"Loading..."},value="Loading...",callback=function(value)
    local label=type(value)=="table" and value[1] or value
    for _,entry in ipairs(R.potionEntries) do if entry.label==label then R.selectedPotion=entry.item;break end end
end})
function R.RefreshPotionData()
    local store=assert(getRewardService("ConsumableStoreServiceClient"),"Potion store is still loading")
    local loaded,inventory=store:PromiseCurrentStoreInventory():Yield()
    assert(loaded,tostring(inventory))
    local dataLoaded,data=store:PromiseStoreData():Yield()
    assert(dataLoaded,tostring(data))
    if not R.alive then return false end
    local stock={}
    for _,group in ipairs(inventory.inventory or {}) do if group.groupKey then stock[group.groupKey]=group.maxStock or 0 end end
    local prices=assert(nativeFilter("table",{Keys={"markupPriceLike","markupPrices"}},true),"Potion prices are still loading")
    local capabilities=getRewardService("PlayerCapabilitiesServiceClient")
    local markup=capabilities and capabilities:GetCapability("LotteryShopMarkup") or 0
    local entries=potionCatalog()
    local labels,selectedLabel={},nil
    for _,entry in ipairs(entries) do
        entry.stock=math.max(0,(stock[entry.group] or 0)-((data.purchases or {})[entry.group] or 0))
        entry.price=prices.markupPriceLike(entry.basePrice,markup)
        local parts={}
        for _,charge in ipairs(entry.price) do table.insert(parts,charge.Type=="Money" and "$"..formatAmount(charge.Value) or formatAmount(charge.Value).." "..charge.Type) end
        entry.priceText=table.concat(parts," + ")
        entry.affordable=store:GetMaxAffordableAmount(entry.price)>=1
        entry.label=string.format("%s | +%g luck | %s | %d left",entry.name,entry.boost,entry.priceText,entry.stock)
        table.insert(labels,entry.label)
        if entry.item==R.selectedPotion then selectedLabel=entry.label end
    end
    R.potionEntries=entries
    R.potionDropdown:Refresh(labels)
    if selectedLabel then R.potionDropdown:Set(selectedLabel)
    elseif labels[1] then R.potionDropdown:Set(labels[1]) end
    R.potionRestockAt=os.clock()+(tonumber(inventory.timeUntilRestock) or 0)
    R.potionStatus="Potion prices and stock refreshed"
    return true
end
function R.RefreshPotions()
    if R.potionBusy or not R.alive then return false end
    R.potionBusy=true
    task.spawn(function()
        local ok,err=pcall(R.RefreshPotionData)
        R.potionBusy=false
        if not ok then R.potionStatus="Shop unavailable: "..tostring(err) end
    end)
    return true
end
function R.BuyLuckPotion(bestAffordable)
    if R.potionBusy or not R.alive then return false end
    R.potionBusy=true
    task.spawn(function()
        local ok,err=pcall(function()
            if not R.RefreshPotionData() then return end
            local chosen
            for _,entry in ipairs(R.potionEntries) do
                if bestAffordable then
                    if entry.stock>0 and entry.affordable then chosen=entry;break end
                elseif entry.item==R.selectedPotion then chosen=entry;break end
            end
            assert(chosen,"No available affordable luck potion")
            assert(chosen.stock>0,"This potion is sold out; wait for restock")
            assert(chosen.affordable,"Not enough cash or Chips for "..chosen.name)
            if not R.alive then return end
            local store=getRewardService("ConsumableStoreServiceClient")
            local success,result=store:PromisePurchaseConsumable(chosen.item,1):Yield()
            assert(success,tostring(result))
            assert(type(result)=="table" and result.success,tostring(type(result)=="table" and result.error or result))
            R.lastPotionPurchase=result;R.lastPotionBought=chosen.item
            R.RefreshPotionData()
            R.potionStatus="Bought 1 × "..chosen.name.." for "..chosen.priceText.."; added to inventory"
        end)
        if not ok then R.potionStatus="Purchase failed: "..tostring(err) end
        R.potionBusy=false
        if R.alive then window:Notify({title="Luck Potions",content=R.potionStatus}) end
    end)
    return true
end
potionTab:CreateButton({name="Refresh potion shop",callback=R.RefreshPotions})
potionTab:CreateButton({name="Buy 1 selected potion",callback=function()R.BuyLuckPotion(false)end})
potionTab:CreateButton({name="Buy strongest affordable luck potion",description="Buys one in-stock potion with the highest base-luck boost; longer duration breaks ties.",callback=function()R.BuyLuckPotion(true)end})
potionTab:CreateButton({name="Show potion details",callback=function()
    for _,entry in ipairs(R.potionEntries) do if entry.item==R.selectedPotion then
        window:Notify({title=entry.name,content=entry.summary.." | "..entry.duration.." minutes | Toxicity "..entry.toxicity.." | "..entry.priceText.." | Stock "..entry.stock.." | Owned "..I:GetItemCount(entry.item)})
        return
    end end
    window:Notify({title="Luck Potions",content=R.potionStatus})
end})
function R.UseLuckPotion()
    if not R.alive or not R.autoPotions or R.potionUseBusy then return false end
    R.potionUseBusy=true;R.nextPotionUse=os.clock()+2
    task.spawn(function()
        local ok,err=pcall(function()
            local effects=assert(getRewardService("TemporaryEffectServiceClient"),"Effects are still loading")
            local synced,result=effects:RequestEffects():Yield()
            assert(synced,tostring(result))
            if not R.alive or not R.autoPotions then return end
            for key,effect in pairs(effects:GetActiveEffects()) do
                local luck=effect.group=="LuckBoost"
                for _,mod in ipairs(effect.capabilityModifications or {}) do
                    if mod.capabilityName=="BaseLuck" and (tonumber(mod.value) or 0)>0 then luck=true end
                end
                if luck and effects:GetRemainingDuration(key)>0 then
                    R.potionUseStatus="Waiting for "..tostring(effect.displayName or key).." to finish"
                    return
                end
            end
            local capabilities=assert(getRewardService("PlayerCapabilitiesServiceClient"),"Luck information is still loading")
            local toxicity=capabilities:GetCapability("Toxicity") or 0
            local ceiling=(capabilities:GetCapability("ToxicityTolerance") or 0)+(capabilities:GetCapability("ToxicityHeadroom") or 0)
            local chosen,owned
            for _,entry in ipairs(potionCatalog()) do
                if I:GetItemCount(entry.item)>0 then
                    owned=true
                    if toxicity+entry.toxicity<=ceiling then chosen=entry;break end
                end
            end
            if not chosen then R.potionUseStatus=owned and "Waiting for toxicity to drop" or "No owned luck potions; waiting for inventory";return end
            if not R.alive or not R.autoPotions then return end
            local service=assert(getRewardService("ConsumableServiceClient"),"Potion service is still loading")
            local success,reply=service:PromiseUseConsumable(chosen.item,1):Yield()
            assert(success,tostring(reply))
            R.lastPotionUse=reply;R.lastPotionUsed=chosen.item;R.potionsUsed=R.potionsUsed+1
            R.nextPotionUse=os.clock()+5;R.potionUseStatus="Used "..chosen.name
        end)
        if not ok then R.lastPotionUseError=tostring(err);R.potionUseStatus="Waiting to retry: "..tostring(err);R.nextPotionUse=os.clock()+10 end
        R.potionUseBusy=false
        if not R.autoPotions or not R.alive then R.potionUseStatus="Off" end
    end)
    return true
end
R.potionUseToggle=potionTab:CreateToggle({name="Auto Use Luck Potions",description="Uses your strongest owned luck potion when no luck potion remains active or queued. Waits for toxicity space. Does not buy potions.",value=false,callback=function(value)
    R.autoPotions=value;R.nextPotionUse=0;R.potionUseStatus=value and "Checking owned luck potions" or "Off"
end})
potionTab:CreateButton({name="Show auto-use status",callback=function()window:Notify({title="Luck Potions",content=R.potionUseStatus})end})
task.defer(R.RefreshPotions)
local upgradesTab=window:CreateTab({name="Upgrades"})
function R.GetUpgradeChoices()
    local gadgets=assert(getRewardService("GadgetServiceClient"),"Upgrade service is still loading")
    local currency=assert(getRewardService("CurrencyServiceClient"),"Currencies are still loading")
    local constants
    for _,candidate in pairs(nativeFilter("table",{Keys={"GADGETS","getGadgetUpgradeDisplayName"}},false)) do
        if type(candidate.GADGETS)=="table" and type(candidate.GADGET_NAMES)=="table"
            and type(candidate.getGadgetUpgradeDisplayName)=="function" then constants=candidate;break end
    end
    assert(constants,"Upgrade catalog is still loading")
    local conditions
    for _,candidate in pairs(nativeFilter("table",{Keys={"checkConditions"}},false)) do
        if type(candidate.checkConditions)=="function" then conditions=candidate;break end
    end
    assert(conditions,"Upgrade requirements are still loading")
    local currencyUtils
    for _,candidate in pairs(nativeFilter("table",{Keys={"normalizePrices","formatPricesRichText"}},false)) do
        if type(candidate.normalizePrices)=="function" then currencyUtils=candidate;break end
    end
    assert(currencyUtils,"Upgrade prices are still loading")
    local state=gadgets:GetUnlockedGadgets()
    local choices={}
    local remaining,locked,unaffordable=0,0,0
    for _,name in ipairs(constants.GADGET_NAMES) do
        local definition=constants.GADGETS[name]
        local level=(state[name] and state[name].level or 0)+1
        local upgrade=level<=definition.MaxUpgradeLevel and definition.Upgrades[level] or nil
        if upgrade then
            remaining=remaining+definition.MaxUpgradeLevel-level+1
            if conditions.checkConditions(upgrade.Conditions,state) then
                local prices=currencyUtils.normalizePrices(upgrade.Price)
                local affordable=true
                local parts={}
                for _,price in ipairs(prices) do
                    if price.Type~="Money" and price.Type~="Chips" then affordable=false
                    elseif currency:GetCurrencyValue(price.Type)<price.Value then affordable=false end
                    table.insert(parts,price.Type=="Money" and "$"..formatAmount(price.Value) or formatAmount(price.Value).." "..tostring(price.Type))
                end
                if affordable then table.insert(choices,{name=name,level=level,
                    display=constants.getGadgetUpgradeDisplayName(name,level),priceText=#parts>0 and table.concat(parts," + ") or "Free"})
                else unaffordable=unaffordable+1 end
            else locked=locked+1 end
        end
    end
    table.sort(choices,function(a,b)if a.level~=b.level then return a.level<b.level end;return a.name<b.name end)
    R.upgradesRemaining=remaining;R.upgradesLocked=locked;R.upgradesUnaffordable=unaffordable
    return choices,gadgets
end
function R.BuyNextUpgrade()
    if not R.alive or not R.autoUpgrades or R.upgradesBusy then return false end
    R.upgradesBusy=true;R.nextUpgrade=os.clock()+2
    task.spawn(function()
        local ok,err=pcall(function()
            local gadgets=assert(getRewardService("GadgetServiceClient"),"Upgrade service is still loading")
            local loaded,state=gadgets:PromiseGetGadgets():Yield()
            assert(loaded and type(state)=="table" and state.success,"Cannot refresh upgrade levels")
            if not R.alive or not R.autoUpgrades then return end
            local choices=R.GetUpgradeChoices()
            local choice=choices[1]
            if not choice then
                R.upgradesStatus=R.upgradesRemaining==0 and "All gadget upgrades purchased" or "Waiting for funds or upgrade prerequisites"
                return
            end
            R.upgradesStatus="Buying "..choice.display.." · "..choice.priceText
            local success,result=gadgets:PromiseUpgradeGadget(choice.name,choice.level):Yield()
            assert(success,tostring(result))
            assert(type(result)=="table" and result.success,tostring(type(result)=="table" and result.error or result))
            R.lastUpgradeReply=result;R.lastUpgradeBought=choice
            R.upgradesBought=R.upgradesBought+1
            R.upgradesStatus="Purchased "..choice.display.." · "..choice.priceText
            R.nextUpgrade=os.clock()+0.5
        end)
        if not ok then R.lastUpgradeError=tostring(err);R.upgradesStatus="Waiting to retry: "..tostring(err);R.nextUpgrade=os.clock()+5 end
        R.upgradesBusy=false
        if not R.alive or not R.autoUpgrades then R.upgradesStatus="Off" end
    end)
    return true
end
R.upgradesToggle=upgradesTab:CreateToggle({name="Auto Buy All Upgrades",description="Spends cash and Chips on eligible gadget unlocks and upgrades, one level at a time. Rechecks prerequisites and funds until switched off.",value=false,callback=function(value)
    R.autoUpgrades=value;R.nextUpgrade=0;R.upgradesStatus=value and "Checking upgrade tree" or "Off"
end})
upgradesTab:CreateButton({name="Show upgrade status",callback=function()
    window:Notify({title="Auto Buy All Upgrades",content=R.upgradesStatus.." | Bought: "..R.upgradesBought})
end})
local moneyTab=window:CreateTab({name="Money Farm"})
function R.SelectMoneyTicket()
    local gui=Shop._lotteryStoreGuiService
    local distribution=gui._rewardDistributionService
    local capabilities=gui._playerCapabilitiesServiceClient
    local rules=nativeFilter("table",{Keys={"usesVanillaRewards","blocksAllModifications","hasLuckCeiling"}},true)
    if not distribution or not capabilities or not rules then R.moneyStatus="Waiting for payout information";return nil end
    local balance=Shop._currencyServiceClient:GetCurrencyValue("Money")
    local budget=math.max(10,balance*0.1)
    local best
    local modifiers={BaseLuck=capabilities:GetCapability("BaseLuck") or 0}
    local complex=capabilities:GetCapability("ComplexLuck")
    if type(complex)=="table" then for key,value in pairs(complex) do modifiers[key]=value end end
    for _,ticket in ipairs(Shop:GetAvailableTickets()) do
        local item=ItemConstants[ticket.ItemName]
        local cost=0
        local charges=Shop:GetTicketCharges(ticket.ItemName)
        local cashOnly=#charges>0
        for _,charge in ipairs(charges) do
            if charge.Type~="Money" then cashOnly=false else cost=cost+charge.Value end
        end
        if item and item.Type=="Scratchoff" and item.RewardGroup and cashOnly and cost>0
            and cost<=budget and Shop:CanAffordTicketLocal(ticket.ItemName) then
            local ok,entries=pcall(function()
                return distribution:GetRewardProbabilityTable(item.RewardGroup,{},rules.usesVanillaRewards(ticket.ItemName) and {} or modifiers)
            end)
            if ok and type(entries)=="table" then
                local expected,total=0,0
                for _,entry in ipairs(entries) do
                    local probability=tonumber(entry.Probability) or 0
                    total=total+probability
                    if entry.Type=="Money" and type(entry.Value)=="number" then expected=expected+entry.Value*probability/100 end
                end
                local profit=expected-cost
                if total>99 and total<101 and profit>0 and (not best or profit>best.profit) then
                    best={item=ticket.ItemName,name=ticket.DisplayName,cost=cost,expected=expected,profit=profit}
                end
            end
        end
    end
    R.moneyChoice=best
    R.moneyStatus=best and string.format("%s | cost $%.0f | estimated cash profit $%.2f/ticket",best.name,best.cost,best.profit)
        or "Waiting for funds or a ticket with positive estimated cash profit"
    return best
end
R.moneyToggle=moneyTab:CreateToggle({name="Auto Money Farm",description="Chooses tickets with positive estimated cash profit. Buys one at a time within 10% of your balance (minimum $10), scratches and claims, then reinvests. Random payouts can lose money.",value=false,callback=function(value)
    if value then R.moneyPreviousBuyItem=R.buyItem elseif R.moneyPreviousBuyItem then R.buyItem=R.moneyPreviousBuyItem end
    R.moneyFarm=value;R.nextMoneyChoice=0;R.moneyChoice=nil
    R.moneyStartBalance=value and Shop._currencyServiceClient:GetCurrencyValue("Money") or R.moneyStartBalance
    R.moneyStatus=value and "Checking cash payouts" or "Off"
    R.buyToggle:Set(value);R.useToggle:Set(value);R.rewardsToggle:Set(value)
end})
moneyTab:CreateButton({name="Show money farm status",callback=function()
    local balance=Shop._currencyServiceClient:GetCurrencyValue("Money")
    local change=balance-(R.moneyStartBalance or balance)
    window:Notify({title="Money Farm",content=R.moneyStatus..string.format(" | Balance $%.0f | Change $%+.0f",balance,change)})
end})
R.poopToggle=tab:CreateToggle({name="Auto Poop",description="Starts when needed and grounded; controls the pressure minigame.",value=false,
    callback=function(v)R.poop=v;R.poopStatus=v and "Waiting until needed" or "Off";if not v then
        releaseBar();if R.startedPoop and P:IsPooping() then P:StopPooping() end;R.startedPoop=false
    end end})
tab:CreateButton({name="Show status",callback=function()
    window:Notify({title="Automation status",content="Use: "..R.useStatus.." | Buy: "..R.buyStatus.." | Poop: "..R.poopStatus})
end})
tab:CreateButton({name="Stop and close",callback=R.Stop})
local accumulator=0
local function complete(t)
    if t.IsScratchOwned and t:IsScratchOwned() and t.IsDeferredReady and not t:IsDeferredReady() then return false end
    if t.HasOverlayScratchSurfaces and t:HasOverlayScratchSurfaces() then return false end
    for _,surface in pairs(t.subtractiveFrames or {}) do
        if surface.GetScratchedFraction and surface:GetScratchedFraction()<1 then return false end
    end
    return t.AllCellsRevealed and t:AllCellsRevealed()==true
end
local function step(dt)
    if not R.alive then return end
    if window.unloaded then R.Stop();return end
    if R.autoUpgrades and not R.upgradesBusy and os.clock()>=R.nextUpgrade then R.BuyNextUpgrade() end
    if R.autoPotions and not R.potionUseBusy and os.clock()>=R.nextPotionUse then R.UseLuckPotion() end
    if R.autoLuck and not R.luckBusy and os.clock()>=R.nextLuck then R.EquipBestLuck() end
    if R.autoRewards and not R.rewardsBusy and os.clock()>=R.nextRewards then R.CheckRewards() end
    if R.poop then
        if P:IsPooping() then
            local view=P._poopingGuiService:GetCurrentView()
            if view and view._pressureBar then
                R.ControlPressure(view._pressureBar)
                R.poopStatus=string.format("Pooping: %d%%",math.floor(view:GetProgress()*100))
            end
        else
            releaseBar()
            if R.wasPooping then R.poopCompletions=R.poopCompletions+1;R.startedPoop=false end
            local can,reason=P:CanStartPooping()
            R.poopStatus=reason or "Ready"
            if can and not R.poopBusy and os.clock()>=R.nextPoop then
                R.poopBusy=true;R.nextPoop=os.clock()+3
                P:StartPooping():Then(function()
                    if not R.alive or not R.poop then P:StopPooping();return end
                    R.startedPoop=true;R.poopStarts=R.poopStarts+1
                end)
                    :Catch(function(e)R.poopStatus=tostring(e)end):Finally(function()R.poopBusy=false end)
            end
        end
        R.wasPooping=P:IsPooping()
    end
    accumulator=accumulator+dt
    if accumulator<1/60 then return end
    accumulator=0
    local tickets=L:GetVisibleCreatedTickets()
    local farmReady=not R.moneyFarm or (#tickets==0 and #R.GetOwnedTickets()==0 and not R.busy)
    if R.moneyFarm and farmReady and not R.buyBusy and os.clock()>=R.nextMoneyChoice then
        R.nextMoneyChoice=os.clock()+2
        local choice=R.SelectMoneyTicket()
        R.buyItem=choice and choice.item or nil
    end
    if R.buy and not R.buyBusy and os.clock()>=R.nextBuy and farmReady and (not R.moneyFarm or R.moneyChoice) then
        if not R.buyItem then R.buyStatus="Select a ticket";R.nextBuy=os.clock()+0.25
        elseif not Shop:CanAffordTicketLocal(R.buyItem) then
            local shortages={}
            for _,missing in ipairs(Shop:GetLocalShortfalls(R.buyItem,1)) do
                table.insert(shortages,formatAmount(missing.Required).." "..missing.Type.." required; have "..formatAmount(missing.Current))
            end
            R.buyStatus="Insufficient funds: "..table.concat(shortages,"; ")
            R.nextBuy=os.clock()+0.5
        else
            local buyingItem=R.buyItem
            local buyingName=Shop:GetTicketByItemName(buyingItem).DisplayName
            local buyingAmount=R.moneyFarm and 1 or Shop:GetMaxAffordableAmount(buyingItem)
            if buyingAmount<1 then R.nextBuy=os.clock()+0.5;return end
            R.buyBusy=true;R.buyStatus="Buying "..buyingAmount.." × "..buyingName
            Shop:PurchaseTicketMultiple(buyingItem,buyingAmount):Then(function(reply)
                R.lastPurchaseReply=reply
                if reply and reply.success then
                    local purchased=tonumber(reply.amount) or buyingAmount
                    R.purchases=R.purchases+purchased;R.buyRetry=0.25;R.nextBuy=0
                    if R.moneyFarm then R.nextMoneyChoice=0 end
                    R.buyStatus=R.buy and "Purchased "..purchased.." × "..buyingName or "Off"
                else
                    R.nextBuy=os.clock()+R.buyRetry;R.buyRetry=math.min(R.buyRetry*2,5)
                    R.buyStatus=R.buy and "Purchase not confirmed; retrying: "..buyingName or "Off"
                end
            end):Catch(function(e)
                R.lastPurchaseError=tostring(e)
                R.buyStatus=R.buy and "Purchase failed; retrying: "..tostring(e) or "Off"
                R.nextBuy=os.clock()+R.buyRetry;R.buyRetry=math.min(R.buyRetry*2,5)
            end)
                :Finally(function()R.buyBusy=false end)
        end
    end
    if R.use then
        R.scratchStatus=#tickets==0 and "Waiting for a ticket" or "Scratching"
        for _,entry in ipairs(tickets) do
            local t=entry.ticketInstance
            if t and t.Gui and t.Gui.Parent and t.Gui.AbsoluteSize.Y>0 and t.AutoScratchBand
                and (not t.CanAutoScratch or t:CanAutoScratch()) and not complete(t) then
                local s=R.sweeps[t] or {progress=0};R.sweeps[t]=s
                if not s.nextPass or os.clock()>=s.nextPass then
                    s.progress=0;s.lastFrontierY=nil
                    if Sweep.step(t,s) then R.scratchSteps=R.scratchSteps+1 end
                    s.nextPass=os.clock()+0.05
                end
            end
        end
    end
    if not R.use or R.busy or os.clock()<R.nextUse or P:IsPooping() then return end
    if #tickets>0 then
        for _,entry in ipairs(tickets) do if not complete(entry.ticketInstance) then R.useStatus="Waiting for scratching";return end end
        R.busy=true;R.useStatus="Claiming completed tickets"
        local position=#tickets
        local info=L._createdTickets:Get(L._visibleTickets:Get(position))
        L:PromiseClaimReward(position):Then(function(reply)
            R.lastClaimReply=reply
            if reply and reply.success then
                R.claims=R.claims+1
                R.claimRetry=0.25;R.nextUse=0
                local coverage={}
                for name,surface in pairs(info.ticketInstance.subtractiveFrames or {}) do
                    if surface.GetScratchedFraction then coverage[tostring(name)]=surface:GetScratchedFraction() end
                end
                R.lastClaimCoverage=coverage
                L:RemoveCreatedTicket(info)
            else
                R.useStatus="Claim not confirmed — waiting to retry"
                R.nextUse=os.clock()+R.claimRetry;R.claimRetry=math.min(R.claimRetry*2,2)
            end
        end)
            :Catch(function(e)
                R.useStatus=tostring(e);R.lastClaimError=tostring(e)
                R.nextUse=os.clock()+R.claimRetry;R.claimRetry=math.min(R.claimRetry*2,2)
            end):Finally(function()R.busy=false end)
    elseif R.use and L:GetCreatedTicketCount()==0 then
        local owned=R.GetOwnedTickets()
        if #owned==0 then
            R.selected=nil;R.useStatus="No tickets — waiting for inventory";R.nextUse=os.clock()+0.5;return
        end
        if not R.selected or not table.find(owned,R.selected) then R.selected=owned[1] end
        if P._activityServiceClient:IsActivityInProgress() then R.useStatus="Waiting for activity";return end
        R.busy=true;R.useStatus="Opening "..R.selected
        I:PromiseUseItem(R.selected,1):Then(function()R.uses=R.uses+1;R.useRetry=0.25;R.nextUse=0 end)
            :Catch(function(e)
                R.useStatus=tostring(e);R.lastUseError=tostring(e)
                R.nextUse=os.clock()+R.useRetry;R.useRetry=math.min(R.useRetry*2,2)
            end)
            :Finally(function()R.busy=false end)
    else R.useStatus="Waiting for existing ticket" end
end
connection=game:GetService("RunService").Heartbeat:Connect(function(dt)
    local ok,err=pcall(step,dt)
    if not ok then
        R.errors=R.errors+1;R.lastError=tostring(err)
        if R.errors>=3 then R.Stop();warn("Lottery GUI stopped: "..R.lastError) end
    end
end)

local function installPaintingObbys(parentRuntime,providedAnchor)
-- LOTTERYWORLD painting obby automation. Real/native filtergc required.
-- Ctrl: hide/show. F8: stop movement. Rewards use the normal exit-rift flow.
if not game:IsLoaded() then game.Loaded:Wait() end
assert(game.PlaceId==103419356526644,"This script is for LOTTERYWORLD")
assert(type(filtergc)=="function","This executor needs native filtergc support")
local function identity()
    local setter=setthreadidentity or setidentity
    if type(setter)=="function" then pcall(setter,8) end
end
identity()
local old=filtergc("table",{Keys={"__PaintingObbyAuto","Stop"},KeyValuePairs={alive=true}},true)
if old then old.Stop() end
local anchor=providedAnchor
local services={}
for _,service in pairs(anchor._serviceBag._services) do
    if type(service)=="table" and service.ServiceName then services[service.ServiceName]=service end
end
local O=assert(services.ObbyServiceClient,"Obby service unavailable")
local A=assert(services.ObbyActivityServiceClient,"Obby activity service unavailable")
local I=assert(services.InventoryServiceClient,"Inventory service unavailable")
local B=assert(services.ObbyBinders,"Obby checkpoint service unavailable")
local player=game:GetService("Players").LocalPlayer
local RunService=game:GetService("RunService")
local R={
    __PaintingObbyAuto=true,
    alive=true,
    enabled=false,
    status="Off",
    completed=0,
    rewards=0,
    generation=0,
    failedSessions={},
    lastStarted=0,
    teleportEnd=true,
}
local window,toggle,inputConnection,endedConnection
local function setEnabled(enabled)
    R.enabled=enabled
    R.generation=R.generation+1
    R.status=enabled and "Checking paintings" or "Off"
    if not enabled then
        local character=player.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if root then root.AssemblyLinearVelocity=Vector3.zero end
    end
end
function R.Stop()
    if not R.alive then return end
    identity()
    setEnabled(false)
    R.alive=false
    if inputConnection then inputConnection:Disconnect() end
    if endedConnection then endedConnection:Disconnect() end

end
window=parentRuntime.window
R.window=window
parentRuntime.obbyAuto=R
local tab=window:CreateTab({name="Painting Obbys"})
toggle=tab:CreateToggle({name="Auto Painting Obbys",description="Uses owned paintings and enters them. Teleport mode jumps to the live exit portal; checkpoint mode follows the course.",value=false,callback=setEnabled})
R.toggle=toggle
R.teleportToggle=tab:CreateToggle({name="Teleport straight to end",description="Auto Painting Obbys jumps to the actual exit portal. The game must still accept completion and grant the reward. Turn off to use the checkpoint route.",value=true,callback=function(value)
    R.teleportEnd=value;R.generation=R.generation+1;R.failedSessions={}
end})
tab:CreateButton({name="Show progress",callback=function()
    window:Notify({title="Painting obbys",content=R.status.."\nCompleted: "..R.completed.." | Reward total: "..R.rewards})
end})
tab:CreateButton({name="Stop obby automation",callback=function()toggle:Set(false)end})
inputConnection=game:GetService("UserInputService").InputBegan:Connect(function(input)
    if input.KeyCode==Enum.KeyCode.F8 then toggle:Set(false) end
end)
endedConnection=O.SessionEnded:Connect(function(result)
    R.lastServerResult=result
    if result and result.completed then
        R.completed=R.completed+1
        R.rewards=R.rewards+(tonumber(result.reward) or 0)
        R.status="Completed: reward "..tostring(result.reward or 0)
        if R.enabled then window:Notify({title="Obby complete",content=R.status}) end
    end
end)
function R.GetOwnedPaintings()
    local list={}
    for itemName in pairs(I._inventoryData._map) do
        if type(itemName)=="string" and itemName:match("^Painting_%d+$") and I:GetItemCount(itemName)>0 then
            table.insert(list,itemName)
        end
    end
    table.sort(list)
    return list
end
local function rootPart()
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health<=0 then return nil end
    return character:FindFirstChild("HumanoidRootPart")
end
local function currentMode(model)
    local modes=filtergc("table",{Keys={"_currentObbyInstance","_runStarted","_initialSpawnPosition"}},false)
    for _,mode in pairs(modes) do
        if mode._isRunning and mode._currentObbyInstance==model then return mode end
    end
    return nil
end
function R.TeleportToExit()
    if not R.alive then return false,"Obby automation has closed" end
    local session=O:GetActiveSessionLocal()
    if not session or session.status~="InProgress" then return false,"Enter a painting obby first" end
    local model=A:GetCurrentObbyModel()
    local mode=model and currentMode(model)
    local rift=mode and mode._endRift
    local root=rootPart()
    if not root then return false,"Waiting for your character" end
    if not rift or not rift.Part or not rift.Part.Parent then return false,"Waiting for this obby's exit portal to load" end
    root.CFrame=CFrame.new(rift.Part.Position)*root.CFrame.Rotation
    root.AssemblyLinearVelocity=Vector3.zero
    root.AssemblyAngularVelocity=Vector3.zero
    R.lastTeleportSession=session.sessionId
    R.status="Teleported to exit: "..tostring(session.obbyName)
    return true
end
tab:CreateButton({name="Teleport to current exit",callback=function()
    local ok,reason=R.TeleportToExit()
    window:Notify({title="Painting obbys",content=ok and "Moved to exit; waiting for the game's completion result" or reason})
end})
local function keepGoing(generation,sessionId)
    if not R.alive or not R.enabled or R.generation~=generation then return false end
    local session=O:GetActiveSessionLocal()
    return session and session.sessionId==sessionId
end
local function travel(getTarget,generation,sessionId,timeout)
    local deadline=os.clock()+timeout
    local commandedPosition
    while keepGoing(generation,sessionId) and os.clock()<deadline do
        local root=rootPart()
        if not root then return false,"Character died; waiting for respawn" end
        local target=getTarget()
        if not target then return false,"Target disappeared" end
        if (target-root.Position).Magnitude<0.7 then return true end
        commandedPosition=commandedPosition or root.Position
        local delta=target-commandedPosition
        local dt=RunService.Heartbeat:Wait()
        if not keepGoing(generation,sessionId) then return false,"Session ended" end
        if not root.Anchored then
            local distance=math.min(delta.Magnitude,16*math.min(dt,0.05))
            if delta.Magnitude>0.001 then commandedPosition=commandedPosition+delta.Unit*distance end
            root.CFrame=CFrame.new(commandedPosition)*root.CFrame.Rotation
            root.AssemblyLinearVelocity=Vector3.zero
        end
    end
    return false,"Movement stopped or timed out"
end
local function checkpoints(model)
    local nodes={}
    local binder=B:GetBinder("Obby/Checkpoint")
    if not binder then return nodes end
    for _,prop in pairs(binder:GetAll()) do
        local context=prop._runtime
        local body=context and context.body
        if body and body:IsDescendantOf(model) and not prop._reached then
            table.insert(nodes,{body=body,prop=prop,order=tonumber(context.attrs.Order) or 0,id=tostring(context.propId)})
        end
    end
    table.sort(nodes,function(a,b)
        if a.order==b.order then return a.id<b.id end
        return a.order<b.order
    end)
    return nodes
end
local function completeSession(session)
    local generation=R.generation
    local id=session.sessionId
    local model=A:GetCurrentObbyModel()
    if not model then R.status="Waiting for the obby to load";return end
    local mode=currentMode(model)
    local rift=mode and mode._endRift
    if not mode or not rift or not rift.Part then
        R.status="Waiting for this obby's exit rift"
        return
    end
    if R.teleportEnd then
        local moved,reason=R.TeleportToExit()
        if not moved then R.status=reason;return end
        R.status="At exit; waiting for the game's reward confirmation"
        local deadline=os.clock()+15
        while keepGoing(generation,id) and os.clock()<deadline do task.wait(0.1) end
        if keepGoing(generation,id) then
            R.failedSessions[id]=true
            R.status="Exit jump was not accepted. Turn off Teleport straight to end to try the checkpoint route."
            window:Notify({title="Painting obbys",content=R.status})
        end
        return
    end
    local nodes=checkpoints(model)
    for index,node in ipairs(nodes) do
        R.status="Checkpoint "..index.."/"..#nodes.." in "..session.obbyName
        local ok,reason=travel(function()
            if node.body.Parent then return (node.body.CFrame*CFrame.new(0,node.body.Size.Y/2+2,0)).Position end
            return nil
        end,generation,id,45)
        if not ok then R.status=reason;return end
        local untilTime=os.clock()+2
        while keepGoing(generation,id) and not node.prop._reached and os.clock()<untilTime do task.wait(0.05) end
        if not node.prop._reached then
            R.status="Checkpoint did not activate; stopped for "..session.obbyName
            R.failedSessions[id]=true
            return
        end
    end
    R.status="Moving to exit: "..session.obbyName
    local ok,reason=travel(function()
        if rift.Part and rift.Part.Parent then return rift.Part.Position end
        return nil
    end,generation,id,100)
    if not keepGoing(generation,id) then return end
    if not ok then R.status=reason;return end
    R.status="Waiting for the game to complete and award rewards"
    local deadline=os.clock()+15
    while keepGoing(generation,id) and os.clock()<deadline do task.wait(0.1) end
    if keepGoing(generation,id) then
        R.failedSessions[id]=true
        R.status="Exit did not complete this session; stopped"
    end
end
local function enterInitiatedSession(session)
    local generation=R.generation
    local handle=O._paintingServiceClient._currentPaintingHandle
    local canvas=handle and handle.Canvas
    if not canvas or not canvas.Parent then R.status="Waiting for the painting entrance";return end
    R.status="Entering painting: "..tostring(session.obbyName)
    travel(function()
        if canvas.Parent then return canvas.Position end
        return nil
    end,generation,session.sessionId,15)
    local deadline=os.clock()+10
    while keepGoing(generation,session.sessionId) and os.clock()<deadline do
        local active=O:GetActiveSessionLocal()
        if active and active.status=="InProgress" then break end
        task.wait(0.1)
    end
end
task.spawn(function()
    while R.alive do
        if R.enabled then
            local ok,err=pcall(function()
                local session=O:GetActiveSessionLocal()
                if session then
                    if R.failedSessions[session.sessionId] then return end
                    if session.status=="InProgress" then completeSession(session)
                    elseif session.status=="Initiated" then enterInitiatedSession(session) end
                elseif not anchor._activityServiceClient:IsActivityInProgress() and not O._isStartingObby and os.clock()-R.lastStarted>=3 then
                    local owned=R.GetOwnedPaintings()
                    if #owned==0 then R.status="No owned paintings; waiting for inventory";return end
                    R.lastStarted=os.clock()
                    R.status="Using "..owned[1]
                    local used,result=I:PromiseUseItem(owned[1],1):Yield()
                    if not used then R.status="Cannot use painting: "..tostring(result);R.lastStarted=os.clock()+5 end
                end
            end)
            if not ok then
                R.lastError=tostring(err)
                toggle:Set(false)
                R.status="Stopped: "..R.lastError
                window:Notify({title="Painting obbys",content=R.status})
            end
        end
        task.wait(0.25)
    end
end)
print("Painting Obbys tab ready. F8 stops obby automation.")
end
installPaintingObbys(R,P)

print("Lottery GUI ready: full-ticket scratch passes, automatic use/claim, Auto Buy. Either Ctrl key toggles the window.")