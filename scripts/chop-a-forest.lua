-- The Forest: owner-authorized client/server validation panel.
-- Place 77239332768345. Updated for version 41. All features start OFF.
-- Run through Real live-reload; standalone fallback also supports reruns.
--!nocheck
local STATE = ...
assert(game.PlaceId == 77239332768345, "This panel targets The Forest only")
local env = getgenv()
if env.ForestAudit and env.ForestAudit.Stop then env.ForestAudit.Stop() end
local P = game:GetService("Players").LocalPlayer
local Shared = game:GetService("ReplicatedStorage").Shared
local CS = game:GetService("CollectionService")
local R = require(Shared.Services.ChopRemotes)
local Config = require(Shared.Configs.Chopping)
local Math = require(Shared.Utilities.UpgradeMath)
local Heat = require(Shared.Utilities.SawHeat)
local Night = require(Shared.Configs.NightMonsters)
local CombatRemotes = Shared.Services.ChopRemotes
local connections={}
local releaseCombat=function() end
local Original = {BagMax=Math.BagMax, CarryMax=Math.CarryMax, Backpack=Math.Backpack,
    At=Heat.At, FullAt=Heat.FullAt}
local function serverCapacity()
    -- Original CarryMax delegates through Math.BagMax, which a local probe can replace.
    local bag=Original.BagMax(P)
    if bag>0 then return bag end
    return math.floor(Config.Logs.CarryMax+Math.Perk(P,"Carry")+Math.Add(P,"Carry"))
end
local A = {Flags={}, Results={}, Running=true, Status="Ready", Sequence=800000,
    Radius=12, Requests=0, TeleportReady=0, TeleportDelay=.07}
env.ForestAudit = A
local toggles = {}
local Window
local function alive()
    return A.Running and (not STATE or STATE.alive())
end
local function record(name, data)
    data.time = workspace:GetServerTimeNow()
    A.Results[name] = data
end
local function root()
    local c = P.Character
    return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end
local revving = false
local function throttle(on)
    if revving ~= on then R.Throttle:FireServer(on); revving=on end
end
local function restore()
    Math.BagMax=Original.BagMax; Math.CarryMax=Original.CarryMax
    Math.Backpack=Original.Backpack; Heat.At=Original.At; Heat.FullAt=Original.FullAt
end
local function stopFeatures()
    table.clear(A.Flags)
    releaseCombat()
    restore()
    throttle(false)
    local rt, hum=root()
    if rt and hum then hum:MoveTo(rt.Position) end
    for _,toggle in toggles do pcall(function() toggle:Set(false) end) end
    A.Status="Stopped; client overrides restored"
end
function A.Stop()
    if not A.Running then return end
    stopFeatures()
    A.Running=false
    for _,connection in connections do connection:Disconnect() end
    if Window then pcall(function() Window:Destroy() end) end
end
if STATE then STATE.onCleanup(A.Stop) end
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
Window = WindUI:CreateWindow({Title="The Forest | Validation Lab", Author="Owner test panel",
    Icon="shield-check", Size=UDim2.fromOffset(650,530), Theme="Dark", Folder="ForestAudit",
    Resizable=true, SideBarWidth=175})
A.Window=Window
Window:SetToggleKey(Enum.KeyCode.RightControl)
Window:OnDestroy(A.Stop)
local Automation=Window:Tab({Title="Automation",Icon="trees"})
local Combat=Window:Tab({Title="Combat",Icon="swords"})
local Tamper=Window:Tab({Title="Tamper tests",Icon="flask-conical"})
local Findings=Window:Tab({Title="Results",Icon="clipboard-list"})
local function toggle(tab,key,title,desc,fn)
    local t=tab:Toggle({Title=title,Desc=desc,Value=false,Callback=function(value)
        A.Flags[key]=value
        if fn then fn(value) end
    end})
    table.insert(toggles,t)
    A.Controls = A.Controls or {}
    A.Controls[key]=t
    return t
end
toggle(Automation,"Cut","Auto cut wood — teleport","On foot: uses your tool. Driving your Big Saw: moves the whole vehicle and lines its saw up with the tree.")
toggle(Automation,"Collect","Auto collect — teleport + batch","Teleports to log clusters and collects up to 16 nearby logs per batch.")
toggle(Automation,"AutoTools","Auto buy tools — axe, chainsaw, then rest",
    "Uses coins at tool stations. Buys prerequisites, skips owned tools, and saves for the next purchase.")
toggle(Automation,"Upgrade","Auto upgrade","Buys tool and gear upgrades; reserves coins for the next auto-buy tool.")
toggle(Automation,"Sell","Auto sell — full backpack only","Drops off wood only at actual server capacity, then immediately returns to farming.")
toggle(Automation,"SawSell","Auto sell Big Saw — full cargo only",
    "While driving your Big Saw: sells only when cargo reaches capacity, then returns to your cutting spot. No coin detour.")
Automation:Slider({Title="Teleport settle delay (ms)",Desc="Lower is faster; raise if the server rejects pickups.",
    Value={Min=30,Max=250,Default=70},Step=10,Callback=function(v) A.TeleportDelay=v/1000 end})
toggle(Combat,"Boss","Auto kill boss — above + behind","Follows above and behind the Guardian; locks character, camera and gun aim onto its hitbox. Works on foot.")
toggle(Combat,"Enemies","Auto kill enemies — above + behind","Follows above and behind the selected enemy; reacquires its hitbox on every move. Works on foot.")
toggle(Combat,"Dodge","Auto dodge attacks","Teleports outside circle, charge and cone warnings; avoids fusing bombers.")
toggle(Combat,"UseGuns","Use owned guns","Uses the strongest owned gun. Otherwise uses an owned melee tool; buys nothing.")
toggle(Tamper,"Bag","Infinite backpack — client tamper","Removes client capacity checks. Server bypass UNCONFIRMED.",
    function(on)
    if on then
        Math.BagMax=function(plr) if plr==P then return math.huge end; return Original.BagMax(plr) end
        Math.CarryMax=function(plr) if plr==P then return math.huge end; return Original.CarryMax(plr) end
        Math.Backpack=function(plr) if plr==P then return true end; return Original.Backpack(plr) end
    else
        Math.BagMax=Original.BagMax; Math.CarryMax=Original.CarryMax; Math.Backpack=Original.Backpack
    end
end)
toggle(Tamper,"Heat","No overheating — client tamper","Removes local heat lock only. Server heat remains visible in Results.",
    function(on)
    if on then
        Heat.At=function() return 0,false,0 end
        Heat.FullAt=function() return math.huge end
    else Heat.At=Original.At; Heat.FullAt=Original.FullAt end
end)
local statusButton=Findings:Button({Title="Refresh live status",Desc="Click to update",
Callback=function()
    local heat=Original.At(Heat.Read(P,{}),Math.Heat(P,"Chainsaw"),workspace:GetServerTimeNow())
    local text=string.format("Logs %s / %s | server heat %.2f | sent %d\n%s",
        tostring(P:GetAttribute("CarriedLogs")),tostring(serverCapacity()),heat,A.Requests,A.Status.."\n"..(A.ToolStatus or "Auto tool buying OFF"))
    WindUI:Notify({Title="Live server state",Content=text,Duration=8})
end})
Findings:Button({Title="Initial distance checks: rejected",
    Desc="400.5-stud pickup: logs stayed 44. 50.8-stud chop: HP stayed 6.16.",
    Callback=function() end})
Findings:Button({Title="Backpack and heat bypasses: unconfirmed",
    Desc="Local overrides are probes. Capacity overflow or damage during server heat lock is required as evidence.",
    Callback=function() end})
Findings:Button({Title="Stop all features",Desc="Restores original client functions and releases throttle.",Callback=stopFeatures})
Findings:Button({Title="Unload panel",Callback=A.Stop})
local lastTeleport=0
local function drivenSaw(hum)
    local seat=hum and hum.SeatPart
    local vehicles=workspace:FindFirstChild("Vehicles")
    if not seat or not seat:IsA("VehicleSeat") or seat.Occupant~=hum or not vehicles then return nil end
    local vehicle=seat.Parent
    while vehicle and vehicle.Parent~=vehicles do vehicle=vehicle.Parent end
    if vehicle and vehicle:IsA("Model") and vehicle.PrimaryPart
        and vehicle:GetAttribute("VehicleId")=="BigSaw"
        and tonumber(vehicle:GetAttribute("Owner"))==P.UserId
        and vehicle:FindFirstChild("DriverSeat")==seat then return vehicle,seat end
    return nil
end
local function moveSaw(vehicle,cf)
    -- Move the assembly, including its seat weld; never unseat the driver.
    for _,part in vehicle:GetDescendants() do
        if part:IsA("BasePart") then
            part.AssemblyLinearVelocity=Vector3.zero
            part.AssemblyAngularVelocity=Vector3.zero
        end
    end
    vehicle:PivotTo(cf)
    lastTeleport=os.clock()
    A.TeleportReady=lastTeleport+math.max(.25,A.TeleportDelay)
end
A.DrivenSaw=drivenSaw
local function teleport(pos,look)
    local rt,hum=root()
    if not rt or not hum or hum.Health<=0 then return false end
    throttle(false)
    local vehicle,seat=drivenSaw(hum)
    if vehicle then
        local pivot=vehicle:GetPivot()
        local rotation=pivot.Rotation
        local direction=look and Vector3.new(look.X-pos.X,0,look.Z-pos.Z)
        if direction and direction.Magnitude>.01 then rotation=CFrame.lookAt(Vector3.zero,direction.Unit) end
        local localSeat=pivot:PointToObjectSpace(seat.Position)
        moveSaw(vehicle,CFrame.new(pos-rotation:VectorToWorldSpace(localSeat))*rotation)
        return true
    end
    hum.Sit=false
    rt.AssemblyLinearVelocity=Vector3.zero
    rt.AssemblyAngularVelocity=Vector3.zero
    rt.CFrame=look and CFrame.lookAt(pos,Vector3.new(look.X,pos.Y,look.Z)) or CFrame.new(pos)
    lastTeleport=os.clock()
    A.TeleportReady=lastTeleport+A.TeleportDelay
    return true
end
local function unlockedTree(tree)
    local unlocked=tonumber(workspace:GetAttribute("AreasUnlocked"))
    local index=tonumber(tree:GetAttribute("AreaIndex"))
    if not index then
        local forest=Config.Forest
        local order=forest and ((forest.Areas and forest.Areas.Order) or forest.Order)
        if order then
            local biome=tree:GetAttribute("Biome")
            for i,key in order do if key==biome then index=i;break end end
        end
    end
    -- Unknown progression/section metadata is skipped, never treated as unlocked.
    return unlocked~=nil and index~=nil and index>=1 and index<=unlocked
end
A.IsTreeUnlocked=unlockedTree
local rejectedTrees=setmetatable({},{__mode="k"})
local function nearestTree(rt)
    local best,base,dist=nil,nil,math.huge
    for i,t in CS:GetTagged("Tree") do
        if i%250==0 then task.wait() end
        if not alive() then return nil,nil,math.huge end
        local b=t:FindFirstChild("TrunkBase")
        if b and t.Parent and unlockedTree(t) and (rejectedTrees[t] or 0)<os.clock() and not t:GetAttribute("Felled") and not t:GetAttribute("Doomed")
            and (t:GetAttribute("HP") or 0)>0 then
            local d=(b.Position-rt.Position).Magnitude
            if d<dist then best=t; base=b; dist=d end
        end
    end
    return best,base,dist
end
local nextCut,nextCollect,nextUpgrade=0,0,0
local target,base,distance
local vehicleTarget,vehicleHP,vehicleProgress,vehicleRetry
local function cutWithSaw(now,vehicle,rt)
    throttle(false)
    local edge=vehicle:FindFirstChild("SawEdge",true)
    if not edge or not edge:IsA("Attachment") then A.Status="Big Saw: waiting for saw attachment";return end
    local hp=tonumber(target:GetAttribute("HP")) or 0
    if vehicleTarget~=target then
        vehicleTarget=target;vehicleHP=hp;vehicleProgress=now;vehicleRetry=0
    elseif hp<vehicleHP then vehicleHP=hp;vehicleProgress=now end
    if now< A.TeleportReady then return end
    local delta=(edge.WorldPosition-base.Position)*Vector3.new(1,0,1)
    if delta.Magnitude>2.5 and now>vehicleRetry then
        local pivot=vehicle:GetPivot()
        local localEdge=pivot:PointToObjectSpace(edge.WorldPosition)
        local away=(rt.Position-base.Position)*Vector3.new(1,0,1)
        away=away.Magnitude>.01 and away.Unit or Vector3.new(1,0,0)
        local facing=CFrame.lookAt(Vector3.zero,-away)
        local position=base.Position-facing:VectorToWorldSpace(localEdge)
        -- Ground the chassis using the game's drive bounds, excluding trees and vehicles.
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        local exclude={P.Character,vehicle,target}
        for _,name in {"Vehicles","Logs","Trees","Monsters","ChopLocal"} do
            local folder=workspace:FindFirstChild(name)
            if folder then table.insert(exclude,folder) end
        end
        params.FilterDescendantsInstances=exclude
        local hit=workspace:Raycast(position+Vector3.new(0,40,0),Vector3.new(0,-120,0),params)
        local box,size=vehicle:GetAttribute("DriveBox"),vehicle:GetAttribute("DriveSize")
        if not hit or typeof(box)~="CFrame" or typeof(size)~="Vector3" then
            A.Status="Big Saw: no safe ground at tree";vehicleRetry=now+1;return
        end
        position=Vector3.new(position.X,hit.Position.Y-box.Position.Y+size.Y/2+.3,position.Z)
        moveSaw(vehicle,CFrame.new(position)*facing)
        vehicleRetry=now+1
        A.Status="Big Saw teleported; saw aligned toward tree"
        return
    end
    if now-vehicleProgress>8 then
        record("vehicleCut",{treeId=target:GetAttribute("TreeId"),accepted=false,reason="No server damage observed"})
        rejectedTrees[target]=now+15;target=nil;vehicleTarget=nil
        A.Status="Big Saw: no cut registered; checking another tree"
        return
    end
    A.Status=vehicle:GetAttribute("SawOn")==true and "Big Saw: waiting for vehicle cut"
        or "Big Saw aligned — turn on the vehicle saw using its normal controls"
end
local function cut(now,rt,hum)
    if not target or not target.Parent or target:GetAttribute("Felled") or not unlockedTree(target) or (rejectedTrees[target] or 0)>now then
        target,base,distance=nearestTree(rt)
    end
    if not target or not base then throttle(false);A.Status="No standing trees in unlocked sections";return end
    local vehicle=drivenSaw(hum)
    if vehicle then cutWithSaw(now,vehicle,rt);return end
    distance=(base.Position-rt.Position).Magnitude
    if distance>8 then
        local offset=(rt.Position-base.Position)*Vector3.new(1,0,1)
        local dir=offset.Magnitude>.01 and offset.Unit or Vector3.new(1,0,0)
        local cf=base.CFrame
        local halfHeight=(math.abs(cf.RightVector.Y)*base.Size.X+
            math.abs(cf.UpVector.Y)*base.Size.Y+math.abs(cf.LookVector.Y)*base.Size.Z)/2
        local y=base.Position.Y-halfHeight+(hum and hum.HipHeight or 2)+rt.Size.Y/2+.1
        teleport(Vector3.new(base.Position.X,y,base.Position.Z)+dir*5,base.Position)
        A.Status="Teleported to tree; waiting for position replication"
        return
    end
    if now<A.TeleportReady then return end
    local tool=P:GetAttribute("Tool") or "Fists"
    local spec=Config.Tools[tool]
    if not spec or spec.Damage<=0 then throttle(false);A.Status="Equip fists, axe, claws or chainsaw";return end
    local heatSpec=Math.Heat(P,tool)
    if heatSpec and not A.Flags.Heat then
        local keys=tool=="ChainsawArms" and Heat.ARM_KEYS or Heat.KEYS
        local _,locked=Original.At(Heat.Read(P,{},keys),heatSpec,workspace:GetServerTimeNow())
        if locked then throttle(false);A.Status="Server heat lock; cooling";return end
    end
    throttle(spec.Continuous==true)
    if now<nextCut then return end
    nextCut=now+math.max(.035,(spec.Interval or .35)*Math.SwingScale(P,tool))
    local offset=(rt.Position-base.Position)*Vector3.new(1,0,1)
    local dir=offset.Magnitude>.01 and offset.Unit or Vector3.new(1,0,0)
    local pos=base.Position+dir*math.min(base.Size.X,base.Size.Z)*.4
    A.Sequence+=1
    local sentSeq=A.Sequence
    if not spec.Continuous then R.Swing:FireServer(1) end
    local before=target:GetAttribute("HP")
    local t=target
    R.Chop:FireServer(t,pos,1,A.Sequence,25)
    A.Requests+=1
    A.Status="Cutting unlocked section "..tostring(t:GetAttribute("AreaIndex"))
    task.delay(.2,function()
        if not alive() or not t.Parent then return end
        local after=t:GetAttribute("HP")
        local mine=t:GetAttribute("LastHitBy")==P.UserId
        record("cut",{treeId=t:GetAttribute("TreeId"),before=before,after=after,
            accepted=after<before and mine,sequence=sentSeq})
        if after<before then
            A.LastCut=os.clock()
            if after<=0 then A.WaitForDrops=os.clock()+.25 end
            A.StalledTree=nil
        elseif A.StalledTree~=t then
            A.StalledTree=t;A.StalledSince=os.clock()
        elseif os.clock()-A.StalledSince>1.25 then
            rejectedTrees[t]=os.clock()+15
            target=nil
        end
    end)
end

-- Combat and dodge scheduler. Uses replicated monster state and server warning geometry.
local hazards={}
local combatTarget,combatOriginalTool,combatOriginalGun
local nextAttack,nextEquip,nextDodge,nextHP=0,0,0,0
local heldCombatTool
local hoverTarget,hoverHumanoid,previousAutoRotate
local function clearHeadLock()
    hoverTarget=nil
    if hoverHumanoid and hoverHumanoid.Parent then hoverHumanoid.AutoRotate=previousAutoRotate end
    hoverHumanoid=nil;previousAutoRotate=nil
end
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function monsterPosition(m)
    local from=m:GetAttribute("MoveFrom")
    local vel=m:GetAttribute("MoveVel")
    local at=m:GetAttribute("MoveAt")
    if typeof(from)=="Vector3" then
        if typeof(vel)=="Vector3" and typeof(at)=="number" then
            return from+vel*math.max(0,workspace:GetServerTimeNow()-at)
        end
        return from
    end
    return m:GetPivot().Position
end
local function monsterAllowed(m)
    local forest=Config.Forest
    local order=forest and ((forest.Areas and forest.Areas.Order) or forest.Order)
    local index=tonumber(m:GetAttribute("AreaIndex"))
    if not index and order then index=table.find(order,m:GetAttribute("Biome")) end
    return index~=nil and index<=(tonumber(workspace:GetAttribute("AreasUnlocked")) or 0)
end
local function monsterAlive(m)
    local state=m:GetAttribute("State")
    return m:IsA("Model") and not m:GetAttribute("DeadAt") and state~="Dead"
        and state~="Underground" and not m:GetAttribute("Hidden")
        and (tonumber(m:GetAttribute("HP")) or 1)>0
end
local function combatEnabled(m)
    if not m or not m.Parent or not monsterAlive(m) or not monsterAllowed(m) then return false end
    return (m:GetAttribute("Monster")=="Guardian" and A.Flags.Boss==true)
        or (m:GetAttribute("Monster")~="Guardian" and A.Flags.Enemies==true)
end
local function monsterAim(m)
    local pos=monsterPosition(m)
    -- Prefer a dedicated hitbox if present; otherwise use the actual head/body part.
    for _,name in {"Hitbox","HitBox","Hurtbox","Head","Torso","HumanoidRootPart"} do
        local part=m:FindFirstChild(name,true)
        if part and part:IsA("BasePart") then
            return pos+(part.Position-m:GetPivot().Position)
        end
    end
    return pos+Vector3.new(0,m:GetExtentsSize().Y/2+(tonumber(m:GetAttribute("Hover")) or 0),0)
end
local function headPose(m,aim)
    -- Face is the game's replicated yaw, in radians; it updates as the monster turns.
    local yaw=m:GetAttribute("Face")
    local forward=typeof(yaw)=="number" and CFrame.Angles(0,yaw,0).LookVector or m:GetPivot().LookVector
    forward=flat(forward)
    forward=forward.Magnitude>.001 and forward.Unit or Vector3.new(0,0,-1)
    local destination=aim-forward*3+Vector3.new(0,3,0)
    return CFrame.lookAt(destination,aim)
end
local function applyCombatLock(m,rt)
    -- Re-resolve the moving hitbox and reapply both aims in the same teleport step.
    local aim=monsterAim(m)
    rt.AssemblyLinearVelocity=Vector3.zero
    rt.AssemblyAngularVelocity=Vector3.zero
    rt.CFrame=headPose(m,aim)
    local camera=workspace.CurrentCamera
    if camera then
        local delta=aim-camera.CFrame.Position
        if delta.Magnitude>.05 then
            local up=math.abs(delta.Unit.Y)>.98 and Vector3.new(0,0,1) or Vector3.yAxis
            camera.CFrame=CFrame.lookAt(camera.CFrame.Position,aim,up)
        end
    end
    return aim
end
local function suspendedCombat()
    return P:GetAttribute("Down")==true or P:GetAttribute("GuardianIntro")==true
        or P:GetAttribute("InCutscene")==true or P:GetAttribute("InSequence")~=nil
end
local renderName="ForestAuditHeadLock_"..P.UserId
local RunService=game:GetService("RunService")
RunService:BindToRenderStep(renderName,Enum.RenderPriority.Camera.Value+1,function()
    if not alive() or not hoverTarget then return end
    local rt,hum=root()
    if not rt or not hum or hum.Health<=0 or hum.SeatPart or suspendedCombat()
        or not combatEnabled(hoverTarget) then clearHeadLock();return end
    if os.clock()<(A.DodgeHold or 0) then return end
    applyCombatLock(hoverTarget,rt)
end)
table.insert(connections,{Disconnect=function()
    RunService:UnbindFromRenderStep(renderName)
    clearHeadLock()
end})
A.MonsterAim=monsterAim
A.HeadPose=headPose
local function hazardContains(w,pos,margin)
    margin=margin or 3
    if w.Shape=="Circle" and typeof(w.At)=="Vector3" then
        return flat(pos-w.At).Magnitude<=(tonumber(w.Radius) or 6)+margin
    end
    local origin=w.From or w.At
    if typeof(origin)~="Vector3" or typeof(w.Dir)~="Vector3" then return false end
    local direction=flat(w.Dir)
    if direction.Magnitude<.001 then return false end
    direction=direction.Unit
    local delta=flat(pos-origin)
    local along=delta:Dot(direction)
    if w.Shape=="Line" then
        local across=(delta-direction*along).Magnitude
        return along>=-margin and along<=(tonumber(w.Length) or 30)+margin
            and across<=(tonumber(w.Width) or 6)/2+margin
    elseif w.Shape=="Cone" then
        local range=(tonumber(w.Range) or 20)+margin
        if delta.Magnitude<=margin then return true end
        return delta.Magnitude<=range and delta.Unit:Dot(direction)>=
            math.cos(math.rad((tonumber(w.Angle) or 45)/2+10))
    end
    return false
end
A.HazardContains=hazardContains
local function addWarning(kind,payload)
    if not alive() or kind~="Warn" or type(payload)~="table" then return end
    local warning=table.clone(payload)
    local time=math.clamp(tonumber(warning.Time) or 1,.1,20)
    local linger=warning.Kind=="Petals" and (Night.Signatures.PetalCloud.Lasts or 6) or .6
    warning.expires=os.clock()+time+linger
    table.insert(hazards,warning)
    if #hazards>64 then table.remove(hazards,1) end
end
local fx=CombatRemotes:FindFirstChild("MonsterFx")
if fx then table.insert(connections,fx.OnClientEvent:Connect(addWarning)) end
local function allMonsters()
    local folder=workspace:FindFirstChild("Monsters")
    return folder and folder:GetChildren() or {}
end
local function danger(pos,now)
    local score=0
    for _,w in hazards do
        if w.expires>now and hazardContains(w,pos) then score+=100 end
    end
    for _,m in allMonsters() do
        if monsterAlive(m) and m:GetAttribute("FuseAt") then
            local radius=Night.Minions.Roles.Bomber.Radius+4
            if flat(pos-monsterPosition(m)).Magnitude<radius then score+=150 end
        end
    end
    return score
end
local function groundPosition(pos,rt,hum)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local exclude={P.Character}
    for _,name in {"Monsters","MonsterFx","ChopLocal","Logs"} do
        local item=workspace:FindFirstChild(name)
        if item then table.insert(exclude,item) end
    end
    params.FilterDescendantsInstances=exclude
    local result=workspace:Raycast(pos+Vector3.new(0,25,0),Vector3.new(0,-80,0),params)
    if not result or result.Normal.Y<.55 then return nil end
    return Vector3.new(pos.X,result.Position.Y+hum.HipHeight+rt.Size.Y/2+.1,pos.Z)
end
local function dodge(now,rt,hum)
    for i=#hazards,1,-1 do if hazards[i].expires<=now then table.remove(hazards,i) end end
    if not A.Flags.Dodge then return false end
    local current=danger(rt.Position,now)
    if current==0 then return now<(A.DodgeHold or 0) end
    throttle(false)
    if now<nextDodge then return true end
    local best,bestCost=nil,math.huge
    for _,radius in {10,20,38,55} do
        for i=0,11 do
            local angle=i*math.pi/6
            local candidate=groundPosition(rt.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),rt,hum)
            if candidate then
                local cost=danger(candidate,now)*100+radius
                if cost<bestCost then best=candidate;bestCost=cost end
            end
        end
        if best and bestCost<100 then break end
    end
    if best and danger(best,now)<current then
        teleport(best)
        A.DodgeHold=now+.2
        record("dodge",{moved=true,beforeDanger=current,afterDanger=danger(best,now)})
        A.Status="Dodged attack warning"
    else A.Status="No safe dodge destination found" end
    nextDodge=now+.12
    return true
end
local function setHeld(tool,on)
    if tool=="Chainsaw" then throttle(on)
    elseif tool=="Flamethrower" then
        local remote=CombatRemotes:FindFirstChild("Flame")
        if remote then remote:FireServer(on) end
    end
end
releaseCombat=function()
    clearHeadLock()
    if heldCombatTool then setHeld(heldCombatTool,false);heldCombatTool=nil end
    if combatOriginalTool and P:GetAttribute("Tool")~=combatOriginalTool then
        R.EquipTool:FireServer(combatOriginalTool)
    end
    if combatOriginalGun and CombatRemotes:FindFirstChild("GunFire") then
        CombatRemotes.GunFire:FireServer("Equip",combatOriginalGun)
    end
    combatOriginalTool=nil;combatOriginalGun=nil;combatTarget=nil
end
local function pickMonster(rt)
    -- Keep a living target locked instead of switching as nearby enemies move.
    if combatEnabled(combatTarget) then return combatTarget end
    local best,score=nil,math.huge
    for _,m in allMonsters() do
        if monsterAlive(m) and monsterAllowed(m) then
            local boss=m:GetAttribute("Monster")=="Guardian"
            if (boss and A.Flags.Boss) or (not boss and A.Flags.Enemies) then
                local s=flat(monsterPosition(m)-rt.Position).Magnitude+(boss and -10000 or 0)
                if s<score then best=m;score=s end
            end
        end
    end
    return best
end
local function combat(now,rt,hum)
    if dodge(now,rt,hum) then
        clearHeadLock()
        if heldCombatTool then setHeld(heldCombatTool,false);heldCombatTool=nil end
        return true
    end
    local m=pickMonster(rt)
    if not m then
        if combatTarget then releaseCombat() end
        return false
    end
    if suspendedCombat() then
        clearHeadLock()
        if heldCombatTool then setHeld(heldCombatTool,false);heldCombatTool=nil end
        throttle(false);return true
    end
    if not combatTarget then
        combatOriginalTool=P:GetAttribute("Tool")
        combatOriginalGun=P:GetAttribute("GunOut")
    end
    combatTarget=m
    local newLock=hoverTarget~=m or hoverHumanoid~=hum
    if newLock then
        clearHeadLock()
        hoverTarget=m;hoverHumanoid=hum;previousAutoRotate=hum.AutoRotate
        hum.AutoRotate=false
        A.TeleportReady=now+A.TeleportDelay
    end
    local aim=applyCombatLock(m,rt)
    local gun
    if A.Flags.UseGuns then
        for _,id in {"Minigun","Rifle","Pistol"} do
            if P:GetAttribute("OwnsGun_"..id)==true then gun=id;break end
        end
    end
    local tool=gun
    if not tool then
        if P:GetAttribute("OwnsChainsaw")==true then tool="Chainsaw"
        elseif P:GetAttribute("OwnsFlamethrower")==true then tool="Flamethrower"
        elseif P:GetAttribute("OwnsAxe")==true then tool="Axe"
        else tool="Fists" end
    end
    if not gun and P:GetAttribute("Tool")~=tool then
        if now>=nextEquip then R.EquipTool:FireServer(tool);nextEquip=now+.5 end
        A.Status="Equipping "..tool;return true
    end
    local gunRemote=CombatRemotes:FindFirstChild("GunFire")
    if gun and P:GetAttribute("GunOut")~=gun then
        if gunRemote and now>=nextEquip then gunRemote:FireServer("Equip",gun);nextEquip=now+.5 end
        return true
    end
    if now<A.TeleportReady then return true end
    if not gun then
        local heatSpec=Math.Heat(P,tool)
        if heatSpec then
            local keys=tool=="Flamethrower" and Heat.FLAME_KEYS or Heat.KEYS
            local _,locked=Original.At(Heat.Read(P,{},keys),heatSpec,workspace:GetServerTimeNow())
            if locked then
                if heldCombatTool then setHeld(heldCombatTool,false);heldCombatTool=nil end
                A.Status="Combat: waiting for server heat recovery"
                return true
            end
        end
    end
    if gun and gunRemote and now>=nextAttack then
        local head=P.Character:FindFirstChild("Head")
        if head then
            local delta=aim-head.Position
            if delta.Magnitude>.1 then gunRemote:FireServer("Fire",gun,head.Position,delta.Unit);A.Requests+=1 end
        end
        nextAttack=now+1/Night.Guns[gun].Rate
    elseif not gun then
        if tool=="Chainsaw" or tool=="Flamethrower" then
            if heldCombatTool~=tool or now>=nextAttack then
                heldCombatTool=tool
                if tool=="Chainsaw" then R.Throttle:FireServer(true);revving=true
                else setHeld(tool,true) end
                nextAttack=now+.35
            end
        elseif now>=nextAttack then
            R.Swing:FireServer(1);A.Requests+=1
            nextAttack=now+math.max(.08,Config.Tools[tool].Interval*Math.SwingScale(P,tool))
        end
    end
    if now>=nextHP then
        nextHP=now+.6
        local hp=tonumber(m:GetAttribute("HP")) or 0
        local beforeHP=hp
        task.delay(.5,function()
            if alive() and m.Parent then
                local after=tonumber(m:GetAttribute("HP")) or 0
                record("combat",{target=m.Name,boss=m:GetAttribute("Monster")=="Guardian",
                    before=beforeHP,after=after,damageObserved=after<beforeHP,
                    lastHitBy=m:GetAttribute("HitBy"),dead=m:GetAttribute("DeadAt")~=nil or after<=0})
            end
        end)
    end
    A.Status="Head locked: "..tostring(m:GetAttribute("DisplayName") or m.Name).." | "..tool
    return true
end

local attemptedLogs=setmetatable({},{__mode="k"})
local function logCandidates(rt,now)
    local list={}
    local logs=workspace:FindFirstChild("Logs")
    if logs then for _,v in logs:GetChildren() do
        if v:IsA("Model") and v:HasTag("Log") and (attemptedLogs[v] or 0)<now then
            table.insert(list,{model=v,distance=(v:GetPivot().Position-rt.Position).Magnitude})
        end
    end end
    table.sort(list,function(x,y) return x.distance<y.distance end)
    return list
end
local function collect(now,rt,list)
    if now<nextCollect then return true end
    local count=P:GetAttribute("CarriedLogs") or 0
    local cap=serverCapacity()
    -- With the tamper probe enabled, deliberately test past the server capacity.
    if count>=cap and not A.Flags.Bag then return false end
    list=list or logCandidates(rt,now)
    if #list==0 then return false end
    local first=list[1].model
    if list[1].distance>12 then
        teleport(first:GetPivot().Position+Vector3.new(0,3,0))
        nextCollect=now+A.TeleportDelay
        A.Status="Teleported to log cluster"
        return true
    end
    if now<A.TeleportReady then return true end
    nextCollect=now+.05
    local sent=0
    for _,entry in list do
        if entry.distance>14 or sent>=16 then break end
        if not A.Flags.Bag and count+sent>=cap then break end
        local model=entry.model
        attemptedLogs[model]=now+.4
        R.PickUpLog:FireServer(model)
        A.Requests+=1
        sent+=1
    end
    A.Status="Collecting log cluster"
    if sent>0 then task.delay(.35,function()
        if alive() then
            local after=P:GetAttribute("CarriedLogs") or 0
            record("collect",{before=count,after=after,capacity=cap,
                sent=sent,accepted=after>count,overflow=after>cap})
        end
    end) end
    return true
end
local sale
local nextSellAttempt=0
local function stations()
    local list=CS:GetTagged("SellOutpost")
    local map=workspace:FindFirstChild("Map")
    local main=map and map:FindFirstChild("SellSpot")
    if main then table.insert(list,main) end
    return list
end
local function nearestStation(rt)
    local best,pad,dist=nil,nil,math.huge
    for _,s in stations() do
        local p=s:FindFirstChild("DepositPad")
        if p and p:IsA("BasePart") then
            local d=(p.Position-rt.Position).Magnitude
            if d<dist then best=s;pad=p;dist=d end
        end
    end
    return best,pad
end
local sawSale
local nextSawSale=0
local function sawCargoFull(vehicle)
    local count=tonumber(vehicle:GetAttribute("CargoCount")) or 0
    local cap=tonumber(vehicle:GetAttribute("Capacity")) or 0
    return cap>0 and count>=cap,count,cap
end
local function parkSawForSale(vehicle,station,pad)
    local bed=vehicle:FindFirstChild("LogBed")
    bed=bed and bed:FindFirstChild("BedZone")
    local seat=vehicle:FindFirstChild("DriverSeat")
    if not bed or not bed:IsA("BasePart") or not seat then return false end
    local pivot=vehicle:GetPivot()
    -- Put the midpoint of driver and cargo beside the pad, within both sell ranges.
    local center=(bed.Position+seat.Position)/2
    local away=(center-pad.Position)*Vector3.new(1,0,1)
    away=away.Magnitude>.01 and away.Unit or Vector3.new(1,0,0)
    local rotation=CFrame.lookAt(Vector3.zero,-away)
    local localCenter=pivot:PointToObjectSpace(center)
    local pos=pad.Position+away*10-rotation:VectorToWorldSpace(localCenter)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local exclude={P.Character,vehicle,station}
    for _,name in {"Vehicles","Logs","Trees","Monsters","ChopLocal","ForestHuts"} do
        local folder=workspace:FindFirstChild(name)
        if folder then table.insert(exclude,folder) end
    end
    params.FilterDescendantsInstances=exclude
    local hit=workspace:Raycast(Vector3.new(pos.X,pad.Position.Y+40,pos.Z),Vector3.new(0,-140,0),params)
    local box,size=vehicle:GetAttribute("DriveBox"),vehicle:GetAttribute("DriveSize")
    if not hit or hit.Normal.Y<.55 or typeof(box)~="CFrame" or typeof(size)~="Vector3" then return false end
    pos=Vector3.new(pos.X,hit.Position.Y-box.Position.Y+size.Y/2+.3,pos.Z)
    moveSaw(vehicle,CFrame.new(pos)*rotation)
    return true
end
local function sellSaw(now,vehicle)
    if not A.Flags.SawSell then sawSale=nil;return false end
    if sawSale and sawSale.vehicle~=vehicle then sawSale=nil end
    local full,count,cap=sawCargoFull(vehicle)
    if not sawSale then
        if now<nextSawSale or not full then return false end
        local station,pad=nearestStation(vehicle.PrimaryPart)
        if not station then A.Status="Big Saw: no selling station loaded";nextSawSale=now+3;return true end
        sawSale={vehicle=vehicle,station=station,pad=pad,origin=vehicle:GetPivot(),
            before=count,capacity=cap,started=now,lastSend=0,lastPark=0}
    end
    local state=sawSale
    throttle(false)
    if count==0 then
        moveSaw(vehicle,state.origin)
        record("sawSell",{before=state.before,after=0,capacity=state.capacity,accepted=true,
            station=state.station:GetFullName(),returned=true})
        sawSale=nil;nextSawSale=now+1;target=nil;vehicleTarget=nil
        A.Status="Big Saw emptied; returned to cutting spot"
        return true
    end
    if not state.pad.Parent or now-state.started>15 then
        record("sawSell",{before=state.before,after=count,accepted=count<state.before,complete=false})
        moveSaw(vehicle,state.origin)
        sawSale=nil;nextSawSale=now+5
        A.Status="Big Saw sale not completed; returned to cutting spot"
        return true
    end
    local rt=root()
    local bed=vehicle:FindFirstChild("LogBed")
    bed=bed and bed:FindFirstChild("BedZone")
    local near=rt and bed and bed:IsA("BasePart")
        and (rt.Position-state.pad.Position).Magnitude<(Config.Selling.ServerDepositReach or 24)-1
        and ((bed.Position-state.pad.Position)*Vector3.new(1,0,1)).Magnitude<(Config.Selling.TruckSellReach or 30)-2
    if not near then
        if now-state.lastPark>=1 then
            state.lastPark=now
            if parkSawForSale(vehicle,state.station,state.pad) then
                A.Status="Big Saw full; teleported to sell zone"
            else A.Status="Big Saw: looking for safe ground at sell zone" end
        end
        return true
    end
    if now<A.TeleportReady then return true end
    if now-state.lastSend>=math.max(.5,Config.Selling.DepositInterval or .5) then
        -- The normal sell UI sends true to include owned truck cargo.
        R.DepositLogs:FireServer(true);A.Requests+=1;state.lastSend=now
    end
    A.Status=string.format("Selling Big Saw cargo: %d / %d",count,cap)
    return true
end
A.SawCargoFull=sawCargoFull
local function atStation(station,pad)
    teleport(pad.Position+pad.CFrame.UpVector*(pad.Size.Y/2+3.1))
    A.Status="Teleported to nearest selling station"
end
local function sell(now,rt)
    if not A.Flags.Sell then sale=nil;return false end
    local count=P:GetAttribute("CarriedLogs") or 0
    local cap=serverCapacity()
    if sale then
        local pad=sale.pad
        if not pad.Parent then sale=nil;return false end
        if (rt.Position-pad.Position).Magnitude>18 then
            atStation(sale.station,pad);return true
        end
        if now<A.TeleportReady then return true end
        if now-(sale.lastSend or 0)>.5 and count>0 then
            R.DepositLogs:FireServer(false);A.Requests+=1;sale.lastSend=now
        end
        if count==0 and now-sale.started>.2 then
            record("sell",{before=sale.before,after=count,accepted=true,station=sale.station:GetFullName()})
            sale=nil;nextSellAttempt=now+1
            target=nil
            return true
        end
        if now-sale.started>5 then
            record("sell",{before=sale.before,after=count,accepted=count<sale.before})
            sale=nil;nextSellAttempt=now+3
        end
        return true
    end
    if count>0 and now>=nextSellAttempt and
        count>=cap then
        local s,pad=nearestStation(rt)
        if s then
            sale={station=s,pad=pad,before=count,started=now}
            atStation(s,pad)
            return true
        end
        A.Status="No loaded selling stations"
    end
    return false
end

-- Tool purchases use the same coin-only BuyTool request as the station UI.
local toolBuyOrder={"Axe","Chainsaw"}
local includedTools={Axe=true,Chainsaw=true}
for _,id in Config.Tools.Order or {} do
    local spec=Config.Tools[id]
    if not includedTools[id] and type(spec)=="table" and type(spec.Price)=="number"
        and spec.Price>0 and spec.Price<math.huge then
        includedTools[id]=true
        table.insert(toolBuyOrder,id)
    end
end
local function toolPurchasePlan()
    for _,id in toolBuyOrder do
        local spec=Config.Tools[id]
        if spec and type(spec.Price)=="number" and spec.Price>0 and spec.Price<math.huge
            and P:GetAttribute("Owns"..id)~=true then
            local prerequisite=spec.RequiresItem
            if prerequisite and not Math.HasItem(P,prerequisite) then
                local item=Math.Find(prerequisite)
                local level=Math.Level(P,prerequisite)
                local price=item and item.Prices and item.Prices[level+1]
                if type(price)~="number" then
                    return {blocked="Required item unavailable: "..tostring(prerequisite),tool=id}
                end
                return {kind="Upgrade",id=prerequisite,tool=id,price=price,level=level,
                    name=item.Name or prerequisite,shop=prerequisite=="GearBackpack" and "Backpack" or prerequisite}
            end
            return {kind="Tool",id=id,tool=id,price=spec.Price,name=spec.DisplayName or id,shop=id}
        end
    end
    return nil
end
A.ToolPurchasePlan=toolPurchasePlan
local purchaseState
local nextToolPurchase=0
local function planOwned(plan)
    if plan.kind=="Tool" then return P:GetAttribute("Owns"..plan.id)==true end
    return Math.Level(P,plan.id)>plan.level
end
local function buyToolStep(now,rt)
    if not A.Flags.AutoTools then
        A.ToolStatus="Auto tool buying OFF"
        -- A request already sent is allowed to finish; disabling never sends another.
        if purchaseState and not purchaseState.inFlight then purchaseState=nil end
        return false
    end
    if purchaseState then
        local state=purchaseState
        if state.inFlight then
            A.ToolStatus="Waiting for purchase: "..state.plan.name
            return now-state.sentAt<8
        end
        if state.sentAt then
            if not state.error and planOwned(state.plan) then
                record("toolPurchase",{tool=state.plan.tool,item=state.plan.id,
                    price=state.plan.price,accepted=true,response=state.response})
                if state.plan.kind=="Tool" then
                    -- Upgrade the farming tool; utility purchases keep the chainsaw equipped.
                    local equip=state.plan.id=="Axe" and "Axe"
                        or (P:GetAttribute("OwnsChainsaw")==true and "Chainsaw" or state.previousTool)
                    if equip then R.EquipTool:FireServer(equip) end
                end
                A.ToolStatus="Purchased "..state.plan.name
                purchaseState=nil
                nextToolPurchase=now+.5
                return true
            end
            if now-state.sentAt<2 then return true end
            local why=state.error or (type(state.response)=="table" and state.response.Why) or "Not confirmed"
            record("toolPurchase",{tool=state.plan.tool,item=state.plan.id,
                accepted=false,reason=tostring(why),response=state.response})
            A.ToolStatus="Purchase pending/rejected: "..tostring(why)
            purchaseState=nil
            nextToolPurchase=now+3
            return false
        end
    end
    if now<nextToolPurchase then return false end
    local plan=toolPurchasePlan()
    if not plan then A.ToolStatus="All coin-priced tools owned";return false end
    if plan.blocked then A.ToolStatus=plan.blocked;nextToolPurchase=now+3;return false end
    local stats=P:FindFirstChild("leaderstats")
    local cash=stats and stats:FindFirstChild("Cash")
    if not cash or cash.Value<plan.price then
        A.ToolStatus=string.format("Saving for %s: %s / %s coins",plan.name,
            tostring(cash and cash.Value or 0),tostring(plan.price))
        return false
    end
    local anchor,best=nil,math.huge
    for _,station in workspace:GetDescendants() do
        if station:GetAttribute("ShopItem")==plan.shop then
            local prompt=station:FindFirstChildWhichIsA("ProximityPrompt",true)
            local at=prompt and prompt.Parent
            local pos=at and ((at:IsA("Attachment") and at.WorldPosition)
                or (at:IsA("BasePart") and at.Position))
            if pos then
                local distance=(pos-rt.Position).Magnitude
                if distance<best then anchor,best=pos,distance end
            end
        end
    end
    if not anchor then A.ToolStatus="Waiting for station: "..plan.name;nextToolPurchase=now+3;return false end
    if best>8 then
        local away=(rt.Position-anchor)*Vector3.new(1,0,1)
        away=away.Magnitude>.01 and away.Unit or Vector3.new(1,0,0)
        teleport(anchor+away*4+Vector3.new(0,.5,0),anchor)
        A.ToolStatus="Going to "..plan.name.." station"
        return true
    end
    if now<A.TeleportReady then return true end
    if not A.Flags.AutoTools or not alive() or planOwned(plan) then return false end
    throttle(false)
    local state={plan=plan,previousTool=P:GetAttribute("Tool"),sentAt=now,inFlight=true}
    purchaseState=state
    A.ToolStatus="Buying "..plan.name.." for "..tostring(plan.price).." coins"
    task.spawn(function()
        local ok,response=pcall(function()
            if plan.kind=="Tool" then return R.BuyTool:InvokeServer(plan.id) end
            R.BuyUpgrade:FireServer(plan.id)
            return {Requested=true}
        end)
        state.response=ok and response or nil
        state.error=not ok and tostring(response) or nil
        state.inFlight=false
        if alive() then A.Requests+=1 end
    end)
    return true
end

local function upgrade(now)
    if now<nextUpgrade then return end
    nextUpgrade=now+.5
    local stats=P:FindFirstChild("leaderstats")
    local cash=stats and stats:FindFirstChild("Cash")
    if not cash then return end
    local spendable=cash.Value
    if A.Flags.AutoTools then
        local plan=toolPurchasePlan()
        if plan then
            -- Ordinary upgrades cannot drain savings for the next tool/prerequisite.
            spendable=plan.price and math.max(0,spendable-plan.price) or 0
        end
    end
    for _,section in Config.Upgrades.Sections do
        if section.Tool==P:GetAttribute("Tool") or section.Tool==nil or section.Tool=="Gear" then
            for _,item in section.Items do
                local level=Math.Level(P,item.Id)
                local price=item.Prices[level+1]
                if price and price<=spendable then
                    R.BuyUpgrade:FireServer(item.Id);A.Requests+=1
                    task.delay(.6,function()
                        if alive() then record("upgrade",{id=item.Id,before=level,
                            after=Math.Level(P,item.Id),accepted=Math.Level(P,item.Id)>level}) end
                    end)
                    return
                end
            end
        end
    end
end
A.Set=function(key,value)
    assert(A.Controls[key], "Unknown toggle")
    A.Controls[key]:Set(value)
end

task.spawn(function()
    while alive() do
        local ok,err=pcall(function()
            local rt,hum=root()
            if not rt or not hum or hum.Health<=0 then throttle(false);return end
            local now=os.clock()
            -- Foot combat/pickup/shop routines rotate the character directly. Keep the
            -- driver's seat and vehicle cutting in control while operating the Big Saw.
            local vehicle=drivenSaw(hum)
            if vehicle then
                if combatTarget then releaseCombat() end
                if sellSaw(now,vehicle) then return end
                if A.Flags.Cut then cut(now,rt,hum) else throttle(false) end
                return
            end
            sawSale=nil
            if combat(now,rt,hum) then return end
            if A.Flags.AutoTools and buyToolStep(now,rt) then return end
            if A.Flags.Upgrade then upgrade(now) end
            local drops=logCandidates(rt,now)
            if sell(now,rt) then return end
            if A.Flags.Collect and collect(now,rt,drops) then throttle(false);return end
            if A.Flags.Cut and now>(A.WaitForDrops or 0) then cut(now,rt,hum) else throttle(false) end
        end)
        if not ok then
            A.Status=tostring(err)
            warn("Forest audit: "..tostring(err))
            stopFeatures()
        end
        task.wait(.025)
    end
end)
Window:SelectTab(1)
WindUI:Notify({Title="Validation Lab ready",Content="All toggles OFF. Right Ctrl shows/hides the panel.",Duration=5})
return {ready=true,placeId=game.PlaceId,features=12,nextTool=toolPurchasePlan(),sellPolicy="actual_full_capacity",sawSellPolicy="actual_full_cargo"}