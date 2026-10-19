-- Catch the Artist! - Rayfield Gen2 word reader for Real.
-- Recovers the current client theme and listens for new announcements.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
assert(game.GameId == 10381189313, "Join Catch the Artist first.")

local env = getgenv()
local previous = env.CatchArtistWordReader
local carriedWord = nil
if type(previous) == "table" then
    if type(previous.Stop) == "function" then previous.Stop() end
end

local player = Players.LocalPlayer
local modules = ReplicatedStorage:WaitForChild("Modules", 10)
assert(modules, "Modules not loaded.")
local utilities = modules:WaitForChild("Utilities", 10)
assert(utilities, "Utilities not loaded.")
local remotes = utilities:WaitForChild("TypedRemote", 10)
assert(remotes, "Remotes not loaded.")
local themeEvent = remotes:WaitForChild("UpdateTheme", 10)
assert(themeEvent and themeEvent:IsA("RemoteEvent"), "Theme event not found.")

local reader = {Word = carriedWord, Running = true}
local connections = {}
local playerConnections = {}
local window = nil
local wordCard = nil
local roleCard = nil
local phaseCard = nil
local imposterCard = nil
local status = "Listening for the next theme"
local statusCard = nil

local espEnabled = true
local espHighlights = {}
local function removeImposterESP(other)
    local highlight = espHighlights[other]
    if highlight then highlight:Destroy() end
    espHighlights[other] = nil
end
local function updateImposterESP(other)
    setthreadidentity(8)
    local character = other.Character
    local show = reader.Running and espEnabled and other~=player
        and other:GetAttribute("InRound")==true and other:GetAttribute("Role")=="Imposter"
        and character~=nil
    if not show then
        removeImposterESP(other)
        return
    end
    local highlight = espHighlights[other]
    if highlight and (highlight.Parent~=character or highlight.Adornee~=character) then
        removeImposterESP(other)
        highlight = nil
    end
    if not highlight then
        local leftover = character:FindFirstChild("CatchArtist_ImposterESP")
        if leftover and leftover:IsA("Highlight") then leftover:Destroy() end
        highlight = Instance.new("Highlight")
        highlight.Name = "CatchArtist_ImposterESP"
        highlight.Adornee = character
        highlight.FillColor = Color3.fromRGB(255,0,0)
        highlight.OutlineColor = Color3.fromRGB(255,0,0)
        highlight.FillTransparency = 0.4
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = character
        espHighlights[other] = highlight
    end
    highlight.Enabled = true
end
local function updateAllImposterESP()
    for _,other in ipairs(Players:GetPlayers()) do updateImposterESP(other) end
end
reader.SetESPEnabled=function(enabled)
    espEnabled = enabled==true
    updateAllImposterESP()
end

local function getImposters()
    local names = {}
    for _, other in ipairs(Players:GetPlayers()) do
        if other:GetAttribute("InRound") == true and other:GetAttribute("Role") == "Imposter" then
            table.insert(names, other.DisplayName .. " (@" .. other.Name .. ")" .. (other == player and " - YOU" or ""))
        end
    end
    table.sort(names)
    return names
end

local function refresh()
    setthreadidentity(8)
    if not window or window.unloaded or not wordCard then return end
    wordCard:SetTitle(reader.Word and ("DRAW: " .. reader.Word) or "Waiting for a word")
    wordCard:Set(reader.Word and "Current captured theme" or "Keep this open for the next theme announcement.")
    roleCard:Set(tostring(player:GetAttribute("Role") or "None"))
    phaseCard:Set(tostring(player:GetAttribute("RoundPhase") or "Waiting"))
    statusCard:Set(status)
    local names = getImposters()
    if #names > 0 then
        imposterCard:Set(table.concat(names, "\n"))
    elseif player:GetAttribute("InRound") ~= true then
        imposterCard:Set("Waiting for a round")
    else
        imposterCard:Set("Not revealed to client")
    end
end

local function clear()
    reader.Word = nil
    status = "Listening for the next theme"
    refresh()
end

function reader.GetWord()
    return reader.Word
end

function reader.Stop()
    setthreadidentity(8)
    if not reader.Running then return end
    reader.Running = false
    for other in pairs(espHighlights) do removeImposterESP(other) end
    local imageCleanup = rawget(reader,"ImageCleanup")
    if type(imageCleanup)=="function" then imageCleanup() end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
    for _, list in pairs(playerConnections) do
        for _, connection in ipairs(list) do connection:Disconnect() end
    end
    table.clear(playerConnections)
    if window and not window.unloaded then window:Unload() end
end

local function validWord(value)
    return type(value) == "string" and value ~= "" and value ~= "nil"
        and not string.find(value, "?", 1, true)
end

local function acceptWord(word, source)
    if not validWord(word) then return false end
    reader.Word = word
    status = source
    refresh()
    return true
end

local function findThemeLabel()
    local gui = player.PlayerGui:FindFirstChild("GUI")
    local top = gui and gui:FindFirstChild("TopFrame")
    local frame = top and top:FindFirstChild("ThemeFrame")
    local label = frame and frame:FindFirstChild("ThemeLabel")
    if label and label:IsA("TextLabel") then return label end
    return nil
end

local function recoverWord()
    if not reader.Running or player:GetAttribute("InRound") ~= true then return false end
    local label = findThemeLabel()
    if not label then return false end

    -- Match only the game's theme-animation closure, never walk the whole GC.
    -- v476: slots 1/2 are announcement versions, 5 is the label, 10 is the actual theme.
    local ok, matches = pcall(function()
        return filtergc("function", {
        Constants = {"Next Theme: ???", "Theme: "},
        Upvalues = {label},
        IgnoreExecutor = true,
        }, false)
    end)
    if ok and type(matches) == "table" then
        for index, fn in ipairs(matches) do
            if index > 8 then break end
            local success, values = pcall(debug.getupvalues, fn)
            if success and values[3] == player and values[5] == label
                and type(values[1]) == "number" and values[1] == values[2]
                and validWord(values[10]) then
                return acceptWord(values[10], "Recovered current theme")
            end
        end
    end

    -- Only trust the settled label. "Next Theme" contains random animation decoys.
    local text = label.Text:match("^Theme:%s*(.+)$")
    if label.Parent.Visible and acceptWord(text, "Read current theme") then return true end
    if not reader.Word then
        status = "Current word unavailable; waiting for next theme"
        refresh()
    end
    return false
end

-- Listen before downloading the GUI so a theme arriving during loading is captured.
table.insert(connections, themeEvent.OnClientEvent:Connect(function(word)
    if not reader.Running then return end
    if type(word) ~= "string" or word == "" or string.find(word, "?", 1, true) then
        reader.Word = nil
        status = "The server did not supply a readable word"
    else
        reader.Word = word
        status = "Theme captured"
        print("[Word Reader] DRAW: " .. word)
    end
    refresh()
end))

-- ShowRole can arrive after UpdateTheme; it must not erase a captured theme.
local syncEvent = remotes:FindFirstChild("SyncState")
local lastPhase = nil
if syncEvent and syncEvent:IsA("RemoteEvent") then
    table.insert(connections, syncEvent.OnClientEvent:Connect(function(phase)
        if phase == lastPhase then return end
        lastPhase = phase
        if phase == "Waiting" or phase == "Intermission" then
            clear()
        else
            task.defer(recoverWord)
        end
    end))
end
local currentLabel = findThemeLabel()
if currentLabel then
    table.insert(connections, currentLabel:GetPropertyChangedSignal("Text"):Connect(function()
        if player:GetAttribute("InRound") ~= true then return end
        local text = currentLabel.Text:match("^Theme:%s*(.+)$")
        if validWord(text) then acceptWord(text, "Read current theme") end
    end))
end
recoverWord()
table.insert(connections, player:GetAttributeChangedSignal("InRound"):Connect(function()
    if player:GetAttribute("InRound") ~= true then clear() end
end))
for _, attribute in ipairs({"Role", "RoundPhase"}) do
    table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(refresh))
end
local function watchPlayer(other)
    if playerConnections[other] then return end
    playerConnections[other] = {
        other:GetAttributeChangedSignal("Role"):Connect(function() updateImposterESP(other); refresh() end),
        other:GetAttributeChangedSignal("InRound"):Connect(function() updateImposterESP(other); refresh() end),
        other.CharacterAdded:Connect(function() updateImposterESP(other) end),
        other.CharacterRemoving:Connect(function() removeImposterESP(other) end),
        other:GetPropertyChangedSignal("DisplayName"):Connect(refresh),
    }
    updateImposterESP(other)
end
table.insert(connections, Players.PlayerAdded:Connect(function(other)
    watchPlayer(other)
    refresh()
end))
table.insert(connections, Players.PlayerRemoving:Connect(function(other)
    removeImposterESP(other)
    local list = playerConnections[other]
    if list then
        for _, connection in ipairs(list) do connection:Disconnect() end
        playerConnections[other] = nil
    end
    task.defer(function()
        if reader.Running then refresh() end
    end)
end))
for _, other in ipairs(Players:GetPlayers()) do watchPlayer(other) end
reader.GetImposters = getImposters
env.CatchArtistWordReader = reader

local reloadState = ... -- Live-reload runner may pass its STATE table.
if type(reloadState) == "table" and type(reloadState.onCleanup) == "function" then
    reloadState.onCleanup(reader.Stop)
end

-- Small colored sketches; coordinates use the game's native 512 x 288 canvas.
local sketches = {}
local palette = {
    ink=Color3.fromRGB(32,38,48), blue=Color3.fromRGB(54,158,229),
    red=Color3.fromRGB(235,83,78), orange=Color3.fromRGB(247,160,57),
    green=Color3.fromRGB(78,173,104), brown=Color3.fromRGB(144,95,61),
    yellow=Color3.fromRGB(250,211,86), white=Color3.new(1,1,1),
    pink=Color3.fromRGB(248,160,184), pale=Color3.fromRGB(212,237,249),
}
local function artist(image, practice)
    local a = {}
    function a.line(points, color, width)
        for i=2,#points do
            practice.drawStrokeSegment(image,Vector2.new(points[i-1][1],points[i-1][2]),
                Vector2.new(points[i][1],points[i][2]),width or 3,palette[color or "ink"],0,Enum.AntiAliasing.Enabled)
        end
    end
    function a.rect(x,y,w,h,color)
        image:DrawRectangle(Vector2.new(x,y),Vector2.new(w,h),palette[color],0,Enum.ImageCombineType.Overwrite)
    end
    function a.circle(x,y,r,color)
        image:DrawCircle(Vector2.new(x,y),r,palette[color],0,Enum.ImageCombineType.Overwrite,Enum.AntiAliasing.Enabled)
    end
    function a.oval(x,y,rx,ry,color)
        for dy=-ry,ry do
            local dx=math.floor(rx*math.sqrt(math.max(0,1-(dy/ry)^2)))
            a.rect(x-dx,y+dy,math.max(1,dx*2),1,color)
        end
    end
    function a.ring(x,y,rx,ry,color,width)
        local points={}
        for i=0,48 do
            local t=i*math.pi/24
            table.insert(points,{x+math.cos(t)*rx,y+math.sin(t)*ry})
        end
        a.line(points,color,width)
    end
    return a
end
function sketches.fish(a)
    a.oval(252,145,94,49,"orange")
    a.line({{172,145},{120,100},{120,190},{172,145}},"orange",9)
    a.circle(304,133,7,"ink")
    a.line({{250,102},{230,73},{281,104}},"red",5)
    a.line({{285,152},{300,160},{314,154}},"ink",2)
    for _,p in ipairs({{365,95},{385,65},{397,119}}) do a.ring(p[1],p[2],8,8,"blue",2) end
    a.line({{90,232},{160,224},{230,233},{300,223},{385,232}},"blue",3)
end
function sketches.cat(a)
    a.oval(253,181,64,53,"orange")
    a.circle(253,109,52,"orange")
    a.line({{209,84},{205,40},{244,69},{270,69},{300,40},{296,87}},"orange",9)
    a.circle(233,104,5,"ink") ; a.circle(275,104,5,"ink")
    a.circle(254,121,5,"pink")
    a.line({{254,126},{241,138},{229,132}},"ink",2)
    a.line({{254,126},{266,138},{279,132}},"ink",2)
    a.line({{208,121},{171,113}},"ink",2) ; a.line({{298,121},{334,113}},"ink",2)
    a.line({{304,202},{351,190},{371,150},{352,138}},"orange",9)
    a.oval(225,225,22,8,"orange") ; a.oval(281,225,22,8,"orange")
end
function sketches.bird(a)
    a.oval(257,151,70,44,"blue") ; a.circle(305,112,32,"blue")
    a.line({{332,106},{365,119},{332,126}},"orange",5)
    a.circle(315,106,5,"ink")
    a.line({{205,145},{130,80},{173,163},{113,175},{205,166}},"blue",7)
    a.line({{252,144},{281,160},{248,177},{222,160}},"ink",2)
    a.line({{251,192},{251,224},{236,229}},"orange",3)
    a.line({{279,191},{279,221},{296,226}},"orange",3)
end
function sketches.bear(a)
    a.circle(217,66,22,"pale") ; a.circle(295,66,22,"pale")
    a.oval(256,180,80,63,"pale") ; a.circle(256,111,60,"pale")
    a.circle(234,104,5,"ink") ; a.circle(277,104,5,"ink")
    a.oval(256,131,28,19,"white") ; a.circle(256,124,8,"ink")
    a.line({{241,142},{256,149},{271,142}},"ink",2)
    a.oval(206,226,27,14,"pale") ; a.oval(306,226,27,14,"pale")
end
function sketches.car(a)
    a.rect(132,138,250,69,"red")
    a.line({{166,139},{199,87},{296,87},{339,139}},"red",9)
    a.rect(205,98,40,35,"pale") ; a.rect(256,98,38,35,"pale")
    a.circle(187,205,29,"ink") ; a.circle(330,205,29,"ink")
    a.circle(187,205,13,"pale") ; a.circle(330,205,13,"pale")
    a.rect(363,151,19,16,"yellow")
end
function sketches.bus(a)
    a.rect(110,79,294,131,"yellow")
    for x=128,333,48 do a.rect(x,96,35,43,"pale") end
    a.rect(348,96,38,102,"blue")
    a.circle(166,211,28,"ink") ; a.circle(346,211,28,"ink")
    a.circle(166,211,12,"white") ; a.circle(346,211,12,"white")
end
function sketches.plane(a)
    a.line({{91,151},{394,151},{418,137}},"blue",11)
    a.line({{251,147},{201,67},{232,67},{310,147}},"blue",8)
    a.line({{251,159},{190,222},{222,222},{315,159}},"blue",8)
    a.line({{111,146},{89,104},{119,104},{161,146}},"blue",7)
    for x=182,359,30 do a.circle(x,149,4,"white") end
end
function sketches.boat(a)
    a.line({{121,181},{151,225},{350,225},{391,181},{121,181}},"brown",7)
    a.line({{256,178},{256,50},{343,166},{256,166}},"blue",5)
    a.line({{243,75},{166,164},{243,164},{243,75}},"orange",5)
    a.line({{80,244},{150,236},{220,245},{290,236},{360,245},{430,237}},"blue",3)
end
function sketches.bike(a)
    a.ring(155,195,50,50,"ink",3) ; a.ring(356,195,50,50,"ink",3)
    a.line({{155,195},{213,123},{274,195},{155,195},{244,195},{305,108},{356,195}},"red",4)
    a.line({{198,118},{232,118}},"ink",4)
    a.line({{303,108},{299,85},{329,83}},"ink",4)
end
function sketches.ball(a)
    a.circle(256,145,93,"orange") ; a.ring(256,145,93,93,"ink",3)
    a.line({{164,145},{348,145}},"ink",3) ; a.line({{256,53},{256,237}},"ink",3)
    a.line({{194,78},{222,107},{231,147},{220,188},{193,211}},"ink",3)
    a.line({{317,78},{290,107},{281,147},{291,188},{318,211}},"ink",3)
end
function sketches.racket(a)
    a.ring(240,111,58,75,"blue",5)
    for x=207,274,16 do a.line({{x,65},{x,157}},"ink",1) end
    for y=80,145,16 do a.line({{193,y},{287,y}},"ink",1) end
    a.line({{240,186},{240,249}},"brown",8) ; a.circle(349,195,22,"green")
end
function sketches.runner(a)
    a.circle(267,61,23,"orange")
    a.line({{263,89},{245,143},{297,171},{331,219}},"blue",7)
    a.line({{246,142},{213,191},{161,196}},"blue",7)
    a.line({{257,104},{213,118},{188,91}},"orange",5)
    a.line({{257,104},{300,124},{331,97}},"orange",5)
    a.line({{143,103},{178,103}},"ink",2) ; a.line({{124,135},{170,135}},"ink",2)
    a.line({{120,240},{391,240}},"green",3)
end
function sketches.swimmer(a)
    a.circle(318,127,22,"orange")
    a.line({{145,169},{265,152},{286,123},{259,85},{219,112}},"blue",6)
    for y=182,234,26 do a.line({{91,y},{141,y-8},{191,y},{241,y-8},{291,y},{341,y-8},{391,y}},"blue",3) end
end
function sketches.mountain(a)
    a.line({{85,230},{229,57},{325,192},{365,114},{442,230},{85,230}},"blue",5)
    a.line({{193,101},{220,115},{234,99},{255,119},{270,110}},"blue",3)
    a.circle(369,63,25,"yellow")
end
function sketches.tree(a)
    a.rect(238,139,36,100,"brown")
    a.circle(209,112,48,"green") ; a.circle(285,112,49,"green") ; a.circle(248,73,54,"green")
    a.line({{127,244},{386,244}},"green",3)
end
function sketches.house(a)
    a.rect(163,124,190,118,"orange")
    a.line({{134,125},{258,40},{382,125},{134,125}},"red",5)
    a.rect(236,170,43,72,"brown")
    a.rect(183,146,34,35,"pale") ; a.rect(299,146,34,35,"pale")
    a.circle(270,209,3,"yellow")
end
function sketches.bed(a)
    a.rect(131,153,254,53,"blue") ; a.rect(131,104,15,133,"brown")
    a.rect(370,179,15,58,"brown") ; a.rect(148,132,67,29,"pale")
    a.rect(214,138,154,21,"blue")
end
function sketches.chair(a)
    a.rect(181,57,145,100,"orange") ; a.rect(165,158,177,23,"brown")
    a.rect(177,181,14,65,"brown") ; a.rect(317,181,14,65,"brown")
end
function sketches.tv(a)
    a.rect(134,70,244,155,"ink") ; a.rect(148,84,214,123,"blue")
    a.line({{208,48},{255,71},{303,48}},"ink",3)
    a.rect(230,225,53,12,"ink") ; a.rect(202,237,109,8,"ink")
    a.circle(367,215,3,"red")
end
function sketches.lamp(a)
    a.line({{211,55},{301,55},{337,139},{175,139},{211,55}},"yellow",7)
    a.line({{256,145},{256,226}},"brown",5) ; a.oval(256,235,65,10,"brown")
    for _,p in ipairs({{144,63,164,80},{348,76,369,60},{256,17,256,35}}) do
        a.line({{p[1],p[2]},{p[3],p[4]}},"yellow",3)
    end
end
function sketches.broom(a)
    a.line({{282,42},{243,180}},"brown",6)
    a.line({{218,167},{177,238},{291,238},{265,178},{218,167}},"orange",7)
    for x=194,274,16 do a.line({{240,182},{x,233}},"brown",2) end
end
function sketches.mug(a)
    a.rect(176,109,139,109,"blue") ; a.ring(327,153,34,36,"blue",7)
    a.oval(245,109,69,15,"pale")
    a.line({{211,79},{202,60},{214,40}},"ink",2)
    a.line({{268,80},{257,60},{270,37}},"ink",2)
end
function sketches.apple(a)
    a.oval(222,155,57,75,"red") ; a.oval(283,155,57,75,"red")
    a.line({{255,89},{263,49}},"brown",5)
    a.oval(286,60,28,12,"green") ; a.line({{195,129},{202,106}},"pink",5)
end
function sketches.carrot(a)
    a.line({{203,91},{308,91},{246,246},{203,91}},"orange",10)
    a.line({{251,85},{220,39}},"green",5)
    a.line({{251,85},{259,29}},"green",5)
    a.line({{251,85},{295,42}},"green",5)
    a.line({{216,126},{242,130}},"brown",2)
    a.line({{263,156},{281,153}},"brown",2)
end
function sketches.cake(a)
    a.rect(155,145,204,89,"pink") ; a.rect(155,142,204,22,"pale")
    a.oval(256,141,102,19,"pink")
    for x=188,324,34 do a.line({{x,130},{x,96}},"blue",3) ; a.oval(x,83,5,10,"orange") end
    a.line({{133,238},{381,238}},"ink",3)
end
function sketches.pizza(a)
    a.line({{143,78},{383,78},{256,246},{143,78}},"yellow",13)
    a.line({{145,75},{381,75}},"brown",10)
    a.circle(208,120,17,"red") ; a.circle(303,118,17,"red") ; a.circle(254,179,17,"red")
end
function sketches.popcorn(a)
    a.rect(183,124,147,120,"red")
    for x=197,309,28 do a.rect(x,125,12,115,"white") end
    for _,p in ipairs({{192,112},{220,90},{252,105},{281,87},{311,111}}) do a.circle(p[1],p[2],23,"yellow") end
end
function sketches.shirt(a)
    a.line({{211,67},{167,86},{123,142},{166,167},{193,137},{193,237},
        {322,237},{322,137},{349,167},{392,142},{348,86},{302,67}},"blue",7)
    a.line({{211,67},{224,93},{254,103},{286,93},{302,67}},"blue",5)
    for y=131,211,25 do a.circle(256,y,4,"orange") end
end
function sketches.shoe(a)
    a.line({{155,107},{244,107},{269,157},{348,175},{381,204},{376,227},
        {138,227},{132,190},{155,107}},"blue",8)
    a.line({{143,210},{376,210}},"ink",3)
    for x=235,295,20 do a.line({{x,163},{x+18,151}},"white",3) end
end
function sketches.hat(a)
    a.oval(256,199,137,20,"brown") ; a.rect(191,93,129,104,"brown")
    a.oval(256,91,64,16,"brown") ; a.rect(191,163,129,20,"orange")
end
function sketches.scarf(a)
    a.line({{178,93},{255,151},{337,88}},"red",16)
    a.line({{256,153},{261,243}},"red",19)
    a.line({{291,140},{334,219}},"red",15)
    for y=176,225,24 do a.line({{244,y},{277,y}},"yellow",3) end
end
function sketches.umbrella(a)
    a.line({{122,137},{146,92},{193,61},{256,49},{318,61},{365,92},{390,137}},"red",7)
    a.line({{122,137},{191,123},{255,138},{320,123},{390,137}},"red",5)
    a.line({{256,54},{256,222},{271,237},{288,225}},"brown",5)
    for _,x in ipairs({98,155,350,410}) do a.line({{x,59},{x-7,79}},"blue",2) end
end
function sketches.ghost(a)
    a.oval(256,133,69,92,"pale") ; a.rect(187,132,138,82,"pale")
    a.line({{187,211},{209,229},{232,211},{256,229},{280,211},{302,229},{325,211}},"blue",3)
    a.oval(234,119,10,16,"ink") ; a.oval(279,119,10,16,"ink") ; a.oval(257,160,12,18,"ink")
end
function sketches.pumpkin(a)
    a.oval(256,164,99,77,"orange") ; a.rect(248,58,18,36,"green")
    a.line({{209,132},{224,113},{239,133},{209,132}},"ink",4)
    a.line({{273,133},{288,113},{304,133},{273,133}},"ink",4)
    a.line({{201,173},{221,191},{240,177},{258,195},{280,177},{308,173}},"ink",5)
end
function sketches.moon(a)
    a.circle(257,143,94,"yellow") ; a.circle(296,112,85,"white")
    for _,p in ipairs({{139,67},{357,204},{385,93}}) do
        a.line({{p[1]-10,p[2]},{p[1]+10,p[2]}},"orange",2)
        a.line({{p[1],p[2]-10},{p[1],p[2]+10}},"orange",2)
    end
end
function sketches.candy(a)
    a.oval(256,144,65,43,"red")
    a.line({{192,144},{143,106},{143,184},{192,144}},"orange",7)
    a.line({{320,144},{370,106},{370,184},{320,144}},"orange",7)
    a.line({{239,110},{272,179}},"white",7)
end
function sketches.cow(a)
    a.oval(255,137,92,63,"pale") ; a.rect(183,180,16,62,"ink") ; a.rect(308,180,16,62,"ink")
    a.circle(203,117,24,"ink") ; a.circle(283,151,28,"ink")
    a.circle(344,116,38,"pale") ; a.oval(356,139,32,18,"pink")
    a.circle(337,106,4,"ink") ; a.circle(361,106,4,"ink")
    a.line({{322,87},{309,62},{336,83}},"brown",3)
    a.line({{358,83},{378,62},{375,94}},"brown",3)
end
function sketches.mouse(a)
    a.oval(248,165,72,48,"pale")
    a.circle(296,130,40,"pale") ; a.circle(274,94,25,"pink") ; a.circle(316,94,25,"pink")
    a.circle(309,129,5,"ink") ; a.circle(335,146,5,"pink")
    a.line({{179,170},{132,152},{109,172},{126,191}},"pink",4)
    a.line({{326,155},{364,153}},"ink",1)
end
function sketches.lion(a)
    a.circle(257,142,100,"brown") ; a.circle(257,142,68,"orange")
    a.circle(232,127,6,"ink") ; a.circle(281,127,6,"ink") ; a.oval(257,160,26,18,"yellow")
    a.circle(257,153,8,"ink") ; a.line({{236,176},{257,185},{278,176}},"ink",3)
end
function sketches.elephant(a)
    a.oval(240,138,100,68,"pale") ; a.circle(325,129,53,"pale")
    a.oval(285,127,38,51,"blue") ; a.circle(344,113,5,"ink")
    a.line({{365,143},{374,197},{350,224},{333,211}},"pale",15)
    a.rect(172,181,30,62,"pale") ; a.rect(278,181,30,62,"pale")
end
function sketches.bat(a)
    a.oval(256,150,27,63,"ink")
    a.line({{235,119},{158,65},{86,162},{142,145},{168,180},{202,155},{235,181}},"ink",12)
    a.line({{277,119},{354,65},{426,162},{370,145},{344,180},{310,155},{277,181}},"ink",12)
    a.circle(246,120,4,"red") ; a.circle(266,120,4,"red")
end
function sketches.desert(a)
    a.circle(365,72,34,"yellow")
    a.line({{75,233},{153,196},{257,231},{354,205},{437,231}},"orange",9)
    a.line({{209,217},{209,103}},"green",10)
    a.line({{209,160},{174,160},{174,130}},"green",8)
    a.line({{210,181},{249,181},{249,140}},"green",8)
end
function sketches.city(a)
    for i,h in ipairs({104,169,130,188,119}) do
        local x=94+(i-1)*67
        a.rect(x,240-h,57,h,"blue")
        for y=250-h,214,27 do a.rect(x+10,y,12,15,"yellow") ; a.rect(x+34,y,12,15,"yellow") end
    end
    a.line({{70,245},{442,245}},"ink",3)
end
function sketches.park(a)
    a.line({{116,233},{177,60},{237,233}},"blue",6)
    a.line({{176,61},{331,61},{392,233}},"blue",6)
    a.line({{245,62},{245,164}},"brown",2) ; a.line({{291,62},{291,164}},"brown",2)
    a.rect(231,164,75,13,"red")
    a.line({{92,247},{425,247}},"green",4)
end
function sketches.door(a)
    a.rect(184,40,145,210,"brown") ; a.rect(196,52,121,186,"orange")
    a.circle(294,150,7,"yellow") ; a.rect(211,68,87,56,"brown") ; a.rect(211,168,87,52,"brown")
end
function sketches.toothbrush(a)
    a.line({{198,229},{280,73}},"blue",10)
    a.line({{275,74},{313,94}},"blue",9)
    for i=0,5 do a.line({{276+i*6,72+i*3},{285+i*6,52+i*3}},"ink",2) end
end
function sketches.ski(a)
    sketches.runner(a)
    a.line({{138,220},{233,240}},"red",4) ; a.line({{302,230},{381,230}},"red",4)
    a.line({{186,93},{144,229}},"ink",2) ; a.line({{331,97},{366,229}},"ink",2)
end
function sketches.leaf(a)
    a.line({{255,241},{251,121}},"brown",4)
    a.line({{251,171},{178,157},{209,136},{166,92},{225,108},{254,43},
        {284,108},{342,92},{305,139},{335,160},{255,187}},"orange",8)
    a.line({{250,154},{212,116}},"brown",2) ; a.line({{254,156},{296,118}},"brown",2)
end
local themeSketch = {}
local function assign(key, names)
    for _,name in ipairs(names) do themeSketch[string.lower(name)] = key end
end
assign("cat",{"Pet","Cute Animal","Animal That Sleeps a Lot"})
assign("bear",{"Animal That Lives Somewhere Cold"})
assign("cow",{"Farm Animal"})
assign("mouse",{"Tiny Animal"})
assign("elephant",{"Big Animal"})
assign("lion",{"Animal You Would Not Want as a Pet","Scary Animal","Jungle Animal"})
assign("cat",{"Animal That Is Very Fast"})
assign("bird",{"Animal with Wings"})
assign("bat",{"Animal That Comes Out at Night","Something That Flies at Night"})
assign("fish",{"Sea Animal"})
assign("car",{"Vehicle with Wheels","Fast Vehicle","Vehicle That Is Very Loud","Vehicle You Would See in a City"})
assign("plane",{"Vehicle That Flies","Vehicle You Would Take on Holiday"})
assign("bus",{"Public Transport","Big Vehicle","Vehicle That Carries Lots of People"})
assign("boat",{"Vehicle on Water"})
assign("bike",{"Vehicle with Two Wheels","Vehicle That Has No Engine","Sport Where You Wear a Helmet","Extreme Sport"})
assign("ball",{"Ball Sport","Team Sport","Sport with a Goal","Sport You Would Play at School","Sport You Would Watch on TV"})
assign("runner",{"Solo Sport","Sport Where You Run a Lot","Sport Where You Need Special Shoes"})
assign("racket",{"Sport with a Racket"})
assign("swimmer",{"Water Sport","Somewhere You Swim"})
assign("ski",{"Winter Sport"})
assign("mountain",{"Somewhere Cold","Somewhere Very High Up"})
assign("tree",{"Somewhere Outdoors","Somewhere Very Quiet","Somewhere You Would Not Want to Get Lost","Somewhere with Animals","Something That Falls in Autumn"})
assign("house",{"Somewhere Hot","Somewhere with Lots of People","Somewhere You Would Find Food","Somewhere You Would Have Fun","Somewhere You Would Go with Your Family"})
assign("desert",{"Somewhere Hot"})
assign("city",{"Somewhere with Lots of People"})
assign("park",{"Somewhere You Would Have Fun","Somewhere You Would Go with Your Family"})
assign("lion",{"Somewhere with Animals"})
assign("leaf",{"Something That Falls in Autumn"})
assign("ghost",{"Somewhere Scary","Somewhere You Would Not Go Alone at Night","Something Spooky","Something You Wear on Halloween","Something You Would See at a Costume Party"})
assign("bed",{"Somewhere You Would Sleep","Something You Sleep On","Something You Find in a Bedroom"})
assign("chair",{"Something You Sit On","Something in a Living Room"})
assign("tv",{"Something You Watch TV On","Something You Plug In","Something That Makes Noise"})
assign("lamp",{"Something That Makes Light","Something That Glows in the Dark","Something You Carry on Halloween Night"})
assign("broom",{"Something You Clean With"})
assign("mug",{"Something in a Kitchen","Something in a Bathroom","Something You Use Every Day","Breakfast"})
assign("door",{"Something You Open"})
assign("toothbrush",{"Something in a Bathroom"})
assign("cake",{"Dessert","Party Food","Something Sweet","Food You Would Eat on Your Birthday"})
assign("pizza",{"Fast Food","Food You Eat with Your Hands","Food That Is Hot","Food That Is Sticky or Messy"})
assign("apple",{"Fruit","Food You Would Take on a Picnic"})
assign("carrot",{"Vegetable"})
assign("popcorn",{"Food You Would Find at a Cinema"})
assign("shirt",{"Something You Wear Outside","Something with Buttons","Something Colourful","Something You Wear in Summer","Something Fancy","Something You Wear to Bed","Something You Wear to Do Sport"})
assign("shoe",{"Something You Wear on Your Feet"})
assign("hat",{"Something You Wear on Your Head"})
assign("scarf",{"Something You Wear in Winter","Something You Wear Around Your Neck"})
assign("umbrella",{"Something That Keeps You Dry"})
assign("pumpkin",{"Something Orange","Something You Do on Halloween Night"})
assign("moon",{"Something That Comes Out at Night"})
assign("candy",{"Something You Eat on Halloween"})

local detailedMode = true
local lastArtKey = nil
local lastArtPixels = nil
local function realisticPixels(key)
    if key == lastArtKey and lastArtPixels then return lastArtPixels end
    local path = "CatchArtistRealistic/" .. key .. ".rgba"
    if type(isfile) ~= "function" or not isfile(path) then return nil end
    local success,bytes = pcall(readfile,path)
    if not success or type(bytes)~="string" or #bytes ~= 512*288*4 then return nil end
    lastArtPixels = buffer.fromstring(bytes)
    lastArtKey = key
    return lastArtPixels
end

local autoEnabled = true
local autoCard = nil
local autoStatus = "Enabled for new drawing rounds"
local drawPending = false
local function drawingStatus(message)
    setthreadidentity(8)
    autoStatus = message
    if autoCard and window and not window.unloaded then autoCard:Set(message) end
end
local function activeCanvas()
    local gui=player.PlayerGui:FindFirstChild("GUI")
    local paint=gui and gui:FindFirstChild("PaintFrame")
    local buttons=paint and paint:FindFirstChild("RightButtons")
    local undo=buttons and buttons:FindFirstChild("UndoButton")
    if not undo then return nil end
    for _,connection in ipairs(getconnections(undo.Activated)) do
        if connection.Function then
            local values=debug.getupvalues(connection.Function)
            if values[1]==true and type(values[2])=="table" and type(values[3])=="table"
                and type(values[3].drawStrokeSegment)=="function" and values[4] then
                return values[4],values[2],values[3]
            end
        end
    end
    return nil
end
local function drawTheme()
    setthreadidentity(8)
    if window and window.unloaded then return false end
    if not reader.Running or player:GetAttribute("InRound")~=true
        or player:GetAttribute("RoundPhase")~="Drawing" then
        drawingStatus("Wait for the drawing phase")
        return false
    end
    if player:GetAttribute("IsFrozen") then
        drawingStatus("Canvas is frozen; try again after thawing")
        return false
    end
    if not reader.Word then recoverWord() end
    local key=reader.Word and themeSketch[string.lower(reader.Word)]
    if not key then
        drawingStatus("No sketch for this theme yet; canvas unchanged")
        return false
    end
    local image,history,practice=activeCanvas()
    if not image then
        drawingStatus("Canvas not ready; try Draw now")
        return false
    end
    local size=image.Size
    if size~=Vector2.new(512,288) then
        drawingStatus("Canvas size changed; drawing stopped")
        return false
    end
    local before=buffer.tostring(image:ReadPixelsBuffer(Vector2.zero,size))
    local usedDetailed = false
    local ok,err=pcall(function()
        local detailedPixels = detailedMode and realisticPixels(key) or nil
        usedDetailed = detailedPixels ~= nil
        if detailedPixels then
            image:WritePixelsBuffer(Vector2.zero,size,detailedPixels)
        else
            image:DrawRectangle(Vector2.zero,size,palette.white,0,Enum.ImageCombineType.Overwrite)
            sketches[key](artist(image,practice))
        end
        local after=buffer.tostring(image:ReadPixelsBuffer(Vector2.zero,size))
        table.insert(history,{type="Snapshot",bufferString=before})
        table.insert(history,{type="Snapshot",bufferString=after})
    end)
    if not ok then
        image:WritePixelsBuffer(Vector2.zero,size,buffer.fromstring(before))
        drawingStatus("Drawing failed: "..tostring(err))
        return false
    end
    drawingStatus("Drew "..key.." for "..reader.Word..(detailedMode and not usedDetailed and " (simple fallback; no ZIP needed)" or "")..". Press Z to undo.")
    print("[Auto Draw] "..reader.Word.." -> "..key)
    return true
end
local function queueDrawing()
    if not autoEnabled or drawPending then return end
    drawPending=true
    task.delay(1.5,function()
        drawPending=false
        if reader.Running and autoEnabled then drawTheme() end
    end)
end
local drawEvent=remotes:FindFirstChild("StartDrawingPhase")
if drawEvent and drawEvent:IsA("RemoteEvent") then
    table.insert(connections,drawEvent.OnClientEvent:Connect(queueDrawing))
end
reader.DrawNow=drawTheme



local copyCard = nil
local playerPicker = nil
local autoToggle = nil
local realisticToggle = nil
local selectedUserId = nil
local playerOptions = {}
local publishedDrawings = {}
local publishedRoundId = nil
local savedCopy = nil
local copyBusy = false
local copySerial = 0
local copyMessage = "Choose a player, then copy their drawing."
local function copyStatus(message)
    setthreadidentity(8)
    copyMessage = message
    if reader.Running and copyCard and window and not window.unloaded then copyCard:Set(message) end
end
local function refreshCopyPlayers()
    setthreadidentity(8)
    local options = {}
    playerOptions = {}
    for _,other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            local label = other.DisplayName .. " (@" .. other.Name .. ")"
            playerOptions[label] = other.UserId
            table.insert(options,label)
        end
    end
    table.sort(options)
    if playerPicker and window and not window.unloaded then playerPicker:Refresh(options) end
    return options
end
local function readPublishedDrawings()
    local event = remotes:FindFirstChild("BroadcastDrawings")
    if not event or not event:IsA("RemoteEvent") then return end
    for _,connection in ipairs(getconnections(event.OnClientEvent)) do
        if connection.Function then
            local values = debug.getupvalues(connection.Function)
            if type(values[1]) == "table" and (type(values[2]) == "number" or type(values[2]) == "string") then
                publishedDrawings = values[1]
                publishedRoundId = values[2]
                return
            end
        end
    end
end
local broadcast = remotes:FindFirstChild("BroadcastDrawings")
if broadcast and broadcast:IsA("RemoteEvent") then
    table.insert(connections,broadcast.OnClientEvent:Connect(function(drawings,roundId)
        if type(drawings) == "table" then
            publishedDrawings = drawings
            publishedRoundId = roundId
        end
    end))
end
readPublishedDrawings()

local function validPixels(pixels,size)
    return type(pixels)=="string" and typeof(size)=="Vector2"
        and size==Vector2.new(512,288) and #pixels==512*288*4
end
local function fetchPublished(userId,ticket)
    readPublishedDrawings()
    local entry = nil
    for _,drawing in pairs(publishedDrawings) do
        if type(drawing)=="table" and drawing.UserId==userId then entry=drawing ; break end
    end
    if not entry then return nil end
    if validPixels(entry.Pixels,entry.Size) then return entry.Pixels,entry.Size end
    local remote = remotes:FindFirstChild("GetDrawingChunk")
    if not entry.HasDrawing or not publishedRoundId or not remote or not remote:IsA("RemoteFunction") then return nil end
    local roundId = publishedRoundId
    local first = remote:InvokeServer(roundId,userId,1)
    if type(first)~="table" or type(first.chunk)~="string"
        or type(first.total)~="number" or first.total%1~=0 or first.total<1 or first.total>32
        or first.size~=Vector2.new(512,288) then return nil end
    local chunks = {first.chunk}
    local length = #first.chunk
    for index=2,first.total do
        if not reader.Running or ticket~=copySerial then return nil end
        local piece = remote:InvokeServer(roundId,userId,index)
        if type(piece)~="table" or type(piece.chunk)~="string" then return nil end
        length = length+#piece.chunk
        if length>512*288*4 then return nil end
        chunks[index] = piece.chunk
    end
    local pixels = table.concat(chunks)
    if validPixels(pixels,first.size) then return pixels,first.size end
    return nil
end
local function pauseAutoForCopy()
    autoEnabled = false
    if autoToggle and window and not window.unloaded then autoToggle:Set(false,true) end
end
local function pasteCopy()
    setthreadidentity(8)
    if not reader.Running or not savedCopy then
        copyStatus("Copy a player's drawing first.")
        return false
    end
    if player:GetAttribute("RoundPhase")~="Drawing" or player:GetAttribute("InRound")~=true then
        copyStatus("Saved "..savedCopy.name.."'s drawing. Paste when your drawing phase starts.")
        return false
    end
    if player:GetAttribute("IsFrozen") then
        copyStatus("Canvas frozen; paste after thawing.")
        return false
    end
    local image,history = activeCanvas()
    if not image or image.Size~=savedCopy.size then
        copyStatus("Your canvas is not ready.")
        return false
    end
    local before = buffer.tostring(image:ReadPixelsBuffer(Vector2.zero,image.Size))
    image:WritePixelsBuffer(Vector2.zero,image.Size,buffer.fromstring(savedCopy.pixels))
    table.insert(history,{type="Snapshot",bufferString=before})
    table.insert(history,{type="Snapshot",bufferString=savedCopy.pixels})
    pauseAutoForCopy()
    copyStatus("Copied "..savedCopy.name.."'s drawing to your canvas. Press Z to undo.")
    return true
end
local function copySelected()
    setthreadidentity(8)
    if not reader.Running or (window and window.unloaded) then return end
    if copyBusy then
        copyStatus("A copy request is already running.")
        return
    end
    local target = selectedUserId and Players:GetPlayerByUserId(selectedUserId)
    if not target or target==player then
        copyStatus("Choose a player from the list first.")
        return
    end
    copyBusy = true
    copySerial = copySerial+1
    local ticket = copySerial
    copyStatus("Fetching "..target.DisplayName.."'s drawing...")
    task.delay(15,function()
        if reader.Running and copyBusy and ticket==copySerial then
            copySerial=copySerial+1
            copyBusy=false
            copyStatus("Drawing request timed out; try again.")
        end
    end)
    task.spawn(function()
        setthreadidentity(8)
        local ok,pixels,size = pcall(function()
            if player:GetAttribute("RoundPhase")=="Drawing" then
                local peek = remotes:FindFirstChild("RequestPeekData")
                if peek and peek:IsA("RemoteFunction") then
                    local allowed,data,dimensions = peek:InvokeServer(target.UserId)
                    if allowed and validPixels(data,dimensions) then return data,dimensions end
                end
                return nil
            end
            return fetchPublished(target.UserId,ticket)
        end)
        if not reader.Running or ticket~=copySerial then return end
        copyBusy=false
        if not ok or not validPixels(pixels,size) then
            copyStatus("Drawing unavailable. Peek may be on cooldown; try during voting or after cooldown.")
            return
        end
        savedCopy={pixels=pixels,size=size,name=target.DisplayName.." (@"..target.Name..")"}
        pauseAutoForCopy()
        pasteCopy()
    end)
end
table.insert(connections,Players.PlayerAdded:Connect(function() refreshCopyPlayers() end))
table.insert(connections,Players.PlayerRemoving:Connect(function()
    task.defer(function() if reader.Running then refreshCopyPlayers() end end)
end))
local function selectDrawingStyle(realistic)
    setthreadidentity(8)
    detailedMode = realistic
    autoEnabled = true
    if realisticToggle then realisticToggle:Set(realistic,true) end
    if autoToggle then autoToggle:Set(true,true) end
    drawingStatus(realistic and "Realistic drawings selected for new rounds" or "Simple drawings selected for new rounds")
end
reader.CopySelected=copySelected
reader.PasteCopy=pasteCopy



-- Standalone URL image importer: no ZIP, localhost server, or files needed.
-- Public image URLs are resized by images.weserv.nl and decoded in Luau.
-- PNG decoder: zlib/DEFLATE + PNG filters -> opaque RGBA pixel buffer.
-- Expects images normalized to a 512x288 PNG by the public image proxy.
local function decodePNG(data)
    assert(type(data) == "string" and data:sub(1, 8) == "\137PNG\r\n\26\n", "Image service did not return a PNG")
    local function be32(s, i)
        local a, b, c, d = s:byte(i, i + 3)
        assert(d, "Truncated PNG")
        return ((a * 256 + b) * 256 + c) * 256 + d
    end

    local p = 9
    local width, height, depth, colorType, interlace
    local paletteBytes, transparencyBytes
    local compressedParts = {}
    while p + 11 <= #data do
        local size = be32(data, p)
        local kind = data:sub(p + 4, p + 7)
        assert(size <= 4 * 1024 * 1024 and p + 12 + size - 1 <= #data, "Invalid PNG chunk")
        local value = data:sub(p + 8, p + 7 + size)
        p = p + 12 + size
        if kind == "IHDR" then
            width, height = be32(value, 1), be32(value, 5)
            depth, colorType, interlace = value:byte(9), value:byte(10), value:byte(13)
            assert(width == 512 and height == 288, "Image service returned incorrect dimensions")
            assert(interlace == 0, "Interlaced PNG was not expected")
        elseif kind == "PLTE" then
            paletteBytes = value
        elseif kind == "tRNS" then
            transparencyBytes = value
        elseif kind == "IDAT" then
            table.insert(compressedParts, value)
        elseif kind == "IEND" then
            break
        end
    end
    assert(width and #compressedParts > 0, "PNG has no image data")
    local channels = ({[0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4})[colorType]
    assert(channels, "Unsupported PNG color mode")
    assert(depth == 8 or depth == 16 or (depth == 1 or depth == 2 or depth == 4) and (colorType == 0 or colorType == 3), "Unsupported PNG bit depth")
    local bitsPerPixel = channels * depth
    local stride = math.ceil(width * bitsPerPixel / 8)
    local filterBpp = math.max(1, math.ceil(bitsPerPixel / 8))
    local expectedLength = height * (stride + 1)

    -- RFC 1951 DEFLATE decoder. Codes arrive MSB-first but bits within bytes
    -- arrive LSB-first; tables therefore index reversed canonical codes.
    local z = table.concat(compressedParts)
    local cmf, flg = z:byte(1, 2)
    assert(flg and cmf % 16 == 8 and (cmf * 256 + flg) % 31 == 0, "Invalid zlib header")
    assert(math.floor(flg / 32) % 2 == 0, "PNG zlib dictionary not supported")
    local at, accumulator, available = 3, 0, 0
    local function bits(n)
        while available < n do
            assert(at <= #z - 4, "Truncated zlib stream")
            accumulator = accumulator + z:byte(at) * 2 ^ available
            available = available + 8
            at = at + 1
        end
        local value = accumulator % (2 ^ n)
        accumulator = math.floor(accumulator / (2 ^ n))
        available = available - n
        return value
    end
    local function huffman(lengths)
        local counts, nextCode, tables = {}, {}, {}
        local maxBits = 0
        for i = 1, #lengths do
            local len = lengths[i]
            if len ~= 0 then
                counts[len] = (counts[len] or 0) + 1
                if len > maxBits then maxBits = len end
            end
        end
        local code = 0
        for len = 1, maxBits do
            code = (code + (counts[len - 1] or 0)) * 2
            nextCode[len] = code
            tables[len] = {}
        end
        for symbol = 0, #lengths - 1 do
            local len = lengths[symbol + 1]
            if len > 0 then
                local canonical = nextCode[len]
                nextCode[len] = canonical + 1
                local reverse = 0
                for _ = 1, len do
                    reverse = reverse * 2 + canonical % 2
                    canonical = math.floor(canonical / 2)
                end
                tables[len][reverse] = symbol
            end
        end
        return function()
            local value = 0
            for len = 1, maxBits do
                value = value + bits(1) * (2 ^ (len - 1))
                local symbol = tables[len][value]
                if symbol ~= nil then return symbol end
            end
            error("Invalid DEFLATE Huffman code")
        end
    end

    local output = {}
    local count = 0
    local function push(byte)
        count = count + 1
        assert(count <= expectedLength, "Decompressed image exceeds expected size")
        output[count] = byte
        if count % 32768 == 0 then task.wait() end
    end
    local lengthBase = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
    local lengthExtra = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
    local distBase = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
    local distExtra = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
    local finished = false
    repeat
        finished = bits(1) == 1
        local blockType = bits(2)
        if blockType == 0 then
            -- Align to the next byte boundary before reading LEN/NLEN.
            accumulator, available = 0, 0
            local n = bits(16)
            local complement = bits(16)
            assert((n + complement) % 65536 == 65535, "Invalid uncompressed block")
            for _ = 1, n do push(bits(8)) end
        else
            assert(blockType == 1 or blockType == 2, "Invalid DEFLATE block type")
            local literal, distance
            if blockType == 1 then
                local lens = {}
                for sym = 0, 287 do
                    lens[sym + 1] = (sym <= 143 and 8) or (sym <= 255 and 9) or (sym <= 279 and 7) or 8
                end
                literal = huffman(lens)
                distance = huffman(table.create(32, 5))
            else
                local hlit = bits(5) + 257
                local hdist = bits(5) + 1
                local hclen = bits(4) + 4
                local order = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}
                local codeLengths = table.create(19, 0)
                for i = 1, hclen do codeLengths[order[i] + 1] = bits(3) end
                local decodeLength = huffman(codeLengths)
                local lengths = {}
                while #lengths < hlit + hdist do
                    local symbol = decodeLength()
                    if symbol <= 15 then
                        lengths[#lengths + 1] = symbol
                    else
                        local times, value
                        if symbol == 16 then
                            assert(#lengths > 0, "Invalid repeated Huffman code")
                            times, value = bits(2) + 3, lengths[#lengths]
                        elseif symbol == 17 then
                            times, value = bits(3) + 3, 0
                        else
                            times, value = bits(7) + 11, 0
                        end
                        for _ = 1, times do lengths[#lengths + 1] = value end
                    end
                    assert(#lengths <= hlit + hdist, "Huffman table overrun")
                end
                local ll, dd = {}, {}
                for i = 1, hlit do ll[i] = lengths[i] end
                for i = 1, hdist do dd[i] = lengths[hlit + i] end
                literal, distance = huffman(ll), huffman(dd)
            end
            while true do
                local symbol = literal()
                if symbol < 256 then
                    push(symbol)
                elseif symbol == 256 then
                    break
                else
                    local li = symbol - 256
                    assert(li >= 1 and li <= 29, "Invalid DEFLATE match length")
                    local length = lengthBase[li] + bits(lengthExtra[li])
                    local di = distance() + 1
                    assert(di >= 1 and di <= 30, "Invalid DEFLATE distance code")
                    local back = distBase[di] + bits(distExtra[di])
                    assert(back <= count, "DEFLATE distance exceeds output")
                    for _ = 1, length do push(output[count - back + 1]) end
                end
            end
        end
    until finished
    assert(count == expectedLength, "Decompressed PNG had an unexpected size")

    local result = buffer.create(width * height * 4)
    local previous = table.create(stride, 0)
    local src = 1
    local function getSample(row, pixel, channel)
        local sampleIndex = pixel * channels + channel
        if depth == 8 then
            return row[sampleIndex + 1]
        elseif depth == 16 then
            return row[sampleIndex * 2 + 1]
        else
            local bit = sampleIndex * depth
            local shift = 8 - depth - bit % 8
            local sample = math.floor(row[math.floor(bit / 8) + 1] / 2 ^ shift) % (2 ^ depth)
            return sample
        end
    end
    for y = 0, height - 1 do
        local filter = output[src]
        src = src + 1
        assert(filter and filter <= 4, "Invalid PNG scanline filter")
        local row = table.create(stride)
        for i = 1, stride do
            local a = i > filterBpp and row[i - filterBpp] or 0
            local b = previous[i] or 0
            local c = i > filterBpp and previous[i - filterBpp] or 0
            local predictor = 0
            if filter == 1 then predictor = a
            elseif filter == 2 then predictor = b
            elseif filter == 3 then predictor = math.floor((a + b) / 2)
            elseif filter == 4 then
                local pa, pb, pc = math.abs(b - c), math.abs(a - c), math.abs(a + b - 2 * c)
                predictor = pa <= pb and pa <= pc and a or (pb <= pc and b or c)
            end
            row[i] = (output[src] + predictor) % 256
            src = src + 1
        end
        for x = 0, width - 1 do
            local r, g, b, alpha
            if colorType == 6 then
                r,g,b,alpha = getSample(row,x,0),getSample(row,x,1),getSample(row,x,2),getSample(row,x,3)
            elseif colorType == 2 then
                r,g,b,alpha = getSample(row,x,0),getSample(row,x,1),getSample(row,x,2),255
                if transparencyBytes and #transparencyBytes >= 6 then
                    if r == transparencyBytes:byte(2) and g == transparencyBytes:byte(4) and b == transparencyBytes:byte(6) then alpha = 0 end
                end
            elseif colorType == 4 then
                r = getSample(row,x,0)
                g,b,alpha = r,r,getSample(row,x,1)
            elseif colorType == 3 then
                local index = getSample(row,x,0)
                assert(paletteBytes and #paletteBytes >= (index + 1) * 3, "Missing PNG palette entry")
                r,g,b = paletteBytes:byte(index*3+1, index*3+3)
                alpha = transparencyBytes and transparencyBytes:byte(index+1) or 255
            else
                r = getSample(row,x,0)
                if depth < 8 then r = math.floor(r*255/(2^depth-1)+0.5) end
                g,b,alpha = r,r,255
                if transparencyBytes and #transparencyBytes >= 2 and getSample(row,x,0) == transparencyBytes:byte(2) then alpha = 0 end
            end
            if alpha < 255 then
                local complement = 255 - alpha
                r = math.floor((r * alpha + complement * 255) / 255 + 0.5)
                g = math.floor((g * alpha + complement * 255) / 255 + 0.5)
                b = math.floor((b * alpha + complement * 255) / 255 + 0.5)
            end
            local out = (y * width + x) * 4
            buffer.writeu8(result, out, r)
            buffer.writeu8(result, out + 1, g)
            buffer.writeu8(result, out + 2, b)
            buffer.writeu8(result, out + 3, 255)
        end
        previous = row
        if y % 24 == 0 then task.wait() end
    end
    return result
end

local HttpService = game:GetService("HttpService")
local imageURL = ""
local imageFit = "Fit whole image"
local imageCard = nil
local imageMessage = "Paste a public image URL, then press Enter to draw."
local imageBusy = false
local imageTicket = 0
local lastImageCacheKey, lastImagePixels = nil, nil
local function imageStatus(message)
    setthreadidentity(8)
    imageMessage = message
    if reader.Running and imageCard and window and not window.unloaded then imageCard:Set(message) end
    print("[Image URL] " .. message)
end
local function normalizeImageURL(url)
    url = tostring(url or "")
    url = (url:gsub("^%s+", "")):gsub("%s+$", "")
    url = (url:gsub("^<", "")):gsub(">$", "")
    if url:match("^www%.") then url = "https://" .. url end
    assert(#url <= 2048 and url:match("^https?://[%w%.%-]+"), "Paste a public http(s) image URL")
    local host = url:match("^https?://([^/:?#]+)") or ""
    assert(host ~= "" and not host:lower():match("^localhost$") and not host:match("^127%.")
       and not host:match("^10%.") and not host:match("^192%.168%.")
       and not host:match("^169%.254%."), "Private/local URLs cannot be imported")
    return url
end
local function validDrawingCanvas()
    assert(reader.Running and not (window and window.unloaded), "Script has been closed")
    assert(player:GetAttribute("InRound") == true and player:GetAttribute("RoundPhase") == "Drawing", "Wait for your drawing phase")
    assert(not player:GetAttribute("IsFrozen"), "Canvas is frozen")
    local image, history = activeCanvas()
    assert(image and image.Size == Vector2.new(512,288), "Drawing canvas is unavailable")
    return image, history
end
local function imagePixels(url, fit)
    local cacheKey = url .. "|" .. fit
    if lastImageCacheKey == cacheKey and lastImagePixels then return lastImagePixels end
    -- Fit: letterbox; Fill: crop to full bounds; Stretch: distort to exact bounds.
    local options
    if fit == "Fill canvas (crop)" then
        options = "&w=512&h=288&fit=cover&output=png"
    elseif fit == "Stretch to canvas" then
        options = "&w=512&h=288&fit=fill&output=png"
    else
        options = "&w=512&h=288&fit=contain&cbg=ffffff&output=png"
    end
    local proxyURL = "https://images.weserv.nl/?url=" .. HttpService:UrlEncode(url) .. options
    imageStatus("Downloading and resizing image...")
    local png = game:HttpGet(proxyURL)
    assert(type(png) == "string" and #png > 0 and #png <= 4*1024*1024, "The image server did not return a usable image")
    imageStatus("Decoding image...")
    local result = decodePNG(png)
    lastImageCacheKey,lastImagePixels=cacheKey,result
    return result
end
local function drawURL()
    if imageBusy then
        imageStatus("Already importing an image")
        return
    end
    imageBusy = true
    imageTicket = imageTicket + 1
    local ticket = imageTicket
    task.spawn(function()
        local ok, err = pcall(function()
            setthreadidentity(8)
            validDrawingCanvas()
            local url = normalizeImageURL(imageURL)
            local pixels = imagePixels(url,imageFit)
            if ticket ~= imageTicket or not reader.Running then return end
            local image,history = validDrawingCanvas()
            local size = image.Size
            local before = buffer.tostring(image:ReadPixelsBuffer(Vector2.zero,size))
            local wrote,drawErr = pcall(function()
                image:WritePixelsBuffer(Vector2.zero,size,pixels)
                local after = buffer.tostring(image:ReadPixelsBuffer(Vector2.zero,size))
                table.insert(history,{type="Snapshot",bufferString=before})
                table.insert(history,{type="Snapshot",bufferString=after})
            end)
            if not wrote then
                image:WritePixelsBuffer(Vector2.zero,size,buffer.fromstring(before))
                error(drawErr)
            end
            pauseAutoForCopy()
            imageStatus("Image drawn! Press Z to undo.")
        end)
        if ticket == imageTicket then imageBusy = false end
        if not ok and ticket == imageTicket then imageStatus("Image failed: "..tostring(err)) end
    end)
end
reader.DrawImageURL = function(url)
    if type(url)=="string" then imageURL=url end
    drawURL()
end
reader.GetImageStatus = function()
    return {url=imageURL,fit=imageFit,busy=imageBusy,message=imageMessage}
end
reader.ImageCleanup = function()
    imageTicket = imageTicket+1
    lastImageCacheKey,lastImagePixels=nil,nil
end



local ok, err = pcall(function()
    local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
    if not reader.Running then return end
    window = Rayfield:CreateWindow({
        name = "Catch the Artist!",
        subtitle = "Drawing Studio",
        sidebarLayout = true,
        theme = "cobalt",
        profile = "Drawing Studio",
        showName = "Drawing Studio",
    })
    reader.Window = window
    window:CreateSection({name = "LIVE ROUND"})
    local tab = window:CreateTab({name = "Overview", icon = 100604009889706})
    tab:CreateSection({name = "Current round"})
    wordCard = tab:CreateText({name = "Waiting for a word", text = "Listening..."})
    tab:CreateSection({name = "Players & roles"})
    imposterCard = tab:CreateText({name = "Imposters", text = "Waiting for role data..."})
    tab:CreateToggle({
        name="Red imposter ESP",
        value=true,
        forgetState=true,
        callback=reader.SetESPEnabled,
    })
    roleCard = tab:CreateText({name = "Your role", text = "None"})
    phaseCard = tab:CreateText({name = "Round phase", text = "Waiting"})
    tab:CreateSection({name = "Connection"})
    statusCard = tab:CreateText({name = "Status", text = status})
    tab:CreateSection({name = "Quick actions"})
    local wordActions = tab:CreateGroup({direction = "row"})
    wordActions:CreateButton({
        name = "Copy word",
        callback = function()
            if reader.Word then
                setclipboard(reader.Word)
                window:Notify({title = "Copied", content = reader.Word})
            else
                window:Notify({title = "Waiting", content = "No word received yet."})
            end
        end,
    })
    wordActions:CreateButton({name = "Refresh word", callback = recoverWord})
    tab:CreateSection({name = "Session"})
    tab:CreateButton({name = "Close and stop", callback = reader.Stop})
    window:CreateSection({name = "DRAWING"})
    local drawTab=window:CreateTab({name="Realistic", icon=125626312718314})
    drawTab:CreateSection({name = "Realistic artwork"})
    autoCard=drawTab:CreateText({name="Drawing status",text=autoStatus})
    autoToggle=drawTab:CreateToggle({
        name="Auto draw each round",
        value=true,
        forgetState=true,
        callback=function(enabled)
            autoEnabled=enabled
            drawingStatus(enabled and "Enabled for new drawing rounds" or "Automatic drawing paused")
        end,
    })
    realisticToggle=drawTab:CreateToggle({
        name="Realistic artwork",
        description="Uses simple sketches when the artwork pack is unavailable.",
        value=true,
        forgetState=true,
        callback=function(enabled)
            detailedMode=enabled
            drawingStatus(enabled and "Detailed artwork selected" or "Simple sketches selected")
        end,
    })
    drawTab:CreateSection({name = "Drawing actions"})
    local realisticActions = drawTab:CreateGroup({direction = "row"})
    realisticActions:CreateButton({name="Use realistic mode",callback=function() selectDrawingStyle(true) end})
    realisticActions:CreateButton({name="Draw now",callback=function()
        detailedMode=true
        realisticToggle:Set(true,true)
        drawTheme()
    end})
    drawTab:CreateText({name="Undo",text="Press Z or use the game's Undo button to restore your previous canvas."})
    local simpleTab=window:CreateTab({name="Simple", icon=125823673784681})
    simpleTab:CreateSection({name = "Simple sketches"})
    simpleTab:CreateText({name="Less realistic drawings",text="Simple colored sketches for all built-in themes. No artwork pack needed."})
    simpleTab:CreateSection({name = "Drawing actions"})
    local simpleActions = simpleTab:CreateGroup({direction = "row"})
    simpleActions:CreateButton({name="Use simple mode",callback=function() selectDrawingStyle(false) end})
    simpleActions:CreateButton({name="Draw now",callback=function()
        detailedMode=false
        realisticToggle:Set(false,true)
        drawTheme()
    end})
    simpleTab:CreateText({name="Undo",text="Press Z to restore your previous canvas."})

    window:CreateSection({name = "IMPORT"})
    local copyTab=window:CreateTab({name="Copy drawings", icon=125823673784681})
    copyTab:CreateSection({name = "Player drawings"})
    copyCard=copyTab:CreateText({name="Copy status",text=copyMessage})
    copyTab:CreateSection({name = "Choose a player"})
    playerPicker=copyTab:CreateDropdown({
        name="Player",
        options=refreshCopyPlayers(),
        forgetState=true,
        callback=function(label) selectedUserId=playerOptions[label] end,
    })
    copyTab:CreateButton({name="Refresh player list",callback=refreshCopyPlayers})
    copyTab:CreateSection({name = "Capture & paste"})
    local copyActions = copyTab:CreateGroup({direction = "row"})
    copyActions:CreateButton({name="Copy drawing",callback=copySelected})
    copyActions:CreateButton({name="Paste to canvas",callback=pasteCopy})
    copyTab:CreateText({name="How it works",text="Copy during drawing uses Peek and its cooldown. During voting, capture a submitted drawing and paste it in your next drawing phase. Copying pauses auto-draw. Press Z to undo."})
    local urlTab=window:CreateTab({name="Photo link", icon=88738500661569})
    urlTab:CreateSection({name = "Photo to drawing"})
    imageCard=urlTab:CreateText({name="Image status",text=imageMessage})
    urlTab:CreateSection({name = "Paste a link, then press Enter"})
    urlTab:CreateInput({
        name="Image URL",
        value="",
        placeholder="https://example.com/image.png",
        forgetState=true,
        callback=function(text)
            imageURL=tostring(text or "")
            -- Rayfield Gen2 commits text on Enter (also on focus loss).
            if imageURL:match("^%s*https?://") or imageURL:match("^%s*www%.") then
                drawURL()
            end
        end,
    })
    urlTab:CreateDropdown({
        name="Image placement",
        options={"Fit whole image","Fill canvas (crop)","Stretch to canvas"},
        value="Fit whole image",
        forgetState=true,
        callback=function(value) imageFit=value end,
    })
    urlTab:CreateSection({name = "Before you draw"})
    urlTab:CreateText({name="Usage",text="Paste a public image link and press Enter during your drawing phase. No separate Load/Draw buttons or ZIP needed. Only the first frame of animated images is drawn. The public image URL is sent to images.weserv.nl for conversion."})
    refresh()
    window:Show()
    -- Right Ctrl toggles menu visibility without stopping any features.
    local menuVisible = true
    local inputService = game:GetService("UserInputService")
    table.insert(connections, inputService.InputBegan:Connect(function(input)
        if not reader.Running or not window or window.unloaded then return end
        if input.KeyCode ~= Enum.KeyCode.RightControl then return end
        if inputService:GetFocusedTextBox() then return end
        if menuVisible then
            window:Hide()
        else
            window:Show()
        end
        menuVisible = not menuVisible
    end))
    if player:GetAttribute("RoundPhase")=="Drawing" then queueDrawing() end
end)
if not ok then
    reader.Stop()
    error("Word Reader GUI failed to load: " .. tostring(err))
end
print("[Word Reader] GUI ready.")


