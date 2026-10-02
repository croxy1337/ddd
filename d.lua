--[[
    ONYX — Skin Changer (standalone)
    ------------------------------------------------------------
    The Skin Changer from ONYX v2 on its own, in the onyxscripts.xyz look
    (design 1, "Onyx site"): near-black window, a soft spotlight from the
    top, a faint grid, a white primary button, an outlined secondary one and
    the green "Undetected" status pill.
    Client-side only — only you can see the skins.

    RightShift shows / hides the window.
--]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local HttpService  = game:GetService("HttpService")
local LocalPlayer  = Players.LocalPlayer

-- Window/caption/pill state and layout constants live here instead of in
-- ~90 top-level locals: some executors (Volt) compile without constant
-- folding, so every local costs one of the main chunk's 200 registers.
local UI = {}

-- The one shared slot: what a re-execution has to find (the last run's
-- cleanup) and the little state that must outlive a run. It holds no API --
-- nothing in it can spawn, equip or build -- and nothing else is global.
do
    local env = (getgenv and getgenv()) or shared
    UI.store = env["\127\3o"] or {}
    env["\127\3o"] = UI.store
end

-- Tear the previous session down before building a new window.
if UI.store.cleanup then pcall(UI.store.cleanup) end

-- This run's identity, taken before anything below can wait (the first run
-- downloads the fonts). A run re-executed meanwhile found no cleanup hook to
-- call yet, and both went on to build a window; the older one now steps aside.
UI.gen = {}
UI.store.gen = UI.gen

--// Palette (the site's zinc scale) ------------------------------
local function hex(h) return Color3.fromHex(h) end
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local C = {
    bg             = hex("#09090b"),
    border         = hex("#27272a"),
    borderHi       = hex("#3f3f46"),
    text           = hex("#fafafa"),
    muted          = hex("#a1a1aa"),
    subtle         = hex("#71717a"),
    field          = hex("#0b0b0d"),
    pill           = hex("#0e0e10"),
    pillHover      = hex("#131316"),
    secondary      = hex("#0c0c0e"),
    secondaryHover = hex("#141417"),
    secondaryPress = hex("#1a1a1e"),
    primaryHover   = hex("#ececf0"),
    primaryPress   = hex("#dcdce0"),
    ink            = hex("#09090b"),   -- text on the white button
    tile           = hex("#0d0d0f"),
    tileHover      = hex("#141417"),
    tileActive     = hex("#1d1d21"),
    skeleton       = hex("#141417"),
    skeletonEdge   = hex("#1c1c1f"),
    green          = hex("#4ade80"),
    greenText      = hex("#6ee7a0"),
    greenBg        = hex("#0f2a1c"),
    greenEdge      = hex("#1e4d33"),
    red            = hex("#f87171"),
    redBg          = hex("#2a1215"),
    redEdge        = hex("#4d1f24"),
    amber          = hex("#fbbf24"),
    amberText      = hex("#fcd34d"),
    amberBg        = hex("#2a1f0a"),
    amberEdge      = hex("#5c4514"),
    teal           = hex("#2dd4bf"),
    tealText       = hex("#5eead4"),
    tealBg         = hex("#0b2624"),
    tealEdge       = hex("#16504b"),
    blurple        = hex("#8891ff"),   -- Discord's blurple, lifted for the dark
    blurpleText    = hex("#b9beff"),
    blurpleBg      = hex("#171a3d"),
    blurpleEdge    = hex("#333b8a"),
    error          = Color3.fromRGB(255, 120, 140),
}
-- MM2's rarity colours: Godly pink, Ancient purple
UI.RARITY = {
    Godly   = Color3.fromRGB(255, 60, 190),
    Ancient = Color3.fromRGB(165, 80, 255),
    Legendary = Color3.fromRGB(224, 65, 58),
    Unique    = Color3.fromRGB(255, 150, 30),
    Classic   = Color3.fromRGB(255, 240, 185),
}

--// Fonts: Geist, like the site ----------------------------------
-- Roblox ships no Geist, but an executor can hand it a font file: download
-- the TTFs once, write a font-family JSON beside them and Font.new() the
-- JSON's getcustomasset path. Cached in OnyxV2/fonts; any failure falls back
-- to Builder Sans / Roboto Mono so the window still builds.
--
-- The files are Vercel's own Geist build, not the Google Fonts copy: that one
-- has no hinting, and Roblox spaces small unhinted text unevenly ("Lightbringe
-- r", words run together). Vercel's build is hinted but has tighter vertical
-- metrics, which Roblox would draw ~14% bigger -- so each file gets the Google
-- copy's metrics written in before it's saved: the same size as ever, with
-- clean spacing.
-- (in a block: the main chunk may only hold 200 locals, and only geist / mono
-- are needed past this point)
local geist, mono
local FW = Enum.FontWeight
do
local FONT_DIR = "OnyxV2/fonts"
local GEIST_CDN = "https://cdn.jsdelivr.net/npm/geist@1.3.1/dist/fonts/"
local GEIST_FACES = {
    { "Regular",   400, GEIST_CDN .. "geist-sans/Geist-Regular.ttf" },
    { "Medium",    500, GEIST_CDN .. "geist-sans/Geist-Medium.ttf" },
    { "SemiBold",  600, GEIST_CDN .. "geist-sans/Geist-SemiBold.ttf" },
    { "ExtraBold", 800, GEIST_CDN .. "geist-sans/Geist-Black.ttf" },       -- Geist calls 800 "Black"
}
local GEIST_MONO_FACES = {
    { "Regular", 400, GEIST_CDN .. "geist-mono/GeistMono-Regular.ttf" },
}
-- the Google copies' vertical metrics: ascender, descender, win ascent / descent
local GEIST_METRICS      = { 1005, -295, 1088, 262 }
local GEIST_MONO_METRICS = { 1005, -295, 1088, 394 }

-- Write vertical metrics into a TTF: hhea ascender / descender / line gap and
-- the matching OS/2 typo and win values. Everything else is left untouched.
local function setMetrics(data, m)
    local hhea, os2
    for i = 0, string.unpack(">I2", data, 5) - 1 do
        local rec = 13 + i * 16
        local tag, off = data:sub(rec, rec + 3), string.unpack(">I4", data, rec + 8)
        if tag == "hhea" then hhea = off elseif tag == "OS/2" then os2 = off end
    end
    if not (hhea and os2) then error("not a TrueType font") end
    local function put(at, fmt, v)
        local bytes = string.pack(fmt, v)
        data = data:sub(1, at) .. bytes .. data:sub(at + #bytes + 1)
    end
    put(hhea + 4, ">i2", m[1]); put(hhea + 6, ">i2", m[2]); put(hhea + 8, ">i2", 0)
    put(os2 + 68, ">i2", m[1]); put(os2 + 70, ">i2", m[2]); put(os2 + 72, ">i2", 0)
    put(os2 + 74, ">I2", m[3]); put(os2 + 76, ">I2", m[4])
    return data
end

local function fontFamily(name, file, faces, metrics)
    local ok, id = pcall(function()
        if not (writefile and readfile and isfile and getcustomasset) then error("no file api") end
        if makefolder and isfolder then
            if not isfolder("OnyxV2") then makefolder("OnyxV2") end
            if not isfolder(FONT_DIR) then makefolder(FONT_DIR) end
        end
        local family = { name = name, faces = {} }
        for _, f in ipairs(faces) do
            local path = ("%s/%s-%s.ttf"):format(FONT_DIR, file, f[1])
            -- a truncated download is smaller than any real face: fetch it again
            if not isfile(path) or #readfile(path) < 20000 then
                local data = game:HttpGet(f[3])
                if type(data) ~= "string" or #data < 20000 then error("font download failed") end
                writefile(path, setMetrics(data, metrics))
            end
            family.faces[#family.faces + 1] = {
                name = f[1], weight = f[2], style = "normal", assetId = getcustomasset(path),
            }
        end
        local json = ("%s/%s.json"):format(FONT_DIR, file)
        writefile(json, HttpService:JSONEncode(family))
        return getcustomasset(json)
    end)
    return ok and id or nil
end

-- new cache names ("Hinted"), so the old Google files are never picked up again
local GEIST      = fontFamily("Geist", "GeistHinted", GEIST_FACES, GEIST_METRICS)
                   or "rbxasset://fonts/families/BuilderSans.json"
local GEIST_MONO = fontFamily("Geist Mono", "GeistMonoHinted", GEIST_MONO_FACES, GEIST_MONO_METRICS)
                   or "rbxasset://fonts/families/RobotoMono.json"
-- The UI's face is Gotham SSm, one step bolder than asked for: Regular and
-- Medium read Bold, SemiBold Bold, Bold and up Heavy. (Still called geist():
-- every label in the file asks for its weight through it.)
do
    local BOLDER = { [FW.Thin] = FW.Medium, [FW.ExtraLight] = FW.Medium, [FW.Light] = FW.Medium,
                     [FW.Regular] = FW.Bold, [FW.Medium] = FW.Bold, [FW.SemiBold] = FW.Bold,
                     [FW.Bold] = FW.Heavy, [FW.ExtraBold] = FW.Heavy, [FW.Heavy] = FW.Heavy }
    function geist(weight)
        return Font.new("rbxasset://fonts/families/GothamSSm.json", BOLDER[weight or FW.Regular] or FW.Bold)
    end
end
function mono(weight) return Font.new(GEIST_MONO, weight or FW.Regular) end
end
-- a newer run started while the fonts were downloading: it owns the screen
if UI.store.gen ~= UI.gen then return end

--// Icons (lucide + solar asset ids) -----------------------------
local ICON = {
    minus     = "rbxassetid://118026365011536",
    maximize  = "rbxassetid://76045941763188",
    minimize2 = "rbxassetid://116269596042539",
    x         = "rbxassetid://110786993356448",
    sword     = "rbxassetid://124448418211665",
    -- the tabs: all lucide outlines, like every other icon in the window
    tabHome      = "rbxassetid://98755624629571",    -- lucide:house
    tabHvh       = "rbxassetid://81872698913435",    -- lucide:swords
    tabSkin      = "rbxassetid://124448418211665",   -- lucide:sword
    tabCombat    = "rbxassetid://110987169760162",   -- lucide:shield
    tabCrosshair = "rbxassetid://134242818164054",   -- lucide:crosshair
    tabButtons   = "rbxassetid://92483947987410",    -- lucide:gamepad-2
    tabEsp       = "rbxassetid://100033680381365",   -- lucide:eye
    tabFling     = "rbxassetid://130551565616516",   -- lucide:zap
    tabFarm      = "rbxassetid://116510979641930",   -- lucide:coins
    tabPlayer    = "rbxassetid://81589895647169",    -- lucide:user
    tabVisuals   = "rbxassetid://138635884129147",   -- lucide:sparkles
    tabKeybinds  = "rbxassetid://121474456068237",   -- lucide:keyboard
    tabSettings  = "rbxassetid://80758916183665",    -- lucide:settings
    search    = "rbxassetid://121018724060431",
    plus      = "rbxassetid://111774323017047",
    trash     = "rbxassetid://109843431391323",
    check     = "rbxassetid://93898873302694",
    frown     = "rbxassetid://124407301067982",
    arrowUp   = "rbxassetid://89282378235317",
    key       = "rbxassetid://83619031955390",   -- lucide:key-round
    monitor   = "rbxassetid://72664649203050",   -- lucide:monitor
    info      = "rbxassetid://124560466474914",  -- lucide:info
    power     = "rbxassetid://96479131758775",   -- lucide:power
    clock     = "rbxassetid://121808839832144",  -- lucide:clock
    flame     = "rbxassetid://98218034436456",   -- lucide:flame
    chevron   = "rbxassetid://134243273101015",  -- lucide:chevron-down
    farmStart = "rbxassetid://135609604299893",  -- lucide:play, the Start farming button
    farmStop  = "rbxassetid://86304921356806",   -- lucide:square, its Stop
    phone     = "rbxassetid://96623008834511",   -- lucide:smartphone
    globe     = "rbxassetid://114238209622913",  -- lucide:globe (Home)
    users     = "rbxassetid://115398113982385",  -- lucide:users (Home)
    cpu       = "rbxassetid://77549309870247",   -- lucide:cpu (Home)
    activity  = "rbxassetid://94212016861936",   -- lucide:activity (Home)
    discord   = "rbxassetid://86699749765447",   -- geist:logo-discord (a sprite sheet: see DISCORD_CELL)
    play      = "rbxassetid://120220597097660",  -- geist:play-fill (a sprite sheet: see PLAY_CELL)
    shadow    = "rbxassetid://8992230677",       -- WindUI's soft window shadow
}
-- geist:logo-discord and geist:play-fill are each one 128px cell of their sheet
UI.DISCORD_CELL = { offset = Vector2.new(256, 0), size = Vector2.new(128, 128) }
UI.PLAY_CELL = { offset = Vector2.new(128, 384), size = Vector2.new(128, 128) }

-- Pictures Roblox can't serve: MM2 points these skins at a thumbnail that
-- never renders, so we bring our own PNG, write it to the executor's
-- workspace once and load it from there. The PNGs live in modelfetch.txt,
-- on their weapon's entry (Picture = { file, data }); the skin engine hands
-- them over here as it loads that file.
UI.localPicture = nil
UI.pictures = {}
do
local pictureCache = {}
function UI.localPicture(key)
    local pic = UI.pictures[key]
    if not pic then return nil end
    if pictureCache[key] ~= nil then return pictureCache[key] or nil end
    local ok, id = pcall(function()
        local decode = (crypt and (crypt.base64decode or (crypt.base64 and crypt.base64.decode))) or base64_decode
        if not (decode and writefile and isfile and getcustomasset) then error("no file api") end
        local dir, path = "OnyxV2/images", "OnyxV2/images/" .. pic.file
        if makefolder and not (isfolder and isfolder(dir)) then pcall(makefolder, "OnyxV2"); pcall(makefolder, dir) end
        if not isfile(path) then writefile(path, decode((pic.data:gsub("%s", "")))) end
        return getcustomasset(path)
    end)
    pictureCache[key] = ok and id or false
    return ok and id or nil
end
end

--// Instance helpers -----------------------------------------------
local function make(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        if k ~= "Parent" then inst[k] = v end
    end
    if props.Parent then inst.Parent = props.Parent end
    return inst
end
local function corner(parent, r)
    return make("UICorner", { CornerRadius = typeof(r) == "UDim" and r or UDim.new(0, r), Parent = parent })
end
local function stroke(parent, color, thickness, transparency)
    return make("UIStroke", {
        Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
    })
end
local function text(props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.BorderSizePixel = 0
    l.FontFace = geist()
    l.TextSize = 14
    l.TextColor3 = C.text
    l.TextXAlignment = Enum.TextXAlignment.Left
    for k, v in pairs(props) do
        if k ~= "Parent" then l[k] = v end
    end
    if props.Parent then l.Parent = props.Parent end
    return l
end
local function image(props)
    local i = Instance.new("ImageLabel")
    i.BackgroundTransparency = 1
    i.BorderSizePixel = 0
    i.ScaleType = Enum.ScaleType.Fit
    for k, v in pairs(props) do
        if k ~= "Parent" then i[k] = v end
    end
    if props.Parent then i.Parent = props.Parent end
    return i
end
local function hlist(parent, gap, props)
    local l = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, gap or 0),
        Parent = parent,
    })
    for k, v in pairs(props or {}) do l[k] = v end
    return l
end
local function pad(parent, l, r, t, b)
    return make("UIPadding", {
        PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
        PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0), Parent = parent,
    })
end
local FULL = UDim.new(1, 0)   -- corner radius for pills and dots

local EASE, DIR = Enum.EasingStyle, Enum.EasingDirection
local function tween(obj, time, props, style, dir)
    local t = TweenService:Create(obj, TweenInfo.new(time, style or EASE.Quint, dir or DIR.Out), props)
    t:Play()
    return t
end
-- Animations that loop forever (the turning rings, the light sweeps, the
-- breathing dots) only run while what they decorate can be seen: closing the
-- window pauses them all, opening it carries them on. Hidden, they still cost
-- frames -- the window keeps ~18k objects alive under the pill. Performance
-- mode (UI.calm) keeps them paused even on screen.
UI.loops = {}
function UI.shown(o)
    while o do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("CanvasGroup") and o.GroupTransparency >= 0.99 then return false end
        if o:IsA("LayerCollector") then return o.Enabled end
        o = o.Parent
    end
    return false
end
function UI.loop(tw, host)
    UI.loops[tw] = host
    if not UI.calm and UI.shown(host) then tw:Play() end
    return tw
end
task.spawn(function()
    local PLAYING = Enum.PlaybackState.Playing
    local miss = {}
    while UI.store.gen == UI.gen do
        for tw, host in pairs(UI.loops) do
            if not host:IsDescendantOf(game) then
                -- gone (or not placed yet): forgotten once it has been away 3s
                miss[tw] = (miss[tw] or 0) + 1
                if miss[tw] > 10 then
                    UI.loops[tw], miss[tw] = nil, nil
                    pcall(function() tw:Cancel() end)
                elseif tw.PlaybackState == PLAYING then
                    tw:Pause()
                end
            else
                miss[tw] = nil
                local want = not UI.calm and UI.shown(host)
                local playing = tw.PlaybackState == PLAYING
                if want and not playing then tw:Play() elseif playing and not want then tw:Pause() end
            end
        end
        task.wait(0.3)
    end
    for tw in pairs(UI.loops) do pcall(function() tw:Cancel() end) end
end)
-- a slow breathing glow, for the "live" status dots
function UI.pulse(glow)
    UI.loop(TweenService:Create(glow, TweenInfo.new(1.1, EASE.Sine, DIR.InOut, -1, true), { Transparency = 0.2 }), glow.Parent or glow)
end
function UI.viewport()
    local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
    if not v or v.X < 50 or v.Y < 50 then return Vector2.new(1920, 1080) end   -- camera not ready yet
    return v
end

-- A note on borders: the design draws its 1px borders INSIDE each box (an
-- inset box-shadow), while a UIStroke draws OUTSIDE it. Every bordered box
-- below is therefore built 1px smaller on each side, with a 1px smaller
-- corner radius, so the stroke's outer edge lands exactly on the design box.

--// Settings, remembered between runs --------------------------------
UI.SETTINGS_PATH = "OnyxV2/skinchanger.json"
local settings = { sounds = true, x = 0, y = 0 }
pcall(function()
    if isfile and readfile and isfile(UI.SETTINGS_PATH) then
        local saved = HttpService:JSONDecode(readfile(UI.SETTINGS_PATH))
        if type(saved) == "table" then
            for k, v in pairs(saved) do settings[k] = v end
        end
    end
end)
local function saveSettings()
    pcall(function()
        if writefile then writefile(UI.SETTINGS_PATH, HttpService:JSONEncode(settings)) end
    end)
end

--// Window ------------------------------------------------------
local conns = {}

-- AutoLocalize is switched off below for everything in here: Roblox would
-- otherwise machine-translate some labels into the player's language ("Off"
-- became "Aus") while the rest stayed English
local gui = make("ScreenGui", {
    Name = "ScreenGui", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999998,
})
pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
gui.AutoLocalize = false
conns[#conns + 1] = gui.DescendantAdded:Connect(function(d)
    if d:IsA("GuiBase2d") then d.AutoLocalize = false end
end)

-- Sounds: the same cues as the main Onyx script, one Sound each, replayed.
local sfx
do
local sfxFolder = make("Folder", { Name = "SFX" })
UI.sfxFolder = sfxFolder       -- (the cleanup lives outside this block)
pcall(function() sfxFolder.Parent = game:GetService("SoundService") end)
local SFX = {
    click  = make("Sound", { SoundId = "rbxassetid://104184340183231", Volume = 0.45, Parent = sfxFolder }),
    hover  = make("Sound", { SoundId = "rbxassetid://107511012621133", Volume = 1, Parent = sfxFolder }),
    tick   = make("Sound", { SoundId = "rbxassetid://107511012621133", Volume = 1, Parent = sfxFolder }),
    error  = make("Sound", { SoundId = "rbxassetid://131039887376992", Volume = 0.5, Parent = sfxFolder }),
}
-- The hover tick is rate-limited, so sweeping the cursor down the
-- tab list gives a few soft ticks rather than a rattle. The slider's tick
-- (its own copy, so it never cuts a hover off) allows a much faster run, so
-- a quick drag still ticks for nearly every number it passes. `speed` pitches
-- a cue up or down.
local GAP = { hover = 0.07, tick = 0.025 }
local lastAt = {}
function sfx(name, speed)
    if not settings.sounds then return end
    local s = SFX[name]
    if not s then return end
    local now = os.clock()
    if GAP[name] and now - (lastAt[name] or 0) < GAP[name] then return end
    lastAt[name] = now
    s.PlaybackSpeed = speed or 1
    s.TimePosition = 0      -- rapid clicks retrigger rather than stack
    s:Play()
end
end

local tooltip = {}             -- filled in below; the cleanup hides it
UI.store.cleanup = function()
    UI.store.cleanup = nil
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if tooltip.hide then pcall(tooltip.hide) end
    if UI.store.engineDestroy then pcall(UI.store.engineDestroy) end
    pcall(function() gui:Destroy() end)
    pcall(function() UI.sfxFolder:Destroy() end)
end

-- the design's 850 wide, 660 tall (100px taller than the mockup, for a fifth
-- row of skins), never bigger than the screen
UI.VIEW = UI.viewport()
UI.BASE = Vector2.new(math.max(560, math.min(850, UI.VIEW.X - 24)), math.max(350, math.min(660, UI.VIEW.Y - 24)))
UI.winW, UI.winH = UI.BASE.X, UI.BASE.Y
-- Both columns start at the 56px title bar's bottom edge, leaving clear air
-- between the tags and window controls up there and the caption line below.
UI.BODY_TOP = 56
-- The caption row is pinned (it stays put while the list scrolls): its 16px
-- text starts 8 below the body's top, with its hairlines through the middle.
-- The scrolling list starts 8px under that text, and its first row -- the
-- search -- 10px further down.
UI.CAPTION_Y = UI.BODY_TOP + 8
UI.HAIRLINE_Y = UI.CAPTION_Y + 8
UI.LIST_TOP = UI.CAPTION_Y + 24
UI.SEARCH_Y = UI.LIST_TOP + 10
-- where the content column starts; the background grid is laid out to pass
-- through it and the caption's hairlines
UI.CONTENT_X = 207 + 20
-- both columns end on the same line: the nav panel's frame stops this far
-- above the window's bottom edge, its 1px outline one row lower, and the
-- scrolling list is cut off right on that outline
UI.BODY_BOTTOM = 16

-- The window may hang off any edge of the screen, but never so far that you
-- can't grab it back: its top edge can't go above the screen, at least 48px
-- of the title bar stays above the bottom edge, and at least 100px of it stays
-- inside the left and right edges. Offsets are from the screen centre.
function UI.clampOffset(ox, oy, w, h)
    local cam = UI.viewport()
    local GRAB, PEEK = 100, 48
    return math.clamp(ox, GRAB - cam.X / 2 - w / 2, cam.X / 2 - GRAB + w / 2),
           math.clamp(oy, h / 2 - cam.Y / 2, cam.Y / 2 - PEEK + h / 2)
end
UI.startX, UI.startY = UI.clampOffset(tonumber(settings.x) or 0, tonumber(settings.y) or 0, UI.winW, UI.winH)

-- Roblox can only fade a whole tree through a CanvasGroup, and a CanvasGroup
-- draws into a texture, which softens text slightly. So the window borrows
-- this one only while it animates and goes straight back to the ScreenGui.
UI.fader = make("CanvasGroup", {
    Name = "Fader", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
    GroupTransparency = 1, Visible = false, ZIndex = 5, Parent = gui,
})

-- holder = window + its shadow; it is what moves, scales and fades
local holder = make("Frame", {
    Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, UI.startX, 0.5, UI.startY),
    Size = UDim2.fromOffset(UI.winW, UI.winH), BackgroundTransparency = 1, Visible = false, ZIndex = 5, Parent = gui,
})
UI.winScale = make("UIScale", { Parent = holder })
UI.SHADOW_REST = { ImageTransparency = 0.45, Position = UDim2.fromOffset(-50, -50), Size = UDim2.new(1, 100, 1, 100) }
UI.winShadow = image({ Name = "Shadow", Image = ICON.shadow, ImageColor3 = BLACK, ImageTransparency = 0.45,
        ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(99, 99, 99, 99),
        Position = UI.SHADOW_REST.Position, Size = UI.SHADOW_REST.Size, ZIndex = 0, Parent = holder })
local win = make("Frame", {
    Name = "Window", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.bg, BorderSizePixel = 0,
    Active = true, ZIndex = 1, Parent = holder,
})
corner(win, 16)
UI.winRim = stroke(win, WHITE, 1, 0.95)     -- the faint white rim

-- Fade plus a short slide: in = rises 10px into place (0.32s), out = sinks
-- 6px and fades (0.2s). Yields until done. Deliberately no scaling: Roblox
-- draws text at whole pixel sizes, so a window growing 0.96 -> 1 shows its
-- text a size too small and then snaps it bigger right at the end.
UI.animateWindow = nil
do
local windowAnim, windowMoving, restPos = 0, false, nil
function UI.animateWindow(show)
    windowAnim += 1
    local mine = windowAnim
    if UI.stopWindowGlide then UI.stopWindowGlide() end
    if not windowMoving then
        restPos = holder.Position
        -- the screen may have changed size while the window was hidden:
        -- come back somewhere it can still be grabbed
        if show and not UI.maximised then
            local ox, oy = UI.clampOffset(restPos.X.Offset, restPos.Y.Offset, UI.winW, UI.winH)
            restPos = UDim2.new(0.5, ox, 0.5, oy)
        end
    end
    windowMoving = true
    local drift = UDim2.fromOffset(0, show and 10 or 6)
    holder.Visible = true
    holder.Parent = UI.fader
    UI.fader.Visible = true
    if show then
        UI.fader.GroupTransparency = 1
        holder.Position = restPos + drift
    end
    local info = show and TweenInfo.new(0.32, EASE.Quint, DIR.Out) or TweenInfo.new(0.2, EASE.Quint, DIR.In)
    TweenService:Create(UI.fader, info, { GroupTransparency = show and 0 or 1 }):Play()
    local t = TweenService:Create(holder, info, { Position = show and restPos or (restPos + drift) })
    t:Play()
    t.Completed:Wait()
    if mine ~= windowAnim or not gui.Parent then return false end
    windowMoving = false
    holder.Position = restPos
    holder.Parent = gui
    UI.fader.Visible = false
    holder.Visible = show
    return true
end
end

--// Backdrop: the site's spotlight and grid ------------------------
-- Both are CSS radial gradients in the design. UIGradient is linear only, so
-- the spotlight is rebuilt from thin horizontal strips, each carrying the
-- exact horizontal profile of its row, and each grid line carries the mask
-- along its own length. It lives in a CanvasGroup so a resize can cross-fade
-- it instead of snapping.

UI.refreshBackdrop = nil
do
-- radial-gradient(ellipse 60% 62% at 50% -8%, white .11 0%, .044 38%, 0 72%)
local SPOT = { rx = 0.60, ry = 0.62, cx = 0.50, cy = -0.08,
               stops = { { 0, 0.11 }, { 0.38, 0.044 }, { 0.72, 0 } } }
local function spotAlpha(t)
    local s = SPOT.stops
    if t <= s[1][1] then return s[1][2] end
    for i = 2, #s do
        if t <= s[i][1] then
            local a, b = s[i - 1], s[i]
            return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1])
        end
    end
    return 0
end

-- grid mask: an ellipse 150% wide x 110% tall from the top centre, solid to
-- 25% of the way out and gone by 80% (the grid reaches the window's sides)
local function gridMask(t)
    if t <= 0.25 then return 1 end
    if t >= 0.8 then return 0 end
    return 1 - (t - 0.25) / (0.8 - 0.25)
end

-- keypoints must start at 0, end at 1 and only ever move forward
local function curve(samples)
    local kps, last = {}, -1
    for _, s in ipairs(samples) do
        local time = math.clamp(s[1], 0, 1)
        if time > last then
            kps[#kps + 1] = NumberSequenceKeypoint.new(time, math.clamp(s[2], 0, 1))
            last = time
        end
    end
    if kps[1].Time > 0 then table.insert(kps, 1, NumberSequenceKeypoint.new(0, kps[1].Value)) end
    if kps[#kps].Time < 1 then kps[#kps + 1] = NumberSequenceKeypoint.new(1, kps[#kps].Value) end
    return NumberSequence.new(kps)
end

local function buildBackdrop(W, H)
    local bd = make("CanvasGroup", {
        Name = "Backdrop", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = win,
    })
    corner(bd, 16)

    -- spotlight: 4px strips, 17 samples each across the lit span of the row.
    -- Switched off: the window reads cleaner as flat black with just the
    -- grid; set SPOTLIGHT = true to bring the glow back.
    local SPOTLIGHT = false
    local rx, ry, cx, cy = SPOT.rx * W, SPOT.ry * H, SPOT.cx * W, SPOT.cy * H
    local tMax = SPOT.stops[#SPOT.stops][1]
    local STRIP = 4
    for y = 0, SPOTLIGHT and math.min(H, math.ceil(cy + tMax * ry)) - 1 or -1, STRIP do
        local dy = (y + STRIP / 2 - cy) / ry
        if math.abs(dy) < tMax then
            local half = rx * math.sqrt(tMax * tMax - dy * dy)
            local samples = { { 0, 1 } }
            for i = 0, 16 do
                local px = (cx - half) + 2 * half * i / 16
                local t = math.sqrt(((px - cx) / rx) ^ 2 + dy * dy)
                samples[#samples + 1] = { px / W, 1 - spotAlpha(t) }
            end
            samples[#samples + 1] = { 1, 1 }
            local strip = make("Frame", {
                BackgroundColor3 = WHITE, BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, math.min(STRIP, H - y)),
                Parent = bd,
            })
            make("UIGradient", { Transparency = curve(samples), Parent = strip })
        end
    end

    -- grid: 1px lines every 60px, white at 4%, masked -- snapped so one
    -- horizontal line runs straight through the caption's hairlines and one
    -- vertical line along the content column's left edge
    local CELL, ALPHA, REACH = 60, 0.04, 0.8
    local gx0 = UI.CONTENT_X % CELL
    local gy0 = UI.HAIRLINE_Y                   -- the first line is the caption's: none up in the title bar
    local mrx, mry, mcx = 1.5 * W, 1.1 * H, 0.5 * W
    local function mask(px, py) return gridMask(math.sqrt(((px - mcx) / mrx) ^ 2 + (py / mry) ^ 2)) end
    for x = gx0, W - 1, CELL do
        local dx = (x - mcx) / mrx
        if math.abs(dx) < REACH then
            local yEnd = math.min(H, mry * math.sqrt(REACH ^ 2 - dx * dx))
            local samples = {}
            for i = 0, 17 do
                local py = yEnd * i / 17
                samples[#samples + 1] = { py / H, 1 - mask(x, py) }
            end
            samples[#samples + 1] = { 1, 1 }
            local line = make("Frame", {
                BackgroundColor3 = WHITE, BackgroundTransparency = 1 - ALPHA, BorderSizePixel = 0,
                Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, 1, 1, 0), Parent = bd,
            })
            make("UIGradient", { Rotation = 90, Transparency = curve(samples), Parent = line })
        end
    end
    for y = gy0, H - 1, CELL do
        local dy = y / mry
        if dy < REACH then
            local half = mrx * math.sqrt(REACH ^ 2 - dy * dy)
            -- Sampled over the part of the line inside the window, with a
            -- transparent end only where the lit span really stops inside it.
            -- Before, a forced transparent start faded every row out at the
            -- left edge while the right edge stayed lit: a lopsided mask.
            local lo, hi = math.max(0, mcx - half), math.min(W, mcx + half)
            local samples = {}
            if lo > 0 then samples[1] = { 0, 1 } end
            for i = 0, 16 do
                local px = lo + (hi - lo) * i / 16
                samples[#samples + 1] = { px / W, 1 - mask(px, y) }
            end
            if hi < W then samples[#samples + 1] = { 1, 1 } end
            local line = make("Frame", {
                BackgroundColor3 = WHITE, BackgroundTransparency = 1 - ALPHA, BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), Parent = bd,
            })
            make("UIGradient", { Transparency = curve(samples), Parent = line })
        end
    end
    return bd
end
local backdrop = buildBackdrop(UI.winW, UI.winH)
function UI.refreshBackdrop(W, H)
    local old, new = backdrop, buildBackdrop(W, H)
    backdrop = new
    new.GroupTransparency = 1
    tween(new, 0.35, { GroupTransparency = 0 })
    tween(old, 0.35, { GroupTransparency = 1 }).Completed:Connect(function() old:Destroy() end)
end
end

--// Tooltips ----------------------------------------------------------
-- A small card anchored to whatever you hover (not trailing the mouse), with
-- a caret pointing at it. Content is a spec table:
--   title, right (a value shown after the title, e.g. "×2"),
--   chips = { { text, color | rainbow = true } ... } then detail (plain text),
--   hints = { { key = "RShift", text = "Toggle" } ... } shown as keycaps,
--   side  = "above" | "below" (flips when there is no room).
-- It appears after a short hover; moving to the next target fades the old one
-- out and opens the new one after the same short wait.
do
    local TIP_RAINBOW = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,  60,  90)),
        ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 170,  40)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(120, 230,  70)),
        ColorSequenceKeypoint.new(0.75, Color3.fromRGB( 40, 200, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(240,  70, 220)),
    })

    local tip = make("CanvasGroup", {
        Name = "Tooltip", BackgroundTransparency = 1, GroupTransparency = 1, Visible = false,
        Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, ZIndex = 30, Parent = gui,
    })
    -- 1px all round for the card's stroke, 7px on the caret's side
    local tipPad = pad(tip, 1, 1, 1, 7)
    local card = make("Frame", {
        BackgroundColor3 = C.pill, BorderSizePixel = 0, Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY,
        ZIndex = 2, Parent = tip,
    })
    corner(card, 8)
    -- a white outline with a soft glow just inside it
    do
        local st = stroke(card, WHITE, 1, 0.2)
        local g = make("UIGradient", { Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, C.borderHi:Lerp(WHITE, 0.1)), ColorSequenceKeypoint.new(0.45, C.borderHi:Lerp(WHITE, 0.1)),
            ColorSequenceKeypoint.new(1, WHITE) }), Parent = st })
        UI.loop(TweenService:Create(g, TweenInfo.new(7, EASE.Linear, DIR.In, -1), { Rotation = 360 }), card)
    end
    -- (the glow sits on the tip, not in the card's list; place() fits it)
    local tipGlow = make("Frame", { BackgroundTransparency = 1, ZIndex = 4, Parent = tip })
    corner(tipGlow, 7)
    stroke(tipGlow, WHITE, 3, 0.86)
    pad(card, 10, 10, 8, 9)
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = card })
    -- the caret: a rotated square half tucked under the card, plus a sliver in
    -- the card's colour that erases the card border across its base
    local caret = make("Frame", {
        BackgroundColor3 = C.pill, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
        Size = UDim2.fromOffset(9, 9), ZIndex = 1, Parent = tip,
    })
    corner(caret, 2)
    stroke(caret, WHITE, 1, 0.35)
    local seam = make("Frame", {
        BackgroundColor3 = C.pill, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(10, 2), ZIndex = 3, Parent = tip,
    })

    local function chip(parent, c, order)
        if c.tag then
            -- the skin cards' own tag: a dark pill, a thin outline in the
            -- skin's colour (or its gradient), heavy small caps to match
            local f = make("Frame", { BackgroundColor3 = hex("#0d0d10"), BorderSizePixel = 0,
                Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = parent })
            corner(f, FULL)
            local st = stroke(f, c.ramp and WHITE or (c.color or C.borderHi), 1)
            st.Transparency = c.color and not c.ramp and 0.45 or 0.35
            if c.ramp then make("UIGradient", { Color = c.ramp, Parent = st }) end
            pad(f, c.dot and 7 or 8, 8)
            hlist(f, 5, { VerticalAlignment = Enum.VerticalAlignment.Center })
            if c.dot then
                corner(make("Frame", { BackgroundColor3 = c.color, BorderSizePixel = 0, Size = UDim2.fromOffset(5, 5),
                    LayoutOrder = 1, Parent = f }), FULL)
            end
            local l = text({ Text = string.upper(c.text), FontFace = geist(FW.ExtraBold), TextSize = 10,
                TextColor3 = c.ramp and WHITE or (c.color and c.color:Lerp(WHITE, 0.3) or C.muted),
                Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = f })
            if c.ramp then make("UIGradient", { Color = c.textRamp or c.ramp, Parent = l }) end
            return
        end
        local f = make("Frame", {
            BorderSizePixel = 0, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
            LayoutOrder = order, Parent = parent,
        })
        corner(f, 5)
        local ink
        if c.color then
            -- tinted with the rarity colour, text a lighter shade of it
            f.BackgroundColor3 = C.pill:Lerp(c.color, 0.16)
            stroke(f, C.pill:Lerp(c.color, 0.45))
            ink = c.color:Lerp(WHITE, 0.35)
        else
            f.BackgroundColor3 = hex("#18181b")
            stroke(f, C.border)
            ink = c.kbd and C.muted or C.text
        end
        pad(f, 6, 6)
        local l = text({
            Text = c.text, FontFace = c.kbd and mono() or geist(FW.SemiBold), TextSize = c.kbd and 10 or 11,
            TextColor3 = ink, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = f,
        })
        if c.rainbow then
            l.TextColor3 = WHITE
            make("UIGradient", { Color = TIP_RAINBOW, Parent = l })
        end
    end

    local function row(order, gap)
        local r = make("Frame", {
            BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
            LayoutOrder = order, Parent = card,
        })
        hlist(r, gap)
        return r
    end

    local function build(spec)
        for _, ch in ipairs(card:GetChildren()) do
            if ch:IsA("GuiObject") and not ch:GetAttribute("TipKeep") then ch:Destroy() end
        end
        local top = row(1, 12)
        text({ Text = spec.title or "", FontFace = geist(FW.SemiBold), TextSize = 13, Size = UDim2.new(0, 0, 1, 0),
               AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = top })
        if spec.right then
            text({ Text = spec.right, FontFace = mono(), TextSize = 11, TextColor3 = C.subtle, Size = UDim2.new(0, 0, 1, 0),
                   AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = top })
        end
        if (spec.chips and #spec.chips > 0) or spec.detail then
            local r = row(2, 5)
            for i, c in ipairs(spec.chips or {}) do chip(r, c, i) end
            if spec.detail then
                text({ Text = spec.detail, TextSize = 12, TextColor3 = C.muted, Size = UDim2.new(0, 0, 1, 0),
                       AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 99, Parent = r })
            end
        end
        if spec.hints and #spec.hints > 0 then
            local r = row(3, 6)
            for i, h in ipairs(spec.hints) do
                chip(r, { text = h.key, kbd = true }, i * 3 - 2)
                text({ Text = h.text, TextSize = 12, TextColor3 = C.subtle, Size = UDim2.new(0, 0, 1, 0),
                       AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i * 3 - 1, Parent = r })
                if i < #spec.hints then   -- a little extra room between pairs
                    make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(4, 1), LayoutOrder = i * 3, Parent = r })
                end
            end
        end
    end

    -- above or below the anchor, centred on it, kept on screen; the caret
    -- follows the anchor's centre even when the card is pushed sideways
    local GuiService = game:GetService("GuiService")
    local function place(anchor, prefer)
        -- AbsolutePosition is measured below Roblox's top bar, but this
        -- ScreenGui ignores that inset, so shift it into the same space
        local inset = GuiService:GetGuiInset()
        -- the card plus the tip's padding (1+1 across, 1+7 down), not the tip
        -- itself: its size still counted the previous card's caret and glow
        local cam, as, ts = UI.viewport(), anchor.AbsoluteSize, card.AbsoluteSize + Vector2.new(2, 8)
        local ap = anchor.AbsolutePosition + inset
        local yAbove, yBelow = ap.Y - 5 - ts.Y, ap.Y + as.Y + 5
        local side = prefer
        if side == "above" and yAbove < 8 then side = "below"
        elseif side == "below" and yBelow + ts.Y > cam.Y - 8 then side = "above" end
        tipPad.PaddingTop = UDim.new(0, side == "below" and 7 or 1)
        tipPad.PaddingBottom = UDim.new(0, side == "above" and 7 or 1)
        local x = math.clamp(ap.X + as.X / 2 - ts.X / 2, 8, math.max(8, cam.X - ts.X - 8))
        local cw, ch = card.AbsoluteSize.X, card.AbsoluteSize.Y
        local cx = math.clamp(ap.X + as.X / 2 - x - 1, 12, math.max(12, cw - 12))
        caret.Position = UDim2.fromOffset(cx, side == "below" and 0 or ch)
        seam.Position = caret.Position
        return Vector2.new(x, side == "above" and yAbove or yBelow), side
    end

    -- the glow hugs the card wherever the card actually is: it was placed
    -- from a size read before the card had finished laying out (and before
    -- the caret-side padding moved it), so it could sit off the card
    local function fitGlow()
        local rel = card.AbsolutePosition - tip.AbsolutePosition
        local cs = card.AbsoluteSize
        -- rel already includes the tip's padding, and the glow (a child of the
        -- tip too) is placed from that same padded origin: take it back out,
        -- or the ring sat a padding's width off the card
        tipGlow.Position = UDim2.fromOffset(rel.X - tipPad.PaddingLeft.Offset + 1, rel.Y - tipPad.PaddingTop.Offset + 1)
        tipGlow.Size = UDim2.fromOffset(math.max(0, cs.X - 2), math.max(0, cs.Y - 2))
    end
    card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGlow)
    card:GetPropertyChangedSignal("AbsolutePosition"):Connect(fitGlow)
    local token, shown, lastHide, watch = 0, false, 0, nil
    local function stopWatch()
        if watch then
            watch:Disconnect()
            watch = nil
        end
    end
    -- Is there still something to point at? The target has to exist, be
    -- visible all the way up (a search can filter it out, the window can be
    -- minimised) and, with a mouse, still be under the cursor. Roblox fires
    -- no MouseLeave when a target disappears from under a still cursor, so
    -- this is checked every frame while a card is up.
    local function stillThere(anchor)
        if not anchor.Parent then return false end
        local o = anchor
        while o and o:IsA("GuiObject") do
            if not o.Visible then return false end
            o = o.Parent
        end
        if UIS.MouseEnabled then
            local m = UIS:GetMouseLocation()
            local ap, as = anchor.AbsolutePosition + GuiService:GetGuiInset(), anchor.AbsoluteSize
            if m.X < ap.X - 2 or m.X > ap.X + as.X + 2 or m.Y < ap.Y - 2 or m.Y > ap.Y + as.Y + 2 then
                return false
            end
        end
        return true
    end

    -- no hover cards while a mouse button is held: you're pressing or dragging
    -- (the pill, the window), and the card would be left behind where it opened
    local function holding()
        return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end
    function tooltip.show(anchor, spec)
        tooltip.current = anchor
        token += 1
        local mine = token
        -- sliding onto another card: the old one fades away first, then the
        -- new one opens after the usual short wait (no gliding across)
        if shown then
            shown = false
            lastHide = os.clock()
            stopWatch()
            tween(tip, 0.12, { GroupTransparency = 1 }).Completed:Connect(function()
                if mine == token then tip.Visible = false end
            end)
        end
        task.delay(0.3, function()
            if mine ~= token or not anchor.Parent or not tip.Parent or holding() then return end
            build(spec)
            tip.GroupTransparency = 1
            tip.Visible = true
            RunService.RenderStepped:Wait()            -- let the card size itself
            if mine ~= token or not anchor.Parent then return end
            local pos, side = place(anchor, spec.side or "above")
            shown = true
            stopWatch()
            watch = RunService.Heartbeat:Connect(function()
                if holding() or not stillThere(anchor) then
                    stopWatch()
                    tooltip.hide()
                end
            end)
            tip.Position = UDim2.fromOffset(pos.X, pos.Y + (side == "above" and 4 or -4))
            tween(tip, 0.18, { Position = UDim2.fromOffset(pos.X, pos.Y), GroupTransparency = 0 })
        end)
    end
    function tooltip.hide()
        token += 1
        local mine = token
        stopWatch()
        -- a short grace: moving straight onto the next target lets show()
        -- take over (it fades this card out itself, then opens the next)
        task.delay(0.06, function()
            if mine ~= token or not shown then return end
            shown = false
            lastHide = os.clock()
            if not tip.Parent then return end
            tween(tip, 0.12, { GroupTransparency = 1 }).Completed:Connect(function()
                if mine == token then tip.Visible = false end
            end)
        end)
    end
    -- straight away, with the same plain 0.28s fade as a card's picture (a
    -- card turning into its 3D model takes its info card with it)
    function tooltip.fadeAway()
        token += 1
        local mine = token
        stopWatch()
        if not shown and not tip.Visible then return end
        shown = false
        tween(tip, 0.28, { GroupTransparency = 1 }).Completed:Connect(function()
            if mine == token then tip.Visible = false end
        end)
    end
    -- spec is a table, or a function returning one (read fresh on each hover)
    function tooltip.attach(obj, spec)
        obj.MouseEnter:Connect(function()
            if obj:GetAttribute("NoTip") then return end   -- (a card showing its 3D model)
            tooltip.show(obj, type(spec) == "function" and spec() or spec)
        end)
        -- only for the target it's showing (or about to show) for: Roblox can
        -- deliver the old target's MouseLeave after the new one's MouseEnter,
        -- and that late leave used to cancel the new target's tooltip
        obj.MouseLeave:Connect(function()
            if tooltip.current == obj then tooltip.hide() end
        end)
        obj.MouseButton1Down:Connect(tooltip.hide)
    end
end

-- absolute sizes divide out the window's UIScale (kept at 1 -- the open/close
-- animations fade and slide rather than scale -- but safe if that changes)
local function unscale() return UI.winScale.Scale > 0 and UI.winScale.Scale or 1 end

--// Topbar --------------------------------------------------------
local toggleMaximise, minimiseWindow, scrollToTop, notify, openTab, selectTab, markTab   -- defined further down

UI.topbar = make("Frame", {
    Name = "Topbar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), ZIndex = 2, Active = true, Parent = win,
})

-- starts where the nav panel's edge does, so the wordmark and the panel
-- below it share one left line
UI.brand = make("Frame", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(15, 0), Size = UDim2.new(0, 0, 1, 0),
    AutomaticSize = Enum.AutomaticSize.X, Parent = UI.topbar,
})
hlist(UI.brand, 12)

-- the wordmark on its own, filling the space the two-line title used to take
text({ Text = "Onyx", FontFace = geist(FW.ExtraBold), TextSize = 22, Size = UDim2.fromOffset(0, 28),
       AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = UI.brand })

-- status tags: [Keyless] [discord.gg/onyxscripts] [PC Version], the site's
-- badges side by side
UI.discordTag = nil   -- clickable: the drag code leaves presses on it alone
UI.platformTag = nil  -- last in the row, so the first to step aside when space runs out
do
    local tags = make("Frame", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 3, Parent = UI.brand,
    })
    pad(tags, 5, 1)
    -- 8px between the boxes = a 6px gap once each 1px outer stroke is drawn
    hlist(tags, 8)
    -- a pill: returns the pill, the row its content goes in, and its stroke
    -- (the row is separate so an overlay can cover the whole pill)
    local pills = {}
    local function tag(bg, edge, order)
        local t = make("Frame", {
            BackgroundColor3 = bg, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 24),
            AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = tags,
        })
        corner(t, FULL)
        local st = stroke(t, edge)
        local rowT = make("Frame", {
            BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = t,
        })
        pad(rowT, 8, 9)
        hlist(rowT, 6)
        pills[#pills + 1] = t
        return t, rowT, st
    end


    -- amber: a gold key and "Keyless"
    local _, keyless = tag(C.amberBg, C.amberEdge, 2)
    image({ Image = ICON.key, ImageColor3 = C.amber, Size = UDim2.fromOffset(12, 12), LayoutOrder = 1, Parent = keyless })
    text({ Text = "Keyless", FontFace = geist(FW.SemiBold), TextSize = 12, TextColor3 = C.amberText,
           Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = keyless })

    -- teal: which version you're on -- a touch screen without a keyboard
    -- is Mobile, anything else is PC
    local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
    local pTag, platform = tag(C.tealBg, C.tealEdge, 5)
    UI.platformTag = pTag
    image({ Image = mobile and ICON.phone or ICON.monitor, ImageColor3 = C.teal, Size = UDim2.fromOffset(12, 12),
            LayoutOrder = 1, Parent = platform })
    text({ Text = mobile and "Mobile Version" or "PC Version", FontFace = geist(FW.SemiBold), TextSize = 12,
           TextColor3 = C.tealText, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
           LayoutOrder = 2, Parent = platform })

    -- blurple: the Discord mark and the invite -- click it to copy the link
    local INVITE = "discord.gg/onyxscripts"
    local function copyText(str)
        for _, f in pairs({ setclipboard, toclipboard, set_clipboard, syn and syn.write_clipboard, Clipboard and Clipboard.set }) do
            if type(f) == "function" and pcall(f, str) then return true end
        end
        return false
    end
    local dTag, dRow, dStroke = tag(C.blurpleBg, C.blurpleEdge, 4)
    UI.discordTag = dTag
    image({ Image = ICON.discord, ImageRectOffset = UI.DISCORD_CELL.offset, ImageRectSize = UI.DISCORD_CELL.size,
            ImageColor3 = C.blurple, Size = UDim2.fromOffset(14, 14), LayoutOrder = 1, Parent = dRow })
    local dLabel = text({ Text = INVITE, FontFace = geist(FW.SemiBold), TextSize = 12, TextColor3 = C.blurpleText,
                          Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = dRow })
    local dBtn = make("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = dTag,
    })
    local HOVER_BG = C.blurpleBg:Lerp(C.blurpleEdge, 0.3)
    local HOVER_EDGE = C.blurpleEdge:Lerp(C.blurple, 0.45)
    local HOVER_INK = C.blurpleText:Lerp(WHITE, 0.45)
    local over = false
    dBtn.MouseEnter:Connect(function()
        over = true
        tween(dTag, 0.15, { BackgroundColor3 = HOVER_BG })
        tween(dStroke, 0.15, { Color = HOVER_EDGE })
        tween(dLabel, 0.15, { TextColor3 = HOVER_INK })
    end)
    dBtn.MouseLeave:Connect(function()
        over = false
        tween(dTag, 0.2, { BackgroundColor3 = C.blurpleBg })
        tween(dStroke, 0.2, { Color = C.blurpleEdge })
        tween(dLabel, 0.2, { TextColor3 = C.blurpleText })
    end)
    dBtn.MouseButton1Down:Connect(function() tween(dTag, 0.06, { BackgroundColor3 = C.blurpleEdge }) end)
    dBtn.MouseButton1Up:Connect(function() tween(dTag, 0.15, { BackgroundColor3 = over and HOVER_BG or C.blurpleBg }) end)
    -- (Home's Discord and YouTube cards copy the same way)
    UI.copyText = copyText
    function UI.copyInvite()
        if copyText("https://" .. INVITE) then
            notify({ title = "Invite copied", body = INVITE .. " is on your clipboard", kind = "discord", key = "discord" })
        else
            notify({ title = "Join our Discord", body = INVITE, kind = "discord", key = "discord", duration = 6 })
        end
    end
    dBtn.MouseButton1Click:Connect(UI.copyInvite)
    tooltip.attach(dBtn, { title = "Join our Discord", hints = { { key = "Click", text = "Copy invite" } }, side = "below" })

    -- The glint: every 5 seconds one slow band of light travels across all
    -- three tags, left to right at an even pace, as if a single beam passed
    -- over the row. Each pill carries its own copy of the band, so it keeps to
    -- the pill's shape, placed from the beam's position on the row; the band is
    -- sized in pixels, so it is the same width on the long tag as the short.
    local GLINT_EVERY, GLINT_SPEED, GLINT_HALF, GLINT_PEAK = 5, 120, 10, 0.5
    local glints = {}
    for _, t in ipairs(pills) do
        local g = make("Frame", {
            BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = t,
        })
        corner(g, FULL)
        glints[#glints + 1] = { pill = t, w = 0, grad = make("UIGradient", {
            Rotation = 20, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new(1), Parent = g,
        }) }
    end
    -- The wordmark catches the beam first, then it carries on over the tags.
    -- Its white can't get any whiter, so "Onyx" rests a shade softer and the
    -- band lifts it to full white as it passes.
    local mark
    for _, c in ipairs(UI.brand:GetChildren()) do
        if c:IsA("TextLabel") and c.Text == "Onyx" then mark = c end
    end
    -- (at 0.2 the lift was too small to see; this rest reads as white on
    -- its own and the band still flashes clearly past it)
    local MARK_REST = C.text:Lerp(C.muted, 0.6)
    local MARK_HALF = 22
    local markGrad = mark and make("UIGradient", { Rotation = 20, Color = ColorSequence.new(MARK_REST), Parent = mark })
    local markW = 0
    local beam = make("NumberValue", { Value = -1000, Parent = tags })
    beam.Changed:Connect(function(x)
        local sc = unscale()
        local x0 = tags.AbsolutePosition.X
        if markGrad then
            local w = mark.AbsoluteSize.X / sc
            if w > MARK_HALF * 2 then
                if w ~= markW then
                    markW = w
                    local k = MARK_HALF / w
                    markGrad.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, MARK_REST), ColorSequenceKeypoint.new(0.5 - k, MARK_REST),
                        ColorSequenceKeypoint.new(0.5, WHITE),
                        ColorSequenceKeypoint.new(0.5 + k, MARK_REST), ColorSequenceKeypoint.new(1, MARK_REST),
                    })
                end
                markGrad.Offset = Vector2.new((x - (mark.AbsolutePosition.X - x0) / sc) / w - 0.5, 0)
            end
        end
        for _, g in ipairs(glints) do
            local w = g.pill.AbsoluteSize.X / sc
            if g.pill.Visible and w > GLINT_HALF * 2 then
                if w ~= g.w then
                    g.w = w
                    local k = GLINT_HALF / w
                    g.grad.Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5 - k, 1),
                        NumberSequenceKeypoint.new(0.5, GLINT_PEAK),
                        NumberSequenceKeypoint.new(0.5 + k, 1), NumberSequenceKeypoint.new(1, 1),
                    })
                end
                g.grad.Offset = Vector2.new((x - (g.pill.AbsolutePosition.X - x0) / sc) / w - 0.5, 0)
            end
        end
    end)
    task.spawn(function()
        while gui.Parent do
            task.wait(GLINT_EVERY)
            if not gui.Parent then break end
            if holder.Visible then
                -- from just before the first pill to just past the last (the
                -- band leans, so it needs a little extra room to clear the ends)
                local reach = GLINT_HALF + 12
                local rowW = tags.AbsoluteSize.X / unscale()
                -- starting on the wordmark, left of the tags
                local from = mark and (mark.AbsolutePosition.X - tags.AbsolutePosition.X) / unscale() - reach or -reach
                beam.Value = from
                tween(beam, (rowW + reach - from) / GLINT_SPEED, { Value = rowW + reach }, EASE.Linear)
            end
        end
    end)
end

-- window controls
local controls = make("Frame", {
    BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 12),
    Size = UDim2.fromOffset(104, 32), Parent = UI.topbar,
})
hlist(controls, 4)
local function control(iconId, order, danger)
    local b = make("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = danger and C.red or WHITE, BackgroundTransparency = 1,
        BorderSizePixel = 0, Size = UDim2.fromOffset(32, 32), LayoutOrder = order, Parent = controls,
    })
    corner(b, 8)
    local ic = image({ Image = iconId, ImageColor3 = C.muted, AnchorPoint = Vector2.new(0.5, 0.5),
                       Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), Parent = b })
    local hoverT = danger and 0.86 or 0.94
    local hoverInk = danger and C.red or C.text
    b.MouseEnter:Connect(function()
        tween(b, 0.12, { BackgroundTransparency = hoverT })
        tween(ic, 0.12, { ImageColor3 = hoverInk })
    end)
    b.MouseLeave:Connect(function()
        tween(b, 0.18, { BackgroundTransparency = 1 })
        tween(ic, 0.18, { ImageColor3 = C.muted })
    end)
    b.MouseButton1Down:Connect(function() tween(b, 0.06, { BackgroundTransparency = hoverT - 0.06 }) end)
    b.MouseButton1Up:Connect(function() tween(b, 0.12, { BackgroundTransparency = hoverT }) end)
    return b, ic
end
UI.minBtn = control(ICON.minus, 1)
UI.maxBtn, UI.maxIcon = control(ICON.maximize, 2)
UI.closeBtn = control(ICON.x, 3, true)
UI.maximised = false
-- The window hides from under a still cursor (minimise, RightShift) and no
-- MouseLeave comes, so the button it was closed with stayed lit when it came
-- back. restore() puts them all back to rest first.
function UI.resetControls()
    for _, b in ipairs({ UI.minBtn, UI.maxBtn, UI.closeBtn }) do
        b.BackgroundTransparency = 1
        local ic = b:FindFirstChildOfClass("ImageLabel")
        if ic then ic.ImageColor3 = C.muted end
    end
end
tooltip.attach(UI.minBtn, { title = "Minimize", hints = { { key = "RShift", text = "Show / hide" },
                                                      { key = "Double-click", text = "the title bar" } }, side = "below" })
tooltip.attach(UI.maxBtn, function()
    return { title = UI.maximised and "Restore size" or "Maximize", side = "below" }
end)
tooltip.attach(UI.closeBtn, { title = "Close", side = "below" })

-- On a narrow window (a small phone screen) the tags would run under the
-- window controls; the last ones step aside, from the end of the row, until
-- there is room for them again.
do
    local need = {}
    local function fit()
        local sc = unscale()
        local left = (controls.AbsolutePosition.X - UI.topbar.AbsolutePosition.X) / sc
        for _, t in ipairs({ UI.discordTag, UI.platformTag }) do
            if t.Visible then
                need[t] = (t.AbsolutePosition.X + t.AbsoluteSize.X - UI.topbar.AbsolutePosition.X) / sc
            end
            t.Visible = (need[t] or 0) + 12 <= left
        end
    end
    UI.topbar:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    UI.discordTag:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    UI.platformTag:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    task.defer(fit)
end

-- Drag by the topbar (kept on screen, remembered); double-click minimises.
-- Once the pointer really moves, the window lifts: its shadow deepens and
-- spreads and the rim catches a little light. It glides after the pointer
-- with a touch of weight rather than being glued to it, and on release it
-- eases into place and settles back down. No scaling, so text stays crisp.
do
    local pressing, lifted, pressAt, startPos, lastClick = false, false, nil, nil, 0
    local target, follow, dragInput = nil, nil, nil
    local SHADOW_LIFT = { ImageTransparency = 0.25, Position = UDim2.fromOffset(-60, -54), Size = UDim2.new(1, 120, 1, 124) }

    local function glide()
        if follow then return end
        -- The position as a float. UDim offsets hold whole pixels, so reading
        -- it back each frame dropped every sub-pixel step: the glide stalled
        -- 1-3px short, never finished, and later pulled a maximised window
        -- back to the old drag spot.
        local pos = Vector2.new(holder.Position.X.Offset, holder.Position.Y.Offset)
        follow = RunService.RenderStepped:Connect(function(dt)
            pos = pos:Lerp(target, 1 - math.exp(-dt * 22))
            if not pressing and (target - pos).Magnitude < 0.3 then
                pos = target
                follow:Disconnect()
                follow = nil
            end
            holder.Position = UDim2.new(0.5, pos.X, 0.5, pos.Y)
        end)
        conns[#conns + 1] = follow
    end
    -- anything else that moves the window (maximise, the open/close animation)
    -- takes over from a glide still in flight instead of fighting it
    UI.stopWindowGlide = function()
        if follow and not pressing then follow:Disconnect(); follow = nil end
    end
    local function lift(up)
        lifted = up
        if up then
            tween(UI.winShadow, 0.25, SHADOW_LIFT)
            tween(UI.winRim, 0.25, { Transparency = 0.88 })
        else
            tween(UI.winShadow, 0.45, UI.SHADOW_REST, EASE.Quart)
            tween(UI.winRim, 0.45, { Transparency = 0.95 }, EASE.Quart)
        end
    end

    -- The one way a drag ends, however the release arrives (or doesn't): it
    -- settles down and remembers the spot. The lost-release path used to set
    -- it down without saving, so the next run opened it at the old place.
    local function finishDrag()
        if not pressing then return end
        pressing, dragInput = false, nil
        if lifted then
            lift(false)
            if not UI.maximised then
                settings.x, settings.y = math.floor(target.X + 0.5), math.floor(target.Y + 0.5)
                saveSettings()
            end
        end
    end
    UI.topbar.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        -- not when the press is on the window controls or the Discord tag
        local p = input.Position
        for _, g in ipairs({ controls, UI.discordTag }) do
            local gp, gs = g.AbsolutePosition, g.AbsoluteSize
            if g.Visible and p.X >= gp.X and p.X <= gp.X + gs.X and p.Y >= gp.Y and p.Y <= gp.Y + gs.Y then return end
        end
        local now = os.clock()
        if now - lastClick < 0.35 then
            lastClick = 0
            if minimiseWindow then task.spawn(minimiseWindow) end
            return
        end
        lastClick = now
        pressing, pressAt, dragInput = true, p, input
        startPos = Vector2.new(holder.Position.X.Offset, holder.Position.Y.Offset)
        target = startPos
        local c; c = input.Changed:Connect(function()
            if input.UserInputState ~= Enum.UserInputState.End and input.UserInputState ~= Enum.UserInputState.Cancel then return end
            c:Disconnect()
            finishDrag()
        end)
    end)
    conns[#conns + 1] = UIS.InputChanged:Connect(function(input)
        if not pressing then return end
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
        -- only the finger that grabbed the title bar moves it (not the
        -- thumbstick's, or any other touch the game is handling)
        if t == Enum.UserInputType.Touch and input ~= dragInput then return end
        -- the release can go missing (let go over another UI, alt-tab): the
        -- window then stayed "held" and ticked after the mouse on its own
        if t == Enum.UserInputType.MouseMovement and dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1
           and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            finishDrag()
            return
        end
        local d = input.Position - pressAt
        if not lifted then
            if Vector2.new(d.X, d.Y).Magnitude < 3 then return end
            lift(true)
            -- a drag, not a click: it mustn't count as the first half of a
            -- double-click (re-grabbing quickly used to minimise the window)
            lastClick = 0
        end
        local ox, oy = UI.clampOffset(startPos.X + d.X, startPos.Y + d.Y, UI.winW, UI.winH)
        target = Vector2.new(ox, oy)
        glide()
    end)
end

-- Hover ring: the same outline animation as the Autofarm cards -- the edge
-- carries a gradient from a dim grey to a whitish highlight that slowly turns
-- round (once every 7s). It fades in on hover and out on leave; it only
-- turns while it's showing.
function UI.hoverRing(parent, radius, inset)
    inset = inset or 0
    local f = make("Frame", {
        Name = "HoverRing", BackgroundTransparency = 1, Position = UDim2.fromOffset(inset, inset),
        Size = UDim2.new(1, -2 * inset, 1, -2 * inset), ZIndex = 8, Parent = parent,
    })
    corner(f, radius)
    local st = make("UIStroke", { Color = WHITE, Thickness = 1, Transparency = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
    local DIM, LIT = C.borderHi:Lerp(WHITE, 0.1), WHITE
    local g = make("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, DIM), ColorSequenceKeypoint.new(0.45, DIM), ColorSequenceKeypoint.new(1, LIT),
        }),
        Parent = st,
    })
    local spin, gen = nil, 0
    return function(on)
        gen += 1
        local mine = gen
        if on then
            if not spin then
                local from = g.Rotation % 360
                g.Rotation = from
                spin = TweenService:Create(g, TweenInfo.new(7, EASE.Linear, DIR.In, -1), { Rotation = from + 360 })
                spin:Play()
            end
            tween(st, 0.18, { Transparency = 0 })
        else
            local t = tween(st, 0.22, { Transparency = 1 })
            t.Completed:Connect(function(state)
                if state == Enum.PlaybackState.Completed and mine == gen and spin then spin:Pause(); spin = nil end
            end)
        end
    end
end

-- Click ripple: a soft white circle that spreads from where you pressed and
-- fades out, clipped to the thing you pressed.
-- Roblox drops MouseLeave when the mouse moves fast, or leaves the window,
-- or a frame pops up under it: the row then stays lit as if hovered. While a
-- button thinks it's hovered this checks each frame that the mouse really is
-- over it, and calls leave() once it isn't.
function C.hoverGuard(b, leave)
    -- (screen space including the top bar, like this GUI: IgnoreGuiInset)
    local UIS_ = game:GetService("UserInputService")
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local p, sz = b.AbsolutePosition + game:GetService("GuiService"):GetGuiInset(), b.AbsoluteSize
        local m = UIS_:GetMouseLocation()
        local x, y = m.X, m.Y
        if not b.Parent or not b.Visible or x < p.X or y < p.Y or x > p.X + sz.X or y > p.Y + sz.Y then
            conn:Disconnect()
            leave()
        end
    end)
    return conn
end

-- A still twin for an icon that pops on hover. A scaled (or tilted) image
-- draws a touch soft -- its edges fall between pixels -- and the frame where
-- it lands back at exactly 100% snapped sharp: it "clicked into HD". The
-- twin is a copy that's never scaled, laid over the original: hidden the
-- moment the pop starts (both look the same then), faded back in over the
-- last stretch of the way down, so the sharpness comes back softly.
-- twin.set(shown, time, delay). A colour tween on the original carries over.
function UI.crispTwin(icon)
    local twin = icon:Clone()
    for _, d in ipairs(twin:GetDescendants()) do
        if d:IsA("UIScale") then d:Destroy() end
    end
    twin.Rotation = 0
    twin.ZIndex = icon.ZIndex + 1
    for _, d in ipairs(twin:GetDescendants()) do
        if d:IsA("GuiObject") then d.ZIndex = d.ZIndex + 1 end
    end
    twin.Parent = icon.Parent
    -- everything that shows, and how opaque it is at rest
    local parts = {}
    local function keep(o)
        if o:IsA("ImageLabel") then parts[#parts + 1] = { o, "ImageTransparency", o.ImageTransparency }
        elseif o:IsA("Frame") and o.BackgroundTransparency < 1 then parts[#parts + 1] = { o, "BackgroundTransparency", o.BackgroundTransparency } end
    end
    keep(twin)
    for _, d in ipairs(twin:GetDescendants()) do keep(d) end
    if icon:IsA("ImageLabel") then
        icon:GetPropertyChangedSignal("ImageColor3"):Connect(function() twin.ImageColor3 = icon.ImageColor3 end)
    end
    local T, running = { twin = twin }, {}
    function T.set(shown, t, delay)
        for _, tw in ipairs(running) do tw:Cancel() end
        running = {}
        for _, p in ipairs(parts) do
            local goal = shown and p[3] or 1
            if not t or t <= 0 then
                p[1][p[2]] = goal
            else
                local tw = TweenService:Create(p[1], TweenInfo.new(t, EASE.Quad, DIR.Out, 0, false, delay or 0), { [p[2]] = goal })
                tw:Play()
                running[#running + 1] = tw
            end
        end
    end
    return T
end

function C.bolden(img, px)
    px = px or 0.6
    local copies = {}
    for _, o in ipairs({ Vector2.new(px, 0), Vector2.new(-px, 0), Vector2.new(0, px), Vector2.new(0, -px) }) do
        copies[#copies + 1] = make("ImageLabel", { BackgroundTransparency = 1, Image = img.Image, ImageColor3 = img.ImageColor3,
            ImageTransparency = img.ImageTransparency, Position = UDim2.fromOffset(o.X, o.Y), Size = UDim2.fromScale(1, 1),
            ZIndex = img.ZIndex, Parent = img })
    end
    -- the picture too: the island's check becomes an X for a failed job, and
    -- copies stuck on the old picture drew a ghost check under the X
    local function sync()
        for _, c in ipairs(copies) do
            c.Image, c.ImageColor3, c.ImageTransparency = img.Image, img.ImageColor3, img.ImageTransparency
        end
    end
    img:GetPropertyChangedSignal("Image"):Connect(sync)
    img:GetPropertyChangedSignal("ImageColor3"):Connect(sync)
    img:GetPropertyChangedSignal("ImageTransparency"):Connect(sync)
    return img
end

function C.ripple(host, radius)
    local clip = make("CanvasGroup", { Name = "Ripple", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
        ZIndex = 9, Parent = host })
    corner(clip, radius or 10)
    local m = UIS:GetMouseLocation() - game:GetService("GuiService"):GetGuiInset()
    local sc = unscale()
    local p = (m - host.AbsolutePosition) / sc
    local reach = math.max(host.AbsoluteSize.X, host.AbsoluteSize.Y) / sc * 2.2
    local dot = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p.X, p.Y),
        Size = UDim2.fromOffset(4, 4), BackgroundColor3 = WHITE, BackgroundTransparency = 0.82, BorderSizePixel = 0,
        ZIndex = 9, Parent = clip })
    corner(dot, FULL)
    local info = TweenInfo.new(0.6, EASE.Quint, DIR.Out)
    TweenService:Create(dot, info, { Size = UDim2.fromOffset(reach, reach), BackgroundTransparency = 1 }):Play()
    task.delay(0.65, function() clip:Destroy() end)
end

--// Tabs ----------------------------------------------------------
-- Every tab of the full Onyx hub, in its order. Home is where Onyx opens; the
-- tabs with no page of their own open a "coming soon" page. `caption` is each
-- tab's resting line in the caption, drawn from the hub's own sections.
local TABS = {
    { id = "home",      name = "Home",               icon = ICON.tabHome,      caption = "EVERYTHING AT A GLANCE" },
    { id = "combat",    name = "Combat",             icon = ICON.tabCombat,    caption = "TOOLS FOR THE SHERIFF AND THE MURDERER" },
    { id = "hvh",       name = "HVH",                icon = ICON.tabHvh,       caption = "HACK VS HACK: TAKE ON OTHER EXPLOITERS" },
    { id = "crosshair", name = "Crosshair",          icon = ICON.tabCrosshair, caption = "A CUSTOM CROSSHAIR FOR THE SHERIFF'S GUN" },
    { id = "skins",     name = "Skin Changer",       icon = ICON.tabSkin },
    { id = "buttons",   name = "Buttons",            icon = ICON.tabButtons,   caption = "ON-SCREEN BUTTONS FOR QUICK ACTIONS" },
    { id = "esp",       name = "ESP",                icon = ICON.tabEsp,       caption = "SEE EVERY PLAYER THROUGH WALLS" },
    { id = "fling",     name = "Fling & Teleport",   icon = ICON.tabFling,     caption = "FLING PLAYERS AND TELEPORT AROUND" },
    { id = "farm",      name = "Autofarm",           icon = ICON.tabFarm,      caption = "FARM COINS AND OPEN BOXES AUTOMATICALLY" },
    { id = "player",    name = "Player",             icon = ICON.tabPlayer,    caption = "SPEED, ESCAPE AND DEFENSE" },
    { id = "visuals",   name = "Visuals",            icon = ICON.tabVisuals,   caption = "SOUNDS, EFFECTS AND PERFORMANCE" },
    { id = "keybinds",  name = "Keybinds",           icon = ICON.tabKeybinds,  caption = "YOUR OWN KEYS FOR EVERYTHING" },
    { id = "settings",  name = "Settings & Configs", icon = ICON.tabSettings,  caption = "INTERFACE, PROTECTION AND CONFIGS" },
}

--// Sidebar -------------------------------------------------------
UI.sidebar = make("Frame", {
    Name = "Sidebar", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, UI.BODY_TOP),
    Size = UDim2.new(0, 227, 1, -UI.BODY_TOP), ZIndex = 2, Parent = win,
})
do
    -- The nav panel: a card holding the tab buttons -- no fill, just a soft
    -- graphite outline with a faint glow (a crisp 1px edge over two wider,
    -- fainter rings), centred between the window's edge and the content
    -- column: 16px of air either side. Its top edge runs along the caption's
    -- line (HAIRLINE_Y: the same pixel row as the caption's hairlines and the
    -- background grid line), and "SELECT TAB" sits on it the way the caption
    -- sits on its hairlines -- a legend, with the edge breaking around it.
    local PANEL_X, PANEL_W, PANEL_B = 16, 195, UI.BODY_BOTTOM
    local PANEL_Y = UI.HAIRLINE_Y + 1 - UI.BODY_TOP     -- the 1px edge is drawn just outside the frame
    local RADIUS, GLOW = 12, 6                    -- corner radius; how far the outline reaches out
    local EDGE = hex("#4a4a52")                   -- one even soft graphite all the way round
    local RINGS = { { 5, 0.95 }, { 3, 0.9 }, { 1, 0.6 } }   -- glow, glow, edge: { thickness, transparency }
    local LEGEND_GAP = 12                         -- air either side of the legend, as on the caption

    -- The outline is drawn three times, each copy clipped to one piece: left of
    -- the legend, right of it, and everything below the top corners. The copies
    -- line up exactly, so it reads as one outline with a clean break in its top
    -- edge -- and the background (grid line included) shows through the break,
    -- just as it does behind the caption.
    local function outline(parent, anchor, pos, size)
        for _, ring in ipairs(RINGS) do
            local r = make("Frame", { BackgroundTransparency = 1, AnchorPoint = anchor, Position = pos, Size = size, Parent = parent })
            corner(r, RADIUS)
            stroke(r, EDGE, ring[1], ring[2])
        end
    end
    local fullW, topH = PANEL_W + GLOW * 2, GLOW + RADIUS
    local topCopy = UDim2.fromOffset(PANEL_W, RADIUS * 4)   -- tall enough that its bottom corners are cut off
    -- left piece: pinned to the left, so only its width changes
    local clipL = make("Frame", {
        BackgroundTransparency = 1, ClipsDescendants = true,
        Position = UDim2.fromOffset(PANEL_X - GLOW, PANEL_Y - GLOW), Size = UDim2.fromOffset(fullW / 2, topH), Parent = UI.sidebar,
    })
    outline(clipL, Vector2.zero, UDim2.fromOffset(GLOW, GLOW), topCopy)
    -- right piece: pinned to the right, its copy too
    local clipR = make("Frame", {
        BackgroundTransparency = 1, ClipsDescendants = true, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromOffset(PANEL_X + PANEL_W + GLOW, PANEL_Y - GLOW), Size = UDim2.fromOffset(fullW / 2, topH), Parent = UI.sidebar,
    })
    outline(clipR, Vector2.new(1, 0), UDim2.new(1, -GLOW, 0, GLOW), topCopy)
    -- the rest: from where the top corners end down past the bottom glow
    local clipB = make("Frame", {
        BackgroundTransparency = 1, ClipsDescendants = true,
        Position = UDim2.fromOffset(PANEL_X - GLOW, PANEL_Y + RADIUS),
        Size = UDim2.new(0, fullW, 1, GLOW - (PANEL_Y + RADIUS + PANEL_B)), Parent = UI.sidebar,
    })
    outline(clipB, Vector2.zero, UDim2.fromOffset(GLOW, -RADIUS), UDim2.new(0, PANEL_W, 1, RADIUS - GLOW))

    -- the legend: tracked like the caption (Geist Medium 11, one label per
    -- character, 2px apart) and on the same row, so the two read as one line
    local LEGEND_Y = UI.HAIRLINE_Y - 8 - UI.BODY_TOP    -- 16 tall, centred on the edge, like the caption on its line
    local legend = make("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(PANEL_X, LEGEND_Y),
        Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X, Parent = UI.sidebar,
    })
    hlist(legend, 2)
    for i, code in utf8.codes("SELECT TAB") do
        local c = utf8.char(code)
        if c == " " then
            make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(2, 16), LayoutOrder = i, Parent = legend })
        else
            text({ Text = c, FontFace = geist(FW.Medium), TextSize = 11, TextColor3 = C.subtle,
                   Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X,
                   TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = i, Parent = legend })
        end
    end
    -- centre it on the panel, on a whole pixel, and open the break around it
    -- (again once the font has loaded and it re-measures)
    local function layoutBreak()
        local w = math.floor(legend.AbsoluteSize.X / unscale() + 0.5)
        local x = PANEL_X + math.floor((PANEL_W - w) / 2)
        legend.Position = UDim2.fromOffset(x, LEGEND_Y)
        clipL.Size = UDim2.fromOffset(math.max(0, x - LEGEND_GAP - (PANEL_X - GLOW)), topH)
        clipR.Size = UDim2.fromOffset(math.max(0, (PANEL_X + PANEL_W + GLOW) - (x + w + LEGEND_GAP)), topH)
    end
    legend:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutBreak)
    layoutBreak()

    -- the panel itself only holds the tabs
    local panel = make("Frame", {
        Name = "NavPanel", BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(PANEL_X, PANEL_Y), Size = UDim2.new(0, PANEL_W, 1, -(PANEL_Y + PANEL_B)), Parent = UI.sidebar,
    })

    -- The tabs: one row each. The open tab sits on a raised pill that glides
    -- to whichever row you pick; the others stay bare until you hover them.
    -- The first row's frame lines up with the search bar's, and the rows
    -- spread out to fill the panel (see spread() below).
    local ROW_H, ROW_GAP = 38, 8
    local listY = UI.SEARCH_Y + 1 - UI.BODY_TOP - PANEL_Y
    local tabList = make("ScrollingFrame", {
        Name = "TabList", BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.Y, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        -- 1px of room on every side, so the pill's outline is never clipped
        Position = UDim2.fromOffset(8, listY - 1), Size = UDim2.new(1, -16, 1, -(listY - 1) - 8), Parent = panel,
    })
    local canvasEnd = make("Frame", {      -- holds the canvas open to just past the last row
        BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1),
        Position = UDim2.fromOffset(0, #TABS * (ROW_H + ROW_GAP) - ROW_GAP + 1), Parent = tabList,
    })
    local cursor = make("Frame", {
        BackgroundColor3 = C.pill, BorderSizePixel = 0, Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 0, ROW_H), Parent = tabList,
    })
    corner(cursor, 9)
    local cursorStroke = stroke(cursor, C.border)

    local HOVER_FILL, PRESS_FILL = hex("#111114"), hex("#18181b")
    local GLIDE = TweenInfo.new(0.4, EASE.Quint, DIR.Out)
    local SOFT = TweenInfo.new(0.2, EASE.Quint, DIR.Out)
    local function play(obj, info, goal) TweenService:Create(obj, info, goal):Play() end
    local rows = {}
    local function paintRow(r)
        local lit = r.on or r.over
        play(r.label, SOFT, { TextColor3 = lit and C.text or C.muted })
        if not r.tab.picture then play(r.icon, SOFT, { ImageColor3 = lit and C.text or C.muted }) end
        -- Hovered (and on the open tab) the icon pops: a quick grow past its
        -- size with a small tilt, then it settles at 120% and straightens;
        -- leaving, it glides back down. Only when the target changes, so a
        -- click doesn't restart it.
        if r.iconScale and r.iconLit ~= lit then
            r.iconLit = lit
            r.popTok = (r.popTok or 0) + 1
            local mine = r.popTok
            if lit then
                if r.crisp then r.crisp.set(false) end       -- (the still twin steps aside: see UI.crispTwin)
                local up = TweenService:Create(r.iconScale, TweenInfo.new(0.16, EASE.Quad, DIR.Out), { Scale = 1.28 })
                up:Play()
                TweenService:Create(r.icon, TweenInfo.new(0.16, EASE.Quad, DIR.Out), { Rotation = -8 }):Play()
                up.Completed:Connect(function()
                    if r.popTok ~= mine then return end
                    TweenService:Create(r.iconScale, TweenInfo.new(0.32, EASE.Sine, DIR.InOut), { Scale = 1.2 }):Play()
                    TweenService:Create(r.icon, TweenInfo.new(0.4, EASE.Back, DIR.Out), { Rotation = 0 }):Play()
                end)
            else
                -- back down evenly (a Quint ease did most of the way in its
                -- first tenth of a second, so the icon seemed to click back)
                TweenService:Create(r.iconScale, TweenInfo.new(0.42, EASE.Sine, DIR.InOut), { Scale = 1 }):Play()
                TweenService:Create(r.icon, TweenInfo.new(0.42, EASE.Sine, DIR.InOut), { Rotation = 0 }):Play()
                -- the sharp twin fades back in over the last of the way down
                if r.crisp then r.crisp.set(true, 0.2, 0.26) end
            end
        end
        -- no grey fill on hover: the turning white outline instead
        if r.ring then r.ring(r.over and not r.on) end
        if r.on then
            play(cursor, SOFT, { BackgroundColor3 = r.over and C.pillHover or C.pill })
            play(cursorStroke, SOFT, { Color = r.over and C.borderHi or C.border })
        end
    end
    function markTab(id)
        for _, r in ipairs(rows) do
            r.on = r.tab.id == id
            if r.on then play(cursor, GLIDE, { Position = r.button.Position }) end
            paintRow(r)
        end
    end

    for i, tab in ipairs(TABS) do
        local b = make("TextButton", {
            Name = tab.id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(1, 1 + (i - 1) * (ROW_H + ROW_GAP)), Size = UDim2.new(1, -2, 0, ROW_H),
            ZIndex = 2, Parent = tabList,
        })
        local hover = make("Frame", {
            BackgroundColor3 = HOVER_FILL, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), Parent = b,
        })
        corner(hover, 9)
        -- the icon keeps to the left edge, all icons on one line; the name is
        -- centred across the whole row on its own, so the icon never shifts it
        -- (the skin picture is a touch bigger than the glyph icons)
        local size = tab.picture and 20 or 16
        local icon = image({
            Image = tab.icon, ImageColor3 = tab.picture and WHITE or C.muted, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 20, 0.5, 0), Size = UDim2.fromOffset(size, size), ZIndex = 2, Parent = b,
        })
        -- (text can't scale smoothly in Roblox -- it redraws at whole pixel
        -- sizes -- so on hover the name glides a few pixels right instead)
        local labelBox = make("Frame", {
            BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = b,
        })
        local label = text({
            Text = tab.name, FontFace = geist(FW.SemiBold), TextSize = 13, TextColor3 = C.muted,
            TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = labelBox,
        })
        local r = { tab = tab, button = b, hover = hover, icon = icon, label = label, over = false, on = false }
        rows[#rows + 1] = r
        -- the icon grows a little on hover (like the skin cards) and eases back,
        -- with a still twin over it at rest (see UI.crispTwin)
        r.crisp = UI.crispTwin(icon)
        local iconScale = make("UIScale", { Parent = icon })
        r.iconScale = iconScale
        r.ring = UI.hoverRing(b, 9, 0)
        local function leave()
            if r.guard then r.guard:Disconnect(); r.guard = nil end
            if not r.over then return end
            r.over = false; paintRow(r)
        end
        b.MouseEnter:Connect(function()
            r.over = true; paintRow(r); sfx("hover")
            if r.guard then r.guard:Disconnect() end
            r.guard = C.hoverGuard(b, function() r.guard = nil; leave() end)
        end)
        b.MouseLeave:Connect(leave)
        b.MouseButton1Down:Connect(function()
            C.ripple(b, 9)
            -- pressed in a touch, then springs back out on release
            play(iconScale, TweenInfo.new(0.12, EASE.Quint, DIR.Out), { Scale = 0.96 })
            -- forget the painted state, so whatever comes next (release, or a
            -- leave when the release lands elsewhere) re-applies the icon's scale
            r.iconLit = nil
            if r.on then play(cursor, SOFT, { BackgroundColor3 = PRESS_FILL })
            else play(hover, SOFT, { BackgroundColor3 = PRESS_FILL }) end
        end)
        b.MouseButton1Up:Connect(function()
            play(hover, SOFT, { BackgroundColor3 = HOVER_FILL })
            play(iconScale, TweenInfo.new(0.4, EASE.Quint, DIR.Out), { Scale = (r.on or r.over) and 1.2 or 1 })
            paintRow(r)
        end)
        b.MouseButton1Click:Connect(function()
            sfx("click")
            if selectTab then selectTab(tab) end
        end)
    end

    -- Spread the rows over the panel's height, so the last one ends as far
    -- from the bottom as the rows sit from the sides. The gap stays between
    -- 6px and 16px: a tall (maximised) window doesn't scatter them. Before the
    -- list has to scroll, the rows give up a little height (down to 32px):
    -- thirteen tabs at 38px don't fit the standard 660px window, and the last
    -- two hid below the panel's edge.
    local function spread()
        local h = tabList.AbsoluteWindowSize.Y / unscale() - 2
        local rowH = math.clamp(math.floor((h - (#TABS - 1) * 6) / #TABS), 32, ROW_H)
        local gap = math.clamp((h - #TABS * rowH) / (#TABS - 1), 6, 16)
        for i, r in ipairs(rows) do
            r.button.Position = UDim2.fromOffset(1, 1 + math.floor((i - 1) * (rowH + gap) + 0.5))
            r.button.Size = UDim2.new(1, -2, 0, rowH)
            -- through a (zero-length) tween: a direct write was overridden by
            -- markTab's glide still running, which then landed on the old spot
            if r.on then TweenService:Create(cursor, TweenInfo.new(0), { Position = r.button.Position }):Play() end
        end
        cursor.Size = UDim2.new(1, -2, 0, rowH)
        canvasEnd.Position = UDim2.fromOffset(0, math.floor(#TABS * rowH + (#TABS - 1) * gap + 1.5))
    end
    tabList:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(spread)

    -- Home starts open, its pill already in place
    for _, r in ipairs(rows) do r.on = r.tab.id == "home" end
    spread()
    markTab("home")
end

--// Content -------------------------------------------------------
-- The scrolling list: the search row, the grid and its states. It starts just
-- under the pinned caption, and its 10px top padding keeps the search row
-- level with the Skin Changer tab.
local content = make("ScrollingFrame", {
    Name = "Content", BackgroundTransparency = 1, BorderSizePixel = 0,
    Position = UDim2.fromOffset(207, UI.LIST_TOP), Size = UDim2.new(1, -214, 1, -(UI.LIST_TOP + UI.BODY_BOTTOM - 1)),
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3,
    ScrollBarImageColor3 = C.borderHi, ScrollBarImageTransparency = 1,
    VerticalScrollBarInset = Enum.ScrollBarInset.None, ZIndex = 2, Parent = win,
})
pad(content, 20, 20, UI.SEARCH_Y - UI.LIST_TOP, 20)
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = content })

-- The list scrolls inside a rounded clip that hugs the tile area (the list's
-- content edges plus 2px for the tile outlines), so tiles passing the top or
-- bottom are cut along a 12px curve -- the tiles' own radius -- rather than a
-- square edge. A CanvasGroup is the only thing Roblox rounds a clip with.
-- The list keeps its exact place and size inside it; only its scrollbar,
-- which sat outside the tile area, is redrawn by hand next to it.
UI.LIST_CLIP_X = UI.CONTENT_X - 2
-- everything that belongs to the Skin Changer tab, so switching tabs can hide
-- it in one go; it covers the window, so nothing inside it moves
UI.skinPage = make("Frame", {
    Name = "SkinPage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = win,
})
UI.listClip = make("CanvasGroup", {
    Name = "ListClip", BackgroundTransparency = 1, BorderSizePixel = 0,
    Position = UDim2.fromOffset(UI.LIST_CLIP_X, UI.LIST_TOP),
    Size = UDim2.new(1, -(UI.LIST_CLIP_X + 25), 1, -(UI.LIST_TOP + UI.BODY_BOTTOM - 1)), ZIndex = 2, Parent = UI.skinPage,
})
corner(UI.listClip, 12)
-- Soft edges for a scrolling page: cards scrolling past fade out over the
-- last 28px instead of being cut off square, and over the first 28px at the
-- top too -- that one grows in with the first 28px of scroll, so at rest
-- nothing up top (the search row) is faded. `host` is the CanvasGroup the
-- page draws in, `scroll` the list inside it.
function C.edgeFade(host, scroll)
    local mask = make("UIGradient", { Rotation = 90, Parent = host })
    local EDGE = 28
    local function fit()
        local h = host.AbsoluteSize.Y
        if h < 60 then return end
        local e = math.clamp(EDGE / h, 0.01, 0.25)
        local top = scroll and math.clamp(scroll.CanvasPosition.Y / EDGE, 0, 1) or 0
        mask.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, top), NumberSequenceKeypoint.new(e, 0),
            NumberSequenceKeypoint.new(1 - e, 0), NumberSequenceKeypoint.new(1, 1),
        })
    end
    host:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    if scroll then scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(fit) end
    task.defer(fit)
end
C.edgeFade(UI.listClip, content)
content.Position = UDim2.fromOffset(207 - UI.LIST_CLIP_X, 0)
content.Size = UDim2.new(1, (UI.LIST_CLIP_X - 207) + 25 - 7, 1, 0)
content.ScrollBarThickness = 0
content.Parent = UI.listClip

-- the scrollbar: 3px, where the built-in one was, sized and placed from the
-- list's scroll; fades in while you scroll and out once it settles
UI.scrollBar = make("Frame", {
    Name = "ScrollBar", BackgroundColor3 = C.borderHi, BackgroundTransparency = 1, BorderSizePixel = 0,
    AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(3, 0), ZIndex = 3, Parent = UI.skinPage,
})
corner(UI.scrollBar, FULL)
function UI.placeScrollBar()
    local s = unscale()
    local view, canvas = content.AbsoluteWindowSize.Y / s, content.AbsoluteCanvasSize.Y / s
    local top = UI.LIST_TOP
    if canvas <= view + 1 then UI.scrollBar.Visible = false return end
    UI.scrollBar.Visible = true
    local h = math.max(24, view * view / canvas)
    local y = content.CanvasPosition.Y / s / (canvas - view) * (view - h)
    UI.scrollBar.Size = UDim2.fromOffset(3, math.floor(h + 0.5))
    UI.scrollBar.Position = UDim2.new(1, -7, 0, math.floor(top + y + 0.5))
end
content:GetPropertyChangedSignal("CanvasPosition"):Connect(UI.placeScrollBar)
content:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(UI.placeScrollBar)
content:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(UI.placeScrollBar)


-- Caption: the site's "PASTE THIS INTO YOUR EXECUTOR" label — uppercase,
-- tracked out, with a hairline either side. Roblox has no letter-spacing, so
-- the text is laid out one character per label with a 2px gap (the design's
-- 1.8px); the hairlines slide to fill whatever is left.
-- Pinned: it sits on the window rather than in the list, so it -- and every
-- status message it shows -- stays in view however far the grid is scrolled.
-- As wide as the list's content (20px in from either side of the list).
UI.captionRow = make("Frame", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(UI.CONTENT_X, UI.CAPTION_Y),
    Size = UDim2.new(1, -(UI.CONTENT_X + 27), 0, 16), ZIndex = 2, Parent = win,
})
-- the letters are placed by hand (see setTracked), and the line is centred
-- in the row on a whole pixel
UI.captionText = make("Frame", {
    BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 16), Parent = UI.captionRow,
})
-- on a whole pixel (row top + 8, i.e. HAIRLINE_Y), so they sit exactly on
-- the background grid line that runs through them
UI.lineL = make("Frame", {
    BackgroundColor3 = C.border, BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(0, 1), Parent = UI.captionRow,
})
UI.lineR = make("Frame", {
    BackgroundColor3 = C.border, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, 8), Size = UDim2.fromOffset(0, 1), Parent = UI.captionRow,
})
-- The hairlines make room for the widest line on show -- during a crossfade
-- that may be the old one still fading out. Making room is a quick 0.14s
-- slide, done before the new letters start to fade in (they wait 0.15s), so
-- a longer line never shows with the hairlines through it; taking freed
-- space back is a slower glide. Instant captions (live search) snap.
UI.captionGhost = nil
UI.captionInstant = false
UI.lineTweens = {}
function UI.layoutHairlines()
    local rowW = UI.captionRow.AbsoluteSize.X / unscale()
    UI.captionText.Position = UDim2.fromOffset(math.floor((rowW - UI.captionText.Size.X.Offset) / 2), 0)
    local textW = UI.captionText.AbsoluteSize.X
    if UI.captionGhost and UI.captionGhost.Parent then textW = math.max(textW, UI.captionGhost.AbsoluteSize.X) end
    local w = math.max(0, ((UI.captionRow.AbsoluteSize.X - textW) / 2) / unscale() - 12)
    for i, line in ipairs({ UI.lineL, UI.lineR }) do
        if UI.lineTweens[i] then UI.lineTweens[i]:Cancel() end
        if w < line.Size.X.Offset then
            if UI.captionInstant then
                line.Size = UDim2.fromOffset(w, 1)
            else
                UI.lineTweens[i] = tween(line, 0.14, { Size = UDim2.fromOffset(w, 1) }, EASE.Quad, DIR.Out)
            end
        else
            UI.lineTweens[i] = tween(line, 0.3, { Size = UDim2.fromOffset(w, 1) })
        end
    end
end
UI.captionText:GetPropertyChangedSignal("AbsoluteSize"):Connect(UI.layoutHairlines)
UI.captionRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(UI.layoutHairlines)
-- One right edge for every tab: the background grid line nearest to where
-- the Skin Changer's search row ends (the left edge, CONTENT_X, is a grid
-- line too). The list widens or narrows the few pixels that put the Spawn
-- all / Despawn all bar's outline on it -- and fitCells puts the last card's
-- there -- the caption's right hairline ends on it, and so do the other
-- tabs' cards (UI.snapPage). Each used to stop a few pixels off it, and off
-- each other.
UI.LIST_CLIP_SIZE = UI.listClip.Size
UI.skinSnap = 0
function UI.snapSkin()
    if not UI.actionBar then return end
    local sc = unscale()
    local barR = (UI.actionBar.AbsolutePosition.X + UI.actionBar.AbsoluteSize.X - win.AbsolutePosition.X) / sc
    if barR < 10 then return end
    local r0 = math.floor(barR + 0.5) - UI.skinSnap      -- where it ends unsnapped
    local g0 = UI.CONTENT_X % 60
    local line = g0 + math.floor((r0 - g0) / 60 + 0.5) * 60
    UI.gridRight = line
    if line - r0 ~= UI.skinSnap then
        UI.skinSnap = line - r0
        UI.listClip.Size = UI.LIST_CLIP_SIZE + UDim2.fromOffset(UI.skinSnap, 0)
    end
    UI.fitCaption()
end
-- the caption row ends on that line (+1: the line's own pixel, as the left
-- hairline starts on its line's)
function UI.fitCaption()
    if not UI.gridRight then return end
    UI.captionRow.Size = UDim2.new(0, UI.gridRight + 1 - UI.CONTENT_X, 0, 16)
end
win:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() task.defer(UI.snapSkin) end)

-- A tab's cards end on that same line. Measured off the page's own cards --
-- the right-most outline it shows, leaving out hover rings and glows that
-- are faded away -- so each page's padding and scrollbar lane count as they
-- are. (The old fixed guess left the Fling page's cards 4px past the line.)
function UI.snapPage(page)
    local function hidden(d, stop)
        local q = d.Parent
        while q and q ~= stop do
            if q:IsA("CanvasGroup") and q.GroupTransparency >= 0.99 then return true end
            q = q.Parent
        end
        return false
    end
    local function fit()
        if not UI.gridRight then return end
        local scroll = page:FindFirstChildWhichIsA("ScrollingFrame")
        if not scroll then return end
        local sc = unscale()
        local best
        for _, d in ipairs(scroll:GetDescendants()) do
            -- (NoSnap: things that float rather than lay out, like Home's chart
            -- bubble -- left where it last was, mid-resize it counted as the
            -- right-most card and shrank Home to 12px for good)
            if d:IsA("GuiObject") and d.Visible and d.AbsoluteSize.X > 40 * sc and not d:GetAttribute("NoSnap") then
                local st = d:FindFirstChildOfClass("UIStroke")
                if st and st.Transparency < 0.9 and not hidden(d, scroll) then
                    local r = d.AbsolutePosition.X + d.AbsoluteSize.X
                    if not best or r > best then best = r end
                end
            end
        end
        if not best then return end
        local applied = page.Size.X.Offset - UI.listClip.Size.X.Offset
        local r0 = math.floor((best - win.AbsolutePosition.X) / sc + 0.5) - applied
        page.Size = UI.listClip.Size + UDim2.fromOffset(UI.gridRight - r0, 0)
    end
    UI.listClip:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() task.defer(fit) end)
    task.defer(fit)
    task.delay(0.5, fit)
    task.delay(2, fit)
    return fit
end

-- Swap the caption. Style: a Color3, or a table with
--   color, gradient = { from, to } (a smooth left-to-right colour ramp),
--   icon / iconColor (a small glyph before the text), hairline (line colour),
--   instant (no fade, for live search updates).
-- The change is a crossfade in place, like the search hints: the old line
-- moves onto a "ghost" row laid out exactly like it and fades away there,
-- while the new line fades in on top, a beat later.
-- Letter widths for the caption. Measured once per letter at 10x the size
-- and scaled down, so each is exact to a fraction of a pixel; the letters are
-- then placed at their true running position, each rounded to a whole pixel
-- on its own. Rounding every width and adding them up instead left odd 1px
-- gaps after some letters ("PERF ORMANCE").
local advance
do
    local cache = {}
    local TS = game:GetService("TextService")
    local function measure(txt)
        local params = Instance.new("GetTextBoundsParams")
        params.Text, params.Font, params.Size, params.Width = txt, geist(FW.Medium), 110, 100000
        local ok, b = pcall(TS.GetTextBoundsAsync, TS, params)
        return ok and b and b.X or nil
    end
    function advance(c)
        local w = cache[c]
        if w then return w end
        if c == " " then
            local a, b = measure("x" .. string.rep(" ", 10) .. "x"), measure("xx")
            w = (a and b) and (a - b) / 100 or 2.75
        else
            local a = measure(string.rep(c, 10))
            w = a and a / 100 or 7
        end
        cache[c] = w
        return w
    end
    -- measure the usual letters up front, so a caption never waits on one
    task.spawn(function()
        for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,'\"·&-…()!?/:×%+"):gmatch(utf8.charpattern) do
            advance(c)
        end
    end)
end

UI.captionAnim = 0
UI.CAPTION_OUT = TweenInfo.new(0.35, EASE.Sine, DIR.InOut)
UI.CAPTION_IN = TweenInfo.new(0.4, EASE.Sine, DIR.InOut, 0, false, 0.15)
UI.shownCaption = nil
-- First n characters of s plus "…" when it's longer. By characters, not
-- bytes: cutting a multi-byte letter in half made setTracked throw.
function UI.cutText(s, n)
    s = tostring(s)
    local len = utf8.len(s)
    if not len or len <= n then return s end
    return s:sub(1, utf8.offset(s, n) - 1) .. "…"
end
function UI.setTracked(str, style)
    -- utf8.codes below throws on broken UTF-8; never let a caption do that
    if type(str) == "string" and not utf8.len(str) then str = (str:gsub("[\128-\255]", "?")) end
    if typeof(style) == "Color3" or style == nil then style = { color = style or C.subtle } end
    -- the same line again (spam-clicking one skin) stays put rather than
    -- fading out and back in on every click
    local sig = table.concat({ str, tostring(style.color), tostring(style.icon), tostring(style.iconColor),
        style.gradient and (tostring(style.gradient[1]) .. tostring(style.gradient[2])) or "" }, "|")
    if sig == UI.shownCaption then return end
    UI.shownCaption = sig
    UI.captionInstant = style.instant == true
    UI.captionAnim += 1
    local mine = UI.captionAnim
    local chars, adv = {}, {}
    for _, code in utf8.codes(str) do chars[#chars + 1] = utf8.char(code) end
    for i, c in ipairs(chars) do adv[i] = advance(c) end    -- may wait on a letter never seen before
    if mine ~= UI.captionAnim then return end
    local old = {}
    for _, ch in ipairs(UI.captionText:GetChildren()) do
        if ch:IsA("GuiObject") then old[#old + 1] = ch end
    end
    if style.instant or #old == 0 then
        for _, ch in ipairs(old) do ch:Destroy() end
        -- and any line still fading out from an earlier change, or it sat
        -- under the new one (drawn at once, full strength) as a double image
        if UI.captionGhost and UI.captionGhost.Parent then UI.captionGhost:Destroy() end
        UI.captionGhost = nil
    else
        local ghost = make("Frame", {
            BackgroundTransparency = 1, Position = UI.captionText.Position, Size = UI.captionText.Size, Parent = UI.captionRow,
        })
        -- only one line fades out at a time: rapid changes (flicking through
        -- tabs) drop the previous leftover instead of stacking them up
        if UI.captionGhost and UI.captionGhost.Parent then UI.captionGhost:Destroy() end
        UI.captionGhost = ghost
        for _, ch in ipairs(old) do
            ch.Parent = ghost
            if ch:IsA("TextLabel") then TweenService:Create(ch, UI.CAPTION_OUT, { TextTransparency = 1 }):Play()
            elseif ch:IsA("ImageLabel") then TweenService:Create(ch, UI.CAPTION_OUT, { ImageTransparency = 1 }):Play() end
        end
        task.delay(UI.CAPTION_OUT.Time + 0.05, function()
            ghost:Destroy()
            if UI.captionGhost == ghost then UI.captionGhost = nil end
            UI.layoutHairlines()
        end)
    end
    tween(UI.lineL, 0.3, { BackgroundColor3 = style.hairline or C.border })
    tween(UI.lineR, 0.3, { BackgroundColor3 = style.hairline or C.border })

    local function appear(inst, prop)
        if style.instant then return end
        inst[prop] = 1
        TweenService:Create(inst, UI.CAPTION_IN, { [prop] = 0 }):Play()
    end
    -- lay the line out: icon, 6px, then each letter at its true position
    -- with 2px of tracking between letters
    local TRACK = 2
    local x = 0
    if style.icon then
        local ic = image({ Image = style.icon, ImageColor3 = style.iconColor or style.color or C.subtle,
                           AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
                           Size = UDim2.fromOffset(11, 11), Parent = UI.captionText })
        appear(ic, "ImageTransparency")
        x = 17
    end
    local n = #chars
    for i, c in ipairs(chars) do
        if c ~= " " then
            local l = text({ Text = c, FontFace = geist(FW.Medium), TextSize = 11, TextColor3 = style.color or WHITE,
                             Position = UDim2.fromOffset(math.floor(x + 0.5), 0),
                             Size = UDim2.fromOffset(math.ceil(adv[i]) + 2, 16), Parent = UI.captionText })
            if style.gradient then
                -- each letter carries its slice of the ramp, so the whole
                -- line reads as one continuous gradient
                local a, b = style.gradient[1], style.gradient[2]
                l.TextColor3 = WHITE
                make("UIGradient", { Color = ColorSequence.new(a:Lerp(b, (i - 1) / n), a:Lerp(b, i / n)), Parent = l })
            end
            appear(l, "TextTransparency")
        end
        x += adv[i] + (i < n and TRACK or 0)
    end
    local w = math.ceil(x)
    UI.captionText.Size = UDim2.fromOffset(w, 16)
    UI.captionText.Position = UDim2.fromOffset(math.floor((UI.captionRow.AbsoluteSize.X / unscale() - w) / 2), 0)
end

-- Status messages go back to the resting caption after 2.5 seconds (or `hold`);
-- a newer message restarts the timer instead of being cut short. While a
-- search is active the resting caption is the result count, not the default
-- hint.
UI.DEFAULT_CAPTION = "CLICK A SKIN TO ADD IT TO YOUR INVENTORY"
UI.searchCaption = nil
UI.tabCaption = nil        -- set while a tab other than the Skin Changer is open
UI.captionToken = 0
-- What the caption rests on when nothing else is going on: "loading" until the
-- skins are in, the failure if they don't load, the usual hint after that.
-- (Resting straight on the hint wiped "loading" and the error after any flash.)
UI.baseCaption = { text = "LOADING SKINS...", color = C.subtle }
local function rest(instant)
    if UI.tabCaption then
        UI.setTracked(UI.tabCaption, { color = C.subtle, instant = instant })
    elseif UI.searchCaption then
        UI.setTracked(UI.searchCaption.text, { color = UI.searchCaption.color, instant = instant })
    else
        local base = UI.baseCaption
        UI.setTracked(base and base.text or UI.DEFAULT_CAPTION, { color = base and base.color or C.subtle, instant = instant })
    end
end
local function flash(str, style, sticky, hold)
    UI.captionToken += 1
    local mine = UI.captionToken
    UI.setTracked(str:upper(), style or C.muted)
    if sticky then return end
    task.delay(hold or 2.5, function()
        if UI.captionToken == mine and UI.captionRow.Parent then rest() end
    end)
end
-- Switching tabs: the caption says which tab just opened (text only), then
-- after 1 second settles on that tab's own resting caption.
function openTab(name)
    flash("Opened " .. name, { color = C.text }, false, 1)
end
UI.setTracked("LOADING SKINS...", C.subtle)

-- search row: the site's code box, then the two buttons
UI.BAR_W = 240     -- the Spawn all / Despawn all bar, built below (room for Gotham's wider words)
local row = make("Frame", {
    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, Parent = content,
})
local field = make("Frame", {
    BackgroundColor3 = C.field, BorderSizePixel = 0, Position = UDim2.fromOffset(1, 1),
    Size = UDim2.new(1, -(UI.BAR_W + 10), 1, -2), Parent = row,
})
corner(field, 11)
UI.fieldStroke = stroke(field, C.border)
UI.searchIcon = image({ Image = ICON.search, ImageColor3 = C.subtle, AnchorPoint = Vector2.new(0, 0.5),
                           Position = UDim2.new(0, 13, 0.5, 0), Size = UDim2.fromOffset(15, 15), Parent = field })
local searchBox = make("TextBox", {
    BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(37, 0), Size = UDim2.new(1, -69, 1, 0),
    FontFace = geist(FW.Medium), TextSize = 13, TextColor3 = C.text, PlaceholderText = "", Text = "",
    ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2, Parent = field,
})

-- The placeholder: a rotating set of hints instead of one fixed line. Every
-- few seconds the current hint dissolves into the next, in place: a soft
-- crossfade, the new one starting just as the old one is half gone. Geist Medium in the lighter grey, so it reads clearly. It
-- hides the moment there's text in the box, and picks up again when it's
-- cleared; while the window is hidden it simply waits.
UI.setHints = nil
do
    local clip = make("Frame", {
        BackgroundTransparency = 1, ClipsDescendants = true, Position = searchBox.Position, Size = searchBox.Size,
        Parent = field,
    })
    local function hintLabel()
        return text({ Text = "", FontFace = geist(FW.Medium), TextSize = 13, TextColor3 = C.muted,
                      TextTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.fromScale(1, 1),
                      Parent = clip })
    end
    local cur, nxt = hintLabel(), hintLabel()
    local hints, index, token = { "Loading skins…" }, 0, 0
    local FADE_OUT = TweenInfo.new(0.35, EASE.Sine, DIR.InOut)
    local FADE_IN = TweenInfo.new(0.4, EASE.Sine, DIR.InOut, 0, false, 0.15)

    local function show(str, instant)
        if instant then
            cur.Text, cur.TextTransparency = str, 0
            return
        end
        TweenService:Create(cur, FADE_OUT, { TextTransparency = 1 }):Play()
        nxt.Text, nxt.TextTransparency = str, 1
        TweenService:Create(nxt, FADE_IN, { TextTransparency = 0 }):Play()
        cur, nxt = nxt, cur
    end
    local function step(instant)
        index = index % #hints + 1
        show(hints[index], instant)
    end

    function UI.setHints(list)
        hints, index = list, 0
        step(false)
    end
    step(true)

    -- rotate every 2.6s while the box is empty and the window is up
    task.spawn(function()
        while gui.Parent do
            task.wait(2.6)
            if holder.Visible and searchBox.Text == "" and #hints > 1 then step(false) end
        end
    end)
    -- typed text replaces the hint at once; clearing brings it back softly
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local empty = searchBox.Text == ""
        clip.Visible = empty
        if empty then
            cur.TextTransparency = 1
            TweenService:Create(cur, FADE_OUT, { TextTransparency = 0 }):Play()
        end
    end)
end
UI.clearBtn = make("ImageButton", {
    Image = ICON.x, ImageColor3 = C.subtle, ImageTransparency = 1, BackgroundTransparency = 1, BorderSizePixel = 0,
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(14, 14),
    AutoButtonColor = false, Parent = field,
})
do
    -- the turning outline shows while you're typing in the box, not on hover
    local ring = UI.hoverRing(field, 11, 0)
    searchBox.Focused:Connect(function() ring(true) end)
    searchBox.FocusLost:Connect(function() ring(false) end)
end
searchBox.Focused:Connect(function()
    tween(UI.fieldStroke, 0.15, { Color = C.borderHi })
    tween(UI.searchIcon, 0.15, { ImageColor3 = C.muted })
end)
searchBox.FocusLost:Connect(function()
    tween(UI.fieldStroke, 0.2, { Color = C.border })
    tween(UI.searchIcon, 0.2, { ImageColor3 = C.subtle })
end)
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    tween(UI.clearBtn, 0.15, { ImageTransparency = searchBox.Text == "" and 1 or 0 })
end)
UI.clearBtn.MouseEnter:Connect(function() tween(UI.clearBtn, 0.12, { ImageColor3 = C.text }) end)
UI.clearBtn.MouseLeave:Connect(function() tween(UI.clearBtn, 0.15, { ImageColor3 = C.subtle }) end)
UI.clearBtn.MouseButton1Click:Connect(function()
    if searchBox.Text ~= "" then searchBox.Text = "" end
end)

-- Spawn all / Despawn all: one bar made of the search field's own surface
-- (same fill, outline, radius and height), split down the middle by a short
-- divider. Each half is an action with a colour of its own -- green for
-- spawning, red for clearing -- carried by its icon and its progress fill.
-- Hover: a soft grey pill fades in inside the half, the icon lights up and moves
-- (the plus turns, the bin tips its lid) and the bar's outline brightens like
-- the search field's does on focus. Press: the pill deepens and the content
-- sinks a pixel, springing back on release. While a job runs, its half fills
-- left to right in its colour.
UI.actionBar = make("Frame", {
    BackgroundColor3 = C.field, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -1, 0, 1), Size = UDim2.fromOffset(UI.BAR_W - 2, 38), Parent = row,
})
corner(UI.actionBar, 11)
UI.barStroke = stroke(UI.actionBar, C.border)
make("Frame", {     -- the divider
    BackgroundColor3 = C.border, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1, 18), Parent = UI.actionBar,
})
-- lit while either half is hovered -- worked out from the halves, not counted:
-- a count went off by one for good the first time Roblox dropped a MouseLeave
function UI.paintBar()
    local hot = (UI.spawnAllBtn and UI.spawnAllBtn.hovered) or (UI.despawnAllBtn and UI.despawnAllBtn.hovered)
    TweenService:Create(UI.barStroke, TweenInfo.new(0.25, EASE.Quint, DIR.Out),
        { Color = hot and C.borderHi or C.border }):Play()
end

-- the hover pill is the same quiet grey on both halves; only the icons and
-- the progress fill carry colour
UI.PILL_HOVER, UI.PILL_PRESS = hex("#18181b"), hex("#222226")
UI.ACTION_STYLE = {
    spawn   = { icon = C.green, tint = UI.PILL_HOVER, press = UI.PILL_PRESS, fill = C.green },
    despawn = { icon = C.red,   tint = UI.PILL_HOVER, press = UI.PILL_PRESS, fill = C.red },
}
function UI.actionButton(kind, label, iconId, side)
    local style = UI.ACTION_STYLE[kind]
    local half = (UI.BAR_W - 2) / 2
    local b = make("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(side == 0 and 0 or half, 0), Size = UDim2.new(0, half, 1, 0), Parent = UI.actionBar,
    })
    -- the hover pill, inset 4px so it sits inside the bar's rounded edge
    local pill = make("Frame", {
        BackgroundColor3 = style.tint, BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), ClipsDescendants = true, Parent = b,
    })
    corner(pill, 8)
    -- progress fill, grows left to right inside the pill while a job runs
    local progress = make("Frame", {
        Name = "Progress", BackgroundColor3 = style.fill, BackgroundTransparency = 1,
        BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = pill,
    })
    corner(progress, 8)
    -- hovered, a ring the full height of the bar round this half: its
    -- outer edge on the bar's own outline, its inner edge at the divider
    local ring = UI.hoverRing(b, 11, 0)
    local inner = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = b })
    hlist(inner, 7, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
    local ic = image({ Image = iconId, ImageColor3 = style.icon, Size = UDim2.fromOffset(14, 14), LayoutOrder = 1, Parent = inner })
    local lbl = text({ Text = label, FontFace = geist(FW.SemiBold), TextSize = 13, TextColor3 = C.muted,
                       Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = inner })
    local a = {
        button = b, label = lbl, icon = ic, pill = pill, progress = progress, primary = kind == "spawn",
        text = label, iconId = iconId, ink = C.muted, iconInk = style.icon, style = style, hovered = false,
    }
    local TURN = kind == "spawn" and 90 or -14
    local SPRING = TweenInfo.new(0.45, EASE.Back, DIR.Out)
    local SOFT = TweenInfo.new(0.25, EASE.Quint, DIR.Out)
    local function play(obj, info, goal) TweenService:Create(obj, info, goal):Play() end

    -- one leave, reached by MouseLeave or by the guard when Roblox drops it
    local guard
    local function leave()
        if guard then guard:Disconnect(); guard = nil end
        if not a.hovered then return end
        a.hovered = false
        UI.paintBar()
        play(ic, SPRING, { Rotation = 0 })
        play(inner, SPRING, { Position = UDim2.new() })
        ring(false)
        if b:GetAttribute("Locked") then return end
        play(lbl, SOFT, { TextColor3 = C.muted })
    end
    b.MouseEnter:Connect(function()
        a.hovered = true
        UI.paintBar()
        if guard then guard:Disconnect() end
        guard = C.hoverGuard(b, function() guard = nil; leave() end)
        if b:GetAttribute("Locked") then return end
        sfx("hover")
        ring(true)
        play(lbl, SOFT, { TextColor3 = C.text })
        play(ic, SPRING, { Rotation = TURN })
    end)
    b.MouseLeave:Connect(leave)
    b.MouseButton1Down:Connect(function()
        if b:GetAttribute("Locked") then return end
        C.ripple(b, 8)
        tween(inner, 0.08, { Position = UDim2.fromOffset(0, 1) }, EASE.Quad)
    end)
    b.MouseButton1Up:Connect(function()
        play(inner, SPRING, { Position = UDim2.new() })
        if b:GetAttribute("Locked") then return end
        play(pill, SOFT, { BackgroundColor3 = style.tint })
    end)
    return a
end
UI.spawnAllBtn   = UI.actionButton("spawn", "Spawn all", ICON.plus, 0)
UI.despawnAllBtn = UI.actionButton("despawn", "Despawn all", ICON.trash, 1)
UI.snapSkin()
task.defer(UI.snapSkin)

-- Wear: a button between the search and Spawn all / Despawn all -- the
-- sparkles and the word, on the same surface -- that opens a small card with the Visuals tab's weapon
-- switches -- knife on belt, two guns, two knives. The sparkles turn green
-- while any of them is on. The switches ARE the Visuals tab's (UI.wearEl):
-- flipping one here flips it there, and the other way round.
UI.WEAR_W = 88
UI.WEAR_CX = -(UI.BAR_W + 8 + UI.WEAR_W / 2)     -- the button's middle, from the row's right edge: the card centres on it
field.Size = UDim2.new(1, -(UI.BAR_W + 10 + UI.WEAR_W + 8), 1, -2)
row.ZIndex = 3                  -- the card opens over the grid below
do
    local btn = make("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = C.field, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -(UI.BAR_W + 8), 0, 1), Size = UDim2.fromOffset(UI.WEAR_W, 38), Parent = row,
    })
    corner(btn, 11)
    stroke(btn, C.border)
    local ring = UI.hoverRing(btn, 11, 0)
    -- icon and word centred together, like Spawn all's
    local inner = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = btn })
    hlist(inner, 7, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
    local ic = image({ Image = ICON.tabVisuals, ImageColor3 = C.subtle, Size = UDim2.fromOffset(15, 15),
        LayoutOrder = 1, ZIndex = 2, Parent = inner })
    local icScale = make("UIScale", { Parent = ic })
    local lbl = text({ Text = "Wear", FontFace = geist(FW.SemiBold), TextSize = 13, TextColor3 = C.muted,
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 2, Parent = inner })

    -- the card: the tooltip's look (its dark fill and slowly turning white
    -- edge), centred under the button
    local ROWS = {
        { key = "belt", title = "Knife on belt", sub = "Wear it at your side" },
        { key = "guns", title = "Two guns", sub = "A gun in each hand" },
        { key = "knives", title = "Two knives", sub = "A knife in each hand" },
    }
    local ROW_H, CARD_W = 46, 272
    local CARD_H = 8 + #ROWS * ROW_H + 8
    -- (a plain frame, faded piece by piece -- see fade() below: in a
    -- CanvasGroup the card is drawn as a picture, and its words came in
    -- thin and soft and only turned bold once it settled)
    local holder = make("Frame", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Visible = false,
        Position = UDim2.new(1, UI.WEAR_CX, 0, 40), Size = UDim2.fromOffset(CARD_W + 2, CARD_H + 2), ZIndex = 10, Parent = row,
    })
    -- (a button, so a press on its padding counts as inside too)
    local card = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.pill, BorderSizePixel = 0,
        Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), Parent = holder })
    corner(card, 12)
    do
        local st = stroke(card, WHITE, 1, 0.2)
        local g = make("UIGradient", { Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, C.borderHi:Lerp(WHITE, 0.1)), ColorSequenceKeypoint.new(0.45, C.borderHi:Lerp(WHITE, 0.1)),
            ColorSequenceKeypoint.new(1, WHITE) }), Parent = st })
        UI.loop(TweenService:Create(g, TweenInfo.new(7, EASE.Linear, DIR.In, -1), { Rotation = 360 }), card)
    end
    local state, painters = {}, {}
    -- set by any press on the card or the button; a click that didn't set it
    -- landed somewhere else and closes the card. (Comparing the mouse with
    -- the card's box was off by the top bar's height on some screens, so a
    -- click on the last row counted as outside.)
    local pressedInside = false
    local function markInside() pressedInside = true end
    card.MouseButton1Down:Connect(markInside)
    for i, r in ipairs(ROWS) do
        local b = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(6, 8 + (i - 1) * ROW_H), Size = UDim2.new(1, -12, 0, ROW_H), Parent = card })
        local hover = make("Frame", { BackgroundColor3 = UI.PILL_HOVER, BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 1, -4), Parent = b })
        corner(hover, 8)
        if i > 1 then
            make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -20, 0, 1), Parent = b })
        end
        local title = text({ Text = r.title, FontFace = geist(FW.SemiBold), TextSize = 13, TextColor3 = C.muted,
            Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -70, 0, 16), ZIndex = 2, Parent = b })
        text({ Text = r.sub, TextSize = 11, TextColor3 = C.subtle, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -70, 0, 14), ZIndex = 2, Parent = b })
        -- the tiles' switch: white track and a dark knob that springs across when on
        local track = make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(36, 20), ZIndex = 2, Parent = b })
        corner(track, FULL)
        local knob = make("Frame", { BackgroundColor3 = C.muted, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(14, 14), ZIndex = 3, Parent = track })
        corner(knob, FULL)
        painters[r.key] = function(on, instant)
            if instant then
                track.BackgroundColor3 = on and WHITE or C.border
                knob.BackgroundColor3 = on and C.bg or C.muted
                knob.Position = UDim2.new(0, on and 19 or 3, 0.5, 0)
                title.TextColor3 = on and C.text or C.muted
                return
            end
            tween(track, 0.2, { BackgroundColor3 = on and WHITE or C.border })
            tween(knob, 0.2, { BackgroundColor3 = on and C.bg or C.muted })
            knob.Size = UDim2.fromOffset(18, 14)
            tween(knob, 0.36, { Position = UDim2.new(0, on and 19 or 3, 0.5, 0) }, EASE.Back, DIR.Out)
            tween(knob, 0.3, { Size = UDim2.fromOffset(14, 14) }, EASE.Quint, DIR.Out)
            tween(title, 0.2, { TextColor3 = on and C.text or C.muted })
        end
        b.MouseEnter:Connect(function() tween(hover, 0.15, { BackgroundTransparency = 0 }) end)
        b.MouseLeave:Connect(function() tween(hover, 0.2, { BackgroundTransparency = 1 }) end)
        b.MouseButton1Down:Connect(function() markInside(); C.ripple(b, 8) end)
        b.MouseButton1Click:Connect(function()
            local el = UI.wearEl and UI.wearEl[r.key]
            if not el then return end           -- the Visuals tab is still being built
            sfx("click")
            el:Set(not el.Value)                -- saves it, runs it, repaints both
        end)
    end

    -- the icon itself turns green while anything is on (no separate dot).
    -- Hover/open brightens a grey icon to white; a green one stays green --
    -- a touch lighter, a small pop, and a pale glint sweeping across the
    -- sparkles over and over until the pointer leaves (or the card closes)
    local open, gen, overBtn = false, 0, false
    local iconRest = C.subtle
    local sheen = { lit = C.green:Lerp(WHITE, 0.22), on = false }
    sheen.img = image({ Image = ic.Image, ImageRectOffset = ic.ImageRectOffset, ImageRectSize = ic.ImageRectSize,
        ImageColor3 = C.green:Lerp(WHITE, 0.8), ImageTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = ic })
    -- (it runs on past the icon's far side, so the out-of-sight stretch is
    -- the pause between sweeps -- a tween's own delay would hold back the
    -- first one too)
    sheen.grad = make("UIGradient", { Rotation = 35, Offset = Vector2.new(-0.8, 0), Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.38, 1), NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(0.62, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = sheen.img })
    sheen.run = TweenService:Create(sheen.grad, TweenInfo.new(1.5, EASE.Linear, DIR.In, -1), { Offset = Vector2.new(1.8, 0) })
    function sheen.paint(hot, t)
        local green = hot and (state.belt or state.guns or state.knives) and true or false
        tween(ic, t, { ImageColor3 = not hot and iconRest or green and sheen.lit or WHITE })
        tween(sheen.img, t, { ImageTransparency = green and 0 or 1 })
        if green == sheen.on then return end
        sheen.on = green
        if green then
            sheen.grad.Offset = Vector2.new(-0.8, 0)
            sheen.run:Play()
            TweenService:Create(icScale, TweenInfo.new(0.16, EASE.Quad, DIR.Out, 0, true), { Scale = 1.18 }):Play()
        else
            task.delay(t, function() if not sheen.on then sheen.run:Cancel() end end)
        end
    end
    local function paintIcon(instant)
        local any = state.belt or state.guns or state.knives
        iconRest = any and C.green or C.subtle
        if not (open or overBtn) then
            if instant then ic.ImageColor3 = iconRest
            else tween(ic, 0.25, { ImageColor3 = iconRest }) end
        else
            sheen.paint(true, 0.25)            -- flipped from the open card
        end
    end
    -- called by the Visuals tab's switches (the first call for each paints
    -- straight in, with no animation)
    function UI.wearPaint(key, on)
        local first = state[key] == nil
        state[key] = on and true or false
        if painters[key] then painters[key](state[key], first) end
        paintIcon(first)
    end

    -- every piece of the card and the transparency it rests at; opening
    -- fades them all up from clear, closing fades them back out
    local fades = {}
    local function keep(o, prop) fades[#fades + 1] = { o, prop, o[prop] } end
    keep(card, "BackgroundTransparency")
    for _, d in ipairs(card:GetDescendants()) do
        if d:IsA("TextLabel") then keep(d, "TextTransparency")
        elseif d:IsA("UIStroke") then keep(d, "Transparency")
        elseif d:IsA("GuiObject") and d.BackgroundTransparency < 1 then keep(d, "BackgroundTransparency") end
    end
    local function fade(shown, t, style, dir)
        for _, f in ipairs(fades) do
            local goal = shown and f[3] or 1
            if t == 0 then f[1][f[2]] = goal else tween(f[1], t, { [f[2]] = goal }, style, dir) end
        end
    end
    fade(false, 0)

    local function setOpen(v)
        if open == v then return end
        open = v
        gen += 1
        local mine = gen
        ring(v or overBtn)
        sheen.paint(v or overBtn, 0.2)
        tween(lbl, 0.2, { TextColor3 = (v or overBtn) and C.text or C.muted })
        if v then
            -- rises into place while it fades up
            fade(false, 0)
            holder.Visible = true
            holder.Position = UDim2.new(1, UI.WEAR_CX, 0, 34)
            tween(holder, 0.32, { Position = UDim2.new(1, UI.WEAR_CX, 0, 44) }, EASE.Quint, DIR.Out)
            fade(true, 0.24, EASE.Quad, DIR.Out)
        else
            fade(false, 0.16, EASE.Quad, DIR.In)
            tween(holder, 0.18, { Position = UDim2.new(1, UI.WEAR_CX, 0, 38) }, EASE.Quad, DIR.In)
                .Completed:Connect(function() if gen == mine and not open then holder.Visible = false end end)
        end
    end
    btn.MouseEnter:Connect(function()
        overBtn = true
        sfx("hover")
        ring(true)
        sheen.paint(true, 0.15)
        tween(lbl, 0.15, { TextColor3 = C.text })
        TweenService:Create(ic, TweenInfo.new(0.45, EASE.Back, DIR.Out), { Rotation = 15 }):Play()
    end)
    btn.MouseLeave:Connect(function()
        overBtn = false
        if not open then
            ring(false)
            sheen.paint(false, 0.2)
            tween(lbl, 0.2, { TextColor3 = C.muted })
        end
        TweenService:Create(ic, TweenInfo.new(0.45, EASE.Back, DIR.Out), { Rotation = 0 }):Play()
    end)
    btn.MouseButton1Down:Connect(function() markInside(); C.ripple(btn, 11) end)
    btn.MouseButton1Click:Connect(function()
        sfx("click")
        icScale.Scale = 0.8
        TweenService:Create(icScale, TweenInfo.new(0.45, EASE.Back, DIR.Out), { Scale = 1 }):Play()
        setOpen(not open)
    end)
    tooltip.attach(btn, { title = "Wear", detail = "Knife on belt, two guns, two knives. Only on your screen." })
    -- a click anywhere else closes it (checked a beat later, once the
    -- card's own buttons have had the press)
    -- (every click resets the mark, open or not: the press that opens the
    -- card must not count for the next one)
    conns[#conns + 1] = UIS.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        task.delay(0.05, function()
            local inside = pressedInside
            pressedInside = false
            if not inside and open then setOpen(false) end
        end)
    end)
    UI.closeWear = function() setOpen(false) end
end

-- the skin grid
UI.GRID_GAP = 8
local grid = make("Frame", {
    Name = "Grid", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 3, Parent = content,
})
UI.gridLayout = make("UIGridLayout", {
    CellSize = UDim2.fromOffset(92, 92), CellPadding = UDim2.fromOffset(UI.GRID_GAP, UI.GRID_GAP),
    SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left, Parent = grid,
})
pad(grid, 1, 0, 1, 0)   -- room for the tile strokes
function UI.syncGridHeight()
    grid.Size = UDim2.new(1, 0, 0, UI.gridLayout.AbsoluteContentSize.Y / unscale() + 4)
end
UI.gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UI.syncGridHeight)
UI.syncGridHeight()

-- Stretch the cells so the grid's right edge lines up with the Despawn all
-- button at any window width, instead of leaving dead space after the last
-- column. 124px is the narrowest a card may get (4 per row at the default
-- size). Cards are portrait, store style: the art square-ish on top, then an
-- info strip (type, name, add button) CARD_INFO_H tall.
UI.CARD_INFO_H = 48
function UI.fitCells()
    local w = math.floor(grid.AbsoluteSize.X / unscale() + 0.5) - 2
    if w <= 0 then return end
    local cols = math.max(1, math.floor((w + UI.GRID_GAP) / (124 + UI.GRID_GAP)))
    -- the gap nearest 8 that splits the row evenly, so the last card ends
    -- exactly on the row's edge -- the grid line the search row ends on --
    -- instead of a few pixels short of it
    local gap = UI.GRID_GAP
    if cols > 1 then
        for _, g in ipairs({ 8, 9, 7, 10, 6, 11 }) do
            if (w - g * (cols - 1)) % cols == 0 then gap = g; break end
        end
    end
    local cell = math.floor((w - gap * (cols - 1)) / cols)
    UI.gridLayout.CellPadding = UDim2.fromOffset(gap, UI.GRID_GAP)
    UI.gridLayout.CellSize = UDim2.fromOffset(cell, math.floor(cell * 0.8) + UI.CARD_INFO_H)
end
grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(UI.fitCells)
UI.fitCells()

-- Empty search: a sad face, "No results found" and a suggestion you can click.
UI.SUGGESTION = "Gingerscope"
UI.emptyState = {}
do
    local holderE = make("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 200), Visible = false, LayoutOrder = 4, Parent = content,
    })
    local group = make("CanvasGroup", {
        BackgroundTransparency = 1, GroupTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = holderE,
    })
    local col = make("Frame", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34),
        Size = UDim2.fromOffset(320, 150), Parent = group,
    })
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center,
                           Padding = UDim.new(0, 12), Parent = col })
    local ring = make("Frame", {
        BackgroundColor3 = C.pill, BorderSizePixel = 0, Size = UDim2.fromOffset(62, 62), LayoutOrder = 1, Parent = col,
    })
    corner(ring, FULL)
    stroke(ring, C.border)
    image({ Image = ICON.frown, ImageColor3 = C.muted, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(28, 28), Parent = ring })
    local words = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(320, 44), LayoutOrder = 2, Parent = col })
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center,
                           Padding = UDim.new(0, 6), Parent = words })
    text({ Text = "No results found", FontFace = geist(FW.SemiBold), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center,
           Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = words })
    local tryRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 22),
                                   AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = words })
    hlist(tryRow, 7)
    text({ Text = "Try with", TextSize = 13, TextColor3 = C.subtle, Size = UDim2.new(0, 0, 1, 0),
           AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = tryRow })
    local chipBtn = make("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = C.pill, BorderSizePixel = 0,
        Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = tryRow,
    })
    corner(chipBtn, 6)
    local chipStroke = stroke(chipBtn, C.border)
    pad(chipBtn, 8, 8)
    local chipText = text({ Text = UI.SUGGESTION, FontFace = mono(), TextSize = 12, TextColor3 = C.muted,
                            Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = chipBtn })
    chipBtn.MouseEnter:Connect(function()
        sfx("hover")
        tween(chipStroke, 0.15, { Color = C.borderHi })
        tween(chipText, 0.15, { TextColor3 = C.text })
    end)
    chipBtn.MouseLeave:Connect(function()
        tween(chipStroke, 0.2, { Color = C.border })
        tween(chipText, 0.2, { TextColor3 = C.muted })
    end)
    chipBtn.MouseButton1Click:Connect(function()
        sfx("click")
        searchBox.Text = UI.SUGGESTION
    end)

    local shown = false
    function UI.emptyState.set(show)
        if show == shown then return end
        shown = show
        if show then
            holderE.Visible = true
            group.GroupTransparency = 1
            col.Position = UDim2.new(0.5, 0, 0, 42)
            tween(group, 0.3, { GroupTransparency = 0 })
            tween(col, 0.4, { Position = UDim2.new(0.5, 0, 0, 34) })
        else
            -- fades out the way it came in (it used to vanish at once),
            -- unless it's asked back before the fade ends
            tween(group, 0.2, { GroupTransparency = 1 }).Completed:Connect(function()
                if not shown then holderE.Visible = false end
            end)
        end
    end
end

-- Skeleton tiles with a shimmer while the skins load, so the grid never sits
-- empty. They make way for the real tiles in buildGrid().
UI.skeletons = {}
do
    local SHINE = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1),
        NumberSequenceKeypoint.new(0.5, 0.94), NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1),
    })
    for i = 1, 24 do
        local s = make("Frame", { BackgroundColor3 = C.tile, BorderSizePixel = 0, LayoutOrder = i, Parent = grid })
        corner(s, 12)
        stroke(s, C.skeletonEdge, 1.5)
        corner(make("Frame", { BackgroundColor3 = C.skeleton, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromScale(0.55, 0.48), Parent = s }), 8)
        corner(make("Frame", { BackgroundColor3 = C.skeleton, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -9), Size = UDim2.new(0.6, 0, 0, 6), Parent = s }), FULL)
        local shine = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
            ZIndex = 3, Parent = s })
        corner(shine, 12)
        local g = make("UIGradient", { Rotation = 20, Transparency = SHINE, Offset = Vector2.new(-1, 0), Parent = shine })
        -- a diagonal wave across the grid, by its real column count (the
        -- cells' 108px minimum makes it 5 at the default size, not 6)
        local cols = UI.gridLayout.AbsoluteCellCount.X
        if cols < 1 then cols = 5 end
        local wave = ((i - 1) % cols + math.floor((i - 1) / cols)) * 0.07
        TweenService:Create(g, TweenInfo.new(1.1, EASE.Linear, DIR.In, -1, false, 0.5 + wave), { Offset = Vector2.new(1, 0) }):Play()
        UI.skeletons[#UI.skeletons + 1] = s
    end
end

-- the back-to-top button's colours, shared with the other tabs' copies
C.toTopEdge, C.toTopEdgeHot = hex("#b4b4b8"), WHITE      -- the ring's tint at rest / on hover
C.toTopInk, C.toTopInkHot = C.muted:Lerp(WHITE, 0.25), C.muted:Lerp(WHITE, 0.5)

-- the spinning ring round a back-to-top button: a gradient on its stroke, lit
-- whitish at one end, one turn every 5 seconds
function C.toTopRing(st)
    st.Color = C.toTopEdge
    local g = make("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, C.borderHi), ColorSequenceKeypoint.new(0.45, C.borderHi),
            ColorSequenceKeypoint.new(1, hex("#e4e4e7")),
        }),
        Parent = st,
    })
    UI.loop(TweenService:Create(g, TweenInfo.new(5, EASE.Linear, DIR.In, -1), { Rotation = 360 }), st.Parent)
end

-- How a back-to-top button comes and goes. In: it rises a little while it
-- fades in and grows smoothly to size, then the arrow glides up into place
-- from below. Out: it shrinks a touch, sinks and fades. Returns the out tween.
-- (Each button rests where it was placed; that spot is remembered.)
function C.toTopPop(wrap, arrow, show)
    local pop = wrap:FindFirstChild("Pop") or make("UIScale", { Name = "Pop", Parent = wrap })
    local home = wrap:GetAttribute("HomeY")
    if not home then
        home = wrap.Position.Y.Offset
        wrap:SetAttribute("HomeY", home)
    end
    local function at(dy) return UDim2.new(1, wrap.Position.X.Offset, 1, home + dy) end
    local ARROW = UDim2.fromScale(0.5, 0.5)
    if show then
        wrap.Visible = true
        wrap.GroupTransparency = 1
        wrap.Position = at(12)
        pop.Scale = 0.6
        tween(wrap, 0.25, { GroupTransparency = 0 }, EASE.Quad, DIR.Out)
        tween(wrap, 0.6, { Position = at(0) }, EASE.Quint, DIR.Out)
        tween(pop, 0.6, { Scale = 1 }, EASE.Quint, DIR.Out)
        arrow.Position = ARROW + UDim2.fromOffset(0, 14)
        arrow.ImageTransparency = 1
        task.delay(0.12, function()
            tween(arrow, 0.5, { Position = ARROW, ImageTransparency = 0 }, EASE.Quint, DIR.Out)
        end)
        return nil
    end
    tween(pop, 0.22, { Scale = 0.8 }, EASE.Quad, DIR.In)
    return tween(wrap, 0.22, { GroupTransparency = 1, Position = at(8) }, EASE.Quad, DIR.In)
end

-- The arrow's feel, shared by every back-to-top button. Hovered, it keeps
-- nudging upward -- "this way" -- in a slow ease up and back. Pressed, the
-- button dips and springs back. Clicked, the arrow launches up out of the
-- button and drops back in from below while the page glides to the top.
function C.toTopFeel(btn, arrow)
    local HOME = UDim2.fromScale(0.5, 0.5)
    local press = make("UIScale", { Parent = btn })
    local tok = 0
    btn.MouseEnter:Connect(function()
        tok += 1
        local mine = tok
        task.spawn(function()
            while tok == mine and btn.Parent do
                local up = TweenService:Create(arrow, TweenInfo.new(0.42, EASE.Sine, DIR.Out), { Position = HOME + UDim2.fromOffset(0, -3) })
                up:Play()
                up.Completed:Wait()
                if tok ~= mine then return end
                local down = TweenService:Create(arrow, TweenInfo.new(0.42, EASE.Sine, DIR.In), { Position = HOME })
                down:Play()
                down.Completed:Wait()
            end
        end)
    end)
    btn.MouseLeave:Connect(function()
        tok += 1
        tween(arrow, 0.25, { Position = HOME, ImageTransparency = 0 }, EASE.Quint, DIR.Out)
        tween(press, 0.25, { Scale = 1 }, EASE.Quint, DIR.Out)
    end)
    btn.MouseButton1Down:Connect(function() tween(press, 0.1, { Scale = 0.9 }, EASE.Quad, DIR.Out) end)
    btn.MouseButton1Up:Connect(function()
        TweenService:Create(press, TweenInfo.new(0.45, EASE.Back, DIR.Out), { Scale = 1 }):Play()
    end)
    btn.MouseButton1Click:Connect(function()
        tok += 1
        local mine = tok
        local out = TweenService:Create(arrow, TweenInfo.new(0.18, EASE.Quad, DIR.In),
            { Position = HOME + UDim2.fromOffset(0, -26), ImageTransparency = 1 })
        out:Play()
        out.Completed:Connect(function()
            if tok ~= mine then return end
            arrow.Position = HOME + UDim2.fromOffset(0, 20)
            tween(arrow, 0.45, { Position = HOME, ImageTransparency = 0 }, EASE.Quint, DIR.Out)
        end)
    end)
end

-- Scroll to top: a round button that rises in once you have scrolled down,
-- and a scrollbar that only shows while you are scrolling.
do
    local wrap = make("CanvasGroup", {
        BackgroundTransparency = 1, GroupTransparency = 1, Visible = false, AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -22, 1, -14), Size = UDim2.fromOffset(38, 38), ZIndex = 3, Parent = UI.skinPage,
    })
    local btn = make("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = C.pill, BorderSizePixel = 0,
        Position = UDim2.fromOffset(1, 1), Size = UDim2.fromOffset(36, 36), Parent = wrap,
    })
    corner(btn, FULL)
    -- a whitish ring so it stands out against the grid; hover only lifts it a
    -- little, never to full white
    local btnStroke = stroke(btn, C.toTopEdge)
    C.toTopRing(btnStroke)
    local arrow = image({ Image = ICON.arrowUp, ImageColor3 = C.toTopInk, AnchorPoint = Vector2.new(0.5, 0.5),
                          Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), Parent = btn })
    C.toTopFeel(btn, arrow)
    btn.MouseEnter:Connect(function()
        sfx("hover")
        tween(btn, 0.15, { BackgroundColor3 = C.pillHover })
        tween(btnStroke, 0.15, { Color = C.toTopEdgeHot })
        tween(arrow, 0.15, { ImageColor3 = C.toTopInkHot })
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, 0.2, { BackgroundColor3 = C.pill })
        tween(btnStroke, 0.2, { Color = C.toTopEdge })
        tween(arrow, 0.2, { ImageColor3 = C.toTopInk })
    end)

    scrollToTop = function()
        if content.CanvasPosition.Y <= 0 then return end
        tween(content, 0.5, { CanvasPosition = Vector2.new(0, 0) }, EASE.Quint, DIR.Out)
    end
    btn.MouseButton1Click:Connect(function()
        sfx("click")
        scrollToTop()
    end)

    local up, idleToken = false, 0
    -- Tab switches: fade with the page. The button sits on skinPage, whose
    -- Visible flips at once, so without this it blinked while the grid faded.
    C.skinToTopFade = function(show, t)
        if not up then return end
        tween(wrap, t or 0.2, { GroupTransparency = show and 0 or 1 })
    end
    content:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        tooltip.hide()                  -- the hovered tile just moved away
        local want = content.CanvasPosition.Y > 160
        if want ~= up then
            up = want
            if want then
                C.toTopPop(wrap, arrow, true)
            else
                C.toTopPop(wrap, arrow, false).Completed:Connect(function()
                    if not up then wrap.Visible = false end
                end)
            end
        end
        -- scrollbar: fade in while moving, out once it settles
        idleToken += 1
        local mine = idleToken
        tween(UI.scrollBar, 0.15, { BackgroundTransparency = 0.2 })
        task.delay(0.9, function()
            if mine == idleToken and content.Parent then tween(UI.scrollBar, 0.4, { BackgroundTransparency = 1 }) end
        end)
    end)
end

--// Tab pages ------------------------------------------------------
-- The other tabs share one page: the tab's icon on a raised tile, its name,
-- and a note that it's on its way. Switching tabs fades the open page out,
-- then the new one in, rising a few pixels -- while the sidebar pill glides
-- over and the caption announces the tab.
do
local tabPage = make("CanvasGroup", {
    Name = "TabPage", BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1, Visible = false,
    Position = UI.listClip.Position, Size = UI.listClip.Size, ZIndex = 2, Parent = win,
})
local pageIcon, pageTitle
do
    local body = make("Frame", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44),
        Size = UDim2.fromOffset(360, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = tabPage,
    })
    make("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = body,
    })
    local function gap(h, order)
        make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(1, h), LayoutOrder = order, Parent = body })
    end
    local tile = make("Frame", {
        BackgroundColor3 = C.pill, BorderSizePixel = 0, Size = UDim2.fromOffset(54, 54), LayoutOrder = 1, Parent = body,
    })
    corner(tile, 14)
    stroke(tile, C.border)
    pageIcon = image({
        ImageColor3 = C.text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(24, 24), Parent = tile,
    })
    gap(16, 2)
    pageTitle = text({
        FontFace = geist(FW.SemiBold), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 3, Parent = body,
    })
    gap(6, 4)
    text({
        Text = "This tab is on its way to Onyx.", TextSize = 13, TextColor3 = C.muted,
        TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 5, Parent = body,
    })
    gap(16, 6)
    -- a small amber "Coming soon" tag, like the ones in the title bar
    local soon = make("Frame", {
        BackgroundColor3 = C.amberBg, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 24),
        AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 7, Parent = body,
    })
    corner(soon, FULL)
    stroke(soon, C.amberEdge)
    pad(soon, 10, 10)
    text({
        Text = "Coming soon", FontFace = geist(FW.SemiBold), TextSize = 12, TextColor3 = C.amberText,
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = soon,
    })
end

do
    local current = nil
    for _, t in ipairs(TABS) do if t.id == "home" then current = t end end    -- (Home opens first)
    local switch = 0
    local PAGE_OUT = TweenInfo.new(0.15, EASE.Quad, DIR.In)
    local PAGE_IN = TweenInfo.new(0.35, EASE.Quint, DIR.Out)
    -- the Skin Changer's list, a tab's own page (Autofarm), or the shared
    -- coming-soon page
    local function pageOf(tab) return tab.id == "skins" and UI.listClip or tab.page or tabPage end

    function selectTab(tab)
        if tab == current then
            -- the open tab again: announce it, and take the grid back to the top
            if tab.id == "skins" then
                -- ...and back to normal: the search is cleared too. Cleared
                -- FIRST, announced after: clearing it resets the caption at
                -- once, which wiped an announcement made before it
                searchBox:ReleaseFocus()
                if searchBox.Text ~= "" then searchBox.Text = "" end
                if scrollToTop then scrollToTop() end
                task.defer(openTab, tab.name, tab.icon)
            else
                openTab(tab.name, tab.icon)
                if tab.toTop then tab.toTop() end
            end
            return
        end
        tooltip.hide()
        searchBox:ReleaseFocus()
        switch += 1
        local mine = switch
        local from = pageOf(current)
        local leavingSkins = current and current.id == "skins"
        if leavingSkins and UI.closeWear then UI.closeWear() end    -- the Wear card goes with its tab
        current = tab
        UI.tabCaption = tab.id ~= "skins" and tab.caption or nil
        markTab(tab.id)
        openTab(tab.name, tab.icon)
        TweenService:Create(from, PAGE_OUT, { GroupTransparency = 1 }):Play()
        if leavingSkins and C.skinToTopFade then C.skinToTopFade(false, PAGE_OUT.Time) end
        task.delay(PAGE_OUT.Time, function()
            if mine ~= switch then return end
            local onSkins = tab.id == "skins"
            UI.skinPage.Visible = onSkins
            tabPage.Visible = not onSkins and not tab.page
            for _, t in ipairs(TABS) do
                if t.page then t.page.Visible = (t == tab) end
            end
            if not onSkins and not tab.page then
                pageIcon.Image = tab.icon
                pageTitle.Text = tab.name
            end
            local to = pageOf(tab)
            local home = UDim2.fromOffset(UI.LIST_CLIP_X, UI.LIST_TOP)
            to.GroupTransparency = 1
            to.Position = home + UDim2.fromOffset(0, 6)
            TweenService:Create(to, PAGE_IN, { GroupTransparency = 0, Position = home }):Play()
            if onSkins and C.skinToTopFade then C.skinToTopFade(true, PAGE_IN.Time) end
            if tab.onShow then task.spawn(tab.onShow) end           -- (Home's cards rise in)
        end)
    end
end
end

--// Toasts --------------------------------------------------------
-- Bottom-right, in the site's card style: dark, 1px border, 12px corners,
-- the icon chip centred on the text and a thin countdown bar along the
-- bottom edge.
--   * Each card sizes itself from its content every time that changes (text
--     can wrap, and Geist can finish loading after the first frame), so the
--     text is never clipped and the bar never lands on it.
--   * A new card opens its slot smoothly, so the stack slides up, not jumps.
--   * Hovering lights the border and holds the countdown.
--   * The same event again (key) updates the live card instead of stacking
--     copies: "+1 Chroma Laser" becomes "+2 Chroma Laser" with a small pop.
--   * At most four on screen; the oldest steps aside.
local toasts = make("Frame", {
    Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20),
    Size = UDim2.new(0, 300, 1, -40), ZIndex = 10, Parent = gui,
})
-- No list padding: each slot carries its own 8px gap (the card sits 8 down
-- inside it), so the gap opens and closes with the slot. A list padding
-- appeared at once next to a new zero-height slot and vanished at once when a
-- closed one was destroyed, so the stack jumped and snapped by 8px.
UI.TOAST_GAP = 8
make("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom,
    Padding = UDim.new(0, 0), Parent = toasts,
})
UI.TOAST_KIND = {
    success = { icon = ICON.check, bg = C.greenBg, edge = C.greenEdge, ink = C.greenText },
    info    = { icon = ICON.info, bg = hex("#18181b"), edge = C.border, ink = C.text },
    off     = { icon = ICON.power, bg = hex("#18181b"), edge = C.border, ink = C.muted },
    wait    = { icon = ICON.clock, bg = hex("#18181b"), edge = C.border, ink = C.muted },
    flame   = { icon = ICON.flame, bg = C.amberBg, edge = C.amberEdge, ink = C.amber },
    discord = { icon = ICON.discord, cell = UI.DISCORD_CELL, bg = C.blurpleBg, edge = C.blurpleEdge, ink = C.blurple },
    youtube = { icon = ICON.play, cell = UI.PLAY_CELL, bg = C.redBg, edge = C.redEdge, ink = C.red },
    neutral = { icon = ICON.trash, bg = hex("#18181b"), edge = C.border, ink = C.text },
    warning = { icon = ICON.x, bg = hex("#2a2110"), edge = hex("#4d3d1a"), ink = C.amber },
    error   = { icon = ICON.x, bg = C.redBg, edge = C.redEdge, ink = C.red },
}
UI.toastOrder, UI.liveToasts = 0, {}

-- notify{ title, body | stack = function(n) -> body, kind, key, duration }
function notify(o)
    local k = UI.TOAST_KIND[o.kind or "success"] or UI.TOAST_KIND.success
    local duration = o.duration or 2.6
    -- the same message again merges into the one already showing (×2, ×3 …)
    -- instead of stacking a copy; callers can still pass their own key
    o.key = o.key or ("%s|%s"):format(o.title or "", o.stack and "" or (o.body or ""))

    if o.key then
        for _, live in ipairs(UI.liveToasts) do
            if live.key == o.key and not live.gone then
                live.bump(o)
                return live
            end
        end
    end

    UI.toastOrder += 1
    local e = { key = o.key, n = 1, gone = false, left = duration, hovering = false }
    local slot = make("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = UI.toastOrder, Parent = toasts,
    })
    local wrap = make("CanvasGroup", {
        BackgroundTransparency = 1, GroupTransparency = 1, Position = UDim2.fromOffset(24, UI.TOAST_GAP),
        Size = UDim2.new(1, 0, 0, 0), Parent = slot,
    })
    local card = make("Frame", {
        BackgroundColor3 = C.pill, BorderSizePixel = 0, Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 0, 0), Parent = wrap,
    })
    corner(card, 11)
    local cardStroke = stroke(card, C.border)

    -- the content row: icon chip | title + body | close, centred vertically;
    -- its bottom padding leaves the bar a lane of its own
    local row = make("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card,
    })
    pad(row, 13, 13, 12, 16)
    hlist(row, 12)
    local chip = make("Frame", {
        BackgroundColor3 = k.bg, BorderSizePixel = 0, Size = UDim2.fromOffset(26, 26), LayoutOrder = 1, Parent = row,
    })
    corner(chip, 7)
    stroke(chip, k.edge)
    local chipScale = make("UIScale", { Parent = chip })
    image({ Image = k.icon, ImageColor3 = k.ink, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            ImageRectOffset = k.cell and k.cell.offset or Vector2.zero, ImageRectSize = k.cell and k.cell.size or Vector2.zero,
            Size = UDim2.fromOffset(15, 15), Parent = chip })
    local words = make("Frame", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(208, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 2, Parent = row,
    })
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = words })
    local titleL = text({ Text = o.title or "", FontFace = geist(FW.SemiBold), TextSize = 14, TextWrapped = true, RichText = true,
                          Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = words })
    local firstBody = o.stack and o.stack(1) or o.body
    local bodyL = text({ Text = firstBody or "", TextSize = 12, TextColor3 = C.muted, TextWrapped = true,
                         Visible = firstBody ~= nil and firstBody ~= "",
                         Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = words })
    local closeT = make("ImageButton", {
        Image = ICON.x, ImageColor3 = C.subtle, BackgroundTransparency = 1, AutoButtonColor = false,
        Size = UDim2.fromOffset(14, 14), LayoutOrder = 3, Parent = row,
    })
    closeT.MouseEnter:Connect(function() tween(closeT, 0.12, { ImageColor3 = C.text }) end)
    closeT.MouseLeave:Connect(function() tween(closeT, 0.15, { ImageColor3 = C.subtle }) end)

    local bar = make("Frame", {
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 13, 1, -7), Size = UDim2.new(1, -26, 0, 2), Parent = card,
    })
    corner(bar, FULL)

    -- the card follows its content's height, whenever it changes
    local opened = false
    local function measure()
        -- whole pixels, so the card (inside its fading CanvasGroup) never
        -- sits between two and blurs or mis-spaces its text
        local h = math.ceil(row.AbsoluteSize.Y)
        if h <= 0 then return end
        card.Size = UDim2.new(1, -2, 0, h)
        wrap.Size = UDim2.new(1, 0, 0, h + 2)
        if opened and not e.gone then slot.Size = UDim2.new(1, 0, 0, h + 2 + UI.TOAST_GAP) end
    end
    row:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)

    local barTween
    local function runBar()
        if barTween then barTween:Cancel() end
        bar.Size = UDim2.new(1, -26, 0, 2)
        barTween = TweenService:Create(bar, TweenInfo.new(math.max(e.left, 0.01), EASE.Linear), { Size = UDim2.new(0, 0, 0, 2) })
        barTween:Play()
        if e.hovering then barTween:Pause() end
    end

    function e.dismiss()
        if e.gone then return end
        e.gone = true
        for i, live in ipairs(UI.liveToasts) do
            if live == e then table.remove(UI.liveToasts, i) break end
        end
        local out = TweenService:Create(wrap, TweenInfo.new(0.2, EASE.Quint, DIR.In),
            { Position = UDim2.fromOffset(24, UI.TOAST_GAP), GroupTransparency = 1 })
        out:Play()
        out.Completed:Wait()
        tween(slot, 0.22, { Size = UDim2.new(1, 0, 0, 0) }).Completed:Wait()
        slot:Destroy()
    end
    -- the same event again: count it in place, pop the icon, restart the clock
    function e.bump(o2)
        e.n += 1
        -- the repeat count, in grey after the title (toasts that count in
        -- their own text, like "+3 Bauble", keep just the title)
        local title = o2.title or o.title or ""
        titleL.Text = o.stack and title or ('%s  <font color="#%s">×%d</font>'):format(title, C.subtle:ToHex(), e.n)
        local b = o2.stack and o2.stack(e.n) or o2.body
        if b then bodyL.Text = b; bodyL.Visible = b ~= "" end
        e.left = duration
        if opened then runBar() end
        chipScale.Scale = 1.18
        tween(chipScale, 0.35, { Scale = 1 }, EASE.Back)
        cardStroke.Color = C.borderHi
        tween(cardStroke, 0.45, { Color = e.hovering and C.borderHi or C.border })
    end
    -- change the words in place -- a countdown, a status -- without
    -- restarting the clock or counting it as a repeat
    function e.set(title, body)
        if title then titleL.Text = title end
        if body then bodyL.Text = body; bodyL.Visible = body ~= "" end
    end

    card.MouseEnter:Connect(function()
        e.hovering = true
        if barTween then barTween:Pause() end
        tween(cardStroke, 0.15, { Color = C.borderHi })
    end)
    card.MouseLeave:Connect(function()
        e.hovering = false
        if barTween then barTween:Play() end
        tween(cardStroke, 0.2, { Color = C.border })
    end)
    closeT.MouseButton1Click:Connect(function() task.spawn(e.dismiss) end)

    UI.liveToasts[#UI.liveToasts + 1] = e
    if #UI.liveToasts > 4 then task.spawn(UI.liveToasts[1].dismiss) end

    task.spawn(function()
        -- let the text lay out (and the font land) before opening the slot
        local t0 = os.clock()
        repeat RunService.RenderStepped:Wait() until row.AbsoluteSize.Y > 0 or os.clock() - t0 > 1
        RunService.RenderStepped:Wait()
        if e.gone or not slot.Parent then return end
        measure()
        opened = true
        tween(slot, 0.28, { Size = UDim2.new(1, 0, 0, wrap.Size.Y.Offset + UI.TOAST_GAP) })   -- the stack slides up
        tween(wrap, 0.35, { Position = UDim2.fromOffset(0, UI.TOAST_GAP), GroupTransparency = 0 })
        runBar()
        while e.left > 0 and not e.gone do
            local dt = RunService.Heartbeat:Wait()
            -- The hover that holds the clock is read from where the mouse
            -- actually is, every frame. MouseLeave never fires when the card
            -- slides out from under a mouse that isn't moving (the stack
            -- shifting as toasts come and go), so a toast could wait forever
            -- on a hover that had already ended.
            -- (mouse space includes the top bar; AbsolutePosition doesn't --
            -- same shift as C.hoverGuard, or the hit box sat a bar too high)
            local m = UIS:GetMouseLocation()
            local p, sz = card.AbsolutePosition + game:GetService("GuiService"):GetGuiInset(), card.AbsoluteSize
            local over = m.X >= p.X and m.X <= p.X + sz.X and m.Y >= p.Y and m.Y <= p.Y + sz.Y
            if over ~= e.hovering then
                e.hovering = over
                if barTween then
                    if over then barTween:Pause() else barTween:Play() end
                end
                tween(cardStroke, 0.2, { Color = over and C.borderHi or C.border })
            end
            if not over then e.left -= dt end
        end
        e.dismiss()
    end)
    return e
end

--// Minimise, maximise, close, RightShift ------------------------------
-- The minimised pill: what stays on screen while the window is minimised —
-- "Onyx ▸ Click to Open", then the live FPS. Click it to reopen; drag it anywhere. A press
-- only counts as a click if the pointer barely moved, so a drag never reopens
-- the window by accident. Dragging lifts it a touch and it glides after the
-- pointer; it can't leave the screen and it remembers where you put it.
-- Nothing here scales: text drawn under a UIScale snaps between pixel sizes
-- mid-animation, so the pill fades, slides and lifts instead.
UI.PILL_H = 40
local pillRoot = make("Frame", {
    Name = "OpenPill", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
    Size = UDim2.fromOffset(100, UI.PILL_H), Visible = false, ZIndex = 10, Parent = gui,
})
UI.pillShadow = image({
    Image = ICON.shadow, ImageColor3 = BLACK, ImageTransparency = 1, ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(99, 99, 99, 99), SliceScale = 0.32,
    Position = UDim2.fromOffset(-18, -13), Size = UDim2.new(1, 36, 1, 36), ZIndex = 0, Parent = pillRoot,
})
UI.pillGroup = make("CanvasGroup", {
    BackgroundTransparency = 1, GroupTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = pillRoot,
})
local pill = make("TextButton", {
    Text = "", AutoButtonColor = false, BackgroundColor3 = C.pill, BorderSizePixel = 0,
    Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), Parent = UI.pillGroup,
})
corner(pill, FULL)
UI.pillStroke = stroke(pill, C.border)
UI.pillContent = make("Frame", {
    BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
    Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = pill,
})
pad(UI.pillContent, 18, 18)
hlist(UI.pillContent, 12)
-- "Onyx ▸ Click to Open │ FPS 164" -- one font, one grey. White for what
-- matters: the name, and the number, which only changes colour when the frame
-- rate is poor (amber when it's dropping, red when it's low).
UI.refreshPillStats = nil
do
    local SIZE = 13
    -- the name (a touch bigger), a small arrow, then what the pill does ("Tap"
    -- on a touch screen). Geist has no ▸ glyph, so the arrow is Geist's own
    -- play icon, in the same grey as the words after it.
    local lead = make("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 1, Parent = UI.pillContent,
    })
    hlist(lead, 6)
    -- (the name is bigger than the words after it, and centred in the row the
    -- bigger word's baseline lands a pixel low: it's lifted to sit level)
    local nameBox = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = lead })
    text({ Text = "Onyx", FontFace = geist(FW.ExtraBold), TextSize = 15, Position = UDim2.fromOffset(0, -1),
           Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = nameBox })
    image({ Image = ICON.play, ImageRectOffset = UI.PLAY_CELL.offset, ImageRectSize = UI.PLAY_CELL.size,
            ImageColor3 = C.muted, Size = UDim2.fromOffset(10, 10), LayoutOrder = 2, Parent = lead })
    local verb = (UIS.TouchEnabled and not UIS.MouseEnabled) and "Tap" or "Click"
    text({ Text = verb .. " to Open", FontFace = geist(FW.Medium), TextSize = SIZE, TextColor3 = C.muted,
           Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3, Parent = lead })

    make("Frame", {      -- the divider
        BackgroundColor3 = C.border, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 14),
        LayoutOrder = 2, Parent = UI.pillContent,
    })

    -- A stat: its name in grey, then the live number (and unit). Geist's
    -- digits aren't all one width -- a 1 is narrower than an 8 -- so a changing
    -- number would nudge everything after it. Each digit gets its own 7px slot
    -- instead: tabular figures, in the same font as the rest.
    local DIGIT_W = 7
    local function stat(label, order, unit)
        local row = make("Frame", {
            BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
            LayoutOrder = order, Parent = UI.pillContent,
        })
        hlist(row, 5)
        text({ Text = label, FontFace = geist(FW.Medium), TextSize = SIZE, TextColor3 = C.muted,
               Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = row })
        local value = make("Frame", {
            BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
            LayoutOrder = 2, Parent = row,
        })
        hlist(value, 0)
        local st = { digits = {}, color = C.text }
        if unit then
            st.unit = text({ Text = unit, FontFace = geist(FW.SemiBold), TextSize = SIZE, TextColor3 = st.color,
                             Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 99, Parent = value })
        end
        function st.set(str)
            str = tostring(str)
            -- once the odometer exists (it's built further down the file),
            -- the number rolls from one value to the next instead of jumping
            if C.odometer and not st.odo then
                for _, d in ipairs(st.digits) do d:Destroy() end
                table.clear(st.digits)
                st.odo = C.odometer({ parent = value, font = geist(FW.SemiBold), size = SIZE, height = SIZE + 3,
                    color = st.color })
                st.odo.frame.LayoutOrder = 1
            end
            if st.odo then st.odo.set(str, str == "--"); return end
            for i = 1, #str do
                local d = st.digits[i] or text({
                    FontFace = geist(FW.SemiBold), TextSize = SIZE, TextColor3 = st.color,
                    TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(0, DIGIT_W, 1, 0), Parent = value,
                })
                d.LayoutOrder, d.Text = i, str:sub(i, i)
                st.digits[i] = d
            end
            for i = #st.digits, #str + 1, -1 do
                st.digits[i]:Destroy()
                st.digits[i] = nil
            end
        end
        function st.paint(color)
            if color == st.color then return end
            st.color = color
            for _, d in ipairs(st.digits) do tween(d, 0.3, { TextColor3 = color }) end
            if st.odo then st.odo.tint(color, 0.3) end
            if st.unit then tween(st.unit, 0.3, { TextColor3 = color }) end
        end
        st.set("--")
        return st
    end
    local fps = stat("FPS", 3)

    -- Frames counted over each half second -- the same count the Performance
    -- counter makes, so the two always agree. (It used to smooth each frame's
    -- duration instead, which let one long hitch drag the reading to 90 while
    -- the game was really running at 480.)
    local shownFps = 60
    function UI.refreshPillStats()
        local f = shownFps
        fps.set(f)
        fps.paint(f < 25 and C.red or f < 45 and C.amberText or C.text)
    end
    local frames, last = 0, os.clock()
    conns[#conns + 1] = RunService.RenderStepped:Connect(function()
        frames += 1
        local now = os.clock()
        local span = now - last
        if span < 0.5 then return end
        shownFps = math.floor(frames / span + 0.5)
        UI.fps = shownFps                   -- (Home shows it too)
        frames, last = 0, now
        if pillRoot.Visible then UI.refreshPillStats() end
    end)
end

-- Rolling numbers, like an odometer: every character sits in its own slot,
-- and when one changes the old one rolls up and out while the new one rolls
-- in from below (the other way when a number falls). Slots count from the
-- right, so the ones and tens of "24/40" and "25/40" stay lined up, and
-- digits share one width (tabular), so nothing shuffles sideways.
do
    local TS = game:GetService("TextService")
    local widths = {}
    local function charW(font, size, ch)
        if ch:match("%d") then ch = "0" end
        local key = tostring(font.Family) .. tostring(font.Weight) .. size
        local t = widths[key]
        if not t then t = {}; widths[key] = t end
        if t[ch] then return t[ch] end
        t[ch] = math.ceil(size * (ch == " " and 0.3 or 0.62))      -- until it's measured
        task.spawn(function()
            local ok, v = pcall(function()
                local p = Instance.new("GetTextBoundsParams")
                p.Font, p.Size, p.Width = font, size, 1000
                if ch == " " then
                    p.Text = "a a"; local a = TS:GetTextBoundsAsync(p).X
                    p.Text = "aa"; return a - TS:GetTextBoundsAsync(p).X
                end
                p.Text = ch
                return TS:GetTextBoundsAsync(p).X
            end)
            if ok and v and v > 0 then t[ch] = math.ceil(v) end
        end)
        return t[ch]
    end
    function C.odometer(o)
        local font, size, h = o.font, o.size, o.height or (o.size + 2)
        local frame = make("Frame", { BackgroundTransparency = 1, ClipsDescendants = true,
            AnchorPoint = o.anchor or Vector2.new(0, 0), Position = o.position or UDim2.new(),
            Size = UDim2.fromOffset(0, h), Parent = o.parent })
        local O = { frame = frame, width = 0 }
        -- a little room either side: the frame clips so digits can roll in
        -- and out, but a heavy face draws a pixel past its measured width
        -- (Gotham's "4" is wider than its "0") and those edges were cut off
        local PAD = 2
        local color, alpha, shown = o.color or C.text, 0, nil
        local slots = {}                      -- [slot from the right] = { label, ch }
        local ROLL = TweenInfo.new(0.42, EASE.Quint, DIR.Out)
        local function label(ch, x, y)
            local l = text({ Text = ch, FontFace = font, TextSize = size, TextColor3 = color, TextTransparency = alpha,
                TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(x + PAD, y),
                Size = UDim2.fromOffset(charW(font, size, ch), h), Parent = frame })
            if o.gradient then make("UIGradient", { Rotation = 90, Color = o.gradient, Parent = l }) end
            return l
        end
        -- the whole number a string shows ("1,234" -> 1234), not just its first
        -- run of digits, which read "1,050" as smaller than "999"
        local function num(s) return tonumber((tostring(s or ""):gsub("[^%d]", "")), 10) end
        function O.set(str, instant, forceDir)
            str = tostring(str or "")
            local chars = {}
            for ch in str:gmatch(utf8.charpattern) do chars[#chars + 1] = ch end
            local n, total = #chars, 0
            for i = 1, n do total += charW(font, size, chars[i]) end
            if str == shown and total == O.width then return end
            -- up as it grows, down as it falls; a caller can say which way when
            -- the text isn't a plain number (a "59m 59s" -> "1h 00m" timer)
            local was, now = num(shown), num(str)
            local dir = forceDir or ((was and now and now < was) and -1 or 1)
            local anim = not instant and shown ~= nil and alpha < 1
            -- Anchored from the right, a width change moves the frame's left
            -- edge, and every digit with it: shift them back by that much so
            -- they stay put on screen (they jumped, then slid back, and a
            -- digit rolling out left a ghost where it no longer was).
            local dx = (total - O.width) * frame.AnchorPoint.X
            if anim and dx ~= 0 then
                for _, s in pairs(slots) do s.label.Position = s.label.Position + UDim2.fromOffset(dx, 0) end
            end
            O.width = total
            frame.Size = UDim2.fromOffset(total + PAD * 2, h)
            local x = 0
            for i = 1, n do
                local ch, k = chars[i], n - i + 1
                local w = charW(font, size, ch)
                local s = slots[k]
                if s and s.ch == ch then
                    s.label.Size = UDim2.fromOffset(w, h)
                    if anim then TweenService:Create(s.label, ROLL, { Position = UDim2.fromOffset(x + PAD, 0) }):Play()
                    else s.label.Position = UDim2.fromOffset(x + PAD, 0) end
                else
                    if s then
                        local old = s.label
                        if anim then
                            TweenService:Create(old, ROLL, { Position = UDim2.fromOffset(old.Position.X.Offset, -dir * h), TextTransparency = 1 }):Play()
                            task.delay(ROLL.Time, function() old:Destroy() end)
                        else
                            old:Destroy()
                        end
                    end
                    local l = label(ch, x, anim and dir * h or 0)
                    if anim then TweenService:Create(l, ROLL, { Position = UDim2.fromOffset(x + PAD, 0) }):Play() end
                    slots[k] = { label = l, ch = ch }
                end
                x += w
            end
            for k = #slots, n + 1, -1 do
                local old = slots[k].label
                slots[k] = nil
                if anim then
                    TweenService:Create(old, ROLL, { TextTransparency = 1 }):Play()
                    task.delay(ROLL.Time, function() old:Destroy() end)
                else
                    old:Destroy()
                end
            end
            shown = str
        end
        function O.alpha(a, t)
            alpha = a
            for _, s in pairs(slots) do
                if t and t > 0 then tween(s.label, t, { TextTransparency = a }, EASE.Quint, DIR.Out) else s.label.TextTransparency = a end
            end
        end
        function O.tint(c, t)
            color = c
            for _, s in pairs(slots) do
                if t and t > 0 then tween(s.label, t, { TextColor3 = c }) else s.label.TextColor3 = c end
            end
        end
        -- a flash of colour (a coin landing) that fades back
        function O.flash(c, back, t)
            O.tint(c)
            O.tint(back, t)
        end
        -- the middle of a character, on screen (the confetti's "/")
        function O.centreOf(ch)
            for _, s in pairs(slots) do
                if s.ch == ch then return s.label.AbsolutePosition + s.label.AbsoluteSize / 2 end
            end
            return frame.AbsolutePosition + frame.AbsoluteSize / 2
        end
        return O
    end
end

-- A stat card: one dark rounded bar split into equal cells by faint
-- dividers, each a heavy number over a small caps label (COINS, LEVEL, PER
-- HOUR ...), both in Gotham SSm Heavy and both washed white to silver from
-- the top down. The Autofarm tab and the island's hover share it.
-- specs = { { "COINS", start text? }, ... }; returns the value labels (or
-- odometers, with o.odo) and the cells, in order.
C.STAT_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
-- the same face, lighter, for the island's words (the pill's own row stays Geist)
C.STAT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
C.STAT_MEDIUM = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
C.STAT_SILVER = ColorSequence.new(WHITE, Color3.fromRGB(182, 182, 192))
function C.statCard(o)
    local card = make("Frame", { BackgroundColor3 = C.field, BorderSizePixel = 0, Position = o.position,
        Size = o.size, Parent = o.parent })
    corner(card, 12)
    stroke(card, C.border)
    local n = #o.specs
    local values, cells = {}, {}
    for i, spec in ipairs(o.specs) do
        local cell = make("Frame", { BackgroundColor3 = C.field, BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.new((i - 1) / n, 3, 0, 3), Size = UDim2.new(1 / n, -6, 1, -6), Parent = card })
        corner(cell, 9)
        if i > 1 then
            make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0,
                Position = UDim2.new((i - 1) / n, 0, 0, 16), Size = UDim2.new(0, 1, 1, -32), Parent = card })
        end
        if o.odo then
            values[i] = C.odometer({ parent = cell, font = C.STAT_FONT, size = 20, height = 22, color = WHITE,
                gradient = C.STAT_SILVER, anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 10) })
            values[i].set(spec[2] or "0", true)
        else
            values[i] = text({ Text = spec[2] or "0", FontFace = C.STAT_FONT, TextSize = 20, TextColor3 = WHITE,
                TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
                Position = UDim2.new(0, 3, 0, 10), Size = UDim2.new(1, -6, 0, 22), Parent = cell })
            make("UIGradient", { Rotation = 90, Color = C.STAT_SILVER, Parent = values[i] })
        end
        local cap = text({ Text = spec[1], FontFace = C.STAT_FONT, TextSize = 11, TextColor3 = WHITE,
            TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.new(0, 3, 0, 37), Size = UDim2.new(1, -6, 0, 13), Parent = cell })
        make("UIGradient", { Rotation = 90, Color = C.STAT_SILVER, Parent = cap })
        cells[i] = cell
    end
    return values, cells, card
end

-- The Dynamic Island. While the window is closed and Onyx is busy -- the farm
-- running, a fling, a Spawn all -- the opener pill unfolds downward into one
-- rounded shape: the pill's row, a thin divider, then what's happening, with
-- a bar when there's progress. Hover it and it widens and drops a little
-- further for the details (the farm's latest move, and the session's coins,
-- rounds and time). Nothing going on and it folds back into the plain pill.
-- Click anywhere on it to open the window. Settings can switch it off.
do
    local ISLAND = {}
    C.island = ISLAND
    function ISLAND.enabled() return settings.island ~= false end
    -- a job with progress (Spawn all): set it while it runs, finish() shows the
    -- result for a moment and then lets go
    function ISLAND.task(spec) ISLAND.job, ISLAND.jobUntil = spec, nil end
    function ISLAND.finish(title, color, icon)
        local j = ISLAND.job
        if not j then return end
        j.title, j.color, j.done, j.icon = title, color or j.color, true, icon
        if j.total then j.n = j.total end
        ISLAND.jobUntil = os.clock() + 1.8
    end
    -- a result in words ("Research Facility won with 12 votes!") with a small
    -- check (or X) springing in beside them and the bar filling up, for a few
    -- seconds; finish() is the wordless big check that ends a job
    function ISLAND.result(title, color, icon, secs)
        ISLAND.job = { title = title, color = color or C.green, mark = { color = color or C.green, icon = icon } }
        ISLAND.jobUntil = os.clock() + (secs or 3.5)
    end
    -- a line for the expanded view ("Resetting to end the round"), for a while
    function ISLAND.note(textStr, secs) ISLAND.noteText, ISLAND.noteUntil = textStr, os.clock() + (secs or 5) end

    local Y0, ROW_H, MORE_H, WIDE = UI.PILL_H - 2, 50, 98, 380
    local hud = make("CanvasGroup", {
        Name = "Island", BackgroundTransparency = 1, GroupTransparency = 1, Visible = false,
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, UI.PILL_H), ZIndex = 0, Parent = pillRoot,
    })
    -- its own soft shadow, following its size (the pill's covers the pill only)
    local shade = image({
        Image = ICON.shadow, ImageColor3 = BLACK, ImageTransparency = 0.5, ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(99, 99, 99, 99), SliceScale = 0.32, Visible = false,
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -13), Size = UDim2.new(1, 36, 0, UI.PILL_H + 36),
        ZIndex = -1, Parent = pillRoot,
    })
    hud:GetPropertyChangedSignal("Size"):Connect(function()
        shade.Size = UDim2.new(1, hud.Size.X.Offset + 36, 0, hud.Size.Y.Offset + 36)
    end)
    local body = make("Frame", { BackgroundColor3 = C.pill, BorderSizePixel = 0, Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 1, -2), Parent = hud })
    corner(body, 19)
    local edge = stroke(body, C.border)
    -- the divider and the row, in one group so a finished job can fade them together
    local rowGroup = make("CanvasGroup", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = body })
    make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Position = UDim2.new(0, 18, 0, Y0),
        Size = UDim2.new(1, -36, 0, 1), Parent = body })

    -- the row: what's happening, then the bar and its count
    local status = text({ Text = "", FontFace = C.STAT_BOLD, TextSize = 13, TextColor3 = WHITE,
        TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, Y0 + 10), Size = UDim2.new(0, 200, 0, 16), Parent = rowGroup })
    -- The words carry the status colour, solid (softened a touch so they
    -- stay easy to read). A new status colour blends over, it never jumps.
    local ink = make("UIGradient", { Color = ColorSequence.new(WHITE), Parent = status })
    -- they stop short of the island's edges (room for the face included) and
    -- end in "..." rather than running out past them. The label is exactly
    -- that room, words centred in it (capStatus): sized to its own text under
    -- a cap, it kept a width from a narrower moment and cut lines that fit
    -- ("Waiting for the..." with 50px to spare)
    status.TextTruncate = Enum.TextTruncate.AtEnd
    local inkNow, inkFrom, inkTo = WHITE, WHITE, WHITE
    local inkBlend = Instance.new("NumberValue")
    inkBlend.Changed:Connect(function(a)
        inkNow = inkFrom:Lerp(inkTo, a)
        ink.Color = ColorSequence.new(inkNow)       -- one solid colour, no fade
    end)
    local function setInk(color)
        local target = (color or WHITE):Lerp(WHITE, 0.2)
        if target == inkTo then return end
        inkFrom, inkTo = inkNow, target
        inkBlend.Value = 0
        tween(inkBlend, 0.35, { Value = 1 }, EASE.Quad, DIR.Out)
    end
    local track = make("CanvasGroup", { BackgroundColor3 = C.border, BorderSizePixel = 0,   -- clips to its round ends
        Position = UDim2.new(0, 18, 0, Y0 + 35), Size = UDim2.new(1, -76, 0, 4), Parent = rowGroup })
    corner(track, FULL)
    local fill = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track })
    corner(fill, FULL)
    local fillGrad = make("UIGradient", { Parent = fill })
    -- no progress to show (a fling): a soft light running along the track
    local sweep = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false, Size = UDim2.fromScale(1, 1), Parent = track })
    local sweepGrad = make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }), Offset = Vector2.new(-1, 0), Parent = sweep })
    UI.loop(TweenService:Create(sweepGrad, TweenInfo.new(1.1, EASE.Sine, DIR.InOut, -1), { Offset = Vector2.new(1, 0) }), sweep)
    local countOdo = C.odometer({ parent = rowGroup, font = C.STAT_FONT, size = 12, height = 14, color = C.muted,
        anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -18, 0, Y0 + 37) })
    local count = countOdo.frame
    -- a fling shows who: the target's face, just left of the words
    local face = image({ Image = "", BackgroundColor3 = C.tile, BackgroundTransparency = 1, ImageTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(20, 20), Visible = false, Parent = rowGroup })
    corner(face, FULL)
    local faceEdge = stroke(face, C.borderHi, 1, 1)
    -- a result shows a mark in the same spot: Spawn all's bold check (or X),
    -- in green (or red), that grows in from nothing with a spring
    ISLAND.mark = image({ Image = ICON.check, ImageColor3 = C.greenText, AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(0, 0), Visible = false, Parent = rowGroup })
    C.bolden(ISLAND.mark, 0.6)
    -- the words' whole width, never cut, so a long line can widen the island
    ISLAND.measure = text({ Text = "", FontFace = C.STAT_BOLD, TextSize = 13, TextTransparency = 1,
        Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X, Parent = rowGroup })
    ISLAND.rowExtra = 0
    local faceFor, faceOff = nil, 0
    -- (the words' own width, not the label's: the label is the whole room)
    local function placeFace()
        local x = faceOff - math.min(status.TextBounds.X, status.AbsoluteSize.X) / 2 - 7
        face.Position = UDim2.new(0.5, x, 0, Y0 + 18)
        ISLAND.mark.Position = UDim2.new(0.5, x - 9, 0, Y0 + 18)
    end
    local function capStatus()
        status.Size = UDim2.new(0, math.max(40, hud.AbsoluteSize.X - 44 - faceOff * 2), 0, 16)
    end
    capStatus()
    hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(capStatus)
    status:GetPropertyChangedSignal("TextBounds"):Connect(placeFace)
    status:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeFace)

    -- Done: the pill's row stays as it is; under the divider the words and
    -- the bar fade and one big check takes their place -- a green disc that
    -- springs in -- then the island folds away.
    local doneView = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, Y0),
        Size = UDim2.new(1, 0, 1, -Y0), ClipsDescendants = false, ZIndex = 4, Parent = body })
    local badge = make("Frame", { BackgroundColor3 = C.green, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), ZIndex = 5, Parent = doneView })
    corner(badge, FULL)
    local badgeCheck = image({ Image = ICON.check, ImageColor3 = C.ink, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62), ZIndex = 6, Parent = badge })
    C.bolden(badgeCheck, 0.7)
    local function popCheck(color, icon)
        badge.BackgroundColor3, badge.BackgroundTransparency = color, 0
        badgeCheck.Image = icon or ICON.check
        badge.Size, badge.Rotation = UDim2.fromOffset(0, 0), -30
        badgeCheck.ImageTransparency = 1
        -- a token: leaving 'done' within the delays bumps it, or the stale
        -- check popped back in over the row after the island had moved on
        ISLAND.popTok = (ISLAND.popTok or 0) + 1
        local mine = ISLAND.popTok
        task.delay(0.3, function()               -- once the words are gone
            if ISLAND.popTok ~= mine then return end
            tween(badge, 0.55, { Size = UDim2.fromOffset(30, 30), Rotation = 0 }, EASE.Back, DIR.Out)
            task.delay(0.12, function()
                if ISLAND.popTok == mine then tween(badgeCheck, 0.25, { ImageTransparency = 0 }) end
            end)
        end)
    end

    -- the hover extras: the latest move, then three small stat boxes
    local more = make("CanvasGroup", { BackgroundTransparency = 1, GroupTransparency = 1,
        Position = UDim2.fromOffset(0, Y0 + ROW_H), Size = UDim2.new(1, 0, 0, MORE_H), Parent = body })
    local detail = text({ Text = "", FontFace = C.STAT_MEDIUM, TextSize = 12, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -36, 0, 16), Parent = more })
    local boxes = C.statCard({ parent = more, odo = true, position = UDim2.fromOffset(18, 24), size = UDim2.new(1, -36, 0, 64),
        specs = { { "COLLECTED" }, { "TOTAL COINS", "-" }, { "PER HOUR", "-" }, { "UPTIME", "0m 00s" } } })

    -- Flinging more than one: hovered, it drops a list of them all, each
    -- face beside its name, one under the other
    -- each one a tile, like the farm's stat boxes: the face, the name in the
    -- fling's white-to-red, and under it their own running light
    local TILE_H, TILE_GAP = 44, 6
    local PERSON_H = TILE_H + TILE_GAP
    local NAME_INK = ColorSequence.new(WHITE, C.red:Lerp(WHITE, 0.2))
    local peopleView = make("CanvasGroup", { BackgroundTransparency = 1, GroupTransparency = 1,
        Position = UDim2.fromOffset(0, Y0 + ROW_H), Size = UDim2.new(1, 0, 0, 0), Parent = body })
    local peopleKey, peopleN, peopleTiles = nil, 0, {}
    local function setPeople(list)
        local key = ""
        for _, w in ipairs(list or {}) do key ..= w.id .. "," end
        if key == peopleKey then return end
        peopleKey, peopleN = key, list and #list or 0
        for _, c in ipairs(peopleView:GetChildren()) do c:Destroy() end
        table.clear(peopleTiles)
        peopleView.Size = UDim2.new(1, 0, 0, peopleN * PERSON_H + 8)
        for i, w in ipairs(list or {}) do
            local tile = make("Frame", { BackgroundColor3 = C.tile, BorderSizePixel = 0,
                Position = UDim2.fromOffset(18, (i - 1) * PERSON_H + 4), Size = UDim2.new(1, -36, 0, TILE_H), Parent = peopleView })
            corner(tile, 10)
            stroke(tile, C.border)
            local pic = image({ Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(w.id),
                BackgroundColor3 = C.pill, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0),
                Size = UDim2.fromOffset(28, 28), Parent = tile })
            corner(pic, FULL)
            stroke(pic, C.borderHi, 1)
            local nm = text({ Text = w.name, FontFace = C.STAT_BOLD, TextSize = 12, TextColor3 = WHITE,
                TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(45, 9),
                Size = UDim2.new(1, -55, 0, 14), Parent = tile })
            make("UIGradient", { Color = NAME_INK, Parent = nm })
            -- their loading line: the island's own track and running light
            local line = make("CanvasGroup", { BackgroundColor3 = C.border, BorderSizePixel = 0,   -- clips to its round ends
                Position = UDim2.fromOffset(45, 29), Size = UDim2.new(1, -56, 0, 3), Parent = tile })
            corner(line, FULL)
            local run = make("Frame", { BackgroundColor3 = C.red:Lerp(WHITE, 0.15), BorderSizePixel = 0,
                Size = UDim2.fromScale(1, 1), Parent = line })
            local runGrad = make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 1) }), Offset = Vector2.new(-1, 0), Parent = run })
            -- each light a little behind the one above, so they ripple down
            task.delay((i - 1) * 0.18, function()
                if runGrad.Parent then
                    UI.loop(TweenService:Create(runGrad, TweenInfo.new(1.1, EASE.Sine, DIR.InOut, -1), { Offset = Vector2.new(1, 0) }), run)
                end
            end)
            peopleTiles[i] = tile
        end
    end

    -- Anywhere on it -- beside the pill's row too, once it has widened -- is
    -- the pill: a click opens the window, a drag carries the lot. (The pill's
    -- press / drag code below drives this too.)
    local hit = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = body })
    ISLAND.hit = hit

    -- a label's text crossfades rather than jumping
    -- New words don't just appear: the old ones lift up and fade, and the
    -- new ones rise into place from a few pixels below. The first words of a
    -- fresh island wait a beat for it to open.
    local swapTok, swapTo, swapBase = {}, {}, {}
    local function swap(label, str)
        if (swapTo[label] or label.Text) == str then return end
        swapTo[label] = str
        swapTok[label] = (swapTok[label] or 0) + 1
        local mine = swapTok[label]
        local base = swapBase[label] or label.Position
        swapBase[label] = base
        local up, below = base + UDim2.fromOffset(0, -5), base + UDim2.fromOffset(0, 7)
        local function riseIn()
            if swapTok[label] ~= mine then return end
            label.Text = str
            label.Position, label.TextTransparency = below, 1
            tween(label, 0.42, { Position = base, TextTransparency = 0 }, EASE.Quint, DIR.Out)
        end
        if label.Text == "" then
            label.TextTransparency = 1
            task.delay(0.14, riseIn)
            return
        end
        tween(label, 0.13, { TextTransparency = 1, Position = up }, EASE.Quad, DIR.In).Completed:Connect(riseIn)
    end

    -- Shapes: closed (just the pill), row, more. Growing eases out long and
    -- soft; folding away is quicker. The pill's own background steps aside
    -- while the island is out, so the two read as one.
    local shape = "closed"
    local over, overSince, act          -- (the pointer's on it; set by the Heartbeat below)
    local function heightOf(s)
        if s == "closed" then return UI.PILL_H end
        if s == "done" then return Y0 + ROW_H end
        if s == "people" then return Y0 + ROW_H + peopleN * PERSON_H + 8 end
        return s == "row" and Y0 + ROW_H or Y0 + ROW_H + MORE_H
    end
    local GROW = TweenInfo.new(0.6, EASE.Quint, DIR.Out)
    local FOLD = TweenInfo.new(0.34, EASE.Quint, DIR.InOut)
    local function setShape(s, fast, color, icon)
        if s == shape then return end
        local was = shape
        shape = s
        if was == "closed" then
            hud.Visible, shade.Visible = true, true
            hud.GroupTransparency = 0
            hud.Position = UDim2.new(0.5, 0, 0, ISLAND.dragging and -2 or 0)
            shade.ImageTransparency = ISLAND.dragging and 0.3 or 0.5
            pill.BackgroundTransparency = 1
            UI.pillStroke.Transparency = 1
            UI.pillShadow.Visible = false
            -- the row doesn't just appear: it waits for the island to open a
            -- little, then fades up into place from a few pixels lower
            if s == "done" then
                -- straight into the check: the row underneath is last time's
                -- (its bar and count), so it's gone at once, not faded out
                rowGroup.GroupTransparency = 1
            else
                -- one after another as it opens: the words rise in (swap),
                -- the bar fades up, the count glides in from the right
                rowGroup.GroupTransparency, rowGroup.Position = 0, UDim2.new()
                track.BackgroundTransparency, fill.BackgroundTransparency = 1, 1
                countOdo.alpha(1)
                count.Position = UDim2.new(1, -8, 0, Y0 + 37)
                local function live() return shape ~= "closed" and shape ~= "done" end
                task.delay(0.26, function()
                    if not live() then return end
                    tween(track, 0.4, { BackgroundTransparency = 0 }, EASE.Quad, DIR.Out)
                    tween(fill, 0.4, { BackgroundTransparency = 0 }, EASE.Quad, DIR.Out)
                end)
                task.delay(0.32, function()
                    if live() then
                        countOdo.alpha(0, 0.45)
                        tween(count, 0.45, { Position = UDim2.new(1, -18, 0, Y0 + 37) }, EASE.Quint, DIR.Out)
                    end
                end)
            end
        end
        -- into the check: the pill's words and the row fade, the corners round
        -- off, and the disc springs in; out of it, all of that comes back
        if s == "done" then
            tween(rowGroup, 0.22, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -5) }, EASE.Quad, DIR.In)
            popCheck(color or C.green, icon)
        elseif was == "done" then
            ISLAND.popTok = (ISLAND.popTok or 0) + 1   -- cancel a check still popping in
            -- folding away: the check goes with the fold, and the old words
            -- stay gone (they only come back if something new takes over)
            -- it fades out where it is (shrinking it read as mushy)
            tween(badge, 0.22, { BackgroundTransparency = 1 }, EASE.Quad, DIR.Out)
            tween(badgeCheck, 0.18, { ImageTransparency = 1 }, EASE.Quad, DIR.Out)
            if s ~= "closed" then
                task.delay(0.15, function()
                    if shape == "done" or shape == "closed" then return end
                    rowGroup.Position = UDim2.fromOffset(0, 5)
                    tween(rowGroup, 0.3, { GroupTransparency = 0, Position = UDim2.new() })
                    -- the bar and count too: if 'done' came right after opening,
                    -- their own fade-ins were skipped and they stayed invisible
                    tween(track, 0.3, { BackgroundTransparency = 0 })
                    tween(fill, 0.3, { BackgroundTransparency = 0 })
                    countOdo.alpha(0, 0.3)
                    tween(count, 0.3, { Position = UDim2.new(1, -18, 0, Y0 + 37) }, EASE.Quint, DIR.Out)
                end)
            end
        end
        local pillW = math.floor(pillRoot.AbsoluteSize.X + 0.5)
        local extra = s == "more" and math.max(0, WIDE - pillW) or (s == "row" and ISLAND.rowExtra or 0)
        local info = fast and TweenInfo.new(0.16, EASE.Quad, DIR.In) or (s == "closed" and FOLD or GROW)
        local tw = TweenService:Create(hud, info, { Size = UDim2.new(1, extra, 0, heightOf(s)) })
        tw:Play()
        -- opening or widening near a screen edge: bring the pill in with it
        if s ~= "closed" and C.reclampPill then C.reclampPill() end
        if s == "more" then
            more.Position = UDim2.fromOffset(0, Y0 + ROW_H + 8)
            task.delay(0.12, function()
                if shape == "more" then
                    tween(more, 0.45, { GroupTransparency = 0, Position = UDim2.fromOffset(0, Y0 + ROW_H) }, EASE.Quint, DIR.Out)
                end
            end)
        else
            tween(more, 0.15, { GroupTransparency = 1 })
        end
        if s == "people" then
            peopleView.Position = UDim2.fromOffset(0, Y0 + ROW_H)
            for i, t in ipairs(peopleTiles) do
                local home = UDim2.fromOffset(18, (i - 1) * PERSON_H + 4)
                t.Position = home + UDim2.fromOffset(0, 8)
                task.delay(0.1 + (i - 1) * 0.05, function()
                    if shape == "people" and t.Parent then tween(t, 0.45, { Position = home }, EASE.Quint, DIR.Out) end
                end)
            end
            task.delay(0.1, function()
                if shape == "people" then tween(peopleView, 0.4, { GroupTransparency = 0 }, EASE.Quad, DIR.Out) end
            end)
        else
            tween(peopleView, 0.15, { GroupTransparency = 1 })
        end
        if fast then
            tween(hud, 0.16, { GroupTransparency = 1 })
            -- its shadow sits outside the hud's CanvasGroup: fade it too, or it
            -- vanished in one frame when the window opened from the island
            tween(shade, 0.16, { ImageTransparency = 1 })
        end
        if s == "closed" then
            tw.Completed:Connect(function(state)
                if state ~= Enum.PlaybackState.Completed or shape ~= "closed" then return end
                hud.Visible, shade.Visible = false, false
                pill.BackgroundTransparency = 0
                UI.pillStroke.Transparency = 0
                UI.pillShadow.Visible = true
                rowGroup.GroupTransparency, rowGroup.Position = 0, UDim2.new()
                -- (next time it opens straight onto its new words, no crossfade
                -- from the old ones)
                status.Text, detail.Text = "", ""
                swapTo[status], swapTo[detail] = nil, nil
                faceFor = nil
                face.Visible = false
                ISLAND.markFor = nil
                ISLAND.mark.Visible = false
                ISLAND.rowExtra = 0
                -- the words' room for the face goes with it: a fling that
                -- ended while folded left them 12px off-centre for good
                faceOff = 0
                swapBase[status] = UDim2.new(0.5, 0, 0, Y0 + 10)
                status.Position = swapBase[status]
            end)
        end
    end
    function ISLAND.close()
        -- forced shut (the window opened): a fling that ends while it's shut
        -- is never seen ending, so don't let it announce "Fling done" later
        ISLAND.flinging = nil
        setShape("closed", true)
    end

    -- Its surface: hovered or held it lightens a step, and a press lightens
    -- it one more, like the pill (whose own background is hidden while the
    -- island is out)
    local pressed = false
    local function paintBody(t)
        local hot = over or ISLAND.dragging
        tween(body, t, { BackgroundColor3 = pressed and hex("#18181b") or hot and C.pillHover or C.pill })
        tween(edge, t, { Color = (hot or pressed) and C.borderHi or C.border })
    end
    ISLAND.paint = paintBody
    function ISLAND.press(on)
        pressed = on
        paintBody(on and 0.08 or 0.15)
    end
    -- Picked up, it comes up whole, like the pill: it rises 2px off its
    -- shadow, which deepens, and settles back down (a touch of spring) when
    -- it's dropped
    function ISLAND.lift(on)
        ISLAND.dragging = on
        tween(hud, on and 0.2 or 0.35, { Position = UDim2.new(0.5, 0, 0, on and -2 or 0) }, on and EASE.Quint or EASE.Back)
        tween(shade, on and 0.2 or 0.3, { ImageTransparency = on and 0.3 or 0.5 })
        paintBody(0.15)
    end
    -- the room it takes while it's out (a drag keeps all of it on screen,
    -- not just the pill), or nil while it's only the pill
    function ISLAND.extent()
        if shape == "closed" then return nil end
        local pillW = math.floor(pillRoot.AbsoluteSize.X + 0.5)
        return shape == "more" and math.max(pillW, WIDE) or pillW + (shape == "row" and ISLAND.rowExtra or 0), heightOf(shape)
    end

    -- what to show right now, or nil: a job (Spawn all) comes first, then
    -- the farm (a fling it does is a detail, on hover), then a fling on its own
    local function current()
        local now = os.clock()
        if ISLAND.job then
            if ISLAND.jobUntil and now > ISLAND.jobUntil then ISLAND.job = nil
            else
                local j = ISLAND.job
                return { title = j.title, color = j.color or C.green, n = j.n, total = j.total, done = j.done, icon = j.icon, mark = j.mark }
            end
        end
        local fl = C.flingNow and C.flingNow()
        local ok, farm = false, nil
        if C.farmHud then ok, farm = pcall(C.farmHud) end
        if ok and type(farm) == "table" and farm.running then
            ISLAND.flinging = nil               -- (the farm's own flings stay a detail)
            local d = farm.detail
            if fl then d = fl.title
            elseif ISLAND.noteText and now < (ISLAND.noteUntil or 0) then d = ISLAND.noteText end
            return { title = farm.title, color = farm.color, n = farm.n, total = farm.cap, farm = farm, detail = d }
        end
        if fl then
            ISLAND.flinging = true
            return { title = fl.title, color = C.red, avatar = fl.avatar, people = fl.people }
        end
        -- a fling (or a fling loop) just ended: the check, in its red
        if ISLAND.flinging then
            ISLAND.flinging = nil
            ISLAND.job, ISLAND.jobUntil = { title = "Fling done", color = C.red, done = true }, now + 1.6
            return { title = "Fling done", color = C.red, done = true }
        end
        return nil
    end

    -- bag full: a pop of confetti out of the count (on the pill's frame, not
    -- in the island's CanvasGroup -- that can't draw rotation)
    local CONFETTI = { C.greenText, C.green, WHITE, hex("#fbbf24"), hex("#60a5fa"), hex("#f472b6") }
    local function burst()
        local box = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = pillRoot })
        local c = countOdo.centreOf("/") - pillRoot.AbsolutePosition
        local bits = {}
        for i = 1, 22 do
            local dotty = math.random() < 0.3
            local f = make("Frame", { BackgroundColor3 = CONFETTI[math.random(#CONFETTI)], BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 20, Parent = box,
                Size = dotty and UDim2.fromOffset(4, 4) or UDim2.fromOffset(3, math.random(6, 8)) })
            if dotty then corner(f, FULL) end
            local a = math.rad(math.random(235, 305))
            bits[i] = { f = f, p = c + Vector2.new(math.random(-8, 8), 0), v = Vector2.new(math.cos(a), math.sin(a)) * math.random(80, 160),
                        r = math.random(0, 360), vr = math.random(-540, 540), sway = math.random() * 6.28 }
        end
        local t, conn = 0, nil
        conn = RunService.RenderStepped:Connect(function(dt)
            t += dt
            for _, b in ipairs(bits) do
                b.v = (b.v + Vector2.new(math.sin(t * 7 + b.sway) * 20, 420) * dt) * (1 - 1.4 * dt)
                b.p += b.v * dt
                b.r += b.vr * dt
                b.f.Position = UDim2.fromOffset(b.p.X, b.p.Y)
                b.f.Rotation = b.r
                if t > 0.9 then b.f.BackgroundTransparency = math.min(1, (t - 0.9) / 0.5) end
            end
            if t > 1.45 or not gui.Parent then conn:Disconnect(); box:Destroy() end
        end)
    end

    local GuiService = game:GetService("GuiService")
    local lastN, celebrated = nil, false
    over, overSince, act = false, 0, nil
    local since = 0
    conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
        -- hover: the whole island, pill row included (AbsolutePosition sits
        -- the top bar's height above the mouse's space in this GUI)
        if shape ~= "closed" then
            if not ISLAND.dragging then
                local m = UIS:GetMouseLocation()
                local p = hud.AbsolutePosition + GuiService:GetGuiInset()
                local s = hud.AbsoluteSize
                local inside = m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y
                if inside ~= over then
                    over, overSince = inside, os.clock()
                    paintBody(0.2)
                end
            end
        elseif over then
            over = false
            paintBody(0)
        end

        since += dt
        if since < 0.1 then return end
        since = 0
        act = ISLAND.enabled() and pillRoot.Visible and not C.pillHiding
              and os.clock() - (C.pillShownAt or 0) > 0.25 and current() or nil
        if not act then
            setShape("closed")
            lastN = nil
            return
        end
        if act.done then
            setShape("done", false, act.color or C.green, act.icon)   -- green spawn, amber partial, red despawn / fling
            lastN = nil
            return
        end
        -- open; hovering a farm island (after a beat, so passing over it
        -- doesn't flap it open) shows the extras; leaving folds them after one
        local wantMore = act.farm ~= nil and over and os.clock() - overSince > 0.12
        if shape == "more" and act.farm and not over and os.clock() - overSince < 0.3 then wantMore = true end
        -- a fling on several: the same, with the list of who
        local hadN = peopleN
        setPeople(act.people)
        local wantPeople = act.people ~= nil and not act.farm and over and os.clock() - overSince > 0.12
        if shape == "people" and act.people and not over and os.clock() - overSince < 0.3 then wantPeople = true end
        setShape(wantMore and "more" or wantPeople and "people" or "row")
        -- someone joined or left the loop while the list is open: it resizes
        if shape == "people" and peopleN ~= hadN then
            TweenService:Create(hud, GROW, { Size = UDim2.new(1, 0, 0, heightOf("people")) }):Play()
        end

        -- the fling's face (or a result's mark): it slides the words over to
        -- make room, and fades (springs) in beside them
        local markKey = act.mark and act.title or nil
        if act.avatar ~= faceFor or markKey ~= ISLAND.markFor then
            faceFor = act.avatar
            ISLAND.markFor = markKey
            faceOff = (faceFor or markKey) and 12 or 0
            capStatus()
            local base = UDim2.new(0.5, faceOff, 0, Y0 + 10)
            swapBase[status] = base
            tween(status, 0.35, { Position = base })
            placeFace()
            if faceFor then
                face.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(faceFor)
                face.Visible = true
                face.ImageTransparency, face.BackgroundTransparency, faceEdge.Transparency = 1, 1, 1
                task.delay(0.14, function()
                    if faceFor == nil then return end
                    tween(face, 0.42, { ImageTransparency = 0, BackgroundTransparency = 0 }, EASE.Quint, DIR.Out)
                    tween(faceEdge, 0.42, { Transparency = 0 }, EASE.Quint, DIR.Out)
                end)
            else
                tween(face, 0.2, { ImageTransparency = 1, BackgroundTransparency = 1 })
                tween(faceEdge, 0.2, { Transparency = 1 })
            end
            -- the mark: Spawn all's check -- grows in from nothing once the
            -- words have moved over, overshooting a touch and settling
            local mk = ISLAND.mark
            if markKey then
                mk.Image = act.mark.icon or ICON.check
                mk.ImageColor3 = (act.mark.icon == ICON.x) and C.red or C.greenText
                mk.Visible, mk.ImageTransparency, mk.Size = true, 0, UDim2.fromOffset(0, 0)
                task.delay(0.14, function()
                    if ISLAND.markFor == markKey then tween(mk, 0.5, { Size = UDim2.fromOffset(16, 16) }, EASE.Back, DIR.Out) end
                end)
            elseif mk.Visible then
                tween(mk, 0.2, { ImageTransparency = 1 })
            end
        end
        swap(status, act.title or "")
        setInk(act.color)
        -- a line too long for the pill widens the island to fit it (up to the
        -- hover width), and it narrows back once the line is gone
        ISLAND.measure.Text = act.title or ""
        local pillW = math.floor(pillRoot.AbsoluteSize.X + 0.5)
        local extra = math.clamp(math.ceil(ISLAND.measure.TextBounds.X) + 44 + faceOff * 2 - pillW, 0, math.max(0, WIDE - pillW))
        if extra ~= ISLAND.rowExtra then
            ISLAND.rowExtra = extra
            if shape == "row" then
                TweenService:Create(hud, GROW, { Size = UDim2.new(1, extra, 0, heightOf("row")) }):Play()
                if C.reclampPill then C.reclampPill() end
            end
        end
        local n, total = act.n, act.total
        sweep.Visible = total == nil and not act.mark
        if act.mark then
            -- a result: the bar fills all the way, warming into its colour
            track.Size = UDim2.new(1, -36, 0, 4)
            countOdo.set("", true)
            fillGrad.Color = ColorSequence.new(WHITE, act.color or C.green)
            tween(fill, 0.5, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
        elseif total and total > 0 then
            countOdo.set(("%d/%d"):format(n or 0, total))
            -- the bar ends 12px before the count, whatever its width
            track.Size = UDim2.new(1, -(36 + math.ceil(countOdo.width) + 12), 0, 4)
            local frac = math.clamp((n or 0) / total, 0, 1)
            -- white where it starts, warming to the job's colour as it nears
            -- the end (green spawn, red despawn, the farm's own colour)
            fillGrad.Color = ColorSequence.new(WHITE, WHITE:Lerp(act.color or C.green, frac))
            -- a coin just landed: flash green FIRST, so this tween fades it
            -- back to white (set after, the running tween overwrote it at once)
            if act.farm and lastN and n and n > lastN then fill.BackgroundColor3 = C.greenText end
            tween(fill, 0.35, { Size = UDim2.fromScale(frac, 1), BackgroundColor3 = WHITE })
        else
            track.Size = UDim2.new(1, -36, 0, 4)
            countOdo.set("", true)
            fill.Size = UDim2.fromScale(0, 1)
        end
        -- the farm: a coin flashes the count green; a full bag gets confetti
        if act.farm then
            if lastN and n > lastN then
                countOdo.flash(C.greenText, C.muted, 0.6)      -- (the bar's flash is set above)
            end
            if n >= total then
                if not celebrated and lastN and lastN < total then task.delay(0.2, burst) end
                celebrated = true
            else
                celebrated = false
            end
            lastN = n
            swap(detail, act.detail or "")
            local f = act.farm
            boxes[1].set(f.coins or "0")
            boxes[2].set(f.total or "-")
            boxes[3].set(f.perHour or "-")
            boxes[4].set(f.ran or "0m 00s", false, 1)   -- time only ever rolls up
        else
            lastN = nil
        end
    end)
end


--// Settings page ---------------------------------------------------
-- For now one section, Interface, with the Dynamic Island switch. Turning it
-- off asks first: a red-edged card, "Not Recommended", and a small preview
-- of the opener with the island and without it.
do
    local page = make("CanvasGroup", {
        Name = "SettingsPage", BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1, Visible = false,
        Position = UI.listClip.Position, Size = UI.listClip.Size, ZIndex = 2, Parent = win,
    })
    corner(page, 12)
    for _, t in ipairs(TABS) do if t.id == "settings" then t.page = page end end
    local scroll = make("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = C.borderHi,
        VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, Parent = page,
    })
    pad(scroll, 2, 6, UI.SEARCH_Y - UI.LIST_TOP, 16)
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
                           HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = scroll })
    C.edgeFade(page, scroll)
    UI.snapPage(page)

    -- section heading, like the Autofarm page's
    local head = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, 18), LayoutOrder = 1, Parent = scroll })
    local headL = text({ Text = "INTERFACE", FontFace = geist(FW.SemiBold), TextSize = 11, TextColor3 = C.subtle,
                         Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = head })
    local headLine = make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Parent = head })
    local function fitHead()
        local w = math.floor(headL.AbsoluteSize.X / unscale() + 10)
        headLine.Position, headLine.Size = UDim2.new(0, w, 0.5, 0), UDim2.new(1, -w, 0, 1)
    end
    headL:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHead)
    fitHead()

    -- the card: title, a line on what it does, the switch on the right
    local card = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.tile, BorderSizePixel = 0,
        Size = UDim2.new(1, -2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = scroll })
    corner(card, 10)
    local cardSt = stroke(card, C.border)
    pad(card, 14, 14, 12, 12)
    local col = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -56, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card })
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3), Parent = col })
    text({ Text = "Dynamic Island", FontFace = geist(FW.SemiBold), TextSize = 13, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1, Parent = col })
    text({ Text = "While the window is closed, the opener unfolds to show what Onyx is doing: the farm and your bag, flings, and Spawn all progress. Hover it for more.",
           TextSize = 12, TextColor3 = C.muted, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0),
           AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = col })
    local track = make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(36, 20), Parent = card })
    corner(track, FULL)
    local knob = make("Frame", { BackgroundColor3 = C.muted, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(14, 14), Parent = track })
    corner(knob, FULL)
    local function paintSwitch(on, instant)
        if instant then
            track.BackgroundColor3 = on and WHITE or C.border
            knob.BackgroundColor3, knob.Position = on and C.bg or C.muted, UDim2.new(0, on and 19 or 3, 0.5, 0)
            return
        end
        tween(track, 0.2, { BackgroundColor3 = on and WHITE or C.border })
        tween(knob, 0.2, { BackgroundColor3 = on and C.bg or C.muted })
        knob.Size = UDim2.fromOffset(18, 14)
        tween(knob, 0.36, { Position = UDim2.new(0, on and 19 or 3, 0.5, 0) }, EASE.Back, DIR.Out)
        tween(knob, 0.3, { Size = UDim2.fromOffset(14, 14) }, EASE.Quint, DIR.Out)
    end
    paintSwitch(settings.island ~= false, true)
    local over = false
    card.MouseEnter:Connect(function() over = true; tween(card, 0.18, { BackgroundColor3 = C.tileHover }); tween(cardSt, 0.18, { Color = C.borderHi }) end)
    card.MouseLeave:Connect(function() over = false; tween(card, 0.22, { BackgroundColor3 = C.tile }); tween(cardSt, 0.22, { Color = C.border }) end)
    card.MouseButton1Down:Connect(function() tween(card, 0.08, { BackgroundColor3 = C.tileActive }) end)
    card.MouseButton1Up:Connect(function() tween(card, 0.2, { BackgroundColor3 = over and C.tileHover or C.tile }) end)

    local function setIsland(on)
        settings.island = on
        saveSettings()
        paintSwitch(on)
        notify({ title = on and "Dynamic Island on" or "Dynamic Island off",
                 body = on and "The opener shows what Onyx is doing while the window is closed." or "The opener is a plain pill now.",
                 kind = on and "success" or "off" })
    end

    --// the "Are you sure?" card
    local veil = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = BLACK, BackgroundTransparency = 1,
        BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 60, Parent = win })
    corner(veil, 16)
    local box = make("CanvasGroup", { BackgroundTransparency = 1, GroupTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(404, 0), AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 61, Parent = veil })
    pad(box, 2, 2, 2, 2)
    local sheet = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.pill, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 61, Parent = box })
    corner(sheet, 14)
    stroke(sheet, C.red, 1.5, 0.1)
    pad(sheet, 18, 18, 16, 16)
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12), Parent = sheet })

    -- title and the warning chip
    local top = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, ZIndex = 61, Parent = sheet })
    text({ Text = "Are you sure?", FontFace = geist(FW.Bold), TextSize = 16, Size = UDim2.new(0.6, 0, 1, 0), ZIndex = 62, Parent = top })
    local chip = make("Frame", { BackgroundColor3 = C.redBg, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 62, Parent = top })
    corner(chip, FULL)
    stroke(chip, C.redEdge)
    pad(chip, 8, 8)
    text({ Text = "Not Recommended", FontFace = geist(FW.SemiBold), TextSize = 11, TextColor3 = C.red,
           Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 63, Parent = chip })
    text({ Text = "Turning off the Dynamic Island leaves you with a basic pill. You won't see the farm, your bag, flings or Spawn all progress while the window is closed.",
           TextSize = 12, TextColor3 = C.muted, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0),
           AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 62, Parent = sheet })

    -- the preview: the opener as it is, and as it would be
    local previews = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 124), LayoutOrder = 3, ZIndex = 61, Parent = sheet })
    -- The opener in miniature, built like the real one (about two thirds its
    -- size): "Onyx > Click to Open | FPS", and with the island, the divider,
    -- the status in its white-into-colour words and the bar warming the same
    -- way, stopping short of the count.
    local function miniPill(parent, y, withIsland)
        local W = 168
        local ROW = 26
        local shell = make("Frame", { BackgroundColor3 = C.pill, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(W, withIsland and ROW + 32 or ROW), ZIndex = 63, Parent = parent })
        corner(shell, withIsland and UDim.new(0, 13) or FULL)
        stroke(shell, C.borderHi)
        local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, ROW), ZIndex = 64, Parent = shell })
        make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
                               VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
                               Padding = UDim.new(0, 5), Parent = row })
        local function word(str, order, weight, size, color)
            return text({ Text = str, FontFace = geist(weight), TextSize = size, TextColor3 = color or C.text, Size = UDim2.new(0, 0, 1, 0),
                          AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, ZIndex = 65, Parent = row })
        end
        word("Onyx", 1, FW.ExtraBold, 11)
        image({ Image = ICON.play, ImageRectOffset = UI.PLAY_CELL.offset, ImageRectSize = UI.PLAY_CELL.size, ImageColor3 = C.muted,
                Size = UDim2.fromOffset(7, 7), LayoutOrder = 2, ZIndex = 65, Parent = row })
        word("Click to Open", 3, FW.Medium, 9, C.muted)
        make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 10), LayoutOrder = 4, ZIndex = 65, Parent = row })
        word("FPS", 5, FW.Medium, 9, C.muted)
        word("60", 6, FW.SemiBold, 9)
        if withIsland then
            local tint = C.green
            make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Position = UDim2.new(0, 12, 0, ROW - 1),
                Size = UDim2.new(1, -24, 0, 1), ZIndex = 64, Parent = shell })
            local st = text({ Text = "Collecting coins", FontFace = geist(FW.SemiBold), TextSize = 10, TextColor3 = WHITE,
                   TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, ROW + 5),
                   Size = UDim2.new(1, 0, 0, 12), ZIndex = 65, Parent = shell })
            make("UIGradient", { Color = ColorSequence.new(WHITE, tint:Lerp(WHITE, 0.2)), Parent = st })
            local tr = make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Position = UDim2.fromOffset(12, ROW + 22),
                Size = UDim2.new(1, -24 - 22 - 8, 0, 3), ZIndex = 64, Parent = shell })
            corner(tr, FULL)
            local fl = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(0.6, 1), ZIndex = 65, Parent = tr })
            corner(fl, FULL)
            make("UIGradient", { Color = ColorSequence.new(WHITE, WHITE:Lerp(tint, 0.6)), Parent = fl })
            text({ Text = "24/40", FontFace = geist(FW.SemiBold), TextSize = 9, TextColor3 = C.muted,
                   TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, ROW + 23.5),
                   Size = UDim2.fromOffset(30, 12), ZIndex = 65, Parent = shell })
        end
        return shell
    end
    local function panel(x, label, labelCol, withIsland)
        local p = make("Frame", { BackgroundColor3 = C.field, BorderSizePixel = 0, Position = UDim2.new(x, x == 0 and 0 or 5, 0, 0),
            Size = UDim2.new(0.5, -5, 1, 0), ZIndex = 62, Parent = previews })
        corner(p, 10)
        stroke(p, C.border)
        -- a hint of the game behind it
        make("UIGradient", { Rotation = 90, Color = ColorSequence.new(hex("#141418"), C.field), Parent = p })
        miniPill(p, withIsland and 14 or 33, withIsland)
        text({ Text = label, FontFace = geist(FW.SemiBold), TextSize = 11, TextColor3 = labelCol, TextXAlignment = Enum.TextXAlignment.Center,
               AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -9), Size = UDim2.new(1, 0, 0, 14), ZIndex = 63, Parent = p })
        return p
    end
    panel(0, "Dynamic Island  ·  now", C.greenText, true)
    local after = panel(0.5, "Basic pill  ·  after", C.red, false)
    stroke(after, C.redEdge).Transparency = 0

    -- the buttons: keep it (white), or turn it off anyway (red)
    local btns = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 4, ZIndex = 61, Parent = sheet })
    make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
                           SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = btns })
    local function btn(label, order, danger)
        local b = make("TextButton", { Text = "", AutoButtonColor = false, BorderSizePixel = 0,
            BackgroundColor3 = danger and C.redBg or WHITE, Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X,
            LayoutOrder = order, ZIndex = 62, Parent = btns })
        corner(b, 9)
        local st = stroke(b, danger and C.redEdge or WHITE)
        pad(b, 14, 14)
        text({ Text = label, FontFace = geist(FW.SemiBold), TextSize = 13, TextColor3 = danger and C.red or C.ink,
               Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 63, Parent = b })
        local base = b.BackgroundColor3
        local hot = danger and C.redBg:Lerp(C.red, 0.12) or C.primaryHover
        b.MouseEnter:Connect(function() sfx("hover"); tween(b, 0.15, { BackgroundColor3 = hot }); if danger then tween(st, 0.15, { Color = C.red }) end end)
        b.MouseLeave:Connect(function() tween(b, 0.2, { BackgroundColor3 = base }); if danger then tween(st, 0.2, { Color = C.redEdge }) end end)
        b.MouseButton1Down:Connect(function() C.ripple(b, 9) end)
        return b
    end
    local turnOff = btn("Turn off anyway", 1, true)
    local keep = btn("Keep it on", 2, false)

    local asking = false
    local function ask(show)
        asking = show
        if show then
            veil.Visible = true
            box.Position = UDim2.new(0.5, 0, 0.5, 10)
            tween(veil, 0.25, { BackgroundTransparency = 0.35 })
            tween(box, 0.4, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, EASE.Quint, DIR.Out)
        else
            tween(box, 0.18, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 6) }, EASE.Quint, DIR.In)
            tween(veil, 0.22, { BackgroundTransparency = 1 }).Completed:Connect(function()
                if not asking then veil.Visible = false end
            end)
        end
    end
    card.MouseButton1Click:Connect(function()
        sfx("click")
        if settings.island ~= false then ask(true) else setIsland(true) end
    end)
    -- (the sheet stays clickable while it fades out: act only on the first click)
    keep.MouseButton1Click:Connect(function() if not asking then return end; sfx("click"); ask(false) end)
    turnOff.MouseButton1Click:Connect(function() if not asking then return end; sfx("click"); ask(false); setIsland(false) end)

    --// SKINS: "Restore my skins on join" (off by default)
    local head2 = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, 18), LayoutOrder = 3, Parent = scroll })
    local head2L = text({ Text = "SKINS", FontFace = geist(FW.SemiBold), TextSize = 11, TextColor3 = C.subtle,
                          Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = head2 })
    local head2Line = make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Parent = head2 })
    local function fitHead2()
        local w = math.floor(head2L.AbsoluteSize.X / unscale() + 10)
        head2Line.Position, head2Line.Size = UDim2.new(0, w, 0.5, 0), UDim2.new(1, -w, 0, 1)
    end
    head2L:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHead2)
    fitHead2()

    local rc = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.tile, BorderSizePixel = 0,
        Size = UDim2.new(1, -2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, Parent = scroll })
    corner(rc, 10)
    local rcSt = stroke(rc, C.border)
    pad(rc, 14, 14, 12, 12)
    local rcCol = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -56, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = rc })
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3), Parent = rcCol })
    text({ Text = "Restore my skins on join", FontFace = geist(FW.SemiBold), TextSize = 13, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1, Parent = rcCol })
    text({ Text = "Remembers the skins you spawned and the knife and gun you have equipped, and puts them back when Onyx loads in a new server.",
           TextSize = 12, TextColor3 = C.muted, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0),
           AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = rcCol })
    local rTrack = make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(36, 20), Parent = rc })
    corner(rTrack, FULL)
    local rKnob = make("Frame", { BackgroundColor3 = C.muted, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(14, 14), Parent = rTrack })
    corner(rKnob, FULL)
    local function paintR(on, instant)
        if instant then
            rTrack.BackgroundColor3 = on and WHITE or C.border
            rKnob.BackgroundColor3, rKnob.Position = on and C.bg or C.muted, UDim2.new(0, on and 19 or 3, 0.5, 0)
            return
        end
        tween(rTrack, 0.2, { BackgroundColor3 = on and WHITE or C.border })
        tween(rKnob, 0.2, { BackgroundColor3 = on and C.bg or C.muted })
        rKnob.Size = UDim2.fromOffset(18, 14)
        tween(rKnob, 0.36, { Position = UDim2.new(0, on and 19 or 3, 0.5, 0) }, EASE.Back, DIR.Out)
        tween(rKnob, 0.3, { Size = UDim2.fromOffset(14, 14) }, EASE.Quint, DIR.Out)
    end
    paintR(settings.restoreSkins == true, true)
    local rOver = false
    rc.MouseEnter:Connect(function() rOver = true; tween(rc, 0.18, { BackgroundColor3 = C.tileHover }); tween(rcSt, 0.18, { Color = C.borderHi }) end)
    rc.MouseLeave:Connect(function() rOver = false; tween(rc, 0.22, { BackgroundColor3 = C.tile }); tween(rcSt, 0.22, { Color = C.border }) end)
    rc.MouseButton1Down:Connect(function() tween(rc, 0.08, { BackgroundColor3 = C.tileActive }) end)
    rc.MouseButton1Up:Connect(function() tween(rc, 0.2, { BackgroundColor3 = rOver and C.tileHover or C.tile }) end)
    rc.MouseButton1Click:Connect(function()
        sfx("click")
        local on = settings.restoreSkins ~= true
        settings.restoreSkins = on
        -- this server's skins count as already restored, so switching it on
        -- never spawns doubles here
        if on then UI.store.restoredJob = game.JobId; UI.saveSkins() end
        saveSettings()
        paintR(on)
        notify({ title = on and "Restoring skins on join" or "Not restoring skins",
                 body = on and "Your spawned and equipped skins come back in every new server." or "New servers start with your real inventory.",
                 kind = on and "success" or "off" })
    end)
    veil.MouseButton1Click:Connect(function() if asking then ask(false) end end)   -- a click outside backs out
end

-- The pill is exactly as wide as its content (Geist may land a frame late).
-- On screen, a change -- a stat gaining a digit -- eases instead of jumping;
-- the content is centred, so the pill's padding covers the difference meanwhile.
UI.pillContent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    local size = UDim2.fromOffset(math.floor(UI.pillContent.AbsoluteSize.X + 0.5) + 2, UI.PILL_H)
    if not pillRoot.Visible then pillRoot.Size = size; return end
    -- folding away: hidePill's tween owns Size (and resets it when done)
    if C.pillHiding then return end
    -- A Size-only tween cancels showPill's slide-in (that tween animates
    -- Position too) and froze the pill mid-slide, 8px off its spot: while
    -- it's sliding in, carry the Position along to where it's going.
    if C.pillShownAt and os.clock() - C.pillShownAt < 0.6 and C.pillSpot then
        tween(pillRoot, 0.25, { Size = size, Position = C.pillSpot() })
    else
        tween(pillRoot, 0.25, { Size = size })
    end
end)

-- where it sits: top-centre of the pill, in screen pixels
local function clampPill(p)
    local cam, w, h = UI.viewport(), pillRoot.Size.X.Offset, UI.PILL_H
    -- while the island is out, all of it stays on screen, not just the pill
    local iw, ih
    if C.island then iw, ih = C.island.extent() end
    if iw then w, h = math.max(w, iw), math.max(h, ih) end
    return Vector2.new(
        math.clamp(p.X, w / 2 + 10, math.max(w / 2 + 10, cam.X - w / 2 - 10)),
        math.clamp(p.Y, 10, math.max(10, cam.Y - h - 10)))
end
local pillPos = Vector2.new(tonumber(settings.pillX) or UI.viewport().X / 2, tonumber(settings.pillY) or 15)
local function placePill(p) pillRoot.Position = UDim2.fromOffset(p.X, p.Y) end
placePill(pillPos)
C.pillSpot = function() return UDim2.fromOffset(pillPos.X, pillPos.Y) end

local pillHovered, pillDragging = false, false
local function paintPill()
    local hot = pillHovered or pillDragging
    tween(pill, 0.15, { BackgroundColor3 = hot and C.pillHover or C.pill })
    tween(UI.pillStroke, 0.15, { Color = hot and C.borderHi or C.border })
end
pill.MouseEnter:Connect(function() pillHovered = true; paintPill() end)
pill.MouseLeave:Connect(function() pillHovered = false; paintPill() end)

-- The island grows down and out of the pill. When it opens or widens near an
-- edge, glide the pill in so ALL of it stays on screen -- clampPill already
-- knows the island's extent, but used to run only while dragging.
C.reclampPill = function()
    if pillDragging or (C.island and C.island.dragging) or not pillRoot.Visible then return end
    local p = clampPill(pillPos)
    if p == pillPos then return end
    pillPos = p
    tween(pillRoot, 0.45, { Position = UDim2.fromOffset(p.X, p.Y) }, EASE.Quint, DIR.Out)
end
-- ...and when the screen changes size (fullscreen toggled, the Roblox window
-- resized): a pill parked at an edge would otherwise end up off it
conns[#conns + 1] = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    if not pillRoot.Visible or pillDragging then return end
    pillPos = clampPill(pillPos)
    placePill(pillPos)
end)

-- The pill grows out of a small dot into its full width as it fades in (its
-- content is centred and clipped, so the words are uncovered from the middle
-- out), and folds back into the dot on the way out.
local function pillWidth() return UDim2.fromOffset(math.floor(UI.pillContent.AbsoluteSize.X + 0.5) + 2, UI.PILL_H) end
local function showPill()
    UI.refreshPillStats()
    -- it vanished from under a still cursor last time (clicked away), which
    -- fires no MouseLeave: come back unlit
    if pillHovered then pillHovered = false; paintPill() end
    pillPos = clampPill(pillPos)
    C.pillHiding, C.pillShownAt = false, os.clock()
    pillRoot.Visible = true
    UI.pillGroup.GroupTransparency = 1
    UI.pillShadow.ImageTransparency = 1
    UI.pillGroup.Position = UDim2.new()
    pillRoot.Size = UDim2.fromOffset(UI.PILL_H, UI.PILL_H)
    pillRoot.Position = UDim2.fromOffset(pillPos.X, pillPos.Y - 8)
    tween(pillRoot, 0.6, { Position = UDim2.fromOffset(pillPos.X, pillPos.Y), Size = pillWidth() }, EASE.Quint, DIR.Out)
    tween(UI.pillGroup, 0.3, { GroupTransparency = 0 }, EASE.Quad, DIR.Out)
    tween(UI.pillShadow, 0.45, { ImageTransparency = 0.55 })
end
local function hidePill()
    C.pillHiding = true
    if C.island then C.island.close() end
    tween(UI.pillGroup, 0.22, { GroupTransparency = 1 }, EASE.Quad, DIR.In)
    tween(UI.pillShadow, 0.2, { ImageTransparency = 1 }, EASE.Quad, DIR.In)
    tween(pillRoot, 0.28, { Position = UDim2.fromOffset(pillPos.X, pillPos.Y - 6), Size = UDim2.fromOffset(UI.PILL_H, UI.PILL_H) }, EASE.Quint, DIR.In)
        .Completed:Connect(function()
            if holder.Visible then
                pillRoot.Visible = false
                placePill(pillPos)
                pillRoot.Size = pillWidth()
            end
        end)
end

local busyWindow = false
local function minimise()
    if busyWindow or not holder.Visible then return end
    busyWindow = true
    tooltip.hide()
    if UI.animateWindow(false) then showPill() end
    busyWindow = false
end
local function restore()
    if busyWindow or holder.Visible then return end
    busyWindow = true
    tooltip.hide()
    UI.resetControls()
    hidePill()
    UI.animateWindow(true)
    busyWindow = false
end
UI.minBtn.MouseButton1Click:Connect(minimise)
minimiseWindow = minimise
C.pillRestore = restore

-- press / drag / release
do
    local pressing, pressAt, startPos, target, follow = false, nil, nil, nil, nil
    -- ease the pill toward the pointer each frame: quick, but never jerky
    local function glide()
        if follow then return end
        -- a float, not read back from the whole-pixel offset (see the window's
        -- glide: that stalled short of the target and never finished)
        local pos = Vector2.new(pillRoot.Position.X.Offset, pillRoot.Position.Y.Offset)
        follow = RunService.RenderStepped:Connect(function(dt)
            pos = pos:Lerp(target, 1 - math.exp(-dt * 30))
            if not pillDragging and (target - pos).Magnitude < 0.3 then
                pos = target
                follow:Disconnect()
                follow = nil
            end
            placePill(pos)
        end)
        conns[#conns + 1] = follow
    end
    -- The pill and the Dynamic Island are one thing to your hand: press
    -- either, anywhere, and it's the same press, drag and drop.
    local island = C.island
    local releaseConn, pressKind, pressInput = nil, nil, nil
    -- One way out of a press, whichever way it ends: a real release (a click
    -- or a drop), a cancelled press, or a mouse release that never arrived
    -- (let go over other UI, alt-tab) -- which left the pill glued to the cursor.
    local function release(asClick)
        if not pressing then return end
        if releaseConn then releaseConn:Disconnect(); releaseConn = nil end
        pressing = false
        if island then island.press(false) end
        if pillDragging then
            -- drop: settle back down, remember the spot
            pillDragging = false
            tween(UI.pillGroup, 0.35, { Position = UDim2.new() }, EASE.Back)
            tween(UI.pillShadow, 0.3, { ImageTransparency = 0.55 })
            if island then island.lift(false) end
            paintPill()
            settings.pillX, settings.pillY = math.floor(pillPos.X + 0.5), math.floor(pillPos.Y + 0.5)
            saveSettings()
        else
            paintPill()
            if asClick then
                sfx("click")
                task.spawn(restore)             -- a click
            end
        end
    end
    local function press(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        if pressing then return end
        pressing, pressAt, startPos, pressKind, pressInput = true, input.Position, pillPos, t, input
        tween(pill, 0.08, { BackgroundColor3 = hex("#18181b") })
        if island then island.press(true) end
        releaseConn = input.Changed:Connect(function()
            local st = input.UserInputState
            if st == Enum.UserInputState.End then release(true)
            elseif st == Enum.UserInputState.Cancel then release(false) end
        end)
    end
    pill.InputBegan:Connect(press)
    if island and island.hit then island.hit.InputBegan:Connect(press) end
    conns[#conns + 1] = UIS.InputChanged:Connect(function(input)
        if not pressing then return end
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
        -- only the finger that pressed the pill drags it (not the thumbstick's)
        if t == Enum.UserInputType.Touch and input ~= pressInput then return end
        -- the mouse moved with the button already up: the release went missing
        if t == Enum.UserInputType.MouseMovement and pressKind == Enum.UserInputType.MouseButton1
           and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            release(false)
            return
        end
        local d = input.Position - pressAt
        if not pillDragging and Vector2.new(d.X, d.Y).Magnitude > 4 then
            -- pick up: rise 2px off its shadow, which deepens
            pillDragging = true
            tooltip.hide()
            tween(UI.pillGroup, 0.2, { Position = UDim2.fromOffset(0, -2) })
            tween(UI.pillShadow, 0.2, { ImageTransparency = 0.3 })
            if island then island.lift(true) end
            paintPill()
        end
        if pillDragging then
            pillPos = clampPill(startPos + Vector2.new(d.X, d.Y))
            target = pillPos
            glide()
        end
    end)
end

-- RightShift shows / hides the window
conns[#conns + 1] = UIS.InputBegan:Connect(function(input)
    -- MM2 marks RightShift as game-processed, so the flag is ignored; typing
    -- in a text box is the one case where the key should not toggle
    if input.KeyCode ~= Enum.KeyCode.RightShift or UIS:GetFocusedTextBox() then return end
    if holder.Visible then task.spawn(minimise) else task.spawn(restore) end
end)

local savedPos
toggleMaximise = function()
    if busyWindow then return end
    busyWindow = true
    tooltip.hide()
    if UI.stopWindowGlide then UI.stopWindowGlide() end
    UI.maximised = not UI.maximised
    local cam = UI.viewport()
    local target, pos
    if UI.maximised then
        savedPos = holder.Position
        target = Vector2.new(math.max(UI.BASE.X, math.floor(cam.X - 80)), math.max(UI.BASE.Y, math.floor(cam.Y - 80)))
        pos = UDim2.fromScale(0.5, 0.5)
    else
        target = UI.BASE
        local ox, oy = UI.clampOffset(savedPos and savedPos.X.Offset or 0, savedPos and savedPos.Y.Offset or 0, UI.BASE.X, UI.BASE.Y)
        pos = UDim2.new(0.5, ox, 0.5, oy)
    end
    UI.winW, UI.winH = target.X, target.Y
    UI.maxIcon.Image = UI.maximised and ICON.minimize2 or ICON.maximize
    local tw = tween(holder, 0.35, { Size = UDim2.fromOffset(target.X, target.Y), Position = pos }, EASE.Quint, DIR.InOut)
    tw.Completed:Wait()
    UI.refreshBackdrop(UI.winW, UI.winH)
    busyWindow = false
end
UI.maxBtn.MouseButton1Click:Connect(function() task.spawn(toggleMaximise) end)
UI.closeBtn.MouseButton1Click:Connect(function()
    if busyWindow then return end
    busyWindow = true
    tooltip.hide()
    UI.animateWindow(false)
    -- Closing Onyx takes the skins off your hands and back, so put the
    -- inventory back too (real counts, your real knife and gun equipped) --
    -- it kept showing spawned skins you could no longer see. Only here, not
    -- on a re-run, and the "Restore my skins on join" list is left alone.
    local eng = UI.engine
    if eng and eng.despawnAll then pcall(eng.despawnAll) end
    if UI.store.cleanup then UI.store.cleanup() end
end)

-- The screen changed size (fullscreen toggled, the Roblox window resized):
-- keep the window grabbable. A normal window is re-clamped at once; a
-- maximised one is re-fitted to the new screen once the resize settles.
UI.fitToken = 0
conns[#conns + 1] = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    if busyWindow or not holder.Visible or holder.Parent ~= gui then return end
    if not UI.maximised then
        local p = holder.Position
        local ox, oy = UI.clampOffset(p.X.Offset, p.Y.Offset, UI.winW, UI.winH)
        holder.Position = UDim2.new(0.5, ox, 0.5, oy)
        return
    end
    UI.fitToken += 1
    local mine = UI.fitToken
    task.delay(0.2, function()
        if mine ~= UI.fitToken or not gui.Parent or busyWindow or not UI.maximised then return end
        local cam = UI.viewport()
        local target = Vector2.new(math.max(UI.BASE.X, math.floor(cam.X - 80)), math.max(UI.BASE.Y, math.floor(cam.Y - 80)))
        if target.X == UI.winW and target.Y == UI.winH then return end
        UI.winW, UI.winH = target.X, target.Y
        local tw = tween(holder, 0.3, { Size = UDim2.fromOffset(target.X, target.Y), Position = UDim2.fromScale(0.5, 0.5) }, EASE.Quint, DIR.Out)
        tw.Completed:Wait()
        if mine == UI.fitToken and gui.Parent then UI.refreshBackdrop(UI.winW, UI.winH) end
    end)
end)

--// Home ----------------------------------------------------------
-- Where Onyx opens: a small dashboard, after the inspiration the user sent
-- (Finora, AIFlow, a glass storage dashboard) but kept in Onyx's own dark
-- monochrome. Up top: your avatar (a soft pulse leaving it every few
-- seconds), a greeting, your name and the time. Then three numbers on cards
-- with tinted icon chips; a
-- live chart of your FPS (or ping) over the last minute; a status list next
-- to the Discord and YouTube cards; and "Made in Germany" at the foot.
-- Opening, the cards rise into place one after another, the numbers roll in
-- and the chart draws itself in from the left. Built in a function of its
-- own, so its locals stay out of the main chunk's 200 registers.
function UI.buildHome()
    local tabOf = {}
    for _, t in ipairs(TABS) do tabOf[t.id] = t end
    local tab = tabOf.home
    local page = make("CanvasGroup", {
        Name = "HomePage", BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1, Visible = false,
        Position = UI.listClip.Position, Size = UI.listClip.Size, ZIndex = 2, Parent = win,
    })
    corner(page, 12)
    tab.page = page

    local scroll = make("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 1,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = C.borderHi,
        VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, Parent = page,
    })
    pad(scroll, 2, 6, UI.SEARCH_Y - UI.LIST_TOP, 16)
    local list = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10),
                                        HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = scroll })
    C.edgeFade(page, scroll)
    local fitPage = UI.snapPage(page)
    -- Home again while it's open: back to the top
    function tab.toTop()
        if scroll.CanvasPosition.Y > 0 then tween(scroll, 0.5, { CanvasPosition = Vector2.zero }, EASE.Quint, DIR.Out) end
    end

    -- Each block sits in a slot the list lays out, and moves inside it: that's
    -- what lets it rise into place (a list pins its children's positions).
    local cards = {}
    local function slot(h, order)
        local s = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, h), LayoutOrder = order, Parent = scroll })
        local inner = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = s })
        cards[#cards + 1] = inner
        return inner
    end
    -- a card: dark, a faint light along its top like glass, and under the
    -- pointer its edge lights a step and its surface lifts a shade
    local CARD_HOT = C.field:Lerp(WHITE, 0.025)
    local function card(parent, pos, size)
        local c = make("Frame", { BackgroundColor3 = C.field, BorderSizePixel = 0, Position = pos or UDim2.new(),
            Size = size or UDim2.fromScale(1, 1), Parent = parent })
        corner(c, 14)
        local st = stroke(c, C.border)
        local sheen = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 44), Parent = c })
        corner(sheen, 14)
        make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.955, 1), Parent = sheen })
        c.MouseEnter:Connect(function()
            tween(st, 0.18, { Color = C.borderHi })
            tween(c, 0.22, { BackgroundColor3 = CARD_HOT })
        end)
        c.MouseLeave:Connect(function()
            tween(st, 0.22, { Color = C.border })
            tween(c, 0.3, { BackgroundColor3 = C.field })
        end)
        return c
    end
    -- Words that change don't just switch: the old ones lift a little and
    -- fade, the new ones rise in from a few pixels below (like the Dynamic
    -- Island's). The first words of an empty label only rise in.
    local swapTo, swapTok, swapBase = {}, {}, {}
    local function swapText(label, str)
        if (swapTo[label] or label.Text) == str then return end
        swapTo[label] = str
        swapTok[label] = (swapTok[label] or 0) + 1
        local mine = swapTok[label]
        local base = swapBase[label] or label.Position
        swapBase[label] = base
        local function riseIn()
            if swapTok[label] ~= mine then return end
            label.Text = str
            label.Position, label.TextTransparency = base + UDim2.fromOffset(0, 6), 1
            tween(label, 0.4, { Position = base, TextTransparency = 0 }, EASE.Quint, DIR.Out)
        end
        if label.Text == "" then riseIn(); return end
        tween(label, 0.13, { TextTransparency = 1, Position = base + UDim2.fromOffset(0, -4) }, EASE.Quad, DIR.In)
            .Completed:Connect(riseIn)
    end
    -- an icon in a small circle tinted its colour
    local function chip(parent, icon, tint, size, pos)
        local d = make("Frame", { BackgroundColor3 = tint:Lerp(C.field, 0.84), BorderSizePixel = 0, Position = pos,
            Size = UDim2.fromOffset(size, size), Parent = parent })
        corner(d, FULL)
        stroke(d, tint:Lerp(C.field, 0.62))
        image({ Image = icon, ImageColor3 = tint, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(math.floor(size * 0.5), math.floor(size * 0.5)), Parent = d })
        return d
    end

    --// the header: avatar, greeting and name on the left, the time on the right
    local head = slot(58, 1)
    local av = image({ Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(LocalPlayer.UserId),
        BackgroundColor3 = C.tile, BackgroundTransparency = 0, ImageTransparency = 1, AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(46, 46), Parent = head })
    corner(av, FULL)
    stroke(av, C.borderHi, 1.5)
    -- The picture fades in once Roblox has it, rather than popping in.
    -- (Fetched by hand: Roblox doesn't load a picture that's fully see-
    -- through, so waiting for IsLoaded on it waited forever. 3s at most.)
    task.spawn(function()
        local done = false
        task.delay(3, function()
            if not done then done = true; tween(av, 0.45, { ImageTransparency = 0 }) end
        end)
        pcall(function() game:GetService("ContentProvider"):PreloadAsync({ av.Image }) end)
        if not done then done = true; tween(av, 0.45, { ImageTransparency = 0 }) end
    end)
    local dot = make("Frame", { BackgroundColor3 = C.green, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, -5, 1, -5), Size = UDim2.fromOffset(11, 11), ZIndex = 2, Parent = av })
    corner(dot, FULL)
    stroke(dot, C.bg, 2.5)
    local greetL = text({ Text = "Welcome,", FontFace = geist(FW.Medium), TextSize = 13, TextColor3 = C.muted,
        Position = UDim2.fromOffset(62, 7), Size = UDim2.new(1, -230, 0, 16), Parent = head })
    local nameL = text({ Text = LocalPlayer.DisplayName, FontFace = C.STAT_FONT, TextSize = 26, TextColor3 = WHITE,
        TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(62, 24), Size = UDim2.new(1, -230, 0, 30), Parent = head })
    make("UIGradient", { Rotation = 90, Color = C.STAT_SILVER, Parent = nameL })
    local clock = C.odometer({ parent = head, font = C.STAT_FONT, size = 22, height = 24, color = WHITE,
        gradient = C.STAT_SILVER, anchor = Vector2.new(1, 0), position = UDim2.new(1, -2, 0, 6) })
    local dateL = text({ Text = "", FontFace = geist(FW.Medium), TextSize = 12, TextColor3 = C.subtle,
        TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -4, 0, 34), Size = UDim2.fromOffset(220, 14), Parent = head })

    --// three numbers, each on its card with a tinted icon chip
    local kpiRow = slot(96, 2)
    local kpis = {}
    local function kpi(icon, tint, title, sub)
        local c = card(kpiRow, nil, UDim2.fromOffset(180, 96))
        -- (the chip stays put under the pointer: only the Discord and YouTube
        -- cards' marks grow)
        chip(c, icon, tint, 30, UDim2.fromOffset(14, 14))
        text({ Text = title, FontFace = geist(FW.SemiBold), TextSize = 12, TextColor3 = C.muted, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(52, 22), Size = UDim2.new(1, -62, 0, 14), Parent = c })
        local k = { card = c }
        k.value = C.odometer({ parent = c, font = C.STAT_FONT, size = 22, height = 24, color = WHITE,
            gradient = C.STAT_SILVER, position = UDim2.fromOffset(12, 51) })
        k.sub = text({ Text = sub, TextSize = 11, TextColor3 = C.subtle, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(14, 78), Size = UDim2.new(1, -28, 0, 13), Parent = c })
        kpis[#kpis + 1] = k
        return k
    end
    local kExec = kpi(ICON.globe, C.blurple, "Executions", "Concurrent")
    local kSession = kpi(ICON.clock, C.amber, "Session", "Since you ran Onyx")
    local kPlayers = kpi(ICON.users, C.teal, "Players", "In this server")
    -- three across, placed by hand so the last one ends exactly on the
    -- page's right edge (whole-pixel thirds came up short)
    local function layoutKpis()
        local w = kpiRow.AbsoluteSize.X / unscale()
        if w >= 120 then                       -- (skipping a passing in-between size)
            local cw = (w - 20) / 3
            for i, k in ipairs(kpis) do
                local x0 = math.floor((i - 1) * (cw + 10) + 0.5)
                local x1 = math.floor((i - 1) * (cw + 10) + cw + 0.5)
                k.card.Position, k.card.Size = UDim2.fromOffset(x0, 0), UDim2.fromOffset(x1 - x0, 96)
            end
        end
        -- and the page's width again: it's snapped to the grid by its
        -- right-most card, and measured mid-resize, before these moved, it
        -- took the maximised window's cards and stuck far too narrow
        -- ("squished to the left" after maximise and back)
        if fitPage then task.defer(fitPage) end
    end
    kpiRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutKpis)
    layoutKpis()

    --// the live chart: FPS (or ping) over the last minute
    local perf = card(slot(150, 3))
    chip(perf, ICON.activity, C.muted, 30, UDim2.fromOffset(14, 14))
    text({ Text = "Performance", FontFace = geist(FW.SemiBold), TextSize = 13,
        Position = UDim2.fromOffset(52, 13), Size = UDim2.fromOffset(200, 16), Parent = perf })
    text({ Text = "Live, over the last minute", TextSize = 11, TextColor3 = C.subtle,
        Position = UDim2.fromOffset(52, 30), Size = UDim2.fromOffset(220, 13), Parent = perf })
    -- the switch: FPS | PING, a raised knob gliding under the one that's on
    local metric = "fps"
    local seg = make("Frame", { BackgroundColor3 = C.tile, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 16), Size = UDim2.fromOffset(112, 26), Parent = perf })
    corner(seg, FULL)
    stroke(seg, C.border)
    local knob = make("Frame", { BackgroundColor3 = C.pill, BorderSizePixel = 0, Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(0.5, -2, 1, -4), Parent = seg })
    corner(knob, FULL)
    stroke(knob, C.borderHi)
    local segL = {}
    local refreshBubble
    local function pick(m)
        metric = m
        tween(knob, 0.34, { Position = UDim2.new(m == "fps" and 0 or 0.5, m == "fps" and 2 or 0, 0, 2) })
        for k, l in pairs(segL) do tween(l, 0.2, { TextColor3 = k == m and C.text or C.subtle }) end
        if refreshBubble then refreshBubble() end
    end
    for i, m in ipairs({ "fps", "ping" }) do
        local b = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
            Position = UDim2.fromScale((i - 1) / 2, 0), Size = UDim2.fromScale(0.5, 1), ZIndex = 2, Parent = seg })
        segL[m] = text({ Text = m == "fps" and "FPS" or "PING", FontFace = geist(FW.SemiBold), TextSize = 11,
            TextColor3 = m == metric and C.text or C.subtle, TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = b })
        b.MouseEnter:Connect(function() if metric ~= m then tween(segL[m], 0.15, { TextColor3 = C.muted }) end end)
        b.MouseLeave:Connect(function() if metric ~= m then tween(segL[m], 0.2, { TextColor3 = C.subtle }) end end)
        b.MouseButton1Click:Connect(function()
            if metric == m then return end
            sfx("click")
            pick(m)
        end)
    end
    -- the plot: three faint guides, the line (2px, over a soft 8px glow),
    -- a dot on the newest point with a ring pulsing out of it, and a bubble
    -- with the newest value
    local plot = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 58),
        Size = UDim2.new(1, -32, 1, -70), Parent = perf })
    for k = 0, 2 do
        make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.95, BorderSizePixel = 0,
            Position = UDim2.fromScale(0, k / 2), Size = UDim2.new(1, 0, 0, 1), Parent = plot })
    end
    local topL = text({ Text = "", FontFace = geist(FW.Medium), TextSize = 10, TextColor3 = C.subtle,
        TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(90, 12), Parent = plot })
    local N, SAMPLE = 48, 1.25             -- 48 points, one every 1.25s: a minute
    local segs, glows = {}, {}
    for i = 1, N - 1 do
        glows[i] = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, Parent = plot })
        corner(glows[i], FULL)
        segs[i] = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
            Visible = false, ZIndex = 2, Parent = plot })
        corner(segs[i], FULL)
    end
    local tip = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(7, 7), Visible = false, ZIndex = 3, Parent = plot })
    corner(tip, FULL)
    local pulse = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false,
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(7, 7), ZIndex = 3, Parent = tip })
    corner(pulse, FULL)
    local pulseSt = stroke(pulse, WHITE, 1, 0.2)
    UI.loop(TweenService:Create(pulse, TweenInfo.new(1.6, EASE.Quint, DIR.Out, -1), { Size = UDim2.fromOffset(22, 22) }), pulse)
    UI.loop(TweenService:Create(pulseSt, TweenInfo.new(1.6, EASE.Quint, DIR.Out, -1), { Transparency = 1 }), pulse)
    local bubble = make("Frame", { BackgroundColor3 = C.pill, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 1),
        Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Visible = false, ZIndex = 4, Parent = plot })
    corner(bubble, 6)
    local bubbleSt = stroke(bubble, C.borderHi, 1, 1)
    pad(bubble, 5, 5)
    bubble:SetAttribute("NoSnap", true)
    -- the newest value rolls its digits like every other number (and from
    -- "FPS" to "ms" when the switch flips)
    local bubbleVal = C.odometer({ parent = bubble, font = C.STAT_FONT, size = 11, height = 14, color = WHITE,
        position = UDim2.fromOffset(0, 3) })
    bubbleVal.alpha(1)
    -- the dot and the bubble fade in once the line has drawn itself
    local tipShown = false
    local function showTip(on)
        tipShown = on
        pulse.Visible = on
        local t = on and 0.35 or 0
        if t == 0 then
            tip.BackgroundTransparency, bubble.BackgroundTransparency, bubbleSt.Transparency = 1, 1, 1
            bubbleVal.alpha(1)
            return
        end
        tween(tip, t, { BackgroundTransparency = 0 })
        tween(bubble, t, { BackgroundTransparency = 0 })
        tween(bubbleSt, t, { Transparency = 0 })
        bubbleVal.alpha(0, t)
    end

    -- the samples, kept even while Home is closed so the chart opens full
    local hist, yDisp = { fps = {}, ping = {} }, {}
    local lastSample = os.clock()
    local function pingNow()
        local ms
        pcall(function() ms = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
        return ms
    end
    local function sample()
        table.insert(hist.fps, UI.fps or hist.fps[#hist.fps] or 60)
        table.insert(hist.ping, pingNow() or hist.ping[#hist.ping] or 0)
        table.insert(yDisp, false)
        if #hist.fps > N then table.remove(hist.fps, 1); table.remove(hist.ping, 1); table.remove(yDisp, 1) end
        lastSample = os.clock()
    end
    task.spawn(function()
        while gui.Parent do
            sample()
            task.wait(SAMPLE)
        end
    end)
    -- the chart's top: a round number a little above the highest point
    local function niceTop(v)
        for _, s in ipairs({ 30, 60, 120, 180, 240, 300, 360, 480, 600, 900, 1200, 2000, 5000 }) do
            if v <= s then return s end
        end
        return math.ceil(v / 1000) * 1000
    end
    function refreshBubble()
        local d = hist[metric]
        local v = d[#d]
        bubbleVal.set(v and (metric == "fps" and ("%d FPS"):format(v) or ("%d ms"):format(math.floor(v + 0.5))) or "")
    end
    -- Drawn every frame while Home is on screen: the whole line glides one
    -- step left between samples (the newest point always comes in at the
    -- right edge), each point eases to its height (a new sample, a new top
    -- or the switch between FPS and ping all morph rather than jump), and
    -- on opening it draws itself in from the left (reveal).
    local reveal = make("NumberValue", { Value = 1 })
    local shownNow, topShown = false, 60
    conns[#conns + 1] = RunService.RenderStepped:Connect(function(dt)
        if not shownNow then return end
        local data = hist[metric]
        local n = #data
        local sc = unscale()
        local w, h = plot.AbsoluteSize.X / sc, plot.AbsoluteSize.Y / sc
        if n < 2 or w < 20 then
            tip.Visible, bubble.Visible = false, false
            if tipShown then showTip(false) end
            return
        end
        local hi = 0
        for _, v in ipairs(data) do if v > hi then hi = v end end
        local top = niceTop(hi * 1.12)
        local ease = 1 - math.exp(-dt * 7)
        topShown += (top - topShown) * (1 - math.exp(-dt * 4))
        local step = w / (N - 1)
        local frac = math.clamp((os.clock() - lastSample) / SAMPLE, 0, 1)
        local cut = reveal.Value * w
        local xs, ys = {}, {}
        for i = 1, n do
            local want = math.clamp(h - 2 - (data[i] / topShown) * (h - 6), 1, h - 1)
            local y = yDisp[i]
            y = (y and y + (want - y) * ease) or want
            yDisp[i] = y
            xs[i], ys[i] = w - (n - i + frac) * step, y
        end
        for i = 1, N - 1 do
            local s, g = segs[i], glows[i]
            local x1, x2 = xs[i], xs[i + 1]
            if x1 and x2 and x1 >= 0 and x2 <= cut then
                local y1, y2 = ys[i], ys[i + 1]
                local dx, dy = x2 - x1, y2 - y1
                local len, mid = math.sqrt(dx * dx + dy * dy), UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
                local rot = math.deg(math.atan2(dy, dx))
                s.Position, s.Size, s.Rotation, s.Visible = mid, UDim2.fromOffset(len + 1.5, 2), rot, true
                g.Position, g.Size, g.Rotation, g.Visible = mid, UDim2.fromOffset(len + 6, 8), rot, true
            else
                s.Visible, g.Visible = false, false
            end
        end
        local lx, ly = xs[n], ys[n]
        local done = reveal.Value > 0.98
        tip.Visible, bubble.Visible = true, true
        if done ~= tipShown then showTip(done) end
        if done then
            tip.Position = UDim2.fromOffset(lx, ly)
            -- (kept inside the chart, whatever its width)
            local bw = bubble.AbsoluteSize.X / sc
            bubble.Position = UDim2.fromOffset(math.clamp(lx - 7, math.min(bw, w), w), math.max(ly - 7, 22))
        end
        local label = metric == "fps" and tostring(top) or (top .. " ms")
        swapText(topL, label)
    end)

    --// a status list (like an uploads list: each line ticked off), with the
    --// Discord and YouTube cards beside it
    local bottom = slot(132, 4)
    local stC = card(bottom, nil, UDim2.new(0.5, -5, 1, 0))
    text({ Text = "Status", FontFace = geist(FW.SemiBold), TextSize = 13,
        Position = UDim2.fromOffset(16, 13), Size = UDim2.new(1, -32, 0, 16), Parent = stC })
    local ROW_Y, ROW_H = 36, 22
    local function statusRow(i, icon, label)
        local y = ROW_Y + (i - 1) * ROW_H
        if i > 1 then
            make("Frame", { BackgroundColor3 = C.border, BackgroundTransparency = 0.35, BorderSizePixel = 0,
                Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, 1), Parent = stC })
        end
        local mid = y + ROW_H / 2
        image({ Image = icon, ImageColor3 = C.subtle, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(16, mid),
            Size = UDim2.fromOffset(14, 14), Parent = stC })
        text({ Text = label, FontFace = geist(FW.Medium), TextSize = 12, TextColor3 = C.muted, AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.fromOffset(38, mid), Size = UDim2.fromOffset(120, 14), Parent = stC })
        local r = { state = nil }
        r.value = text({ Text = "", FontFace = geist(FW.SemiBold), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -34, 0, mid),
            Size = UDim2.fromOffset(130, 14), Parent = stC })
        -- on the right: a green tick when it's fine, a dot otherwise
        r.tick = image({ Image = ICON.check, ImageColor3 = C.greenText, ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, -20, 0, mid), Size = UDim2.fromOffset(12, 12), Parent = stC })
        C.bolden(r.tick, 0.5)
        r.dot = make("Frame", { BackgroundColor3 = C.subtle, BackgroundTransparency = 1, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -20, 0, mid), Size = UDim2.fromOffset(7, 7), Parent = stC })
        corner(r.dot, FULL)
        return r
    end
    -- state: "ok" (a tick), "live" (a green dot), "busy" (amber), "off" (grey)
    local function setRow(r, value, state)
        swapText(r.value, value)
        if state == r.state then return end
        r.state = state
        tween(r.value, 0.25, { TextColor3 = state == "live" and C.greenText or state == "off" and C.subtle or C.text })
        tween(r.tick, 0.25, { ImageTransparency = state == "ok" and 0 or 1 })
        tween(r.dot, 0.25, { BackgroundTransparency = state == "ok" and 1 or 0,
            BackgroundColor3 = state == "live" and C.green or state == "busy" and C.amber or C.subtle })
    end
    local rExec = statusRow(1, ICON.cpu, "Executor")
    local rSkins = statusRow(2, ICON.tabSkin, "Skin Changer")
    local rFarm = statusRow(3, ICON.tabFarm, "Autofarm")
    local rIsland = statusRow(4, ICON.phone, "Dynamic Island")

    -- Discord and YouTube, stacked on the right. Each whole card is the
    -- button and copies its link (like the Discord tag up top); pointed at,
    -- it lights a step and its mark grows a little.
    local right = make("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.5, 5, 0, 0),
        Size = UDim2.new(0.5, -5, 1, 0), Parent = bottom })
    local function social(o)
        local c = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = o.bg, BorderSizePixel = 0,
            Position = o.position, Size = UDim2.new(1, 0, 0.5, -5), Parent = right })
        corner(c, 14)
        local st = stroke(c, o.edge)
        local mark = o.logo(c)                                        -- (the mark sits at x=30, centred)
        local crisp = UI.crispTwin(mark)                              -- (sharp at rest: see UI.crispTwin)
        local markScale = make("UIScale", { Parent = mark })
        text({ Text = o.title, FontFace = geist(FW.SemiBold), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(56, 14), Size = UDim2.new(1, -66, 0, 16), Parent = c })
        text({ Text = o.sub, TextSize = 12, TextColor3 = o.subColor, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(56, 32), Size = UDim2.new(1, -66, 0, 14), Parent = c })
        local over, popTok = false, 0
        local hotBg, hotEdge = o.bg:Lerp(o.edge, 0.3), o.edge:Lerp(o.ink, 0.45)
        -- The mark pops like the tab icons: a quick grow past its size with a
        -- small tilt, then it settles at 120% and straightens; leaving, it
        -- glides back down evenly (a quick ease made both feel like clicks).
        c.MouseEnter:Connect(function()
            over = true
            sfx("hover")
            tween(c, 0.18, { BackgroundColor3 = hotBg })
            tween(st, 0.18, { Color = hotEdge })
            popTok += 1
            local mine = popTok
            crisp.set(false)
            local up = TweenService:Create(markScale, TweenInfo.new(0.16, EASE.Quad, DIR.Out), { Scale = 1.28 })
            up:Play()
            TweenService:Create(mark, TweenInfo.new(0.16, EASE.Quad, DIR.Out), { Rotation = -8 }):Play()
            up.Completed:Connect(function()
                if popTok ~= mine then return end
                TweenService:Create(markScale, TweenInfo.new(0.32, EASE.Sine, DIR.InOut), { Scale = 1.2 }):Play()
                TweenService:Create(mark, TweenInfo.new(0.4, EASE.Back, DIR.Out), { Rotation = 0 }):Play()
            end)
        end)
        c.MouseLeave:Connect(function()
            over = false
            tween(c, 0.22, { BackgroundColor3 = o.bg })
            tween(st, 0.22, { Color = o.edge })
            popTok += 1
            TweenService:Create(markScale, TweenInfo.new(0.42, EASE.Sine, DIR.InOut), { Scale = 1 }):Play()
            TweenService:Create(mark, TweenInfo.new(0.42, EASE.Sine, DIR.InOut), { Rotation = 0 }):Play()
            crisp.set(true, 0.2, 0.26)
        end)
        c.MouseButton1Down:Connect(function()
            C.ripple(c, 14)
            tween(c, 0.06, { BackgroundColor3 = o.bg })
        end)
        c.MouseButton1Up:Connect(function() tween(c, 0.18, { BackgroundColor3 = over and hotBg or o.bg }) end)
        c.MouseButton1Click:Connect(function()
            sfx("click")
            o.onClick()
        end)
    end
    social({
        position = UDim2.new(), bg = C.blurpleBg, edge = C.blurpleEdge, ink = C.blurple, subColor = C.blurpleText,
        title = "Join the Onyx Discord", sub = "Updates, configs and support",
        logo = function(c)
            return image({ Image = ICON.discord, ImageRectOffset = UI.DISCORD_CELL.offset, ImageRectSize = UI.DISCORD_CELL.size,
                ImageColor3 = C.blurple, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 30, 0.5, 0),
                Size = UDim2.fromOffset(24, 24), Parent = c })
        end,
        onClick = function() if UI.copyInvite then UI.copyInvite() end end,
    })
    -- YouTube's mark drawn the way the logo is: a red rounded box with a
    -- white play triangle in it (no filled YouTube logo in the icon sets)
    local YT = "youtube.com/@OnyxScripts"
    social({
        position = UDim2.new(0, 0, 0.5, 5), bg = C.redBg, edge = C.redEdge, ink = C.red, subColor = hex("#fca5a5"),
        title = "Subscribe on YouTube", sub = YT,
        logo = function(c)
            local box = make("Frame", { BackgroundColor3 = hex("#ff0033"), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 30, 0.5, 0), Size = UDim2.fromOffset(26, 18), Parent = c })
            corner(box, 5)
            image({ Image = ICON.play, ImageRectOffset = UI.PLAY_CELL.offset, ImageRectSize = UI.PLAY_CELL.size, ImageColor3 = WHITE,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 1, 0.5, 0), Size = UDim2.fromOffset(9, 9), Parent = box })
            return box
        end,
        onClick = function()
            if UI.copyText and UI.copyText("https://" .. YT) then
                notify({ title = "Link copied", body = YT .. " is on your clipboard", kind = "youtube", key = "youtube" })
            else
                notify({ title = "Subscribe on YouTube", body = YT, kind = "youtube", key = "youtube", duration = 6 })
            end
        end,
    })

    --// Made in Germany: the page's signature, at its foot. A small German
    -- flag and the words in spaced-out heavy caps running through the flag's
    -- colours, standing still -- the user didn't want them animated, only a
    -- swoosh: every few seconds (and once as Home opens) one quick, crisp
    -- streak of white light sweeps across, a slanted streak over the flag and
    -- a flash running through the letters. (No glow behind either: the user
    -- had it taken out.) A spacer above takes up whatever room the page has
    -- left, so it always sits at the bottom.
    local spacer = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, 0), LayoutOrder = 98, Parent = scroll })
    local foot = slot(34, 99)
    local fRow = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 2, Parent = foot })
    hlist(fRow, 2)
    -- the flag: 25 x 15, so each stripe is a whole 5px, with a hairline round
    -- it so the black stripe still reads on the dark page; the swoosh's
    -- streak runs through it, clipped to its shape
    local flag = make("CanvasGroup", { BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = UDim2.fromOffset(25, 15),
        LayoutOrder = 1, ZIndex = 2, Parent = fRow })
    corner(flag, 3)
    stroke(flag, C.borderHi, 1, 0.2)
    for i, col in ipairs({ hex("#000000"), hex("#dd0000"), hex("#ffce00") }) do
        make("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, Position = UDim2.fromOffset(0, (i - 1) * 5),
            Size = UDim2.new(1, 0, 0, 5), ZIndex = 2, Parent = flag })
    end
    local streak = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -20, 0.5, 0), Size = UDim2.fromOffset(5, 34),
        Rotation = 22, ZIndex = 3, Parent = flag })
    make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = streak })
    make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(8, 16), LayoutOrder = 2, Parent = fRow })   -- (air after the flag)
    -- the words: a label per letter, 2px apart like the caption's
    local letters = {}
    for i, code in utf8.codes("MADE IN GERMANY") do
        local ch = utf8.char(code)
        if ch == " " then
            make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(3, 16), LayoutOrder = 10 + i, Parent = fRow })
        else
            local l = text({ Text = ch, FontFace = C.STAT_FONT, TextSize = 12, TextColor3 = WHITE,
                TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X,
                LayoutOrder = 10 + i, ZIndex = 2, Parent = fRow })
            letters[#letters + 1] = { label = l, grad = make("UIGradient", { Color = C.STAT_SILVER, Parent = l }), c0 = WHITE, c1 = WHITE }
        end
    end
    -- One gradient across the whole line, through the flag: black (a
    -- charcoal, so the M still reads on the dark page), red, gold. Each
    -- letter carries its own piece of it, from where it starts to where it
    -- ends, so the colours flow on from letter to letter; re-cut whenever
    -- the letters re-measure.
    local FLAG_RAMP = { { 0, hex("#64646e") }, { 0.42, hex("#e8202a") }, { 1, hex("#ffce00") } }
    local function flagAt(t)
        t = math.clamp(t, 0, 1)
        for k = 2, #FLAG_RAMP do
            local a, b = FLAG_RAMP[k - 1], FLAG_RAMP[k]
            if t <= b[1] then return a[2]:Lerp(b[2], (t - a[1]) / (b[1] - a[1])) end
        end
        return FLAG_RAMP[#FLAG_RAMP][2]
    end
    local function paintLetters()
        local first, last = letters[1].label, letters[#letters].label
        local x0 = first.AbsolutePosition.X
        local span = last.AbsolutePosition.X + last.AbsoluteSize.X - x0
        if span <= 0 then return end
        for _, L in ipairs(letters) do
            L.c0 = flagAt((L.label.AbsolutePosition.X - x0) / span)
            L.c1 = flagAt((L.label.AbsolutePosition.X + L.label.AbsoluteSize.X - x0) / span)
            L.grad.Color = ColorSequence.new(L.c0, L.c1)
        end
    end
    fRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(paintLetters)
    task.defer(paintLetters)
    -- the spacer fills what the page has left
    local function fillSpacer()
        local sc = unscale()
        local avail = scroll.AbsoluteWindowSize.Y / sc - (UI.SEARCH_Y - UI.LIST_TOP) - 16
        local used = list.AbsoluteContentSize.Y / sc - spacer.Size.Y.Offset
        local want = math.max(0, math.floor(avail - used))
        if want ~= spacer.Size.Y.Offset then spacer.Size = UDim2.new(1, -2, 0, want) end
    end
    list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fillSpacer)
    scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(fillSpacer)
    task.defer(fillSpacer)

    -- The swoosh: a narrow band of white light crossing the line left to
    -- right in about a second (half a second was too quick for the user),
    -- quicker in the middle and easing at the ends. Over the flag it's the slanted streak; over each letter, the
    -- letter's own colours flash toward white as the band goes by.
    local swooshing = false
    local function swoosh()
        if swooshing then return end
        swooshing = true
        local t, conn = 0, nil
        conn = RunService.RenderStepped:Connect(function(dt)
            t += dt
            local sc = unscale()
            local band, x0, w = 20 * sc, fRow.AbsolutePosition.X, fRow.AbsoluteSize.X
            local p = math.clamp(t / 1.05, 0, 1)
            local bx = x0 - band + (w + band * 2) * (0.5 - 0.5 * math.cos(math.pi * p))
            streak.Position = UDim2.new(0, (bx - flag.AbsolutePosition.X) / sc, 0.5, 0)
            for _, L in ipairs(letters) do
                local d = math.abs(L.label.AbsolutePosition.X + L.label.AbsoluteSize.X / 2 - bx)
                local k = d < band and (0.5 + 0.5 * math.cos(math.pi * d / band)) or 0
                L.grad.Color = ColorSequence.new(L.c0:Lerp(WHITE, 0.85 * k), L.c1:Lerp(WHITE, 0.85 * k))
            end
            if p >= 1 or not gui.Parent then
                conn:Disconnect()
                for _, L in ipairs(letters) do L.grad.Color = ColorSequence.new(L.c0, L.c1) end
                streak.Position = UDim2.new(0, -20, 0.5, 0)
                swooshing = false
            end
        end)
    end
    task.spawn(function()
        while gui.Parent do
            task.wait(5)
            if shownNow then swoosh() end
        end
    end)
    -- opening: one swoosh once the cards have risen into place
    local function footIntro()
        task.delay(0.9, function() if shownNow then swoosh() end end)
    end

    --// keeping it live
    local t0 = os.clock()
    local executor = "Unknown"
    pcall(function()
        local n = identifyexecutor and identifyexecutor()
        if type(n) == "string" and n ~= "" then executor = n end
    end)
    local function refresh()
        local hour = tonumber(os.date("%H")) or 12
        local greet = hour < 5 and "Good night" or hour < 12 and "Good morning" or hour < 18 and "Good afternoon" or "Good evening"
        swapText(greetL, LocalPlayer.DisplayName ~= LocalPlayer.Name and ("%s, @%s"):format(greet, LocalPlayer.Name) or (greet .. ","))
        clock.set(os.date("%H:%M"))
        swapText(dateL, ("%s, %d %s"):format(os.date("%A"), tonumber(os.date("%d")) or 1, os.date("%B")))
        local secs = math.floor(os.clock() - t0)
        kExec.value.set("1 Million")
        kSession.value.set(secs >= 3600 and ("%dh %02dm"):format(secs // 3600, (secs % 3600) // 60)
            or ("%dm %02ds"):format(secs // 60, secs % 60), false, 1)        -- time only ever rolls up
        kPlayers.value.set(("%d/%d"):format(#Players:GetPlayers(), Players.MaxPlayers))
        refreshBubble()
        setRow(rExec, executor, "ok")
        local skins = UI.engine and UI.engine.list
        setRow(rSkins, skins and (#skins .. " skins") or "Loading", skins and "ok" or "busy")
        local farmOn = false
        if C.farmHud then
            local ok, f = pcall(C.farmHud)
            farmOn = ok and type(f) == "table" and f.running == true
        end
        setRow(rFarm, farmOn and "Farming" or "Off", farmOn and "live" or "off")
        local island = settings.island ~= false
        setRow(rIsland, island and "On" or "Off", island and "ok" or "off")
    end
    -- Opening: the blocks rise into place one after another (the page fades
    -- in around them), the numbers roll in from nothing, and the chart
    -- draws itself in from the left
    function tab.onShow()
        shownNow = true
        for i, c in ipairs(cards) do
            c.Position = UDim2.fromOffset(0, 16)
            TweenService:Create(c, TweenInfo.new(0.6, EASE.Quint, DIR.Out, 0, false, 0.05 * (i - 1)),
                { Position = UDim2.new() }):Play()
        end
        for _, k in ipairs(kpis) do k.value.set("0", true) end
        reveal.Value = 0
        TweenService:Create(reveal, TweenInfo.new(1.2, EASE.Quint, DIR.Out, 0, false, 0.25), { Value = 1 }):Play()
        footIntro()
        task.delay(0.18, function() pcall(refresh) end)
    end
    task.spawn(function()
        while gui.Parent do
            shownNow = UI.shown(page)
            if shownNow then pcall(refresh) end
            task.wait(0.5)
        end
    end)
    -- Onyx opens here: Home showing, the Skin Changer's page hidden until you pick it
    UI.skinPage.Visible = false
    page.Visible, page.GroupTransparency = true, 0
    UI.tabCaption = tab.caption
    UI.setTracked(tab.caption, { color = C.subtle, instant = true })
    pcall(refresh)
    task.delay(0.1, tab.onShow)
end
UI.buildHome()

-- open
task.spawn(UI.animateWindow, true)

--// Skin Changer engine --------------------------------------

-- Onyx's skin engine, embedded whole and wrapped in a function.
--
-- The wrapper is load-bearing, not style: this script sits at 177 of Luau's
-- 200 registers per function and the spawner declares 109 of its own. Pasted at
-- top level that is an instant "Out of local registers" and nothing compiles.
-- Inside a function its locals get their own budget.
--
-- Not called at load. It reads and compiles ~260KB of mesh data, which would put
-- the 0.25s startup back into the seconds. Kicked off in the background once
-- the UI exists, and the grid fills in when it lands.
local function initSpawner()
--[[
    Onyx — Skin Changer engine  (client-side)
    ----------------------------------------------------------------
    • Pick a weapon from the list -> it goes into your inventory.
    • Equip it from the NORMAL MM2 inventory -> it renders on your character
      with the real mesh / size / effects, holstered and in-hand.
    • Spawn all / Despawn all. Despawn restores the counts you started with
      rather than deleting weapons you actually own.

    Godly and Ancient only (171 weapons). Pink outline = Godly, purple =
    Ancient, [Chroma] tag on chroma variants.

    Why it polls instead of listening:
      The live MM2 inventory equips by writing ProfileData.Weapons.Equipped and
      firing the remote DIRECTLY — it never calls EquipService.EquipItem, so
      EquippedChanged never fires. This POLLS ProfileData.Weapons.Equipped,
      which every equip path writes to, so it catches the equip either way.

    Mesh data is read from a file on this PC -- see MESH_FILE below. That file
    is the `local MESHES_FULL = {...}` table on its own; this is just the logic.

    Reality check (FilteringEnabled): client-side only — only you see it; it
    can't be used for real combat. The spawn itself is a local ProfileData spoof.
--]]

local CONFIG = {
    InjectParticles = true,   -- ParticleEmitter / Fire / Smoke / Sparkles / Lights
    HideOriginal    = true,   -- hide your real held weapon so only the spawn shows
    PollRate        = 0.1,    -- how often to check for an equip change (seconds)
}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService     = game:GetService("InsertService")
local LocalPlayer       = Players.LocalPlayer

pcall(function() if setthreadidentity then setthreadidentity(2) end end)

-- re-runnable: tear down any previous instance
if UI.store.engineDestroy then pcall(UI.store.engineDestroy) end
-- the store only learns this run's token (to tell a newer run apart) and how
-- to shut it down, never the engine itself
local SELF = { conns = {}, tok = {} }
UI.store.engine = SELF.tok
UI.store.engineDestroy = function() if SELF.destroy then SELF.destroy() end end

local ClientServices = ReplicatedStorage:WaitForChild("ClientServices")
local EquipService = require(ClientServices:WaitForChild("EquipService"))
local Sync         = require(ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync"))
local ProfileData  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData"))
local WeaponDB     = Sync.Weapons -- == Sync.Item (full weapon database)
local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local InvDataChanged = Remotes:WaitForChild("Inventory"):WaitForChild("InventoryDataChanged")

-------------------------------------------------------------------------------
-- Embedded weapon mesh data (scraped from the game)
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Weapon mesh data comes from a file on this PC, not the web: modelfetch.txt,
-- kept in the executor's workspace at OnyxV2/modelfetch.txt (executors can only
-- read inside their own workspace). The file is plain Luau data that returns a
-- table of weapons, one `W.Name = {...}` block each (its header explains the
-- layout). Older copies are one big `local MESHES_FULL = {...}` instead; those
-- still load, a return appended inside the same chunk hands that local over.
-- Update the models by replacing that file; nothing is downloaded.
-------------------------------------------------------------------------------
local MESH_FILE = "OnyxV2/modelfetch.txt"

local MESHES_FULL
do
    if not (isfile and readfile) then
        error("[Onyx] this executor can't read files, so the skin models can't load", 0)
    end
    if not isfile(MESH_FILE) then
        error("[Onyx] " .. MESH_FILE .. " is missing -- put modelfetch.txt in the workspace's OnyxV2 folder", 0)
    end
    local ok, body = pcall(readfile, MESH_FILE)
    if not ok or type(body) ~= "string" or #body < 1000 then
        error("[Onyx] couldn't read " .. MESH_FILE, 0)
    end
    local oldFormat = body:find("local%s+MESHES_FULL%s*=") ~= nil
    local chunk, err = loadstring(oldFormat and (body .. "\nreturn MESHES_FULL") or body)
    if not chunk then
        error("[Onyx] " .. MESH_FILE .. " failed to compile -- " .. tostring(err), 0)
    end
    local ran, res = pcall(chunk)
    if not ran then
        error("[Onyx] " .. MESH_FILE .. " failed to load -- " .. tostring(res), 0)
    end
    MESHES_FULL = res
    if type(MESHES_FULL) ~= "table" or next(MESHES_FULL) == nil then
        error("[Onyx] " .. MESH_FILE .. " returned no weapons", 0)
    end
    -- pictures carried in the file (for skins whose game thumbnail never loads)
    for key, entry in pairs(MESHES_FULL) do
        local pic = type(entry) == "table" and entry.Picture
        if type(pic) == "table" and type(pic.file) == "string" and type(pic.data) == "string" then
            UI.pictures[key] = pic
        end
    end
end

local MESHES = {}
for k, v in pairs(MESHES_FULL) do MESHES[k] = v end
MESHES_FULL = nil

-------------------------------------------------------------------------------
-- Plain Sweet never got captured -- the scrape has SweetChroma and no "Sweet".
-- MM2 layers chroma as a separate Decal named "Chroma" over the base model (the
-- plain/chroma diffs show it: Deathshard has no decal, DeathshardChroma has
-- exactly one), so derive the plain one by cloning SweetChroma without it.
--
-- Caveat worth knowing: on Deathshard the chroma variant ALSO carries its own
-- base texture, so this is only exact if Sweet's chroma is purely the decal. It
-- is a reconstruction, not scraped data.
-------------------------------------------------------------------------------
do
    local src = MESHES.SweetChroma
    if src and src.Model and not MESHES.Sweet then
        local function copy(node)
            local out = { Class = node.Class, Id = node.Id, Name = node.Name,
                          Props = node.Props, Tags = node.Tags }
            if node.Children then
                out.Children = {}
                for _, ch in ipairs(node.Children) do
                    if not (ch.Class == "Decal" and ch.Name == "Chroma") then
                        out.Children[#out.Children + 1] = copy(ch)
                    end
                end
            end
            return out
        end
        local meta = {}
        for k, v in pairs(src.Meta or {}) do meta[k] = v end
        meta.Chroma = nil                     -- or startChroma would rainbow it
        MESHES.Sweet = { Complete = false, Meta = meta, Model = copy(src.Model) }
    end
end

-------------------------------------------------------------------------------
-- Keep only what this script is for: Godly and Ancient weapons that we can
-- actually draw. Everything downstream -- the browse list, the name box, the
-- holster and the in-hand overlay -- reads MESHES, so filtering here is the
-- single place that enforces it.
--
-- The mesh-data half of the test matters as much as the rarity half. MM2 lists
-- Sweet and SweetChroma as two separate Godly knives sharing the display name
-- "Sweet", but the scrape only ever captured SweetChroma -- so plain Sweet could
-- be spawned and then render nothing. That is the "sweet chroma works, sweet
-- doesn't" case, and it is also what used to wedge the in-hand overlay. If we
-- cannot draw it, it does not belong here.
-------------------------------------------------------------------------------
local ALLOWED_RARITY = { Godly = true, Ancient = true, Legendary = true, Unique = true, Classic = true }

-- Unreleased items ship with their name masked (Emptybringer / EmptybringerChroma
-- are both ItemName = "???"). Matching the mask means future ones drop out too.
local function isPlaceholderName(n)
    n = tostring(n or "")
    return n == "" or n:match("^%?+$") ~= nil
end

do
    local kept, dropped = {}, 0
    for key, mesh in pairs(MESHES) do
        local info = WeaponDB[key]
        if type(info) == "table"
            and (info.ItemType == "Knife" or info.ItemType == "Gun")
            and ALLOWED_RARITY[info.Rarity]
            and not isPlaceholderName(info.ItemName)
        then kept[key] = mesh else dropped = dropped + 1 end
    end
    MESHES = kept
end

local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function trimAsset(v)
    if type(v) == "string" then return (v:gsub("^%s+", ""):gsub("%s+$", "")) end
    return v
end

local function applyProps(inst, props, skip)
    for k, v in pairs(props) do
        if not (skip and skip[k]) then
            if k == "MeshId" or k == "TextureId" or k == "TextureID" or k == "Texture" then v = trimAsset(v) end
            -- The engine runs at identity 2 (to require MM2's modules), and
            -- there a SurfaceAppearance's maps (ColorMap, TexturePack...) need
            -- the Plugin capability -- the texture silently never landed and
            -- the mesh showed bare. When the plain write fails, step the
            -- thread up for that one write and straight back down.
            if not pcall(function() inst[k] = v end) and setthreadidentity and getthreadidentity then
                local was = getthreadidentity()
                pcall(setthreadidentity, 8)
                pcall(function() inst[k] = v end)
                pcall(setthreadidentity, was)
            end
        end
    end
end

-- MeshPart via CreateMeshPartAsync (STRING signature works on Potassium), rescaled.
-- Each mesh is fetched once and kept: CreateMeshPartAsync takes ~1s, which was
-- the gap between clicking a skin and it reaching your hand. Later builds clone
-- the kept one instantly (and the list is preloaded in the background).
local MESHPART_TPL = {}
local function meshPartTemplate(meshId)
    local tpl = MESHPART_TPL[meshId]
    if tpl == "loading" then                  -- someone else is fetching it: wait for theirs
        local t0 = os.clock()
        while MESHPART_TPL[meshId] == "loading" and os.clock() - t0 < 10 do task.wait() end
        tpl = MESHPART_TPL[meshId]
    end
    if tpl == nil then
        MESHPART_TPL[meshId] = "loading"
        pcall(function()
            tpl = game:GetService("InsertService"):CreateMeshPartAsync(meshId, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
        end)
        MESHPART_TPL[meshId] = tpl or false
    end
    return (typeof(tpl) == "Instance") and tpl or nil
end
local function createMeshPart(props)
    local meshId = trimAsset(props.MeshId or "")
    local size = props.Size or Vector3.new(1, 1, 1)
    local part
    local tpl = meshPartTemplate(meshId)
    if tpl then pcall(function() part = tpl:Clone() end) end
    if part then pcall(function() part.Size = size end); return part end
    local p = Instance.new("Part"); p.Size = size
    local sm = Instance.new("SpecialMesh"); sm.MeshType = Enum.MeshType.FileMesh
    pcall(function() sm.MeshId = meshId end); pcall(function() sm.TextureId = trimAsset(props.TextureID or "") end)
    sm.Parent = p
    return p
end

-------------------------------------------------------------------------------
-- Chroma (rainbow-cycle the "Chroma" decal / part)
-------------------------------------------------------------------------------
local CHROMA = {
    Color3.fromRGB(255,0,0), Color3.fromRGB(255,255,0), Color3.fromRGB(0,255,0),
    Color3.fromRGB(0,255,255), Color3.fromRGB(0,0,255), Color3.fromRGB(255,0,255),
}
local function chromaColor(t)
    local n = #CHROMA; local phase = t % n; local i = math.floor(phase)
    return CHROMA[i + 1]:Lerp(CHROMA[((i + 1) % n) + 1], phase - i)
end
local function isChroma(name, data)
    if data.Meta and data.Meta.Chroma == true then return true end
    return name:sub(-6) == "Chroma"
end
local CHROMA_FLASH_RATE = 1.8              -- bulb colour snaps per second
local CHROMA_LAYER = "rbxassetid://18363392181" -- MM2's neutral chroma texture
local function startChroma(overlay)
    -- bulbs (ChromaPart) FLASH; the garland/strip (ChromaDecal) smoothly RGBs.
    -- Prefer exact roles from scraped chroma tags (attribute "MM2Chroma"); if the
    -- data has no tags, fall back to a SAFE heuristic that never touches the green
    -- tree decal (only Neon parts flash; only "chroma"-named decals cycle).
    local flashParts, smoothDecals, smoothOther, smoothMeshes = {}, {}, {}, {}
    local tagged = false
    for _, d in ipairs(overlay:GetDescendants()) do
        local role = d:GetAttribute("MM2Chroma")
        if role then
            tagged = true
            if role == "part" then flashParts[#flashParts + 1] = d
            elseif role == "decal" and d:IsA("Decal") then
                pcall(function() d.Texture = CHROMA_LAYER end) -- neutral -> clean RGB, no muddy tint
                smoothDecals[#smoothDecals + 1] = d
            elseif role == "fire" then smoothOther[#smoothOther + 1] = d end
        end
    end
    if not tagged then
        for _, d in ipairs(overlay:GetDescendants()) do
            if d:IsA("BasePart") and (d.Material == Enum.Material.Neon or d.Name:lower():find("light")) then
                flashParts[#flashParts + 1] = d
            elseif d:IsA("Decal") and d.Name:lower():find("chroma") then
                smoothDecals[#smoothDecals + 1] = d
            elseif d:IsA("Fire") then
                smoothOther[#smoothOther + 1] = d
            end
        end
        -- No dedicated chroma decal? Then the chroma element is the ROOT part's
        -- COLOUR — e.g. the red Christmas strip showing through the transparent
        -- parts of the (opaque) green tree decal, or a whole-mesh chroma. The green
        -- tree decal is opaque so it stays green; only the strip area cycles.
        if #smoothDecals == 0 then
            smoothOther[#smoothOther + 1] = overlay
        end
    end

    -- A textured SpecialMesh IGNORES its part's Color, so on those weapons the
    -- cycle above ran correctly and changed nothing on screen -- Deathshard
    -- Chroma's root Color was sweeping 0.68,1,0 -> 0.07,1,0 while the blade sat
    -- there fully textured. VertexColor is the tint that actually lands, so
    -- gather every textured mesh hanging off a part we are already cycling.
    local cycling = {}
    for _, s in ipairs(smoothOther) do if s:IsA("BasePart") then cycling[s] = true end end
    for _, b in ipairs(flashParts) do cycling[b] = nil end   -- those flash, handled below
    for _, d in ipairs(overlay:GetDescendants()) do
        if d:IsA("SpecialMesh") and d.TextureId ~= "" and cycling[d.Parent] then
            smoothMeshes[#smoothMeshes + 1] = d
        end
    end
    if overlay:IsA("Part") and cycling[overlay] then
        local sm = overlay:FindFirstChildWhichIsA("SpecialMesh")
        if sm and sm.TextureId ~= "" then smoothMeshes[#smoothMeshes + 1] = sm end
    end

    if #flashParts == 0 and #smoothDecals == 0 and #smoothOther == 0 and #smoothMeshes == 0 then return nil end

    local conn = RunService.Heartbeat:Connect(function()
        local now = os.clock()
        local col = chromaColor(now)
        for _, s in ipairs(smoothDecals) do s.Color3 = col end
        for _, s in ipairs(smoothMeshes) do s.VertexColor = Vector3.new(col.R, col.G, col.B) end
        for _, s in ipairs(smoothOther) do
            if s:IsA("Fire") then s.Color = col elseif s:IsA("BasePart") then s.Color = col end
        end
        local step = math.floor(now * CHROMA_FLASH_RATE)
        for i, b in ipairs(flashParts) do
            b.Color = CHROMA[((step + i - 1) % #CHROMA) + 1]
        end
    end)
    -- Dies with its overlay, however the overlay goes: MM2 destroying the
    -- display part on respawn, a re-apply, a re-execution. Before, only an
    -- explicit cleanup stopped it, so one leaked every round.
    overlay.Destroying:Once(function() conn:Disconnect() end)
    return conn
end

-------------------------------------------------------------------------------
-- Overlay builders
-------------------------------------------------------------------------------
local STRUCTURAL = { WeldConstraint=true, Weld=true, Motor6D=true, RigidConstraint=true, Bone=true, Snap=true, ManualWeld=true, Rotate=true, RotateP=true, RotateV=true }

-- carry over MM2 chroma tags (ChromaPart/ChromaDecal/ChromaFire) as an attribute
local function chromaTag(inst, node)
    if not (inst and node.Tags) then return end
    for _, t in ipairs(node.Tags) do
        local r = (t == "ChromaPart" and "part") or (t == "ChromaDecal" and "decal") or (t == "ChromaFire" and "fire") or nil
        if r then pcall(function() inst:SetAttribute("MM2Chroma", r) end) end
    end
end

local function instantiateNode(node)
    local cls = node.Class
    if STRUCTURAL[cls] then return nil end
    local inst
    if cls == "MeshPart" then
        inst = createMeshPart(node.Props)
        applyProps(inst, node.Props, { MeshId = true, Size = true, RelCF = true, CanCollide = true })
    else
        local ok, res = pcall(Instance.new, cls)
        if not ok or not res then return nil end
        inst = res
        applyProps(inst, node.Props, { RelCF = true })
    end
    -- Name lives on the NODE, not inside Props, so applyProps never copied it and
    -- every rebuilt instance kept its class default. That is what broke chroma:
    -- MM2's chroma layer is a Decal named "Chroma", startChroma matches on that
    -- name, and the rebuilt decal was arriving called "Decal".
    if node.Name then pcall(function() inst.Name = node.Name end) end
    chromaTag(inst, node)
    return inst
end

-- PHASE 1: create the whole tree (may YIELD on MeshParts). Collect BaseParts +
-- their RelCF. No positioning/welding yet — that happens in finalizeOverlay,
-- after a FRESH CFrame read, so async delays can't strand parts at a stale spot.
local function rebuildTree(node, parentInst, root, idToInst, parts, deferred)
    for _, child in ipairs(node.Children or {}) do
        local inst = instantiateNode(child)
        if inst then
            idToInst[child.Id] = inst
            if inst:IsA("BasePart") then
                inst.Anchored, inst.CanCollide, inst.CanQuery, inst.CanTouch, inst.Massless = false, false, false, false, true
                parts[#parts + 1] = { inst = inst, relcf = child.Props.RelCF }
                inst.Parent = root
                rebuildTree(child, inst, root, idToInst, parts, deferred)
            elseif inst:IsA("Attachment") then
                if child.Props.RelCF then pcall(function() inst.CFrame = child.Props.RelCF end) end
                inst.Parent = root
                rebuildTree(child, inst, root, idToInst, parts, deferred)
            elseif inst:IsA("Beam") or inst:IsA("Trail") then
                inst.Parent = parentInst
                deferred[#deferred + 1] = { inst = inst, a0 = child.Att0, a1 = child.Att1 }
                rebuildTree(child, inst, root, idToInst, parts, deferred)
            else
                inst.Parent = parentInst
                rebuildTree(child, inst, root, idToInst, parts, deferred)
            end
        else
            rebuildTree(child, parentInst, root, idToInst, parts, deferred) -- skipped joint
        end
    end
end

local function buildFullOverlay(data)
    local rn = data.Model
    if not rn then return nil end
    local root
    if rn.Class == "MeshPart" then
        root = createMeshPart(rn.Props)
        applyProps(root, rn.Props, { MeshId = true, Size = true, RelCF = true, CanCollide = true })
    else
        root = Instance.new("Part")
        applyProps(root, rn.Props, { RelCF = true, CanCollide = true })
    end
    if rn.Name then pcall(function() root.Name = rn.Name end) end
    chromaTag(root, rn)
    root.Anchored, root.CanCollide, root.CanQuery, root.CanTouch, root.Massless = false, false, false, false, true
    local idToInst = { [rn.Id] = root }
    local parts, deferred = {}, {}
    rebuildTree(rn, root, root, idToInst, parts, deferred)
    for _, d in ipairs(deferred) do
        if d.a0 and idToInst[d.a0] then pcall(function() d.inst.Attachment0 = idToInst[d.a0] end) end
        if d.a1 and idToInst[d.a1] then pcall(function() d.inst.Attachment1 = idToInst[d.a1] end) end
    end
    return { root = root, parts = parts }
end

-- PHASE 2: SYNCHRONOUS. Place root at targetCF, children at targetCF*RelCF, weld.
local function finalizeOverlay(built, targetCF)
    local root = built.root
    pcall(function() root.CFrame = targetCF end)
    for _, p in ipairs(built.parts) do
        if p.relcf then pcall(function() p.inst.CFrame = targetCF * p.relcf end) end
        -- a Weld with the offset written in, not a WeldConstraint: that one
        -- measures the gap when it switches on, a frame or so later -- if you
        -- were walking, the skin kept that gap and hung back behind you
        local w = Instance.new("Weld"); w.Part0 = root; w.Part1 = p.inst
        w.C0 = root.CFrame:ToObjectSpace(p.inst.CFrame); w.Parent = p.inst
    end
    return root
end

-- OLD flat format (weapons without a full tree)
local PARTICLE_CLASSES = { ParticleEmitter=true, Fire=true, Smoke=true, Sparkles=true, PointLight=true, SpotLight=true, SurfaceLight=true }
local function buildFlatOverlay(data)
    local root, meshes, decals, effects
    do
        root, meshes, decals, effects = nil, {}, {}, {}
        for _, e in ipairs(data.Display or {}) do
            if e.Path == "(root)" then root = e
            elseif e.Class == "SpecialMesh" then meshes[#meshes+1] = e
            elseif e.Class == "Decal" or e.Class == "Texture" then decals[#decals+1] = e
            elseif PARTICLE_CLASSES[e.Class] then effects[#effects+1] = e end
        end
    end
    if not root then return nil end
    local part
    if root.Class == "MeshPart" then
        part = createMeshPart(root.Props)
        applyProps(part, root.Props, { MeshId = true, Size = true, CanCollide = true })
    else
        part = Instance.new("Part"); part.Size = root.Props.Size or Vector3.new(1,1,1)
        applyProps(part, root.Props, { Size = true, CanCollide = true })
        for _, m in ipairs(meshes) do
            local sm = Instance.new("SpecialMesh"); sm.MeshType = Enum.MeshType.FileMesh
            applyProps(sm, m.Props); sm.Parent = part
        end
    end
    part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.Massless = false, false, false, false, true
    if root.Name then pcall(function() part.Name = root.Name end) end
    for _, d in ipairs(decals) do
        local dc = Instance.new("Decal"); applyProps(dc, d.Props)
        if d.Name then pcall(function() dc.Name = d.Name end) end   -- "Chroma" matters here too
        dc.Parent = part
    end
    for _, e in ipairs(effects) do
        local ok, inst = pcall(Instance.new, e.Class)
        if ok and inst then
            applyProps(inst, e.Props)
            if e.Name then pcall(function() inst.Name = e.Name end) end
            inst.Parent = part
        end
    end
    return { root = part, parts = {} }
end

local function buildAnyOverlay(data)
    if data.Model then return buildFullOverlay(data) end
    if data.Display then return buildFlatOverlay(data) end
    return nil
end

-- mesh id of a weapon (for the "is the game already showing this?" check)
local function targetMeshId(data)
    if data.Model then
        local rn = data.Model
        if rn.Class == "MeshPart" then return trimAsset(rn.Props.MeshId or "") end
        for _, c in ipairs(rn.Children or {}) do
            if c.Class == "SpecialMesh" then return trimAsset(c.Props.MeshId or "") end
        end
        return ""
    end
    for _, e in ipairs(data.Display or {}) do
        if e.Path == "(root)" and e.Class == "MeshPart" then return trimAsset(e.Props.MeshId or "") end
        if e.Class == "SpecialMesh" then return trimAsset(e.Props.MeshId or "") end
    end
    return ""
end
local function baseMeshId(base)
    if not base then return "" end
    if base:IsA("MeshPart") then return trimAsset(base.MeshId or "") end
    local sm = base:FindFirstChildWhichIsA("SpecialMesh", true)
    return sm and trimAsset(sm.MeshId or "") or ""
end

-------------------------------------------------------------------------------
-- Holster alignment
--
-- MM2 hangs a display weapon off a RigidConstraint: the display part carries an
-- Attachment (named "CustomAttachment" when the model ships one) that gets
-- pinned to a character attachment -- LowerTorso.GunBelt / UpperTorso.KnifeBack.
-- So the game's own placement is exactly
--     display.CFrame = anchor.WorldCFrame * weaponAttachment.CFrame:Inverse()
-- and that attachment is the ONLY thing encoding each weapon's mesh axis
-- convention (some guns are modelled barrel-along-X, others along Z, etc).
--
-- The overlay used to be parked at plain base.CFrame, which silently bakes in
-- the *base* weapon's attachment -- so every spawn inherited the orientation
-- correction of whatever weapon the server really has equipped, and the same
-- spawn looked different depending on your real loadout. Now we undo the base's
-- attachment and apply the spawned weapon's own.
-------------------------------------------------------------------------------
local ID = CFrame.identity

-- exact: the attachment shipped inside a scraped full model tree
local function findAttCF(node)
    for _, c in ipairs(node.Children or {}) do
        if c.Class == "Attachment" and c.Name == "CustomAttachment" and c.Props and c.Props.RelCF then
            return c.Props.RelCF
        end
        local r = findAttCF(c)
        if r then return r end
    end
    return nil
end

local function rootSize(data)
    if data.Model then return data.Model.Props and data.Model.Props.Size end
    for _, e in ipairs(data.Display or {}) do
        if e.Path == "(root)" then return e.Props and e.Props.Size end
    end
    return nil
end

-- "longest axis -> shortest axis" signature of the display part, e.g. "YZX"
local function axisProfile(size)
    if not size then return nil end
    local a = { { size.X, "X" }, { size.Y, "Y" }, { size.Z, "Z" } }
    table.sort(a, function(p, q) return p[1] > q[1] end)
    return a[1][2] .. a[2][2] .. a[3][2]
end

-- Group fallbacks for the ~650 weapons we only have flat display data for.
-- Built by clustering the 72 scraped CustomAttachments by item type + axis
-- profile. Groups whose models overwhelmingly ship NO attachment are left out
-- on purpose so they resolve to identity -- that is what MM2 itself does there
-- (DefaultKnife holsters correctly with an identity attachment). Knife_YZX is
-- 82:11 identity and Gun_YZX is 6:2, so those two stay identity.
-- These are approximations; the exact-data paths above always win.
local FALLBACK_ATT = {
    -- Gingerscope; 26 of the 43 guns in this group are within 10 deg of it
    Gun_ZYX   = CFrame.new(0.12991, -0.00003, 0.075, 1, 0, 0, 0, 0.70713, 0.70708, -0, -0.70708, 0.70713),
    Gun_ZXY   = CFrame.new(0.12991, 0, 0.07501, 0.00002, -0.5, -0.86603, 1, -0.00004, 0.00005, -0.00006, -0.86603, 0.5),   -- Harvester
    Gun_XYZ   = CFrame.new(-0.22989, 0.09821, 0.1, 0.00001, 0.98481, -0.17362, -0.00001, 0.17362, 0.98481, 1, -0.00001, 0.00001), -- ElderwoodGun
    Knife_YXZ = CFrame.new(0, 0, 0, -0.0446, -0.00031, -0.99901, 0.03549, 0.99937, -0.00189, 0.99837, -0.03553, -0.04456), -- Deathshard; all 5 within 1 deg
    Knife_ZYX = CFrame.new(0.00151, -0.12701, -0.15448, -0.99867, 0.03727, 0.03568, -0.04098, -0.15276, -0.98741, -0.03135, -0.98756, 0.15409), -- Clockwork
    -- no full-tree sample for Z-long-X-wide knives; they share Clockwork's blade axis
    Knife_ZXY = CFrame.new(0.00151, -0.12701, -0.15448, -0.99867, 0.03727, 0.03568, -0.04098, -0.15276, -0.98741, -0.03135, -0.98756, 0.15409),
}

-- Whatever the game actually shows us is ground truth. Remember the real
-- attachment per mesh id, so a spawn reusing that mesh is placed exactly -- this
-- is what covers the seasonal reskins, which all share a handful of meshes.
UI.store.learned = UI.store.learned or {}
local LEARNED = UI.store.learned
-- name -> CFrame, a hand-tuned pose for a weapon that still looks off.
-- OVERRIDE is the holster attachment, OVERRIDE_GRIP the in-hand rotation.
local OVERRIDE = {}
local OVERRIDE_GRIP = {}

-- The display's own holster attachment: the CustomAttachment it ships, else the
-- one its RigidConstraint pins to KnifeBack / GunBelt (MM2 makes that one, at
-- identity, for a display that ships none). Not just any attachment: a godly's
-- display carries effect attachments too.
local function baseAttachment(part)
    if not part then return nil end
    local a = part:FindFirstChild("CustomAttachment")
    if a and a:IsA("Attachment") then return a end
    for _, c in ipairs(part:GetChildren()) do
        if c:IsA("RigidConstraint") then
            if c.Attachment1 and c.Attachment1.Parent == part then return c.Attachment1 end
            if c.Attachment0 and c.Attachment0.Parent == part then return c.Attachment0 end
        end
    end
    a = part:FindFirstChild("Attachment")
    if a and a:IsA("Attachment") then return a end
    return part:FindFirstChildWhichIsA("Attachment")
end

-- a mesh by its number alone: the same mesh is written "rbxassetid://N" in one
-- place and "http://www.roblox.com/asset/?id=N" in another
function UI.meshNum(id)
    if type(id) ~= "string" then return "" end
    return id:match("id=(%d+)") or id:match("://(%d+)") or id:match("(%d+)") or ""
end

-- A weapon built from its tool handle shares its mesh, and with it its frame,
-- with the scraped reskins of the same weapon, so their real attachment is the
-- exact live answer for it too (Gold Minty hangs like the other Mintys, not by
-- a shape guess). Mesh -> attachment, built once on first use; siblings that
-- disagree are left out and the shape fallback decides.
function UI.siblingAttCF(data)
    local map = UI.siblingAtt
    if not map then
        map = {}
        local bad = {}
        for _, d in pairs(MESHES) do
            if d.Model and not (d.Meta and d.Meta.Handle) then
                local k = UI.meshNum(targetMeshId(d))
                if k ~= "" and not bad[k] then
                    local a = findAttCF(d.Model) or ID
                    if map[k] and map[k] ~= a then map[k], bad[k] = nil, true
                    else map[k] = a end
                end
            end
        end
        UI.siblingAtt = map
    end
    return map[UI.meshNum(targetMeshId(data))]
end

local function learnFrom(base)
    local k, a = UI.meshNum(baseMeshId(base)), baseAttachment(base)
    if k ~= "" and a then LEARNED[k] = a.CFrame end
end

local function weaponAttCF(name, data, slot)
    if OVERRIDE[name] then return OVERRIDE[name] end
    -- a scraped full tree is authoritative: no CustomAttachment in it means the
    -- real model has none either, and MM2 uses identity for those. (Not so for a
    -- weapon built from its tool handle, Meta.Handle: a handle has no display
    -- attachment at all, so those go by what the game showed us, then by a
    -- scraped sibling with the same mesh, then by their shape.)
    if data.Model and not (data.Meta and data.Meta.Handle) then return findAttCF(data.Model) or ID end
    local k = UI.meshNum(targetMeshId(data))
    if k ~= "" and LEARNED[k] then return LEARNED[k] end
    local sib = data.Meta and data.Meta.Handle and UI.siblingAttCF(data)
    if sib then return sib end
    local t = (data.Meta and data.Meta.ItemType) or slot
    -- A knife built from its tool handle is held by its real Grip, and that
    -- grip's turn is exactly how its mesh sits against MM2's standard knife
    -- (DefaultKnife: no turn in the hand, identity on the back). So it hangs
    -- by that same turn. The shape guess read Gingerscythe Ancient's nearly
    -- square mesh as Clockwork's and hung it upside down.
    if data.Meta and data.Meta.Handle and t == "Knife" and typeof(data.Meta.Grip) == "CFrame" then
        return data.Meta.Grip.Rotation
    end
    local p = axisProfile(rootSize(data))
    return (p and FALLBACK_ATT[t .. "_" .. p]) or ID
end

-- base.CFrame * baseAtt is the anchor's world CFrame (that is what the rigid
-- constraint guarantees), so this stays correct even while the character moves,
-- without a second world read that could tear against the first.
local function alignedCF(base, attCF)
    local a = baseAttachment(base)
    return base.CFrame * (a and a.CFrame or ID) * attCF:Inverse()
end

-------------------------------------------------------------------------------
-- hide / restore
-------------------------------------------------------------------------------
local function hideInto(list, inst)
    if inst:IsA("BasePart") or inst:IsA("Decal") then
        list[#list+1] = { inst = inst, prop = "Transparency", val = inst.Transparency }
        pcall(function() inst.Transparency = 1 end)
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
        list[#list+1] = { inst = inst, prop = "Enabled", val = inst.Enabled }
        pcall(function() inst.Enabled = false end)
    end
end
local function restore(hidden)
    for _, h in ipairs(hidden) do pcall(function() h.inst[h.prop] = h.val end) end
end

-- Hiding a Handle is not a one-shot. The SERVER puts Handle.Transparency back to
-- 0 when the throw animation returns the knife to your hand, and that replicates
-- straight over our local hide -- so the default mesh pops back in underneath the
-- skin and you see both. No client script does it, so there is nothing to hook;
-- we just re-assert the hide whenever the property drifts off 1.
local function keepHidden(hidden)
    local guards = {}
    for _, h in ipairs(hidden) do
        local inst, prop = h.inst, h.prop
        guards[#guards + 1] = inst:GetPropertyChangedSignal(prop):Connect(function()
            -- comparing first means the write is a no-op once settled, so this
            -- cannot retrigger itself. A write that gets past it is the
            -- server's own (the knife back from a throw): that is the value to
            -- put back when the skin comes off, not the one seen first -- a
            -- skin applied mid-throw had recorded the throw's temporary 1, and
            -- left the real knife invisible after the skin was removed.
            if prop == "Enabled" then
                if inst.Enabled then h.val = true; inst.Enabled = false end
            elseif inst.Transparency ~= 1 then
                h.val = inst.Transparency
                inst.Transparency = 1
            end
        end)
    end
    return guards
end
local function unguard(guards)
    for _, g in ipairs(guards or {}) do pcall(function() g:Disconnect() end) end
end

-------------------------------------------------------------------------------
-- Character / display refs
-------------------------------------------------------------------------------
local function char() return LocalPlayer.Character end
local function displayValue(slot)
    local c = char(); if not c then return nil end
    local ref = c:FindFirstChild("DisplayRef" .. slot)
    return ref and ref.Value or nil
end
local function waitDisplay(slot, timeout)
    local deadline = os.clock() + (timeout or 1)
    while os.clock() < deadline do
        local v = displayValue(slot); if v then return v end
        task.wait(0.05)
    end
    return displayValue(slot)
end

-------------------------------------------------------------------------------
-- LOBBY overlay (weld skin over the holstered DisplayRef weapon)
-------------------------------------------------------------------------------
local state, lastApplied, token = {}, {}, {}

-- Holster overlays are parented into the shared WeaponDisplays folder, NOT under
-- the character -- so state[slot] is not a reliable record of everything we made.
-- Two ways one gets orphaned and left rendering forever:
--   * the character respawns, MM2 destroys the display part our overlay was
--     welded to, and the overlay survives as a sibling in the folder
--   * two equips race: the second one's cleanup runs before the first has
--     assigned state[slot], then the first overwrites it and its overlay is lost
-- Sweeping by attribute catches both, and anything left by an earlier re-run.
local function sweepOverlays(slot, keep)
    local ws = workspace:FindFirstChild("WeaponDisplays")
    if not ws then return end
    for _, d in ipairs(ws:GetChildren()) do
        if d ~= keep and d:GetAttribute("_sl") == slot then
            pcall(function() d:Destroy() end)
        end
    end
end

local function cleanup(slot)
    sweepOverlays(slot)
    local st = state[slot]; if not st then return end
    if st.chroma then pcall(function() st.chroma:Disconnect() end) end
    if st.overlay then pcall(function() st.overlay:Destroy() end) end
    restore(st.hidden)
    state[slot] = nil
end

local matchChromaSize   -- set below realSize (a chroma drawn at its normal version's size)
local SIZE_BASE = {}    -- colour variant -> its normal weapon (filled below)
-- the weapon a clone copies: a colour variant's or a chroma's normal version
local function baseSkinOf(name)
    if type(name) ~= "string" then return nil end
    -- MM2 names chromas both ways: "LugerChroma" and "ChromaLightbringer"
    for _, b in ipairs({ SIZE_BASE[name] or false, name:match("^(.-)Chroma$") or false, name:match("^Chroma(.+)$") or false }) do
        if b and b ~= "" and b ~= name and MESHES[b] then return b end
    end
    return nil
end
-- The game already shows this exact item: same mesh AND same texture. Chromas
-- and colour variants reuse the normal weapon's mesh, so a mesh match alone
-- would leave your back showing the plain weapon instead of the variant.
local function sameLook(base, data, name)
    local mesh = baseMeshId(base)
    if mesh == "" or mesh ~= targetMeshId(data) then return false end
    if isChroma(name, data) or baseSkinOf(name) then return false end
    local have = ""
    if base:IsA("MeshPart") then have = base.TextureID or "" else
        local sm = base:FindFirstChildWhichIsA("SpecialMesh", true)
        have = sm and sm.TextureId or ""
    end
    local want = ""
    local function texOf(p) return p and (p.TextureID or p.TextureId) or "" end
    if data.Model then
        local rn = data.Model
        if rn.Class == "MeshPart" then want = texOf(rn.Props) else
            for _, c in ipairs(rn.Children or {}) do
                if c.Class == "SpecialMesh" then want = texOf(c.Props); break end
            end
        end
    else
        for _, e in ipairs(data.Display or {}) do
            if (e.Path == "(root)" and e.Class == "MeshPart") or e.Class == "SpecialMesh" then want = texOf(e.Props); break end
        end
    end
    return trimAsset(have) == trimAsset(want)
end
local function apply(slot, name)
    if state[slot] and lastApplied[slot] == name and name ~= nil then return end
    token[slot] = (token[slot] or 0) + 1
    local myToken = token[slot]
    cleanup(slot)
    local data = name and MESHES[name]
    if not data then lastApplied[slot] = name; return end
    lastApplied[slot] = name
    local base = displayValue(slot) or waitDisplay(slot, 1.5)
    if token[slot] ~= myToken then return end
    if not base then
        return
    end
    learnFrom(base)                                           -- record real attachment first
    if sameLook(base, data, name) then return end
    -- a clone sits on your back / side exactly where its normal version does
    -- (not one built from its own tool handle: the normal version's placement
    -- belongs to a different model, so it goes by its own)
    local handleBuilt = data.Meta and data.Meta.Handle
    local holsterKey = (not handleBuilt and baseSkinOf(name)) or name
    -- a hand-tuned pose for this exact skin wins (OVERRIDE is keyed by the
    -- skin's own name, which weaponAttCF(holsterKey) never looked up)
    local attCF = OVERRIDE[name] or weaponAttCF(holsterKey, MESHES[holsterKey] or data, slot)
    local built = buildAnyOverlay(data)                       -- phase 1 (may yield)
    if not built or not built.root or token[slot] ~= myToken or not base.Parent then
        if built and built.root then built.root:Destroy() end; return
    end
    -- Hide the real weapon only now, after the yield: hiding before it let a
    -- superseded apply() restore (un-hide) the weapon under the newer skin,
    -- and made the newer one record "already hidden" as the weapon's real look.
    local hidden = {}
    hideInto(hidden, base)
    for _, d in ipairs(base:GetDescendants()) do hideInto(hidden, d) end
    local targetCF = alignedCF(base, attCF)
    -- the offset from the display part, taken in the same instant as the
    -- target: reading base.CFrame again at weld time (after the resize,
    -- which can wait a frame) caught you mid-run or mid-jump, and the skin
    -- kept the gap -- frozen where you'd been until you re-equipped
    local baseRel = base.CFrame:ToObjectSpace(targetCF)
    finalizeOverlay(built, targetCF)                          -- phase 2 (fresh CFrame, synchronous)
    local overlay = built.root
    if matchChromaSize and not handleBuilt then pcall(matchChromaSize, overlay, name, data) end
    -- the resize can fetch a mesh and wait: a newer equip may have landed meanwhile
    if token[slot] ~= myToken or not base.Parent then
        restore(hidden); overlay:Destroy(); return
    end
    overlay:SetAttribute("_ov", true)
    overlay:SetAttribute("_sl", slot)
    overlay.Parent = base.Parent or base
    -- (exact offset, written in -- see finalizeOverlay)
    local w = Instance.new("Weld"); w.Part0 = base; w.Part1 = overlay
    w.C0 = baseRel * targetCF:ToObjectSpace(overlay.CFrame); w.Parent = overlay
    local chroma = isChroma(name, data) and startChroma(overlay) or nil
    sweepOverlays(slot, overlay)   -- kill anything a racing apply() left behind
    state[slot] = { overlay = overlay, hidden = hidden, chroma = chroma }
end

-------------------------------------------------------------------------------
-- Held-weapon alignment
--
-- A held weapon is posed by Tool.Grip, which is per-weapon and which we have no
-- scraped data for. The holster attachment is NOT a stand-in for it: normalising
-- the grip through it stands Harvester on end in your hand, because a crossbow
-- hangs on the belt nothing like a pistol does.
--
-- What does generalise is that every weapon gets posed into the SAME frame: the
-- hand mount, handle.CFrame * Tool.Grip. That resolves to RightHand.CFrame times
-- the hand's own grip attachment, so it is identical no matter which weapon the
-- server actually handed you -- read the Grip off the real tool and the live
-- handle drops out of the maths entirely.
--
-- So: put every gun in one fixed pose in that frame. The convention below is
-- read straight off MM2's own tools (standard gun 1.83/0.95/0.325 with a Ry(90)
-- grip; DefaultKnife 0.4/3/0.7 with an identity grip), which means a weapon
-- already modelled that way lands exactly on the handle -- identity, the old
-- behaviour -- and everything else is rotated into the same pose.
--
-- Which END of the long axis is the barrel is a coin flip we can't read off a
-- bounding box; a weapon that comes out backwards needs one tuneGrip() call.
-------------------------------------------------------------------------------
local AXIS = { X = Vector3.new(1,0,0), Y = Vector3.new(0,1,0), Z = Vector3.new(0,0,1) }

local function axisOrder(size)   -- longest, middle, shortest
    local a = { { size.X, "X" }, { size.Y, "Y" }, { size.Z, "Z" } }
    table.sort(a, function(p, q) return p[1] > q[1] end)
    return a[1][2], a[2][2], a[3][2]
end

-- images of the weapon's own long / middle / thin axis in hand-mount space
local CANON = {
    Gun   = { Vector3.new(0,0,1), Vector3.new(0,1,0), Vector3.new(-1,0,0) }, -- barrel out along -Z, height up, thin sideways
    Knife = { Vector3.new(0,1,0), Vector3.new(0,0,1), Vector3.new(1,0,0)  }, -- blade up, width back, thin sideways
}

-- Roll about the weapon's OWN long axis, on top of the canonical pose.
--
-- This is the one call a bounding box genuinely cannot make. CANON assumes the
-- middle axis is the weapon's height and belongs vertical, which holds for every
-- gun shape in the data -- a Luger is 0.51/1.18/1.35, mid IS its height. On a
-- crossbow the middle axis is the prod's span and belongs HORIZONTAL, so without
-- this the limbs come out spread vertically. Only Harvester and Icepiercer have
-- that shape (both 2.2448/0.6549/2.88); a mid:long ratio test would have caught
-- every Luger too, so this stays an explicit list.
-- negative quarter turn: +pi/2 also lays the limbs flat, but upside down
-- Applied in the weapon's OWN frame, after the canonical pose. Two failure modes
-- land here, both of which a bounding box genuinely cannot call:
--
--   * the axis sort is right but the roll is ambiguous -- a crossbow's second
--     axis is the prod's span (horizontal) where a gun's is its height
--     (vertical), same numbers, opposite meaning
--   * the Size is not the rendered shape at all -- Sweet's SpecialMesh is scaled
--     0.069, so Part.Size describes a box nothing is drawn in and the sort picks
--     a "long" axis that is not the blade
--
-- All measured in-game with tuneGrip, not derived.
local GRIP_TWEAK = {
    Harvester   = CFrame.Angles(0, 0, -math.pi / 2),  -- quarter turn about the long axis
    Icepiercer  = CFrame.Angles(0, 0, -math.pi / 2),
}

-- Weapons whose model is already authored in the handle's own convention, so the
-- canonical axis mapping should be skipped entirely and the overlay left sitting
-- exactly on the handle.
--
-- Sweet is the case that proved this exists: its SpecialMesh is scaled 0.069, so
-- the root Part's Size describes a box nothing is drawn in and axisOrder reads a
-- "long axis" that is not the blade. Every rotation derived from it was wrong.
-- Tuning it by hand converged on plain identity.
-- Half turns the axis mapping gets wrong, done in the weapon's own frame:
-- "muzzle" turns it about its height axis (barrel was pointing at you),
-- "upright" rolls it about its long axis (it was on its head).
local GRIP_FLIP = {
    SwirlyGun = "muzzle", SwirlyGunChroma = "muzzle", Jinglegun = "muzzle",
    Icebeam = "muzzle", Iceblaster = "muzzle",
    Minty = "upright", Sugar = "upright",
}

local GRIP_AS_IS = {
    Sweet       = true,
    SweetChroma = true,
}

-- Slide along the weapon's own long axis, in studs. The overlay is centred on
-- the handle, which sits mid-stock on a crossbow and leaves the hand short of
-- the trigger; positive pulls the weapon back into the arm.
local GRIP_NUDGE = {
    Harvester  = 0.5,
    Icepiercer = 0.5,
}

-- The weapon's real shape, for the grip maths. A root that's a plain Part
-- with a SpecialMesh inside (the chroma variants, and older guns like Ocean,
-- Blossom, Jingle Gun) has a box Size that says nothing about the mesh --
-- Ocean's is 0.03 x 0.23 x 0.05 -- so the pose was worked out from nonsense
-- and those guns came out turned. Measure the mesh itself: its native size
-- (read once per mesh and cached) times the SpecialMesh scale. A chroma now
-- lands exactly like its normal version.
local MESH_NATIVE = {}
local function realSize(data)
    local rn = data and data.Model
    if not (rn and rn.Class == "Part") then return nil end
    for _, c in ipairs(rn.Children or {}) do
        if c.Class == "SpecialMesh" and c.Props and c.Props.MeshId then
            local id = trimAsset(c.Props.MeshId)
            -- another thread is reading this mesh right now: wait for its answer
            -- (a skin built meanwhile fell back to the box size and came out small)
            if MESH_NATIVE[id] == "loading" then
                local t0 = os.clock()
                while MESH_NATIVE[id] == "loading" and os.clock() - t0 < 10 do task.wait() end
            end
            if MESH_NATIVE[id] == nil then
                MESH_NATIVE[id] = "loading"
                local got
                pcall(function()
                    local tpl = meshPartTemplate(id)
                    got = tpl and tpl.MeshSize
                end)
                MESH_NATIVE[id] = got or false
            end
            if MESH_NATIVE[id] == "loading" then return nil end
            local native = MESH_NATIVE[id]
            local sc = c.Props.Scale or Vector3.new(1, 1, 1)
            if native then return native * sc end
        end
    end
    return nil
end

-- Scale a chroma's model (about its root) so its longest side matches its
-- normal version's -- used for the weapon in your hand and on your back alike.
-- Colour variants (Gold/Silver/Bronze/Red/Blue Harvester, Raygun, Minty,
-- Elderwood, Swirly, Constellation, Celestial, Icebreaker, Iceblaster ...) are
-- drawn at their normal weapon's size too: strip the colour word (and the _
-- joining it) off the key and, if what's left is a weapon we have, that's it.
-- (Shark Seeker is its own model -- it keeps its own grip and size)
for key in pairs(MESHES) do
    for _, c in ipairs({ "Blue", "Bronze", "Gold", "Silver", "Red" }) do
        local rest = key:gsub("_?" .. c .. "_?", "", 1)
        if rest ~= key and rest ~= "" and MESHES[rest] and not SIZE_BASE[key] then SIZE_BASE[key] = rest end
    end
end
matchChromaSize = function(overlay, skin, data)
    local base = baseSkinOf(skin)
    local baseData = base and base ~= "" and MESHES[base] or nil
    if not baseData then return end
    local function longest(v) return v and math.max(v.X, v.Y, v.Z) or nil end
    local wantV = realSize(baseData) or rootSize(baseData)
    local haveV = realSize(data) or rootSize(data)
    local k
    -- Same mesh as the normal one: match every side, not just the length. The
    -- colour Harvesters stretch the shared mesh unevenly (0.06 x 0.05 x 0.05),
    -- which left them a fifth wider even with the length matched.
    if wantV and haveV and targetMeshId(data) ~= "" and targetMeshId(data) == targetMeshId(baseData)
       and haveV.X > 0 and haveV.Y > 0 and haveV.Z > 0 then
        k = Vector3.new(wantV.X / haveV.X, wantV.Y / haveV.Y, wantV.Z / haveV.Z)
        if (k - Vector3.one).Magnitude <= 0.01 then return end
    else
        local want, have = longest(wantV), longest(haveV)
        local u = (want and have and have > 0) and want / have or 1
        if math.abs(u - 1) <= 0.01 then return end
        k = Vector3.new(u, u, u)
    end
    local rootCF = overlay.CFrame
    local parts = { overlay }
    for _, d in ipairs(overlay:GetDescendants()) do
        if d:IsA("BasePart") then parts[#parts + 1] = d end
    end
    for _, d in ipairs(overlay:GetDescendants()) do
        if d:IsA("SpecialMesh") then d.Scale *= k; d.Offset *= k
        elseif d:IsA("Attachment") then d.Position *= k end
    end
    for _, part in ipairs(parts) do
        local rel = rootCF:ToObjectSpace(part.CFrame)
        pcall(function() part.Size *= k end)
        part.CFrame = rootCF * (rel - rel.Position + rel.Position * k)
    end
end

local function gripAlignCF(tool, name, data, slot)
    -- Exact first: a weapon copied off a real player carries that tool's own
    -- Grip (Meta.Grip). The game places a held Handle so that hand * grip lines
    -- up, so ours (placed by OUR tool's Grip) needs Grip * realGrip^-1 to sit
    -- exactly where the real one would -- no guessing from its shape.
    local realGrip = data and data.Meta and data.Meta.Grip
    -- (our Tool.Grip is never changed -- it replicates -- so this is always
    -- the game's own Grip and the skin lands where the real Handle would)
    if typeof(realGrip) == "CFrame" then return tool.Grip * realGrip:Inverse() end
    if name and GRIP_AS_IS[name] then return ID end
    -- Every MM2 knife model is authored in the knife handle's own frame (blade
    -- along +Y, same as the default knife), and the real knives' Grips are all
    -- the default one -- so a knife sits on the handle exactly as it is.
    -- worked out from each knife's own mesh: blade up, the handle's middle
    -- exactly where the default knife's grip point is
    local kcf = data and data.Meta and data.Meta.KnifeCF
    if slot == "Knife" and typeof(kcf) == "CFrame" then return kcf end
    if slot == "Knife" then return ID end
    local size, canon = realSize(data) or rootSize(data), CANON[slot]
    if not (size and canon) then return ID end
    local wl, wm, wt = axisOrder(size)
    local col = { [wl] = canon[1], [wm] = canon[2], [wt] = canon[3] }
    -- an odd axis permutation would mirror the mesh; flip the thin axis instead
    if AXIS[wl]:Cross(AXIS[wm]):Dot(AXIS[wt]) < 0 then col[wt] = -col[wt] end
    -- rotation only: the Grip's offset would slide the weapon off to the hand's
    -- grip point, and the handle's own centre is where we want it sitting
    local cf = tool.Grip.Rotation * CFrame.fromMatrix(Vector3.new(), col.X, col.Y, col.Z)
    -- both post-multiplied, so they act in the weapon's own frame: the tweak
    -- turns it, the nudge slides it along its long axis
    local tweak = name and GRIP_TWEAK[name]
    if tweak then cf = cf * tweak end
    local flip = name and GRIP_FLIP[name]
    if flip then cf = cf * CFrame.fromAxisAngle(AXIS[flip == "muzzle" and wm or wl], math.pi) end
    local nudge = name and GRIP_NUDGE[name]
    if nudge then cf = cf * CFrame.new(AXIS[wl] * nudge) end
    return cf
end

-- Align a weapon onto a reference part that is ALREADY posed correctly (a stuck
-- knife the server placed in a wall). Unlike the grip case there is no fixed
-- convention to aim at -- the reference's own axes are the target, so this
-- adapts if the real weapon's proportions differ.
local function alignToPart(refSize, data)
    -- the real mesh size, like gripAlignCF: a Part root's box Size says nothing
    -- about the SpecialMesh inside it, and poses taken from it came out turned
    local size = realSize(data) or rootSize(data)
    if not size then return ID end
    local wl, wm, wt = axisOrder(size)
    local rl, rm, rt = axisOrder(refSize)
    local col = { [wl] = AXIS[rl], [wm] = AXIS[rm], [wt] = AXIS[rt] }
    -- both triples are permutations of X/Y/Z; if their handedness differs the
    -- mapping mirrors the mesh, so flip the least visible axis
    local sw = AXIS[wl]:Cross(AXIS[wm]):Dot(AXIS[wt])
    local sr = AXIS[rl]:Cross(AXIS[rm]):Dot(AXIS[rt])
    if sw ~= sr then col[wt] = -col[wt] end
    return CFrame.fromMatrix(Vector3.new(), col.X, col.Y, col.Z)
end

-------------------------------------------------------------------------------
-- Backpack icon
--
-- MM2 draws its own hotbar and the whole icon path is client-side: BackpackScript
-- just copies Tool.TextureId into Container.ToolIcon.Image. Write both -- the
-- TextureId so the game's own refresh (fires on every equip/reorder) keeps our
-- icon, and the ImageLabel so it repaints now rather than on the next event.
-------------------------------------------------------------------------------
-- One image per weapon, chroma or not.
--
-- MM2 gives 22 of its 33 chroma/normal pairs DIFFERENT ItemIDs (Luger 198042673
-- vs LugerChroma 3187395551, and so on), so the hotbar icon changed depending on
-- which variant you were holding. Resolve to the base weapon when we have it.
-- Both naming orders exist in the DB: "LugerChroma" and "ChromaDarkbringer".
local function baseWeaponKey(name)
    if not name then return nil end
    return name:match("^(.-)Chroma$") or name:match("^Chroma(.+)$")
end

local function weaponIcon(name, data)
    local own = UI.localPicture(name)
    if own then return own end
    -- The game's own picture for this exact variant first -- the same one the
    -- skin grid shows. It used to jump to the base weapon's picture, so a
    -- Chroma Blizzard sat in the backpack looking like a plain Blizzard.
    local info = WeaponDB[name]
    local img = type(info) == "table" and info.Image
    if type(img) == "string" and img ~= "" then
        -- Older weapons store the legacy "Thumbs/Asset.ashx?...assetId=N"
        -- link, which no longer loads -- and the fallback below (a thumbnail
        -- of the ItemID) is often a DIFFERENT asset with a blank picture, so
        -- those slots sat empty. The assetId in that link is the real
        -- picture: ask for it the modern way.
        local legacy = img:match("[?&]assetId=(%d+)")
        if legacy then return ("rbxthumb://type=Asset&w=150&h=150&id=%s"):format(legacy) end
        return img
    end
    local meta = data.Meta
    if not meta then
        local base = baseWeaponKey(name)
        meta = base and MESHES[base] and MESHES[base].Meta
    end
    if not meta then return nil end
    -- rbxthumb is the format MM2 itself uses; Meta.Image is a legacy
    -- Thumbs/Asset.ashx URL on the older weapons and no longer renders
    if meta.ItemID then return ("rbxthumb://type=Asset&w=150&h=150&id=%d"):format(meta.ItemID) end
    return meta.Image
end

-- Set ONLY Tool.TextureId and let MM2 paint the slot itself.
--
-- This used to also write the ImageLabel directly, finding the slot by matching
-- its current image against the tool's old TextureId. That is a guess, and it
-- guessed wrong: it painted the knife's icon onto the gun's slot and vice versa,
-- and once crossed the wrong images kept matching each other so it never
-- recovered -- the hotbar said "knife" and handed you a gun.
--
-- BackpackScript keeps the only authoritative tool->frame map private, but it
-- rebuilds every icon from TextureId in updateItemFrame, which it runs on add,
-- equip and unequip. So writing TextureId alone is both correct and sufficient:
-- the icon can never land on the wrong slot, because we never choose the slot.
-- Which hotbar slot belongs to which tool, answered by the UI itself.
--
-- BackpackScript keeps its tool->frame map private, but on creating a frame it
-- wires that frame's Name change to write its OWN tool's name into NameLabel:
--     u12:GetPropertyChangedSignal("Name"):Connect(function()
--         u12.Container.NameLabel.Text = u10.Name
--     end)
-- So nudging a frame's Name makes the UI tell us whose it is. Deterministic --
-- unlike matching on the frame's current image, which is a guess and once
-- cross-painted the knife's icon onto the gun's slot with no way back.
local frameCache = setmetatable({}, { __mode = "k" })

local function frameForTool(tool)
    local cached = frameCache[tool]
    if cached and cached.Parent then return cached end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local ui = pg and pg:FindFirstChild("BackpackUI")
    local list = ui and ui:FindFirstChild("BackpackFrame")
    if not list then return nil end
    for _, item in ipairs(list:GetChildren()) do
        local ct = item:IsA("GuiObject") and item:FindFirstChild("Container")
        local nl = ct and ct:FindFirstChild("NameLabel")
        if nl and ct:FindFirstChild("ToolIcon") then
            local name0, text0 = item.Name, nl.Text
            item.Name = name0 .. " "          -- fires MM2's handler
            task.wait()
            local owner = nl.Text
            item.Name = name0                 -- put both back before anyone sees
            task.wait()
            nl.Text = text0
            if owner == tool.Name then frameCache[tool] = ct; return ct end
        end
    end
    return nil
end

-- Paints from the tool's CURRENT TextureId, not the one it was called with:
-- a skin swap restores the old icon and sets the new one back to back, both
-- repaint in the background, and whichever finished last used to win -- a
-- late "restore" left the slot with the new picture AND the "Knife"/"Gun"
-- name drawn over it. Repainting from the live value (now, and once more a
-- moment later) always lands on the right state.
local function paintSlot(tool, _)
    local function paint()
        local ct = frameForTool(tool)
        if not ct then return end
        local img = tool.TextureId
        local icon = ct:FindFirstChild("ToolIcon")
        if icon then icon.Image = img end
        local nl = ct:FindFirstChild("NameLabel")
        -- BackpackScript shows the name only when TextureId is blank
        if nl then nl.Text = (img == "" and tool.Name) or "" end
    end
    task.spawn(paint)
    task.delay(0.35, function() if tool.Parent then pcall(paint) end end)
end

local function setToolIcon(tool, img)
    if not img or img == "" then return nil end
    local old = tool.TextureId
    tool.TextureId = img          -- authoritative: MM2 rebuilds from this
    paintSlot(tool, img)          -- and repaint now, rather than on the next equip
    return old
end

local function restoreToolIcon(tool, old)
    if not old then return end
    pcall(function() tool.TextureId = old end)
    paintSlot(tool, old)
end

-------------------------------------------------------------------------------
-- Shot sound
--
-- Some guns ship a custom firing sound as a Sound named "AltSound" INSIDE the
-- weapon model, and the server swaps it onto the Handle. The ids are not
-- reachable from this client:
--   * the scrape has the AltSound nodes but every one came through with
--     Props = {}, so no SoundId was ever captured
--   * Sync.Item has no sound field on any of its 997 entries
--   * nothing named AltSound exists anywhere in the datamodel, and there is no
--     weapon-sound library in ReplicatedStorage or SoundService
--   * no client script so much as mentions AltSound or Gunshot
--   * the model assets themselves answer 403 to GetObjects
--
-- So SHOT_SOUND is a fixed, hand-filled table.
-------------------------------------------------------------------------------
-- Every id here is load-tested in-experience. The originally supplied ids for
-- Gingerscope/Raygun/Snowcannon were re-uploads by the "MM2 Clips" account and
-- returned "User is not authorized to access Asset" -- Roblox gates private audio
-- on who is asking, and MM2 only holds rights to Nikilis's own uploads. These are
-- authorized replacements found via the toolbox audio search.
local SHOT_SOUND = {
    -- Nikilis's own upload ("Crossbow_MagicShot1"), shared by both crossbows
    ["Harvester"]        = "rbxassetid://7808472682",       -- 1.18s
    ["Icepiercer"]       = "rbxassetid://7808472682",
    -- named "EnergyRifle_Shot12" / "SnowcannonShot" -- MM2's own internal names,
    -- so these are faithful copies rather than someone's approximation
    ["Raygun"]           = "rbxassetid://92066070356304",   -- 1.46s
    ["RaygunChroma"]     = "rbxassetid://92066070356304",   -- chroma reuses the base sound
    ["Snowcannon"]       = "rbxassetid://136161856273464",  -- 0.72s
    ["SnowcannonChroma"] = "rbxassetid://136161856273464",
    -- no copy carrying MM2's internal name ("Gun_SniperRifle_Shot11") is public;
    -- three unrelated uploaders independently land on 0.57s, so that is very
    -- likely the real clip. Worth an ear check.
    -- read straight off a real Gingerscope's Handle.AltSound
    ["Gingerscope"]      = "rbxassetid://15666290706",
}
-- The game fires Handle.Gunshot, so retarget that rather than adding a sound of
-- our own -- keeps MM2's timing, volume and rolloff.
-- `src` (optional): the skin's own AltSound -- its id, and its speed and
-- volume too (Harvester's shot is its clip played at 1.4x).
-- src is the SKIN's own AltSound (from the overlay), never the Handle's: a real
-- custom gun keeps its own AltSound on the Handle, and taking that one played
-- the real gun's shot under the skin. That real one (realAlt) is pointed at the
-- skin's sound too while the skin is on, since the game may play it instead.
local function setShotSound(tool, skin, src, realAlt)
    local id = (src and src.SoundId) or SHOT_SOUND[skin]
    local h = id and tool:FindFirstChild("Handle")
    local shot = h and h:FindFirstChild("Gunshot")
    if not (shot and shot:IsA("Sound")) then return nil end
    local st = { sound = shot, old = shot.SoundId, speed = shot.PlaybackSpeed, volume = shot.Volume }
    shot.SoundId = id
    if src then
        shot.PlaybackSpeed = src.PlaybackSpeed
        shot.Volume = src.Volume
    end
    if realAlt and realAlt:IsA("Sound") and realAlt.Parent then
        st.alt, st.altOld = realAlt, realAlt.SoundId
        realAlt.SoundId = id
    end
    return st
end

local function restoreShotSound(st)
    if st and st.sound then
        pcall(function()
            st.sound.SoundId = st.old
            st.sound.PlaybackSpeed = st.speed
            st.sound.Volume = st.volume
        end)
    end
    if st and st.alt then pcall(function() st.alt.SoundId = st.altOld end) end
end

-------------------------------------------------------------------------------
-- IN-ROUND overlay (weld skin over the real murderer/sheriff weapon Handle)
-------------------------------------------------------------------------------
local toolState = {}
local function isMine(inst)
    if inst:IsDescendantOf(LocalPlayer) then return true end
    local c = char(); return c ~= nil and inst:IsDescendantOf(c)
end
local function overlayTool(tool, slot)
    if toolState[tool] then return end
    -- Claim the tool BEFORE the first yield. Checking only at the top let two
    -- quick skin clicks both pass while the first was still building, so both
    -- skins ended up welded to one weapon. unoverlayTool clears this claim,
    -- which makes an in-flight build give up at its next check.
    local claim = { pending = true, hidden = {} }
    toolState[tool] = claim
    local function stillMine()
        return toolState[tool] == claim and tool.Parent ~= nil and UI.store.engine == SELF.tok
    end
    local function giveUp(root)
        if root then pcall(function() root:Destroy() end) end
        if toolState[tool] == claim then toolState[tool] = nil end
    end
    local handle = tool:FindFirstChild("Handle") or tool:WaitForChild("Handle", 5)
    if not handle or not stillMine() then return giveUp() end
    local skin = ProfileData.Weapons.Equipped[slot]
    local data = skin and MESHES[skin]
    if not data then return giveUp() end
    claim.skin = skin
    -- a live tool handle ships no holster attachment, so only a real
    -- CustomAttachment is learned here (anything else is an effect's)
    if handle:FindFirstChild("CustomAttachment") then learnFrom(handle) end
    local built = buildAnyOverlay(data)              -- phase 1 (may yield)
    if not built or not built.root or not stillMine() then return giveUp(built and built.root) end
    -- A weapon copied off a real player knows its real Grip: give OUR tool
    -- that Grip while the skin is on, so the Handle itself sits where the real
    -- one would. Then the skin needs no correction, and everything the game
    -- measures from the Handle -- where the bullet leaves the muzzle -- lines
    -- up with the gun you see. (Posing only the skin left the shot coming from
    -- the default gun's position.)
    local meta = data.Meta or {}
    -- A chroma gun is held, sized and fires exactly like its normal version:
    -- borrow the normal one's grip, muzzle and hold where the chroma has none,
    -- and do the grip maths with the normal one's data.
    -- (colour variants -- Gold Harvester, Red Icepiercer, Blue Minty ... -- the
    -- same: held exactly where their normal weapon is)
    local base = baseSkinOf(skin)                                  -- guns and knives alike
    local baseData = base and base ~= "" and MESHES[base] or nil
    if baseData then
        local bm = baseData.Meta or {}
        for _, k in ipairs({ "Grip", "Muzzle", "Hold" }) do
            if meta[k] == nil then meta[k] = bm[k] end
        end
        data.Meta = meta
    end
    local oldGrip, gripGuard
    if false then   -- tool.Grip replicates to everyone; placed locally below instead
        oldGrip = tool.Grip
        local grip = meta.Grip
        -- Better still, where the real one sits against the HAND (HandPose):
        -- avatars put their grip point in different places, so the same Grip
        -- left the gun a little above this hand. Solve the Grip that lands the
        -- Handle exactly there from this hand's own grip weld.
        local c = char()
        local rg = c and c:FindFirstChild("RightHand") and c.RightHand:FindFirstChild("RightGrip")
        if typeof(meta.HandPose) == "CFrame" and rg and rg:IsA("Weld") then
            grip = meta.HandPose:Inverse() * rg.C0
        end
        pcall(function() tool.Grip = grip end)
        -- the game rewrites Grip on equip; keep ours while the skin is on
        gripGuard = tool:GetPropertyChangedSignal("Grip"):Connect(function()
            if tool.Grip ~= grip then pcall(function() tool.Grip = grip end) end
        end)
    end
    -- (a weapon built from its own tool handle carries its real Grip and its
    -- real size: held by those, never by its normal version's -- unless it IS
    -- its normal version's model. Gold / Silver / Bronze / Blue Candy share
    -- Candy's mesh, and the Studio tools' turned Grip held them the other way
    -- round from the Candy you know; a colour variant is held like its normal
    -- weapon.)
    local meshOf = UI.meshNum(targetMeshId(data))
    local sameModel = baseData and meta.Handle and meshOf ~= "" and meshOf == UI.meshNum(targetMeshId(baseData))
    local gripCF = OVERRIDE_GRIP[skin]
        or (baseData and (not meta.Handle or sameModel) and not OVERRIDE_GRIP[skin] and gripAlignCF(tool, base, baseData, slot))
        or gripAlignCF(tool, skin, data, slot)
    local handTarget = handle.CFrame * gripCF
    finalizeOverlay(built, handTarget)   -- phase 2 (fresh handle CFrame, synchronous)
    local overlay = built.root
    if matchChromaSize and not meta.Handle then pcall(matchChromaSize, overlay, skin, data) end
    -- gripAlignCF and the resize can both fetch meshes and wait: re-check the
    -- claim before touching the real weapon, then hide it
    if not stillMine() or not handle.Parent then return giveUp(overlay) end
    local hidden = {}
    hideInto(hidden, handle)
    for _, d in ipairs(handle:GetDescendants()) do hideInto(hidden, d) end
    -- stamped before it enters the world, so Performance mode's watchers
    -- already see it as ours
    overlay:SetAttribute("_ov", true)
    overlay.Parent = handle
    -- (exact offset, written in -- see finalizeOverlay)
    local w = Instance.new("Weld"); w.Part0 = handle; w.Part1 = overlay
    w.C0 = gripCF * handTarget:ToObjectSpace(overlay.CFrame); w.Parent = overlay
    local chroma = isChroma(skin, data) and startChroma(overlay) or nil
    overlay:SetAttribute("_ov", true)   -- so we can find it again inside a clone
    -- A real custom gun keeps its CustomBeam (the bullet's look) and AltSound
    -- (its shot) straight on the Handle -- that's where MM2's gun code looks.
    -- Ours arrive one level down, inside the overlay, where nothing reads them,
    -- so the game fell back to the plain beam and shot. Put copies where the
    -- game looks while the skin is on.
    -- a real custom gun's own shot sound, there before we lift anything
    local realAlt = handle:FindFirstChild("AltSound")
    local lifted = {}
    for _, name in ipairs({ "CustomBeam", "AltSound" }) do
        local src = overlay:FindFirstChild(name)
        if src and not handle:FindFirstChild(name) and (not src:IsA("Sound") or src.SoundId ~= "") then
            local c = src:Clone()
            c.Parent = handle
            lifted[#lifted + 1] = c
        end
    end
    -- Its own hold animation (Gingerscope's two-handed CustomHold): the real
    -- tool carries it as an Animation straight on the Tool. Add it there, and
    -- play it ourselves whenever the gun is out -- the game only looks for it
    -- as the tool is equipped, which happens before the skin goes on.
    local hold
    if type(meta.Hold) == "string" then
        -- LOCAL ONLY. Anything played on your own Animator replicates (everyone
        -- saw the two-handed hold), so the hold runs on a hidden copy of your
        -- rig that only exists on this client, and every frame your arm joints
        -- take its pose through Motor6D.Transform -- which never replicates.
        -- Everyone else sees the normal one-handed hold.
        local ARM = { RightShoulder = true, RightElbow = true, RightWrist = true,
                      LeftShoulder = true, LeftElbow = true, LeftWrist = true }
        local dummy, track, stepConn
        local pairsJ = {}
        local function stop()
            if stepConn then stepConn:Disconnect(); stepConn = nil end
            if track then pcall(function() track:Stop(0) end); track = nil end
            if dummy then pcall(function() dummy:Destroy() end); dummy = nil end
            for mine in pairs(pairsJ) do pcall(function() mine.Transform = CFrame.new() end) end
            pairsJ = {}
        end
        local function play()
            stop()
            local c = char()
            if not c or tool.Parent ~= c then return end
            local was = c.Archivable
            c.Archivable = true
            local ok = pcall(function() dummy = c:Clone() end)
            c.Archivable = was
            if not ok or not dummy then return end
            for _, d in ipairs(dummy:GetDescendants()) do
                if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("Accessory") or d:IsA("Clothing")
                   or d:IsA("Decal") or d:IsA("Sound") or d:IsA("ParticleEmitter") then
                    pcall(function() d:Destroy() end)
                elseif d:IsA("BasePart") then
                    d.Transparency, d.CanCollide, d.CanQuery, d.CanTouch = 1, false, false, false
                end
            end
            local root = dummy:FindFirstChild("HumanoidRootPart")
            if root then root.Anchored = true; root.CFrame = CFrame.new(0, -5000, 0) end
            dummy.Name = "HoldRig"
            dummy.Parent = workspace.CurrentCamera
            local hum = dummy:FindFirstChildOfClass("Humanoid")
            local animator = hum and (hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum))
            if not animator then stop(); return end
            -- match each of our arm joints to the copy's
            for _, m in ipairs(c:GetDescendants()) do
                -- newer avatars joint with AnimationConstraints, older ones Motor6Ds
                if (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) and ARM[m.Name] and m.Parent then
                    local twinPart = dummy:FindFirstChild(m.Parent.Name, true)
                    local twin = twinPart and twinPart:FindFirstChild(m.Name)
                    if twin and twin.ClassName == m.ClassName then pairsJ[m] = twin end
                end
            end
            local anim = Instance.new("Animation")
            anim.AnimationId = meta.Hold
            pcall(function()
                track = animator:LoadAnimation(anim)
                track.Priority, track.Looped = Enum.AnimationPriority.Action, true
                track:Play(0.15)
            end)
            -- the animator rewrites Transform during the frame, so write ours
            -- both after it (PreSimulation) and right before drawing (PreRender)
            local function copy()
                if tool.Parent ~= char() then stop(); return end
                for mine, twin in pairs(pairsJ) do mine.Transform = twin.Transform end
            end
            local c1 = RunService.PreSimulation:Connect(copy)
            local c2 = RunService.PreRender:Connect(copy)
            stepConn = { Disconnect = function() c1:Disconnect(); c2:Disconnect() end }
        end
        hold = { conns = { tool.Equipped:Connect(play), tool.Unequipped:Connect(stop) }, stop = stop }
        task.defer(play)
    end
    -- Your shots' bullets: the game builds them from the Handle's CustomBeam
    -- template, but leaves them switched off for a skinned gun and starts them
    -- where the base gun's muzzle would be. Catch each one as it appears near
    -- this gun, switch it on, and move its start to the real weapon's muzzle
    -- (Meta.Muzzle, measured off a real one's shots).
    local bullets
    if handle:FindFirstChild("CustomBeam") then
        bullets = workspace.DescendantAdded:Connect(function(d)
            if not (d:IsA("Beam") and d.Name == "CustomBeam") or tool.Parent ~= char() then return end
            task.defer(function()
                local a0 = d.Attachment0
                if not (a0 and handle.Parent) or (a0.WorldPosition - handle.Position).Magnitude > 8 then return end
                d.Enabled = true
                if typeof(meta.Muzzle) == "Vector3" then
                    -- Muzzle is in the real Handle's space: our skin root sits exactly there
                    pcall(function() a0.WorldPosition = overlay.CFrame:PointToWorldSpace(meta.Muzzle) end)
                end
            end)
        end)
    end
    local oldIcon = setToolIcon(tool, weaponIcon(skin, data))
    toolState[tool] = { overlay = overlay, hidden = hidden, chroma = chroma, icon = oldIcon, skin = skin,
                        -- the game only ever plays Gunshot for a skinned gun (the
                        -- AltSound we add is never picked up), so Gunshot takes
                        -- the skin's own AltSound id when it has one
                        guards = keepHidden(hidden), lifted = lifted, bullets = bullets,
                        shot = setShotSound(tool, skin, (function()
                            local a = overlay:FindFirstChild("AltSound")     -- the skin's own
                            return a and a:IsA("Sound") and a.SoundId ~= "" and a or nil
                        end)(), realAlt),
                        oldGrip = oldGrip, gripGuard = gripGuard, hold = hold,
                        muzzle = typeof(meta.Muzzle) == "Vector3" and meta.Muzzle or nil }
end
-- (There used to be a guard here that stopped "stale" skin hold animations on
-- your character's Animator. Skin holds now run only on the local HoldRig
-- above, so the only tracks it could still catch were REAL holds of a real
-- custom-hold gun -- and stopping those on your own Animator replicates, so
-- other players saw your real Gingerscope held one-handed. Removed.)

local function myToolsForSlot(slot)
    local out = {}
    for _, t in ipairs(CollectionService:GetTagged(slot == "Gun" and "Weapon_Gun" or "Weapon_Knife")) do
        if isMine(t) then out[#out + 1] = t end
    end
    return out
end
local function unoverlayTool(tool)
    local st = toolState[tool]; if not st then return end
    -- still building: dropping the claim is enough, the build aborts itself
    if st.pending then toolState[tool] = nil; return end
    if st.chroma then pcall(function() st.chroma:Disconnect() end) end
    if st.overlay then pcall(function() st.overlay:Destroy() end) end
    if st.bullets then pcall(function() st.bullets:Disconnect() end) end
    if st.hold then
        for _, c in ipairs(st.hold.conns) do pcall(function() c:Disconnect() end) end
        st.hold.stop()
    end
    for _, c in ipairs(st.lifted or {}) do pcall(function() c:Destroy() end) end
    if st.gripGuard then st.gripGuard:Disconnect() end
    if st.oldGrip then pcall(function() tool.Grip = st.oldGrip end) end
    pcall(restoreToolIcon, tool, st.icon)
    restoreShotSound(st.shot)
    unguard(st.guards)                       -- before restore, or it would re-hide
    restore(st.hidden)
    toolState[tool] = nil
end

-------------------------------------------------------------------------------
-- Spawn
-------------------------------------------------------------------------------
-- A snapshot of Owned from before we ever touched it, so "despawn" means "put it
-- back how it was" rather than "delete weapons".
--
-- Kept in the store deliberately: re-running must NOT adopt our own spawns as
-- the new baseline. Tracking only what the current run spawned was the earlier
-- bug -- re-run the script and everything already handed out became permanent.
local BASELINE = UI.store.baseline
if not BASELINE then
    BASELINE = {}
    for k, v in pairs(ProfileData.Weapons.Owned) do BASELINE[k] = v end
    UI.store.baseline = BASELINE
end

-- what you actually had equipped, so despawning can hand those back
local BASELINE_EQUIPPED = UI.store.baselineEq
if not BASELINE_EQUIPPED then
    BASELINE_EQUIPPED = { Knife = ProfileData.Weapons.Equipped.Knife,
                          Gun   = ProfileData.Weapons.Equipped.Gun }
    UI.store.baselineEq = BASELINE_EQUIPPED
end

-- Telling MM2 about weapon changes, instantly and without a freeze.
--
-- What one InventoryDataChanged costs, measured: MM2's weapons tab rebuilds
-- its lists from ProfileData on every one -- every weapon you own, not just
-- the one named -- and builds a tile for each weapon it hasn't got one for
-- (~0.5ms a tile: 260 new skins in one go was a 121ms freeze). It only
-- removes a weapon cleanly when the change names that weapon. And its
-- Crafting module rebuilds the whole salvage grid on every weapon change too.
--
-- So a batch of changes (everything queued in the same frame) is passed on
-- as: removals taken straight out of MM2's tab (instant, see dropTiles), then
-- the new weapons a dozen or so a frame -- the ones still waiting are kept out
-- of ProfileData for the instant each change runs, so MM2 builds tiles only
-- for its own dozen. Every frame stays around 6ms; a full Spawn all lands in
-- about a third of a second.
-- The salvage grid is rebuilt only when you actually open it (below).
local invPending, invQueued, invFlushing = {}, false, false
-- the weapons MM2 has tiles for: what you owned when this loaded, then kept
-- up to date as batches go through
local invShown = {}
for k, v in pairs(ProfileData.Weapons.Owned) do if (tonumber(v) or 0) > 0 then invShown[k] = true end end

-- MM2's Crafting module rebuilds the salvage grid (Crafting > Salvage) on
-- every weapon change -- with a few hundred weapons that alone is a 150ms
-- freeze, for a screen that's almost never open. Its listener is swapped
-- (once a session) for one that only notes the grid is stale, and rebuilds
-- it -- once -- when the salvage screen is open or opens.
do
    local G = UI.store.salvage
    if not G then
        G = { dirty = false }
        UI.store.salvage = G
        local function screens()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local g = pg and pg:FindFirstChild("MainGUI")
            g = g and g:FindFirstChild("Game")
            local craft = g and g:FindFirstChild("Crafting")
            local inv = craft and craft:FindFirstChild("Inventory")
            return craft, inv and inv:FindFirstChild("Salvage")
        end
        local function open()
            local craft, salvage = screens()
            return craft and craft.Visible and salvage and salvage.Visible
        end
        local queued = false
        local function rebuild()
            queued = false
            if not G.dirty or not open() then return end
            G.dirty = false
            pcall(function()
                require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CraftModule")).GenerateSalvageInventory()
            end)
        end
        local function poke()
            if not queued then queued = true; task.defer(rebuild) end
        end
        pcall(function()
            for _, c in ipairs(getconnections(InvDataChanged.Event)) do
                local f = c.Function
                local src = f and debug.info(f, "s")
                if type(src) == "string" and src:find("CraftModule") then c:Disconnect() end
            end
        end)
        InvDataChanged.Event:Connect(function(kind)
            if kind == "Weapons" then G.dirty = true; poke() end
        end)
        task.spawn(function()
            local craft, salvage
            local t0 = os.clock()
            repeat
                craft, salvage = screens()
                if not (craft and salvage) then task.wait(1) end
            until (craft and salvage) or os.clock() - t0 > 120
            if not (craft and salvage) then return end
            craft:GetPropertyChangedSignal("Visible"):Connect(poke)
            salvage:GetPropertyChangedSignal("Visible"):Connect(poke)
        end)
        -- (the listener may already have been cut this session: start stale)
        G.dirty = true
    end
end

-- MM2's own inventory state (InventoryModule.MyInventory): Data[kind][section]
-- [key] = { Frame = its tile, ... } and Sort[kind][section] = the order, a
-- list of keys. Found through its InventoryDataChanged listener.
local function mm2Module()
    local ok, list = pcall(getconnections, InvDataChanged.Event)
    if not ok or type(list) ~= "table" then return nil end
    for _, c in ipairs(list) do
        local f = c.Function
        local okU, ups = pcall(debug.getupvalues, f)
        if f and okU and type(ups) == "table" then
            for _, u in pairs(ups) do
                if type(u) == "table" and type(rawget(u, "MyInventory")) == "table" then return u end
            end
        end
    end
end
local function mm2Inventory()
    local m = mm2Module()
    return m and m.MyInventory
end
-- The Equipped panel in MM2's inventory (your knife and gun) only redraws
-- through its own UpdateMyEquip -- announcing EquippedChanged doesn't reach
-- it, so after equipping or despawning a skin it kept showing the old one.
local function refreshEquipPanel()
    local m = mm2Module()
    if not (m and type(m.UpdateMyEquip) == "function") then return end
    -- on a thread of its own: running MM2's function drops the permissions of
    -- whatever thread runs it, and ours then couldn't touch our own UI any
    -- more (Despawn all stuck on "0", tiles frozen after a click)
    task.defer(function() pcall(m.UpdateMyEquip) end)
end
-- Take skins out of MM2's weapons tab directly: their tiles, their entries,
-- their place in the order. MM2 itself only removes a weapon cleanly when the
-- change names that exact weapon -- one change covering many left entries
-- behind with no tile, and every later update then crashed on them (nothing
-- new showed up any more). Doing it here is instant, however many there are.
local function dropTiles(keys)
    local my = mm2Inventory()
    local data = my and my.Data and my.Data.Weapons
    if type(data) ~= "table" then return false end
    local gone = {}
    for _, k in ipairs(keys) do gone[k] = true end
    for _, items in pairs(data) do
        if type(items) == "table" then
            for k in pairs(gone) do
                local e = items[k]
                if e ~= nil then
                    if type(e) == "table" and typeof(e.Frame) == "Instance" then pcall(function() e.Frame:Destroy() end) end
                    items[k] = nil
                end
            end
        end
    end
    local sort = my.Sort and my.Sort.Weapons
    if type(sort) == "table" then
        for _, order in pairs(sort) do
            if type(order) == "table" then
                for i = #order, 1, -1 do if gone[order[i]] then table.remove(order, i) end end
            end
        end
    end
    return true
end
-- After each batch: anything in MM2's weapons tab you don't own and that has
-- no tile, and any key in its order it has no entry for, is cleared -- the
-- leftovers that made its updates crash, from whatever source.
local function healTiles()
    local my = mm2Inventory()
    local owned = ProfileData.Weapons.Owned
    local data = my and my.Data and my.Data.Weapons
    if type(data) ~= "table" then return end
    for _, items in pairs(data) do
        if type(items) == "table" then
            for k, e in pairs(items) do
                if type(e) == "table" and e.Frame == nil and (owned[k] or 0) <= 0 then items[k] = nil end
            end
        end
    end
    local sort = my.Sort and my.Sort.Weapons
    if type(sort) == "table" then
        for sec, order in pairs(sort) do
            local items = data[sec]
            if type(order) == "table" and type(items) == "table" then
                for i = #order, 1, -1 do if items[order[i]] == nil then table.remove(order, i) end end
            end
        end
    end
end

local function flushInv()
    invQueued = false
    if invFlushing then return end          -- the running flush picks these up
    invFlushing = true
    local owned = ProfileData.Weapons.Owned
    -- one change, told to MM2 -- with the new weapons still waiting kept out
    -- of ProfileData for that instant, so it only builds tiles for its own
    local function fire(name, holdFrom, list)
        local held = {}
        if list then
            for j = holdFrom, #list do local k = list[j]; held[k] = owned[k]; owned[k] = nil end
        end
        pcall(function() InvDataChanged:Fire("Weapons", name, owned[name] or 0) end)
        for k, v in pairs(held) do owned[k] = v end
    end
    while next(invPending) do
        local adds, drops, counts = {}, {}, {}
        for name in pairs(invPending) do
            if (owned[name] or 0) > 0 then
                if invShown[name] then counts[#counts + 1] = name else adds[#adds + 1] = name end
            elseif invShown[name] then
                drops[#drops + 1] = name
            end
        end
        table.clear(invPending)
        -- gone: straight out of MM2's tab (or, failing that, one change each)
        if #drops > 0 then
            if not dropTiles(drops) then
                for _, k in ipairs(drops) do fire(k, 1, adds) end
            end
            for _, k in ipairs(drops) do invShown[k] = nil end
        end
        -- a new count on a weapon it already shows
        local t0 = os.clock()
        for _, k in ipairs(counts) do
            fire(k, 1, adds)
            if os.clock() - t0 > 0.006 then task.wait(); t0 = os.clock() end
        end
        -- new weapons: a dozen or so a frame, sized to keep each frame ~6ms
        local i, per = 1, 12
        while i <= #adds do
            local last = math.min(#adds, i + per - 1)
            local s0 = os.clock()
            fire(adds[i], last + 1, adds)
            local dt = os.clock() - s0
            for j = i, last do if (owned[adds[j]] or 0) > 0 then invShown[adds[j]] = true end end
            i = last + 1
            per = math.clamp(math.floor(per * 0.006 / math.max(dt, 0.0005)), 4, 40)
            if i <= #adds then task.wait() end
        end
    end
    pcall(healTiles)
    invFlushing = false
end
local function queueInv(name)
    invPending[name] = true
    if not invQueued and not invFlushing then
        invQueued = true
        task.defer(flushInv)
    end
end
local function spawnWeapon(name, amount)
    amount = amount or 1
    local owned = ProfileData.Weapons.Owned
    owned[name] = (owned[name] or 0) + amount
    queueInv(name)
end

-- Undo every spawn: walk the whole spawnable set and put each entry back to its
-- baseline count, removing it outright if you owned none. Driving it off MESHES
-- rather than a per-run log means it also clears spawns from earlier runs.
-- onProgress(remaining), if given, is called after each skin is put back, so
-- the UI can count down.
-- The server's own record of what you really own -- a read-only fetch
-- (Remotes.Inventory.GetProfileData). The snapshot taken at the first run can
-- be wrong: taken before the game had finished loading your inventory, it
-- held 3 of your 6 weapons, and "back to your real skins" then deleted the
-- other 3. So every despawn asks the server first and resets the snapshot to
-- its answer; the snapshot is only the fallback if the ask fails.
local function syncBaselineFromServer()
    local ok, data = pcall(function()
        return Remotes:WaitForChild("Inventory"):WaitForChild("GetProfileData"):InvokeServer()
    end)
    local w = ok and type(data) == "table" and type(data.Weapons) == "table" and data.Weapons
    if not (w and type(w.Owned) == "table") then return false end
    table.clear(BASELINE)
    for k, v in pairs(w.Owned) do BASELINE[k] = v end
    if type(w.Equipped) == "table" then
        BASELINE_EQUIPPED.Knife = w.Equipped.Knife or BASELINE_EQUIPPED.Knife
        BASELINE_EQUIPPED.Gun = w.Equipped.Gun or BASELINE_EQUIPPED.Gun
    end
    return true
end
task.spawn(syncBaselineFromServer)   -- right the snapshot as soon as the script loads, too

local function removeSpawned(onProgress)
    syncBaselineFromServer()
    local owned = ProfileData.Weapons.Owned
    -- collect first, so the total is known up front for the countdown
    local todo = {}
    for key in pairs(MESHES) do
        if owned[key] ~= BASELINE[key] then todo[#todo + 1] = key end
    end
    local n = #todo
    if onProgress then pcall(onProgress, n) end
    -- the same as Spawn all: every change is written at once and MM2 hears
    -- about them together (one per skin, each rebuilding the salvage grid,
    -- is what made Despawn all lag and crawl)
    for i, key in ipairs(todo) do
        owned[key] = BASELINE[key]          -- nil = you never owned it
        queueInv(key)                       -- told in one batch (see flushInv)
        if onProgress then pcall(onProgress, n - i) end
    end
    -- Anything you no longer own cannot stay equipped. Go through EquipItem
    -- rather than writing Equipped directly: it fires EquippedChanged, which is
    -- what MM2's inventory listens to. Nil-ing the field left the equipped panel
    -- still showing weapons you no longer had, because nothing told it to redraw.
    for _, slot in ipairs({ "Knife", "Gun" }) do
        local eq = ProfileData.Weapons.Equipped[slot]
        if eq and owned[eq] == nil then
            local back = BASELINE_EQUIPPED[slot]
            if not (back and owned[back]) then          -- baseline pick is gone too
                back = nil
                for key in pairs(owned) do
                    local info = WeaponDB[key]
                    if type(info) == "table" and info.ItemType == slot then back = key; break end
                end
            end
            back = back or ((slot == "Knife") and "DefaultKnife" or "DefaultGun")
            -- Do what EquipService.EquipItem does internally, rather than calling
            -- it: EquipItem resolves the item through ItemService:GetItemInfo
            -- first, which does not resolve the default weapons, so it failed
            -- silently and left the panel showing a weapon you no longer owned.
            ProfileData.Weapons.Equipped[slot] = back
            pcall(function() EquipService.EquippedChanged:Fire(slot, back) end)
        end
    end
    refreshEquipPanel()
    return n
end
-- Browse list: godlies and ancients only -- 171 of the ~990 weapons. The list
-- is the whole UI now, so anything not in here is simply unreachable;
-- nothing else can be spawned.
-- Straight off MESHES, which is already filtered to drawable godlies/ancients.
local weaponList = {}
local NAME_FIX = { SharkSeeker = "Shark Seeker" }   -- MM2's own data misses the space
for key in pairs(MESHES) do
    local info = WeaponDB[key]
    weaponList[#weaponList+1] = { key = key, name = NAME_FIX[key] or (type(info) == "table" and info.ItemName) or key,
                                  type = (type(info) == "table" and info.ItemType) or "",
                                  rarity = (type(info) == "table" and info.Rarity) or "",
                                  -- worth showing: chroma and base variants share a display
                                  -- name in MM2's data, so the list has two rows reading
                                  -- "Sweet" with nothing else to tell them apart
                                  chroma = isChroma(key, MESHES[key]) }
end
table.sort(weaponList, function(a, b)
    if a.type ~= b.type then return a.type < b.type end
    if a.rarity ~= b.rarity then return a.rarity < b.rarity end
    return a.name:lower() < b.name:lower()
end)


-------------------------------------------------------------------------------
-- Equip detection (poll ProfileData.Weapons.Equipped) + hooks
-------------------------------------------------------------------------------
local lastEquipped = { Knife = nil, Gun = nil }
pcall(function() lastEquipped.Knife = ProfileData.Weapons.Equipped.Knife; lastEquipped.Gun = ProfileData.Weapons.Equipped.Gun end)
task.spawn(function()
    for _, slot in ipairs({ "Knife", "Gun" }) do
        local eq = ProfileData.Weapons.Equipped[slot]
        if eq then task.spawn(function() apply(slot, eq) end) end
    end
    while UI.store.engine == SELF.tok do
        for _, slot in ipairs({ "Knife", "Gun" }) do
            local eq
            pcall(function() eq = ProfileData.Weapons.Equipped[slot] end)
            if eq ~= lastEquipped[slot] then
                lastEquipped[slot] = eq
                local name = eq
                task.spawn(function() apply(slot, name) end)
                -- Refresh from the TAGS, not from toolState.
                --
                -- overlayTool bails before registering when a skin has no mesh
                -- data, so that tool drops out of toolState -- and a refresh
                -- driven by toolState could then never put it back. Equipping a
                -- meshless weapon and then a real one left the skin on your back
                -- (apply() does not use toolState) but never in your hand. The
                -- rarity/mesh filter makes that unreachable from the UI now, but
                -- the loop was wrong regardless.
                for _, tool in ipairs(myToolsForSlot(slot)) do
                    task.spawn(function() unoverlayTool(tool); overlayTool(tool, slot) end)
                end
            end
        end
        task.wait(0.1)
    end
end)
local ecConn = EquipService.EquippedChanged.Event:Connect(function(itemType, name)
    if itemType == "Knife" or itemType == "Gun" then
        lastEquipped[itemType] = name
        task.spawn(function() apply(itemType, name) end)
        -- and the one in your hand right now, or it kept the old skin until
        -- the next equip (this handler beats the poll loop to the change)
        for _, tool in ipairs(myToolsForSlot(itemType)) do
            task.spawn(function() unoverlayTool(tool); overlayTool(tool, itemType) end)
        end
    end
end)
table.insert(SELF.conns, ecConn)

local function watchCharacter(c)
    -- Whenever a skin is set for the slot, not only while one is showing:
    -- right after a respawn state is empty, so a holster display that turned
    -- up late was never skinned. And through cleanup, so the old overlay and
    -- its chroma go properly.
    local function reskin(slot)
        task.delay(0.2, function()
            if UI.store.engine ~= SELF.tok then return end
            local cur = lastApplied[slot]
            if cur then
                if state[slot] then cleanup(slot) end
                apply(slot, cur)
            end
        end)
    end
    -- A display that only MOVES (a radio on your back sends the knife from
    -- KnifeBack to KnifeBelt at your side) takes the welded skin with it. One
    -- that is swapped for a new display only changes the ref's Value, with no
    -- ref added, so that is watched too.
    local function watchRef(ref)
        local slot = (ref.Name == "DisplayRefKnife") and "Knife" or "Gun"
        if not ref:IsA("ObjectValue") then return slot end
        table.insert(SELF.conns, ref:GetPropertyChangedSignal("Value"):Connect(function()
            if ref.Value then reskin(slot) end
        end))
        return slot
    end
    for _, n in ipairs({ "DisplayRefKnife", "DisplayRefGun" }) do
        local ref = c:FindFirstChild(n)
        if ref then watchRef(ref) end
    end
    local cc = c.ChildAdded:Connect(function(child)
        local n = child.Name
        if n == "DisplayRefKnife" or n == "DisplayRefGun" then reskin(watchRef(child)) end
    end)
    table.insert(SELF.conns, cc)
end
if char() then watchCharacter(char()) end
local caConn = LocalPlayer.CharacterAdded:Connect(function(c)
    for _, slot in ipairs({ "Knife", "Gun" }) do local st = state[slot]; if st and st.overlay then pcall(function() st.overlay:Destroy() end) end end
    state = {}
    watchCharacter(c)
    task.delay(1.0, function()
        if UI.store.engine ~= SELF.tok then return end      -- closed or re-run meanwhile
        for _, slot in ipairs({ "Knife", "Gun" }) do if lastApplied[slot] then apply(slot, lastApplied[slot]) end end
    end)
end)
table.insert(SELF.conns, caConn)

-- IN-ROUND weapon tags
for _, tag in ipairs({ "Weapon_Knife", "Weapon_Gun" }) do
    local slot = (tag == "Weapon_Gun") and "Gun" or "Knife"
    for _, t in ipairs(CollectionService:GetTagged(tag)) do
        if isMine(t) then task.spawn(function() overlayTool(t, slot) end) end
    end
    table.insert(SELF.conns, CollectionService:GetInstanceAddedSignal(tag):Connect(function(t)
        if isMine(t) then task.spawn(function() overlayTool(t, slot) end) end
    end))
    table.insert(SELF.conns, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(t) unoverlayTool(t) end))
end

-------------------------------------------------------------------------------
-- Thrown knives
--
-- ThrowingKnifeVisuals builds the projectile by CLONING the Tool's Handle, then
-- forcing the clone visible:
--     local KnifeVisual = v1:Clone()
--     ... if VH then KnifeVisual.Transparency = 1; VH.Transparency = 0
--         else KnifeVisual.Transparency = 0 end
-- Our overlay is a child of that Handle so it rides along in the clone, but the
-- game's reset un-hides the default mesh underneath it and you see both. Re-hide
-- the game's geometry on the clone, leaving only our skin.
--
-- KnifeVisual is parented last, after those transparency writes, so waiting for
-- it is enough to land after them -- no need to fight the game for the property.
-------------------------------------------------------------------------------
-- The knife in your HAND during a throw. MM2 hides it with a server-side
-- Handle.Transparency = 1, but our Handle is already 1 locally, so that write
-- changes nothing here and the held skin stayed in your hand for the whole
-- flight (while everyone else saw an empty hand). Hide the held skin ourselves
-- until the server's return write -- Handle back to 0, which keepHidden then
-- re-hides -- says the knife is back. A timeout covers a knife that never is.
local function hideHeldKnifeSkin()
    local c = char()
    if not c then return end
    for tool, st in pairs(toolState) do
        if st.overlay and not st.pending and not st.throwHidden and tool.Parent == c
           and CollectionService:HasTag(tool, "Weapon_Knife") then
            local list = {}
            hideInto(list, st.overlay)
            for _, d in ipairs(st.overlay:GetDescendants()) do hideInto(list, d) end
            st.throwHidden = list
            local done = false
            local function back()
                if done then return end
                done = true
                if toolState[tool] == st and st.throwHidden == list then
                    restore(list)
                    st.throwHidden = nil
                end
            end
            local handle = tool:FindFirstChild("Handle")
            if handle then handle:GetPropertyChangedSignal("Transparency"):Once(back) end
            task.delay(10, back)
        end
    end
end

local function fixThrownKnife(proj)
    local vis = proj:WaitForChild("KnifeVisual", 5)
    if not vis then return end
    local overlay
    for _, d in ipairs(vis:GetDescendants()) do
        if d:GetAttribute("_ov") then overlay = d; break end
    end
    if not overlay then return end          -- somebody else's knife, or no skin on ours
    hideHeldKnifeSkin()
    local throwaway = {}                    -- the clone is Debris'd; nothing to restore
    hideInto(throwaway, vis)
    for _, d in ipairs(vis:GetDescendants()) do
        if d ~= overlay and not d:IsDescendantOf(overlay) then hideInto(throwaway, d) end
    end
end
table.insert(SELF.conns, CollectionService:GetInstanceAddedSignal("ThrowingKnife"):Connect(function(proj)
    task.spawn(fixThrownKnife, proj)
end))

-------------------------------------------------------------------------------
-- Stuck knives
--
-- Where the thrown knife LANDS the server drops a fresh Workspace.StuckKnife: a
-- plain Part carrying the default knife mesh, untagged, with no link back to the
-- Tool we skinned. No client script builds it, so unlike the projectile there is
-- nothing to hook -- we watch for it and skin it ourselves.
--
-- It is always ours: MM2 has exactly one murderer, so if we are carrying a
-- throwable knife every StuckKnife in the world came off our throw. With no
-- knife we skip entirely rather than paint our skin onto someone else's.
-------------------------------------------------------------------------------
local stuckState = {}

local function haveKnifeTool()
    local c = char()
    for _, t in ipairs(CollectionService:GetTagged("Weapon_Knife")) do
        if t:IsDescendantOf(LocalPlayer) or (c and t:IsDescendantOf(c)) then return true end
    end
    return false
end

local function unskinStuck(part)
    local st = stuckState[part]; if not st then return end
    stuckState[part] = nil
    if st.chroma then pcall(function() st.chroma:Disconnect() end) end
    unguard(st.guards)
    -- still in the world (Onyx closed, not the knife cleaned up): show the
    -- game's own knife again rather than leaving an invisible one stuck there
    if st.hidden and part.Parent then restore(st.hidden) end
    if st.overlay then pcall(function() st.overlay:Destroy() end) end
end

local function skinStuckKnife(part)
    if stuckState[part] or not haveKnifeTool() then return end
    local skin = ProfileData.Weapons.Equipped.Knife
    local data = skin and MESHES[skin]
    if not data then return end
    stuckState[part] = {}                                  -- claim it before we yield
    local built = buildAnyOverlay(data)                    -- phase 1 (may yield)
    if not built or not built.root or not part.Parent then
        if built and built.root then built.root:Destroy() end
        stuckState[part] = nil
        return
    end
    -- the server already posed this part correctly; borrow its axes
    -- (alignToPart can fetch a mesh and wait: the knife may be gone after)
    local align = alignToPart(part.Size, data)
    if not part.Parent or UI.store.engine ~= SELF.tok then
        built.root:Destroy()
        stuckState[part] = nil
        return
    end
    local hidden = {}
    hideInto(hidden, part)
    for _, d in ipairs(part:GetDescendants()) do hideInto(hidden, d) end
    finalizeOverlay(built, part.CFrame * align)
    local overlay = built.root
    overlay.Parent = part
    -- (exact offset, written in -- see finalizeOverlay)
    local w = Instance.new("Weld"); w.Part0 = part; w.Part1 = overlay
    w.C0 = part.CFrame:ToObjectSpace(overlay.CFrame); w.Parent = overlay
    stuckState[part] = {
        overlay = overlay,
        chroma  = isChroma(skin, data) and startChroma(overlay) or nil,
        guards  = keepHidden(hidden),
        hidden  = hidden,
    }
    -- these parts are disposable, so nothing to restore -- just drop the
    -- Heartbeat/property connections so they don't outlive the instance
    part.Destroying:Once(function() unskinStuck(part) end)
end

local function watchStuck(d)
    if d:IsA("BasePart") and d.Name == "StuckKnife" then task.spawn(skinStuckKnife, d) end
end
for _, d in ipairs(workspace:GetChildren()) do watchStuck(d) end
table.insert(SELF.conns, workspace.ChildAdded:Connect(watchStuck))

-------------------------------------------------------------------------------
-- REMOVED: the inventory-tile equip fallback.
--
-- It bound a SECOND handler to MM2's own ActionButton and re-derived the item
-- from the tile's label text via `lookup`. That lookup is name-first-wins and
-- MM2 reuses display names -- Deathshard and DeathshardChroma are both
-- ItemName = "Deathshard" -- so it resolved the wrong key, then ran after
-- Inventory2's correct EquipItem and overwrote it. Clicking a weapon equipped a
-- different one, or appeared to do nothing when it resolved to what was already
-- on. It also leaked a connection per tile (202 and climbing).
--
-- Nothing is lost: the poller below reads ProfileData.Weapons.Equipped, which
-- BOTH equip paths write, which is the whole reason this build polls instead of
-- listening to EquippedChanged.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Public API
--
-- What the Skin Changer tab drives the engine with. initSpawner() returns it
-- to this file's UI only; it is never published anywhere.
-------------------------------------------------------------------------------
SELF.spawn      = spawnWeapon      -- (key, amount)
SELF.despawnAll = removeSpawned    -- restores your pre-spawn counts
-- preload every skin's meshes in the background, so a click is instant
task.spawn(function()
    task.wait(2)
    -- SpecialMesh ids too (realSize and the 3D preview fetch those), and the
    -- flat-format entries (Display, no Model): skipping them left exactly
    -- those clicks waiting on CreateMeshPartAsync
    local function one(n)
        if (n.Class == "MeshPart" or n.Class == "SpecialMesh") and n.Props and n.Props.MeshId and n.Props.MeshId ~= "" then
            meshPartTemplate(trimAsset(n.Props.MeshId))
            task.wait()
        end
    end
    local function walk(n)
        if type(n) ~= "table" then return end
        one(n)
        for _, c in ipairs(n.Children or {}) do walk(c) end
    end
    for _, d in pairs(MESHES) do
        if UI.store.engine ~= SELF.tok then return end
        if type(d) == "table" then
            if d.Model then pcall(walk, d.Model)
            else
                for _, e in ipairs(d.Display or {}) do
                    if UI.store.engine ~= SELF.tok then return end
                    if type(e) == "table" then pcall(one, e) end
                end
            end
        end
    end
end)
SELF.equipped = function(slot) return ProfileData.Weapons.Equipped[slot] end
-- where a skinned gun's shot really leaves it (the skin's measured muzzle, in
-- the world), or nil when the skin has none and the game's own start stands
SELF.muzzleOf = function(tool)
    local st = toolState[tool]
    if st and st.muzzle and st.overlay and st.overlay.Parent then
        return st.overlay.CFrame:PointToWorldSpace(st.muzzle)
    end
    return nil
end
-- a copy of a skin whose chroma is running (a thrown knife's twin): it gets
-- the same chroma, in step with the rest -- a clone only keeps the colour it
-- had the moment it was made. Nothing for a skin that isn't a chroma.
SELF.chromaClone = function(tool, model)
    local st = toolState[tool]
    if st and st.chroma and model and model.Parent then return startChroma(model) end
    return nil
end
SELF.equip      = function(key)    -- equip a weapon you hold (spawned or real), the way MM2's inventory does
    local data = MESHES[key]
    local slot = data and data.Meta and data.Meta.ItemType
    if slot ~= "Knife" and slot ~= "Gun" then return false end
    ProfileData.Weapons.Equipped[slot] = key
    pcall(function() EquipService.EquippedChanged:Fire(slot, key) end)
    refreshEquipPanel()
    return true
end
SELF.list       = weaponList       -- { {key, name, type, rarity, chroma}, ... }
SELF.icon       = function(key)    -- rbxthumb url for a weapon key, or nil
    local data = MESHES[key]
    return data and weaponIcon(key, data) or nil
end
SELF.owned      = function(key)    -- how many you hold right now (real + spawned)
    return ProfileData.Weapons.Owned[key] or 0
end
-- A standalone copy of a weapon's model for the grid's 3D preview: built from
-- the same data as the skins you hold, every part anchored, nothing welded to
-- you, effects off. Returns the Model and whether it's a chroma (its colours
-- cycle through SELF.chroma(root), which hands back the connection).
SELF.model      = function(key)
    local data = MESHES[key]
    local built = data and buildAnyOverlay(data)
    if not built then return nil end
    finalizeOverlay(built, CFrame.new())
    local m = Instance.new("Model")
    built.root.Parent = m
    m.PrimaryPart = built.root
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") then d.Anchored = true
        elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then d:Destroy()
        elseif d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles")
            or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light") then pcall(function() d.Enabled = false end)
        elseif d:IsA("Sound") then d:Destroy() end
    end
    -- what you actually see, piece by piece: a MeshPart draws at its Size, a
    -- Part with a file mesh at the mesh's own size times its Scale (its Size
    -- says nothing about it), invisible parts not at all
    local boxes = {}
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") and d.Transparency < 0.98 then
            local cf, size = d.CFrame, d.Size
            local sm = not d:IsA("MeshPart") and d:FindFirstChildOfClass("SpecialMesh")
            if sm then
                if sm.MeshType == Enum.MeshType.FileMesh then
                    local native
                    pcall(function()
                        local tpl = meshPartTemplate(trimAsset(sm.MeshId))
                        native = tpl and tpl.MeshSize
                    end)
                    size = (native or d.Size) * sm.Scale
                else
                    size = d.Size * sm.Scale
                end
                cf = cf * CFrame.new(sm.Offset)
            end
            boxes[#boxes + 1] = { cf, size }
        end
    end
    return m, isChroma(key, data), boxes
end
SELF.chroma     = function(root) return startChroma(root) end

SELF.destroy = function()
    -- Every engine loop (equip poll, mesh preload, in-flight overlay builds)
    -- runs only while this is the live engine. Without this, closing Onyx left
    -- the poll running, and equipping a spawned skin later put it back on.
    SELF.dead = true
    if UI.store.engine == SELF.tok then UI.store.engine, UI.store.engineDestroy = nil, nil end
    -- an apply() still waiting (display lookup, mesh build) finishes into
    -- nothing: every one of its checkpoints compares this token
    for s in pairs(token) do token[s] += 1 end
    for _, cn in ipairs(SELF.conns) do pcall(function() cn:Disconnect() end) end
    for slot in pairs(state) do pcall(cleanup, slot) end
    for tool in pairs(toolState) do pcall(unoverlayTool, tool) end
    for part in pairs(stuckState) do pcall(unskinStuck, part) end
end

    -- A newer run took over while this one was loading (destroy didn't exist
    -- yet, so it couldn't tear this one down): do it now, and never hand back
    -- the newer run's engine as if it were ours.
    if UI.store.engine ~= SELF.tok then SELF.destroy(); return nil end
    return SELF
end

--// Skin grid ------------------------------------------------------

-- Set once initSpawner() lands. Everything that touches the spawner goes
-- through this, so the buttons are safe to press before it's ready.
local ENGINE = nil

-- "Restore my skins on join": what you spawned (key -> how many) and what you
-- have equipped are kept in the settings file, and put back once per server.
-- Recorded always, so switching it on later still knows this session's skins.
function UI.noteSpawn(key, n)
    settings.skins = type(settings.skins) == "table" and settings.skins or {}
    settings.skins[key] = (tonumber(settings.skins[key]) or 0) + (n or 1)
    UI.saveSkins()
end
function UI.clearSpawns()
    settings.skins = {}
    UI.saveSkins()
end
function UI.saveSkins()
    if not settings.restoreSkins then return end
    if ENGINE and ENGINE.equipped then
        settings.skinsEquipped = { Knife = ENGINE.equipped("Knife"), Gun = ENGINE.equipped("Gun") }
    end
    saveSettings()
end
function UI.restoreSkins()
    if not settings.restoreSkins or not ENGINE or UI.store.restoredJob == game.JobId then return end
    UI.store.restoredJob = game.JobId
    local n = 0
    for key, count in pairs(type(settings.skins) == "table" and settings.skins or {}) do
        count = math.clamp(tonumber(count) or 0, 0, 50)
        if count > 0 and pcall(ENGINE.spawn, key, count) then n += 1 end
    end
    local eq = type(settings.skinsEquipped) == "table" and settings.skinsEquipped or {}
    for _, slot in ipairs({ "Knife", "Gun" }) do
        local key = eq[slot]
        if type(key) == "string" and ENGINE.owned and (ENGINE.owned(key) or 0) > 0 then pcall(ENGINE.equip, key) end
    end
    if n > 0 then notify({ title = "Skins restored", body = ("%d skins back, and your equipped knife and gun."):format(n), kind = "success" }) end
end
-- MM2's own weapon database: per-variant icon art (the spawner's lookup maps
-- chroma variants to the base weapon's picture).
local WEAPON_DB = nil
local tiles = {}

-- Only the tiles you can see are drawn. All 373 tiles were live all the
-- time -- some 25k pieces of UI -- and every frame of a window drag moved
-- every one of them: 16ms a frame dragging, 8ms idle. Now a tile out of view
-- keeps its slot in the grid (so nothing reflows) but its body and hover
-- glow are switched off: 8ms dragging, 5ms idle. A row either side of the
-- view stays drawn, so scrolling never shows a tile popping in.
function UI.cullTiles()
    UI.cullQueued = false
    local k = unscale()
    local top = content.AbsolutePosition.Y - 140 * k
    local bottom = content.AbsolutePosition.Y + content.AbsoluteWindowSize.Y + 140 * k
    for _, e in ipairs(tiles) do
        local t = e.tile
        local y = t.AbsolutePosition.Y
        local show = e.flying ~= nil or (y + t.AbsoluteSize.Y >= top and y <= bottom)
        if e.drawn ~= show then
            e.drawn = show
            e.body.Visible = show
            if e.glow then e.glow.Visible = show end
        end
    end
end
-- at most once a frame, however many things moved
function UI.queueCull()
    if UI.cullQueued then return end
    UI.cullQueued = true
    task.defer(UI.cullTiles)
end
content:GetPropertyChangedSignal("CanvasPosition"):Connect(UI.queueCull)
content:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(UI.queueCull)
UI.gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UI.queueCull)

-- Favourites: a star on every card; starred skins are always on top -- at
-- home and in search results -- in their usual order among themselves.
-- Kept in the settings file, so they're still starred next time.
UI.favs = type(settings.favs) == "table" and settings.favs or {}
settings.favs = UI.favs
function UI.tileOrder(e, searching)
    return (searching and e.searchOrder or e.homeOrder) - (UI.favs[e.key] and 1000000 or 0)
end
-- A layer over the whole screen, above the window, for effects that fly past
-- the window's edges (inside the skin list they were clipped at its border).
-- Things placed here are in screen pixels: scale them by unscale() to match
-- the window.
function UI.fx()
    if not (UI.fxLayer and UI.fxLayer.Parent) then
        UI.fxLayer = make("Frame", { Name = "FX", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 60, Parent = gui })
    end
    return UI.fxLayer
end
-- a ColorSequence's colour at t
function UI.rampAt(seq, t)
    local kps = seq.Keypoints
    for n = 2, #kps do
        if t <= kps[n].Time then
            local a, b = kps[n - 1], kps[n]
            return a.Value:Lerp(b.Value, (t - a.Time) / math.max(1e-6, b.Time - a.Time))
        end
    end
    return kps[#kps].Value
end
-- A gradient can't be tweened (a ColorSequence isn't a tweenable value), so
-- this blends one into another by hand: both are sampled at the same points
-- and mixed a little more each frame, easing out, landing on the target
-- exactly. A newer blend on the same gradient takes over from wherever this
-- one has got to.
function UI.blendGradient(g, to, dur)
    local from = g.Color
    local tok = (g:GetAttribute("_blend") or 0) + 1
    g:SetAttribute("_blend", tok)
    local t0, N = os.clock(), 12
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if g:GetAttribute("_blend") ~= tok or not g.Parent then conn:Disconnect(); return end
        local a = math.min(1, (os.clock() - t0) / (dur or 0.5))
        if a >= 1 then g.Color = to; conn:Disconnect(); return end
        local e = 1 - (1 - a) ^ 3
        local kps = {}
        for n = 0, N - 1 do
            local x = n / (N - 1)
            kps[#kps + 1] = ColorSequenceKeypoint.new(x, UI.rampAt(from, x):Lerp(UI.rampAt(to, x), e))
        end
        g.Color = ColorSequence.new(kps)
    end)
end

-- Icon lookup, same order MM2's own inventory uses: a usable Image first, then
-- the assetId out of a legacy Image URL, then ItemID, then the spawner's own.
local function iconFor(key)
    local own = UI.localPicture(key)
    if own then return own end
    local e = WEAPON_DB and WEAPON_DB[key]
    if e then
        local img = type(e.Image) == "string" and e.Image or nil
        if img and (img:find("rbxassetid") or img:find("rbxthumb")) then return img end
        if img then
            local assetId = img:match("[Aa]sset[Ii][Dd]=(%d+)") or img:match("[?&]id=(%d+)")
            if assetId then return "rbxthumb://type=Asset&w=150&h=150&id=" .. assetId end
        end
        if tonumber(e.ItemID) then
            return ("rbxthumb://type=Asset&w=150&h=150&id=%s"):format(tostring(e.ItemID))
        end
    end
    return ENGINE.icon(key) or ""
end

local RAINBOW = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,  60,  90)),
    ColorSequenceKeypoint.new(0.20, Color3.fromRGB(255, 170,  40)),
    ColorSequenceKeypoint.new(0.40, Color3.fromRGB(120, 230,  70)),
    ColorSequenceKeypoint.new(0.60, Color3.fromRGB( 40, 200, 255)),
    ColorSequenceKeypoint.new(0.80, Color3.fromRGB(110,  90, 255)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(240,  70, 220)),
})

-- Black text outline. TextStrokeTransparency is locked at 1px; a UIStroke in
-- Contextual mode outlines the glyphs instead of the box and can go thicker.
local function textOutline(lbl)
    return make("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Color = BLACK, Thickness = 1.5, Parent = lbl,
    })
end

-- Both tile badges (Chroma, and the ×N count) are the same solid dark chip
-- with a light edge, so they read clearly over any skin picture.
local CHIP_FILL, CHIP_EDGE = hex("#111114"), hex("#3a3a42")
-- the rainbow, lifted a little toward white so it pops on the dark chip
local RAINBOW_TEXT = (function()
    local keys = {}
    for _, k in ipairs(RAINBOW.Keypoints) do
        keys[#keys + 1] = ColorSequenceKeypoint.new(k.Time, k.Value:Lerp(WHITE, 0.2))
    end
    return ColorSequence.new(keys)
end)()

local Variant = {}      -- (one local: the file is at Luau's 200-local limit)
-- a soft top-left shine over a circle, so it reads as a round gem
function Variant.shine(dot)
    local sh = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = dot.ZIndex + 1, Parent = dot })
    corner(sh, 8)
    make("UIGradient", { Rotation = 60, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(0.35, 0.85), NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = sh })
    return sh
end

-- The chroma mark: a small rainbow circle. Returns the
-- parts the reveal animation fades in.
-- The chroma / colour mark: a gem circle that, while you hover the card,
-- unfolds to the right into a small chip naming it ("Chroma", "Gold" ...) in
-- the theme's own chip style. Returns the fade parts, plus .expand(on).
function Variant.pill(parent, ramp, label)
    -- opened, it's the card's tag: a dark pill with the skin's gradient on its
    -- outline and on its small bold caps (CHROMA, SILVER ...); closed, the gem
    local D = 16
    local EDGE_OPEN = 0.35
    label = string.upper(label)
    local b = make("Frame", {
        Name = "TagPill", Position = UDim2.fromOffset(8, 8),
        Size = UDim2.fromOffset(D, D), BackgroundColor3 = hex("#0d0d10"), BackgroundTransparency = 1,
        BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 5, Parent = parent,
    })
    corner(b, FULL)
    local pillEdge = stroke(b, WHITE, 1)
    pillEdge.Transparency = 1
    make("UIGradient", { Color = ramp, Parent = pillEdge })
    -- inset so the gem's own thin outline sits fully inside the chip (at the
    -- chip's edge it was clipped on one side and read as a sliver of pill)
    local dot = make("Frame", { Position = UDim2.fromOffset(1.5, 1.5), Size = UDim2.fromOffset(D - 3, D - 3),
        BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 6, Parent = b })
    corner(dot, 8)
    local edge = stroke(dot, CHIP_EDGE, 1.5)
    make("UIGradient", { Color = ramp, Rotation = 45, Parent = dot })
    local sh = Variant.shine(dot)
    local l = make("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(D + 1, -1), Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X, FontFace = geist(FW.ExtraBold), TextSize = 10, TextColor3 = WHITE,
        Text = label, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Visible = false, Parent = b,
    })
    make("UIGradient", { Color = (ramp == RAINBOW) and RAINBOW_TEXT or ramp, Parent = l })
    local parts = {
        { dot, "BackgroundTransparency", 0 }, { edge, "Transparency", 0 }, { sh, "BackgroundTransparency", 0 },
        { l, "TextTransparency", 0 },
    }
    parts.pill = b          -- so the card can place it
    -- The whole tag fading away (or back) as one piece, drifting a few pixels
    -- down as it goes -- open or not, it doesn't fold up first. Coming back it
    -- returns as the closed gem; the word stays tucked away.
    -- (the same plain 0.28s fade as a card's picture, in place)
    function parts.fadeAway(hide)
        local goal = hide and 1 or 0
        for _, p in ipairs({ { dot, "BackgroundTransparency" }, { edge, "Transparency" }, { sh, "BackgroundTransparency" } }) do
            tween(p[1], 0.28, { [p[2]] = goal })
        end
        if hide then
            tween(b, 0.28, { BackgroundTransparency = 1 })
            tween(pillEdge, 0.28, { Transparency = 1 })
            tween(l, 0.28, { TextTransparency = 1 })
        end
    end
    -- the feel: the chip springs open past its size and settles back, the
    -- gem pops and gives a little twist, the word slides in behind it, and a
    -- glint runs across the chip once it's open. Closing is quick and quiet.
    local dotScale = make("UIScale", { Parent = dot })
    local glint = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 0, Visible = false, ZIndex = 7, Parent = b })
    corner(glint, 8)
    local glintGrad = make("UIGradient", { Rotation = 20, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1), NumberSequenceKeypoint.new(0.5, 0.55),
        NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = glint })
    -- smooth, no overshoot: overshooting then settling back clipped the
    -- word's last letter off as the final step
    local OPEN = TweenInfo.new(0.45, EASE.Quint, DIR.Out)
    -- the word's real rendered width, measured once it has drawn
    local textW = nil
    task.spawn(function()
        -- straight from the font, so it's right even for a card that has
        -- never been on screen
        local ok, v = pcall(function()
            local q = Instance.new("GetTextBoundsParams")
            q.Text, q.Font, q.Size, q.Width = label, l.FontFace, l.TextSize, 1000
            return game:GetService("TextService"):GetTextBoundsAsync(q).X
        end)
        if ok and v then textW = v end
    end)
    local SHUT = TweenInfo.new(0.22, EASE.Quint, DIR.Out)
    local gen = 0
    local watch
    function parts.expand(on)
        gen += 1
        local mine = gen
        -- Roblox can miss the MouseLeave on a quick flick; while open, keep
        -- checking the pointer is still over the card and close if it isn't
        if watch then watch:Disconnect(); watch = nil end
        if on and UIS.MouseEnabled then
            watch = RunService.Heartbeat:Connect(function()
                local m = UIS:GetMouseLocation() - game:GetService("GuiService"):GetGuiInset()
                local p, sz = parent.AbsolutePosition, parent.AbsoluteSize
                -- spinning the 3D model by hand: stays open wherever the pointer goes
                if parent.Parent and parts.keepOpen and parts.keepOpen() then return end
                if not parent.Parent or m.X < p.X or m.X > p.X + sz.X or m.Y < p.Y or m.Y > p.Y + sz.Y then
                    parts.expand(false)
                end
            end)
        end
        b:SetAttribute("Open", on)
        if on then l.Visible = true end
        local tw = textW or math.max(l.TextBounds.X, #label * 6)
        local w = on and (D + 1 + math.ceil(tw) + 5) or D
        TweenService:Create(b, on and OPEN or SHUT, { Size = UDim2.fromOffset(w, D) }):Play()
        TweenService:Create(b, TweenInfo.new(on and 0.25 or 0.18, EASE.Quad, DIR.Out), { BackgroundTransparency = on and 0 or 1 }):Play()
        TweenService:Create(pillEdge, TweenInfo.new(on and 0.25 or 0.18, EASE.Quad, DIR.Out), { Transparency = on and EDGE_OPEN or 1 }):Play()
        if on then
            l.Visible = true
            -- gem: one smooth turn, no bounce
            dot.Rotation = 0
            TweenService:Create(dot, TweenInfo.new(0.6, EASE.Quint, DIR.Out), { Rotation = 360 }):Play()
            -- word slides in from under the gem
            l.Position = UDim2.fromOffset(D - 8, -1)
            l.TextTransparency = 1
            TweenService:Create(l, TweenInfo.new(0.5, EASE.Quint, DIR.Out), { Position = UDim2.fromOffset(D + 1, -1) }):Play()
            TweenService:Create(l, TweenInfo.new(0.35, EASE.Quad, DIR.Out), { TextTransparency = 0 }):Play()
        else
            glint.Visible = false
            TweenService:Create(dot, SHUT, { Rotation = 0 }):Play()
            -- the word fades as it tucks back under the gem, so nothing is
            -- ever cut off by the closing edge
            TweenService:Create(l, TweenInfo.new(0.14, EASE.Quad, DIR.Out), { TextTransparency = 1 }):Play()
            local t = TweenService:Create(l, SHUT, { Position = UDim2.fromOffset(D - 8, -1) })
            t.Completed:Connect(function(state)
                if state == Enum.PlaybackState.Completed and mine == gen then l.Visible = false end
            end)
            t:Play()
        end
    end
    return parts
end
local function chromaBadge(parent)
    return Variant.pill(parent, RAINBOW, "Chroma")
end

-- Colour variants (Blue / Bronze / Gold / Silver / Red Gingerscope ...): the
-- card shows the weapon's own name, and a small circle in the variant's own
-- metal gradient marks which one it is -- same spot as the chroma circle.
do
local VARIANT_RAMP = {
    Blue   = ColorSequence.new({ ColorSequenceKeypoint.new(0, hex("#cfe8ff")), ColorSequenceKeypoint.new(0.5, hex("#4a9bff")), ColorSequenceKeypoint.new(1, hex("#123f9e")) }),
    Bronze = ColorSequence.new({ ColorSequenceKeypoint.new(0, hex("#ffe0bd")), ColorSequenceKeypoint.new(0.5, hex("#c9783a")), ColorSequenceKeypoint.new(1, hex("#5c2d0e")) }),
    Gold   = ColorSequence.new({ ColorSequenceKeypoint.new(0, hex("#fff8d1")), ColorSequenceKeypoint.new(0.5, hex("#f2c200")), ColorSequenceKeypoint.new(1, hex("#8a6400")) }),
    Silver = ColorSequence.new({ ColorSequenceKeypoint.new(0, hex("#ffffff")), ColorSequenceKeypoint.new(0.5, hex("#c3c9d2")), ColorSequenceKeypoint.new(1, hex("#5d6470")) }),
    Red    = ColorSequence.new({ ColorSequenceKeypoint.new(0, hex("#ffd0d0")), ColorSequenceKeypoint.new(0.5, hex("#f03a3a")), ColorSequenceKeypoint.new(1, hex("#7a0a10")) }),
}
-- Their own weapons that only happen to start with a colour: a real colour
-- set comes in four (Blue / Bronze / Gold / Silver, or Red for Blue). Blue
-- Elite showed as a blue "Elite" in the middle of the Legendaries.
local OWN_WEAPON = { Seer = true, Luger = true, Elite = true, Fire = true }
function Variant.of(display)
    local first, rest = tostring(display):match("^(%a+)%s+(.+)$")
    if first and VARIANT_RAMP[first] and not OWN_WEAPON[rest] then return first, rest end
    return nil, display
end
function Variant.badge(parent, which)
    return Variant.pill(parent, VARIANT_RAMP[which], which)
end
Variant.ramp = VARIANT_RAMP
end

-- "+1" that floats up out of a tile and fades
local function plusOne(tile)
    local l = make("TextLabel", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(40, 22), Font = Enum.Font.FredokaOne, TextSize = 18, Text = "+1",
        TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
        TextColor3 = C.greenText, ZIndex = 9, Parent = tile,
    })
    local outline = textOutline(l)
    local info = TweenInfo.new(0.65, EASE.Quad, DIR.Out)
    TweenService:Create(l, info, { Position = UDim2.new(0.5, 0, 0.5, -20), TextTransparency = 1 }):Play()
    TweenService:Create(outline, info, { Transparency = 1 }):Play()
    task.delay(0.7, function() l:Destroy() end)
end

-- fade a tile's parts in after `delay` (they start invisible)
local REVEAL = TweenInfo.new(0.4, EASE.Quint, DIR.Out)
local function reveal(parts, delay)
    for _, p in ipairs(parts) do p[1][p[2]] = p[4] or 1 end
    task.delay(delay, function()
        for _, p in ipairs(parts) do
            if p[1].Parent then TweenService:Create(p[1], REVEAL, { [p[2]] = p[3] }):Play() end
        end
    end)
end

-- how many of a skin you hold right now (real + spawned)
local function ownedOf(key)
    local ok, n = pcall(function() return ENGINE and ENGINE.owned and ENGINE.owned(key) end)
    return ok and tonumber(n) or 0
end

-- The "×N" chip in a tile's corner: fades in, flashes green when it goes up,
-- fades out at 0. No scaling, so its number never jumps between pixel sizes.
-- the odometer roll: the old number slides up and fades out, the new one
-- rises in from below, flashing green and settling back to white. (No size
-- pop: a spring on its scale dipped it smaller for a beat before it settled.)
function UI.countRoll(e, was, n)
    local b = e.countBadge
    e.countText.TextColor3 = C.greenText
    tween(e.countText, 0.6, { TextColor3 = WHITE })
    e.countAnimTok = (e.countAnimTok or 0) + 1
    local tok = e.countAnimTok
    b.ClipsDescendants = true
    if e.countGhost then e.countGhost:Destroy() end
    local ghost = e.countText:Clone()
    for _, g in ipairs(ghost:GetChildren()) do if not g:IsA("UIGradient") then g:Destroy() end end
    ghost.Text = was > 99 and "99+" or tostring(was)
    ghost.Position = UDim2.new()
    ghost.TextTransparency = 0
    ghost.Parent = b
    e.countGhost = ghost
    tween(ghost, 0.32, { Position = UDim2.fromOffset(0, -14), TextTransparency = 1 }, EASE.Quint, DIR.Out)
        .Completed:Connect(function() ghost:Destroy(); if e.countGhost == ghost then e.countGhost = nil end end)
    e.countText.Position = UDim2.fromOffset(0, 14)
    e.countText.TextTransparency = 1
    tween(e.countText, 0.38, { Position = UDim2.new(), TextTransparency = 0 }, EASE.Back, DIR.Out)
    task.delay(0.5, function() if e.countAnimTok == tok then b.ClipsDescendants = false end end)
end
local function setCount(e, n, bump)
    if n == e.count then return end
    local was = e.count or 0
    e.count = n
    local b = e.countBadge
    if n > 0 then
        e.countText.Text = n > 99 and "99+" or tostring(n)   -- (caps at 99+)
        -- a chip still fading out counts as hidden: the count came back
        -- mid-fade, and the fade used to run on and leave an empty chip
        if not b.Visible or e.countFading then
            e.countFading = false
            if not b.Visible then
                b.Visible = true
                e.countText.TextTransparency = 1
            end
            -- (stays hidden while the card shows its 3D model)
            tween(e.countText, 0.3, { TextTransparency = e.labelsHidden and 1 or 0 })
        elseif n > was then
            -- one more. While you hover, the card shows its 3D model and the
            -- number is hidden: keep the old value and roll once it's back.
            if e.labelsHidden then e.rollFrom = e.rollFrom or was
            else UI.countRoll(e, was, n) end
        end
    elseif b.Visible then
        e.countFading = true
        e.countAnimTok = (e.countAnimTok or 0) + 1      -- cancel any roll in progress
        e.rollFrom = nil
        tween(e.countText, 0.2, { TextTransparency = 1 }).Completed:Connect(function()
            if e.count == 0 then b.Visible = false; e.countFading = false end
        end)
    end
end
local function refreshCounts(bump)
    for _, e in ipairs(tiles) do setCount(e, ownedOf(e.key), bump) end
end

-- Rarity outlines as gradients, lit from the top-left and deepening to the
-- bottom-right. On hover the ramp turns, so the light glides round the edge.
local RARITY_RAMP = {
    Godly     = ColorSequence.new({ ColorSequenceKeypoint.new(0, hex("#ffd6f5")), ColorSequenceKeypoint.new(0.45, hex("#ff3cbe")), ColorSequenceKeypoint.new(1, hex("#8a0060")) }),
    Ancient   = ColorSequence.new({ ColorSequenceKeypoint.new(0, hex("#ecdcff")), ColorSequenceKeypoint.new(0.45, hex("#9b50ff")), ColorSequenceKeypoint.new(1, hex("#4a14a8")) }),
    Legendary = ColorSequence.new({ ColorSequenceKeypoint.new(0, hex("#ffd2cc")), ColorSequenceKeypoint.new(0.45, hex("#ff3b30")), ColorSequenceKeypoint.new(1, hex("#8a1010")) }),
    Unique    = ColorSequence.new({ ColorSequenceKeypoint.new(0, hex("#ffe9c2")), ColorSequenceKeypoint.new(0.45, hex("#ff9a1f")), ColorSequenceKeypoint.new(1, hex("#a34a00")) }),
    Classic   = ColorSequence.new({ ColorSequenceKeypoint.new(0, hex("#ffffff")), ColorSequenceKeypoint.new(0.45, hex("#fff2c0")), ColorSequenceKeypoint.new(1, hex("#c9a94a")) }),
}

-- What success looks like, everywhere: the caption turns into a white -> green
-- ramp with a check and green hairlines...
local SUCCESS = { gradient = { C.text, C.greenText }, icon = ICON.check, iconColor = C.greenText, hairline = C.greenEdge }

-- ...and the tile shines green: a soft green wash plus a bright band that
-- sweeps corner to corner. A single spawn and the Spawn all ripple share it.
local SHINE_BAND = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.36, 1),
    NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(0.64, 1), NumberSequenceKeypoint.new(1, 1),
})
-- Hover glint: the same diagonal sweep, but white, under half as wide and
-- much softer -- a quick catch of light as the cursor lands on a tile.
local GLINT_BAND = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.38, 1),
    NumberSequenceKeypoint.new(0.47, 0.72), NumberSequenceKeypoint.new(0.5, 0.58),
    NumberSequenceKeypoint.new(0.53, 0.72), NumberSequenceKeypoint.new(0.62, 1), NumberSequenceKeypoint.new(1, 1),
})
local GLINT = TweenInfo.new(0.7, EASE.Quad, DIR.Out)

local function shine(e, delay, color, now)
    color = color or C.greenText          -- (red when Despawn all sweeps them)
    local run = now and function(f) f() end or function(f) task.delay(delay or 0, f) end
    run(function()
        if not e.tile.Parent then return end
        e.shineGrad.Color = ColorSequence.new(color)
        e.wash.BackgroundColor3 = color
        e.wash.BackgroundTransparency = 0.84
        tween(e.wash, 0.6, { BackgroundTransparency = 1 }, EASE.Quad)
        e.shineGrad.Offset = Vector2.new(-1, 0)
        e.shine.Visible = true
        tween(e.shineGrad, 0.65, { Offset = Vector2.new(1, 0) }, EASE.Quad).Completed:Connect(function()
            if e.shineGrad.Offset.X > 0.99 then e.shine.Visible = false end
        end)
    end)
end

-- the green shine rippling across the tiles on screen, corner to corner
-- (Despawn all runs it in red)
-- Each card is timed by where it really sits on screen, not by its place in
-- the list: after a search or a scroll the list order and the grid differ,
-- and the sweep came out ragged. Now it's one clean diagonal, whatever's shown.
local function wave(color)
    local cell = UI.gridLayout.CellSize.X.Offset + UI.GRID_GAP
    local cp, cs = content.AbsolutePosition, content.AbsoluteSize
    local us = unscale()
    local on, x0, y0 = {}, math.huge, math.huge
    for _, e in ipairs(tiles) do
        local t = e.tile
        if t.Visible then
            local ap, as = t.AbsolutePosition, t.AbsoluteSize
            if ap.Y + as.Y > cp.Y and ap.Y < cp.Y + cs.Y then
                local p = ap / us
                on[#on + 1] = { e, p }
                x0, y0 = math.min(x0, p.X), math.min(y0, p.Y)
            end
        end
    end
    -- One clock for the whole sweep: each card starts on the frame its turn
    -- comes up. Separate task.delay timers (the first card's a zero one) woke
    -- on different frames, so the first card ran out of step with the rest.
    local queue = {}
    for _, it in ipairs(on) do
        local col = math.floor((it[2].X - x0) / cell + 0.5)
        local row = math.floor((it[2].Y - y0) / (UI.gridLayout.CellSize.Y.Offset + UI.GRID_GAP) + 0.5)
        queue[#queue + 1] = { e = it[1], at = (col + row) * 0.035 }
    end
    table.sort(queue, function(a, b) return a.at < b.at end)
    local t0, i = os.clock(), 1
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local now = os.clock() - t0
        while queue[i] and queue[i].at <= now do
            shine(queue[i].e, nil, color, true)
            i += 1
        end
        if not queue[i] then conn:Disconnect() end
    end)
end

-- Spawn all and Despawn all lock each other out: while one runs, both ignore
-- clicks and the idle one fades to grey (0.12s, colour only).
local busy, lockedAt = false, 0
local FADE = TweenInfo.new(0.12, EASE.Sine, DIR.InOut)
local GREY_INK = Color3.fromRGB(70, 70, 76)
local function fade(a, ink, iconInk)
    TweenService:Create(a.label, FADE, { TextColor3 = ink }):Play()
    TweenService:Create(a.icon, FADE, { ImageColor3 = iconInk }):Play()
end
-- While a run is going the button shows no words or numbers, just a green
-- ring that isn't closed -- half of it lit, fading off -- turning in place.
-- When the run ends it shrinks away and the check springs in where it was.
function C.spinnerOf(a)
    if a.spinner then return a.spinner end
    local sp = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(0, 0), Visible = false, ZIndex = 3, Parent = a.button })
    corner(sp, FULL)
    -- green for Spawn all, red for Despawn all
    local st = stroke(sp, a.primary and C.greenText or C.red, 2)
    make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.42, 0),
        NumberSequenceKeypoint.new(0.62, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = st })
    UI.loop(TweenService:Create(sp, TweenInfo.new(0.75, EASE.Linear, DIR.In, -1), { Rotation = 360 }), sp)
    a.spinner, a.spinnerStroke = sp, st
    return sp
end
function C.startSpin(a)
    local sp = C.spinnerOf(a)
    a.spinAt = os.clock()
    tween(a.label, 0.12, { TextTransparency = 1 })
    tween(a.icon, 0.12, { ImageTransparency = 1 })
    sp.Visible = true
    sp.Size = UDim2.fromOffset(0, 0)
    -- a new spin outranks a stop still fading out: a tween (not a direct set)
    -- cancels that fade, and the token stops its end from hiding the spinner
    a.spinTok = (a.spinTok or 0) + 1
    tween(a.spinnerStroke, 0.05, { Transparency = 0 })
    tween(sp, 0.4, { Size = UDim2.fromOffset(16, 16) }, EASE.Back, DIR.Out)
end
-- the spinner goes; mode "done" leaves the words hidden for the check
function C.stopSpin(a, done)
    local sp = a.spinner
    if sp and sp.Visible then
        local mine = a.spinTok
        tween(sp, 0.16, { Size = UDim2.fromOffset(0, 0) }, EASE.Quint, DIR.In)
        tween(a.spinnerStroke, 0.16, { Transparency = 1 }).Completed:Connect(function()
            if a.spinTok == mine and a.spinnerStroke.Transparency > 0.99 then sp.Visible = false end
        end)
    end
    if not done then
        tween(a.label, 0.25, { TextTransparency = 0 })
        tween(a.icon, 0.25, { ImageTransparency = 0 })
    end
end
local function lock(running, idle)
    busy = true
    lockedAt = os.clock()
    -- a check still showing from the last run steps aside at once
    for _, a in ipairs({ running, idle }) do
        a.doneTok = (a.doneTok or 0) + 1
        if a.check then a.check.ImageTransparency = 1; a.check.Size = UDim2.fromOffset(0, 0) end
        a.label.TextTransparency, a.icon.ImageTransparency = 0, 0
    end
    -- The bump above cancels the idle half's deferred finish, which is the
    -- only thing that would have stopped its spinner (a Despawn all started
    -- right after a Spawn all left one turning forever). Stop it here.
    if idle.spinner and idle.spinner.Visible then C.stopSpin(idle) end
    C.startSpin(running)
    running.button:SetAttribute("Locked", true)
    idle.button:SetAttribute("Locked", true)
    -- the running half keeps its tinted pill as the track for its progress
    tween(running.pill, 0.15, { BackgroundTransparency = 0, BackgroundColor3 = running.style.tint })
    tween(running.label, 0.15, { TextColor3 = C.text })
    tween(idle.pill, 0.15, { BackgroundTransparency = 1 })
    fade(idle, GREY_INK, GREY_INK)
end
local function unlock()
    -- a job that finishes instantly (nothing to despawn) would cancel the
    -- grey-out mid-fade; hold the lock until the fade has played through
    local left = FADE.Time + 0.15 - (os.clock() - lockedAt)
    if left > 0 then task.wait(left) end
    busy = false
    for _, a in ipairs({ UI.spawnAllBtn, UI.despawnAllBtn }) do
        a.button:SetAttribute("Locked", nil)
        fade(a, a.hovered and C.text or a.ink, a.iconInk)
        -- always clear: hover is shown by the ring now, and nothing else
        -- would ever fade a grey pill lit here back out
        tween(a.pill, 0.25, { BackgroundTransparency = 1, BackgroundColor3 = a.style.tint })
    end
end

-- progress fill inside a button, then a short "done" state with a check
local function setProgress() end   -- (the spinner shows it's working; no fill, no count)
local function finishProgress(a)
    -- Done: the word and icon fade and a green check springs in, centred,
    -- turning into place; after a moment it shrinks away and they come back.
    -- Keyed on a token, so a new run (see lock) cancels a check mid-show.
    a.doneTok = (a.doneTok or 0) + 1
    local mine = a.doneTok
    a.label.Text, a.icon.Image = a.text, a.iconId
    -- a run that's over in a blink still shows the spinner for a beat first
    local hold = 0.5 - (os.clock() - (a.spinAt or 0))
    if hold > 0 then
        task.delay(hold, function() if a.doneTok == mine then a.doneTok -= 1; finishProgress(a) end end)
        return
    end
    C.stopSpin(a, true)
    tween(a.label, 0.12, { TextTransparency = 1 })
    tween(a.icon, 0.12, { ImageTransparency = 1 })
    local chk = a.check
    if not chk then
        chk = image({ Image = a.primary and ICON.check or ICON.x, ImageColor3 = a.primary and C.greenText or C.red, ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
                      Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), ZIndex = 3, Parent = a.button })
        C.bolden(chk, 0.6)
        a.check = chk
    end
    chk.Size, chk.Rotation, chk.ImageTransparency = UDim2.fromOffset(0, 0), -40, 0
    task.delay(0.14, function()
        if a.doneTok == mine then tween(chk, 0.5, { Size = UDim2.fromOffset(18, 18), Rotation = 0 }, EASE.Back, DIR.Out) end
    end)
    tween(a.progress, 0.35, { BackgroundTransparency = 1 }).Completed:Connect(function()
        if a.progress.BackgroundTransparency > 0.99 then a.progress.Size = UDim2.fromScale(0, 1) end
    end)
    task.delay(1.4, function()
        if not a.label.Parent or a.doneTok ~= mine then return end
        tween(chk, 0.2, { ImageTransparency = 1 }, EASE.Quad, DIR.Out)
        task.delay(0.1, function()
            if a.doneTok ~= mine then return end
            tween(a.label, 0.25, { TextTransparency = 0 })
            tween(a.icon, 0.25, { ImageTransparency = 0 })
        end)
    end)
end

-- RichText-safe text, for highlighting what you searched inside the names
local function esc(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end
local HIGHLIGHT = "#6ee7a0"   -- (a plain string: Luau folds it, so it costs no local slot)
-- what you typed runs pale green into green across its letters (RichText can't put
-- a gradient on part of a label, so each letter gets its own step)
function C.inkRun(s)
    local chars = {}
    for ch in s:gmatch(utf8.charpattern) do chars[#chars + 1] = ch end
    local out = {}
    for i, ch in ipairs(chars) do
        local c = WHITE:Lerp(hex(HIGHLIGHT), 0.35 + 0.65 * (#chars > 1 and (i - 1) / (#chars - 1) or 1))   -- pale green into green
        out[i] = '<font color="#' .. c:ToHex() .. '">' .. esc(ch) .. "</font>"
    end
    return table.concat(out)
end

-- Search, animated. Tiles that stop matching fade out; the ones that stay
-- glide from where they were to where the grid now puts them (the grid
-- itself can't animate, so each tile's visuals live in a Body frame that is
-- offset back to its old spot and slid home); the ones that start matching
-- fade in with a small rise. Only what is on screen animates -- the rest
-- snap, unseen -- and fast typing never strands a tile half faded.
local SEARCH_OUT  = TweenInfo.new(0.12, EASE.Quad, DIR.In)
local SEARCH_IN   = TweenInfo.new(0.3, EASE.Quint, DIR.Out)
local SEARCH_MOVE = TweenInfo.new(0.34, EASE.Quint, DIR.Out)
local searchToken = 0

local function onScreen(obj)
    local cp, cs = content.AbsolutePosition, content.AbsoluteSize
    local op, os_ = obj.AbsolutePosition, obj.AbsoluteSize
    return op.Y + os_.Y > cp.Y - 40 and op.Y < cp.Y + cs.Y + 40
end
local function setParts(e, hidden)
    for _, part in ipairs(e.parts) do part[1][part[2]] = hidden and 1 or part[3] end
end
local function fadeParts(e, hidden, info)
    for _, part in ipairs(e.parts) do
        TweenService:Create(part[1], info, { [part[2]] = hidden and 1 or part[3] }):Play()
    end
end

local function applySearch()
    tooltip.hide()
    for _, e in ipairs(tiles) do
        if e.preview then e.hoverTok = (e.hoverTok or 0) + 1; e.preview.hide() end
    end
    searchToken += 1
    local mine = searchToken
    local q = searchBox.Text
    local ql = q:lower()
    local leaving, entering, staying, shown = {}, {}, {}, 0
    for _, e in ipairs(tiles) do
        local s0, f0
        if ql ~= "" then s0, f0 = e.search:find(ql, 1, true) end
        local match = ql == "" or s0 ~= nil or (e.tags and e.tags:find(ql, 1, true) ~= nil)
        if match then shown += 1 end
        if e.tile.Visible then
            if match then staying[#staying + 1] = e else leaving[#leaving + 1] = e end
        elseif match then
            entering[#entering + 1] = e
        end
        -- what you typed, highlighted green inside the name as shown (a
        -- colour variant shows "Gingerscope", but "blue" still finds it)
        if s0 then s0, f0 = e.display:lower():find(ql, 1, true) end
        if s0 then
            e.name.RichText = true
            e.name.Text = esc(e.display:sub(1, s0 - 1)) .. C.inkRun(e.display:sub(s0, f0)) .. esc(e.display:sub(f0 + 1))
        elseif e.name.RichText then
            e.name.RichText = false
            e.name.Text = e.display
        end
    end

    local shownQuery = UI.cutText(q, 18)
    if ql == "" then
        UI.searchCaption = nil
    elseif shown > 0 then
        UI.searchCaption = { text = ('%d %s MATCH "%s"'):format(shown, shown == 1 and "SKIN" or "SKINS", shownQuery:upper()),
                          color = C.muted }
    else
        UI.searchCaption = { text = ('NO SKINS MATCH "%s"'):format(shownQuery:upper()), color = C.subtle }
    end
    UI.captionToken += 1      -- a pending status reset now lands on this caption
    rest(true)

    -- results start at the top
    if content.CanvasPosition.Y > 0 then
        TweenService:Create(content, SEARCH_MOVE, { CanvasPosition = Vector2.new(0, 0) }):Play()
    end

    -- 1. the leavers fade out; stayers caught mid fade by fast typing come back
    local anyOut = false
    for _, e in ipairs(leaving) do
        if onScreen(e.tile) then
            anyOut = true
            fadeParts(e, true, SEARCH_OUT)
        else
            setParts(e, true)
        end
    end
    for _, e in ipairs(staying) do
        if e.body.BackgroundTransparency > 0.01 then fadeParts(e, false, SEARCH_IN) end
    end

    task.delay(anyOut and SEARCH_OUT.Time or 0, function()
        if mine ~= searchToken then return end
        -- 2. note where every stayer is drawn, let the grid rearrange...
        local before = {}
        for _, e in ipairs(staying) do before[e] = e.body.AbsolutePosition end
        for _, e in ipairs(tiles) do
            e.tile.LayoutOrder = UI.tileOrder(e, ql ~= "")
        end
        for _, e in ipairs(leaving) do e.tile.Visible = false end
        for _, e in ipairs(entering) do
            setParts(e, true)
            e.tile.Visible = true
        end
        UI.emptyState.set(ql ~= "" and shown == 0)
        RunService.RenderStepped:Wait()
        if mine ~= searchToken then return end
        UI.cullTiles()      -- (a reorder alone doesn't resize the grid, so nothing else redraws)
        -- ...then slide each one from its old spot to its new one
        local k = unscale()
        for _, e in ipairs(staying) do
            local d = before[e] - e.tile.AbsolutePosition
            if d.Magnitude > 0.5 and onScreen(e.tile) then
                e.body.Position = UDim2.fromOffset(d.X / k, d.Y / k)
                TweenService:Create(e.body, SEARCH_MOVE, { Position = UDim2.new() }):Play()
            else
                e.body.Position = UDim2.new()
            end
        end
        -- 3. the newcomers fade in, rising a few pixels, in reading order
        local n = 0
        for _, e in ipairs(entering) do
            if onScreen(e.tile) then
                n += 1
                e.body.Position = UDim2.fromOffset(0, 8)
                task.delay(math.min(n, 18) * 0.012, function()
                    if mine ~= searchToken then return end
                    fadeParts(e, false, SEARCH_IN)
                    TweenService:Create(e.body, SEARCH_IN, { Position = UDim2.new() }):Play()
                end)
            else
                setParts(e, false)
                e.body.Position = UDim2.new()
            end
        end
    end)
end

-- Rest the pointer on a skin for a second and its picture turns into the
-- real weapon: the same model you'd hold, built once into a small viewport
-- in the card, lying across with a slight tilt like the icon and turning
-- slowly on the spot (anchored -- no physics). Leave and it fades back to the
-- picture; the model is kept for the next time.
-- is the pointer really on this? (shown, the game window focused, and inside it)
do
    local UIS_, GS = game:GetService("UserInputService"), game:GetService("GuiService")
    conns[#conns + 1] = UIS_.WindowFocusReleased:Connect(function() C.unfocused = true end)
    conns[#conns + 1] = UIS_.WindowFocused:Connect(function() C.unfocused = false end)
    function C.pointerOn(obj)
        if C.unfocused or not obj.Parent then return false end
        local o = obj
        while o and not o:IsA("ScreenGui") do
            if o:IsA("GuiObject") and not o.Visible then return false end
            o = o.Parent
        end
        if not o then return false end
        local p, s = obj.AbsolutePosition + GS:GetGuiInset(), obj.AbsoluteSize
        local m = UIS_:GetMouseLocation()
        return m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y
    end
end

function C.preview3D(tile, body, img, key)
    local P = {}
    local vp, cam, model, spin, chroma, isChroma, boxes = nil, nil, nil, nil, nil, false, nil
    local building, want = false, false
    local TILT = CFrame.Angles(0, 0, math.rad(22))
    local BASE = math.pi * 2 / 6                     -- one slow turn every six seconds
    local yaw, pitch, vel, pvel = 0, 0, BASE, 0
    local held, dragged, grabConn, movedAt = false, false, nil, 0
    local function pose()
        local r = CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, yaw, 0) * TILT
        model:PivotTo(r)
    end
    -- Framed from what you actually see (not the parts' boxes: a mesh on a
    -- Part draws at its own size, and invisible parts count for nothing):
    -- laid along its longest side, the next one standing up, centred on its
    -- middle, and the camera exactly far enough back that no side of it ever
    -- leaves the frame while it turns.
    local function frame()
        local pts = {}
        for _, b in ipairs(boxes or {}) do
            local cf, h = b[1], b[2] / 2
            for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
                pts[#pts + 1] = cf:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
            end end end
        end
        if #pts == 0 then
            local cf, size = model:GetBoundingBox()
            local h = size / 2
            for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
                pts[#pts + 1] = cf:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
            end end end
        end
        local rootCF = model.PrimaryPart and model.PrimaryPart.CFrame or model:GetPivot()
        local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
        for _, p in ipairs(pts) do
            local q = rootCF:PointToObjectSpace(p)
            lo, hi = lo:Min(q), hi:Max(q)
        end
        local size = hi - lo
        local axes = { { rootCF.RightVector, size.X }, { rootCF.UpVector, size.Y }, { rootCF.LookVector, size.Z } }
        table.sort(axes, function(a, b) return a[2] > b[2] end)
        local pivot = CFrame.fromMatrix(rootCF:PointToWorldSpace((lo + hi) / 2), axes[1][1], axes[2][1])
        -- With a PrimaryPart set, Roblox ignores Model.WorldPivot and pivots on
        -- the primary part's own pivot -- so the weapon spun around its root
        -- part's origin instead of its centre. Put the pivot there instead.
        if model.PrimaryPart then
            model.PrimaryPart.PivotOffset = model.PrimaryPart.CFrame:ToObjectSpace(pivot)
        else
            model.WorldPivot = pivot
        end
        local r, top = 0, 0
        for _, p in ipairs(pts) do
            local q = TILT * pivot:PointToObjectSpace(p)
            r = math.max(r, math.sqrt(q.X * q.X + q.Z * q.Z))
            top = math.max(top, math.abs(q.Y))
        end
        local aspect = vp.AbsoluteSize.Y > 1 and vp.AbsoluteSize.X / vp.AbsoluteSize.Y or 1.1
        local tanV = math.tan(math.rad(15))
        local tanH = tanV * aspect
        local d = math.max(r * math.sqrt(1 + 1 / (tanH * tanH)), r + top / tanV) * 1.04
        cam.FieldOfView = 30
        cam.CFrame = CFrame.lookAt(Vector3.new(0, 0, d), Vector3.zero)
        pose()
    end
    -- Weightless: let go mid-flick and it keeps turning, easing back to the
    -- slow turn in whichever way you threw it; a tilt drifts back level.
    local function step(dt)
        if not held then
            local sign = vel >= 0 and 1 or -1
            vel += (BASE * sign - vel) * (1 - math.exp(-dt * 0.9))
            yaw = (yaw + vel * dt) % (math.pi * 2)
            pvel *= math.exp(-dt * 2.2)
            pitch += pvel * dt
            pitch += -pitch * (1 - math.exp(-dt * 1.1))
        end
        pose()
    end
    local function fadeIn()
        if not want or not model then return end
        if isChroma and not chroma then
            local ok, c = pcall(ENGINE.chroma, model.PrimaryPart)
            chroma = ok and c or nil
        end
        if not spin then
            spin = RunService.RenderStepped:Connect(function(dt)
                if not vp.Parent then spin:Disconnect(); spin = nil; return end
                step(dt)
            end)
        end
        tween(vp, 0.4, { ImageTransparency = 0 }, EASE.Quint, DIR.Out)
        if P.onReveal then P.onReveal() end      -- the card clears its labels for the model
        P.covering = true                         -- (hide() gives the picture back, however far this got)
        tween(img, 0.28, { ImageTransparency = 1 })
    end
    function P.show()
        want = true
        if not (ENGINE and ENGINE.model) then return end
        if not vp then
            vp = make("ViewportFrame", {
                BackgroundTransparency = 1, ImageTransparency = 1, Ambient = hex("#a8a8b4"), LightColor = WHITE,
                LightDirection = Vector3.new(-0.6, -1, -0.8), AnchorPoint = img.AnchorPoint, Position = img.Position,
                Size = img.Size, ZIndex = 4, Parent = body,     -- over the picture (3) and its outline (2)
            })
            cam = Instance.new("Camera")
            cam.Parent = vp
            vp.CurrentCamera = cam
        end
        if model then return fadeIn() end
        if building then return end
        building = true
        task.spawn(function()
            local ok, m, chromaSkin, b = pcall(ENGINE.model, key)
            building = false
            if not ok or not m then return end
            if not vp.Parent then m:Destroy(); return end
            model, isChroma, boxes = m, chromaSkin and true or false, b
            model.Parent = vp
            frame()
            fadeIn()
        end)
    end
    function P.hide(keepPicture)
        want = false
        P.release()
        if not vp then return end
        -- only when the preview was actually covering the picture: search
        -- hides every tile's preview, and this fade then fought the card's
        -- own fade-in, so the picture showed up before its card
        -- The picture comes back whenever the model had started taking its
        -- place. (Checking only whether the model showed missed a hide that
        -- landed while the model was still fading in: the picture kept
        -- fading out, the model faded away, and the card stood empty.)
        if not keepPicture and (P.covering or vp.ImageTransparency < 0.99) then tween(img, 0.3, { ImageTransparency = 0 }) end
        P.covering = false
        tween(vp, 0.25, { ImageTransparency = 1 }).Completed:Connect(function(state)
            -- a second hide() cancels this tween and fires this at once, with
            -- the viewport still half visible: only a finished fade resets it
            if state ~= Enum.PlaybackState.Completed or want then return end
            if spin then spin:Disconnect(); spin = nil end
            if chroma then pcall(function() chroma:Disconnect() end); chroma = nil end
            yaw, pitch, vel, pvel = 0, 0, BASE, 0
            if model then pose() end
        end)
    end
    -- Hold on the turning model and drag to spin it yourself (and tilt it);
    -- let go while moving and it's thrown.
    function P.grab(input)
        dragged = false
        if not (want and model and vp.ImageTransparency < 0.5) then return end
        held = true
        local start, last, lastT = input.Position, input.Position, os.clock()
        movedAt = os.clock()
        if grabConn then grabConn:Disconnect() end
        grabConn = game:GetService("UserInputService").InputChanged:Connect(function(i)
            local t = i.UserInputType
            if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
            local d = i.Position - last
            local now = os.clock()
            local dt = math.max(now - lastT, 1 / 240)
            last, lastT = i.Position, now
            if (i.Position - start).Magnitude > 4 then dragged = true end
            if d.Magnitude > 0 then movedAt = now end
            yaw += d.X * 0.012
            pitch = math.clamp(pitch + d.Y * 0.012, -1.2, 1.2)
            vel = math.clamp(vel + (d.X * 0.012 / dt - vel) * 0.45, -14, 14)
            pvel = math.clamp(pvel + (d.Y * 0.012 / dt - pvel) * 0.45, -8, 8)
        end)
        local c; c = input.Changed:Connect(function()
            local s = input.UserInputState
            if s ~= Enum.UserInputState.End and s ~= Enum.UserInputState.Cancel then return end
            c:Disconnect()
            P.release()
        end)
    end
    function P.release()
        if grabConn then grabConn:Disconnect(); grabConn = nil end
        if not held then return end
        held = false
        -- held still before letting go: no throw, just the slow turn again
        if os.clock() - movedAt > 0.08 then vel = BASE * (vel >= 0 and 1 or -1); pvel = 0 end
    end
    function P.held() return held end
    function P.consumeDrag()
        local d = dragged
        dragged = false
        return d
    end
    return P
end

-- Every card to its place after the order changed (a star added or taken
-- off): the ones on screen glide from where they were, the ones that arrive
-- from further away rise in.
function UI.reorderTiles()
    local searching = searchBox.Text ~= ""
    local before = {}
    for _, e in ipairs(tiles) do
        if e.tile.Visible and onScreen(e.tile) then before[e] = e.body.AbsolutePosition end
    end
    for _, e in ipairs(tiles) do e.tile.LayoutOrder = UI.tileOrder(e, searching) end
    task.spawn(function()
        RunService.RenderStepped:Wait()
        UI.cullTiles()
        local k = unscale()
        for _, e in ipairs(tiles) do
            if e.tile.Visible and onScreen(e.tile) then
                local was = before[e]
                local d = was and (was - e.tile.AbsolutePosition) or Vector2.new(0, 10 * k)
                if d.Magnitude > 0.5 then
                    e.body.Position = UDim2.fromOffset(d.X / k, d.Y / k)
                    TweenService:Create(e.body, SEARCH_MOVE, { Position = UDim2.new() }):Play()
                end
            end
        end
    end)
end
function UI.toggleFav(e)
    local on = not UI.favs[e.key]
    UI.favs[e.key] = on or nil
    settings.favs = UI.favs
    saveSettings()
    if e.starPaint then e.starPaint(true) end
    -- starred or unstarred while you're still on it: it stays put until you
    -- leave it (the burst and the colours play right away), then goes to
    -- its place
    if e.hovered then
        e.reorderPending = true
    else
        e.reorderPending = nil
        UI.reorderTiles()
    end
    if on then flash(e.display .. " · in your favourites", SUCCESS)
    else flash(e.display .. " · out of your favourites", { color = C.muted }) end
end

local function buildGrid()
    -- the skeletons make way; the real tiles fade in where they stood
    for _, s in ipairs(UI.skeletons) do s:Destroy() end
    table.clear(UI.skeletons)

    -- groups: chromas, then Ancients, then Godlies; guns before knives and
    -- A-Z inside each group
    local RANK = { Unique = 2, Ancient = 3, Godly = 4, Legendary = 5, Classic = 6 }
    local function group(w) return w.chroma and 1 or (RANK[w.rarity] or 7) end
    local items = {}
    for _, w in ipairs(ENGINE.list) do items[#items + 1] = w end
    table.sort(items, function(a, b)
        local ga, gb = group(a), group(b)
        if ga ~= gb then return ga < gb end
        -- all the Seers together, at the very end of their group
        local sa, sb = a.name:find("Seer") ~= nil, b.name:find("Seer") ~= nil
        if sa ~= sb then return sb end
        if a.type ~= b.type then return a.type == "Gun" end
        return a.name:lower() < b.name:lower()
    end)

    local cols = math.max(1, math.floor((grid.AbsoluteSize.X / unscale() + UI.GRID_GAP) / (UI.gridLayout.CellSize.X.Offset + UI.GRID_GAP)))
    local HOVER = TweenInfo.new(0.2, EASE.Quint, DIR.Out)

    for i, w in ipairs(items) do
        local rarity = UI.RARITY[w.rarity] or C.border
        -- The tile is an invisible slot the grid lays out; everything you see
        -- lives in `body` inside it, so a search can slide the body from where
        -- the tile was to where it now sits (see applySearch).
        local tile = make("TextButton", {
            Name = w.key, LayoutOrder = i * 2, Text = "", AutoButtonColor = false,
            BackgroundTransparency = 1, BorderSizePixel = 0, Parent = grid,
        })
        -- The card, store style: the art on top over a faint grid with a soft
        -- glow in the skin's colour, a small rarity chip in the corner, then
        -- under a hairline the type (GUN / KNIFE) in that colour, the name,
        -- and a little green add button. Quiet dark card, thin outline.
        local INFO_H = UI.CARD_INFO_H
        local body = make("Frame", {
            Name = "Body", BackgroundColor3 = C.tile, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = tile,
        })
        corner(body, 12)
        local edge = stroke(body, WHITE, 1)
        -- the outline keeps the skin's own colours (rainbow for chromas, the
        -- metal for colour variants), but faint -- it lights up on hover
        local vRamp = Variant.ramp[(Variant.of(w.name))]
        local ownRamp = (w.chroma and RAINBOW) or vRamp or RARITY_RAMP[w.rarity] or ColorSequence.new(rarity)
        local edgeRamp = make("UIGradient", { Color = ownRamp, Rotation = 45, Parent = edge })
        local EDGE_REST = 0.72
        edge.Transparency = EDGE_REST
        local glowColor = w.chroma and Color3.fromRGB(150, 110, 255) or (vRamp and vRamp.Keypoints[2].Value) or rarity

        -- the art area: a faint grid and the glow behind the weapon
        local art = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1),
            Size = UDim2.new(1, -2, 1, -(INFO_H + 1)), ClipsDescendants = true, ZIndex = 1, Parent = body })
        corner(art, 11)
        local artGlow = image({ Image = ICON.shadow, ImageColor3 = glowColor, ImageTransparency = 0.8,
            ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(99, 99, 99, 99),
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(1.1, 1.05),
            ZIndex = 1, Parent = art })
        -- a chroma's glow is the chroma itself: the rainbow, not one colour
        local glowGrad
        if w.chroma then
            artGlow.ImageColor3 = WHITE
            glowGrad = make("UIGradient", { Color = RAINBOW, Rotation = 35, Parent = artGlow })
        end
        -- Hovered, the aura breathes: a slow, gentle swell and ease of its
        -- size (never brighter than at rest -- only a touch dimmer on the out
        -- breath), and a chroma's rainbow slowly turns. Back to rest on leave.
        local GLOW_REST_T, GLOW_REST_S = artGlow.ImageTransparency, artGlow.Size
        local auraConn
        local function aura(on)
            if auraConn then auraConn:Disconnect(); auraConn = nil end
            if not on then
                tween(artGlow, 0.5, { ImageTransparency = GLOW_REST_T, Size = GLOW_REST_S }, EASE.Sine, DIR.Out)
                if glowGrad then tween(glowGrad, 0.6, { Rotation = 35 }, EASE.Quint, DIR.Out) end
                return
            end
            local t0 = os.clock()
            auraConn = RunService.RenderStepped:Connect(function(dt)
                local b = 0.5 - math.cos((os.clock() - t0) * 2.1) * 0.5     -- 0 -> 1 -> 0, one breath ~3s
                artGlow.Size = GLOW_REST_S + UDim2.fromScale(0.08 * b, 0.07 * b)
                artGlow.ImageTransparency = GLOW_REST_T + 0.05 * b
                if glowGrad then glowGrad.Rotation = (glowGrad.Rotation + dt * 30) % 360 end
            end)
        end
        local gridParts = {}
        for k = 1, 4 do
            gridParts[#gridParts + 1] = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.955, BorderSizePixel = 0,
                Position = UDim2.new(k / 5, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 1, Parent = art })
        end
        for k = 1, 3 do
            gridParts[#gridParts + 1] = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.955, BorderSizePixel = 0,
                Position = UDim2.new(0, 0, k / 4, 0), Size = UDim2.new(1, 0, 0, 1), ZIndex = 1, Parent = art })
        end

        local img = image({ Image = iconFor(w.key), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
                            Size = UDim2.new(1, -26, 1, -(INFO_H + 22)), ZIndex = 2, Parent = body })
        local imgScale = make("UIScale", { Parent = img })
        local preview = C.preview3D(tile, body, img, w.key)

        -- the info: hairline, type, name, add button
        local sep = make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Position = UDim2.new(0, 10, 1, -INFO_H),
            Size = UDim2.new(1, -20, 0, 1), ZIndex = 3, Parent = body })
        local typeL = make("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.new(0, 10, 1, -INFO_H + 9), Size = UDim2.new(1, -46, 0, 11),
            FontFace = geist(FW.ExtraBold), TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = (w.chroma or vRamp) and WHITE or rarity:Lerp(WHITE, 0.15), Text = string.upper(tostring(w.type or "")),
            ZIndex = 4, Parent = body,
        })
        if w.chroma or vRamp then make("UIGradient", { Color = w.chroma and RAINBOW_TEXT or vRamp, Parent = typeL }) end
        local name = make("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.new(0, 10, 1, -INFO_H + 21), Size = UDim2.new(1, -46, 0, 16),
            FontFace = geist(FW.SemiBold), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = WHITE, Text = select(2, Variant.of(w.name)), ZIndex = 4, Parent = body,
        })

        -- the rarity chip, top-left: CHROMA in a rainbow, a colour variant in
        -- its metal, otherwise the rarity (GODLY / ANCIENT ...) with its dot
        local variant = Variant.of(w.name)
        local badgeParts
        -- Every skin gets the gem: CHROMA in the rainbow, a colour variant in its
        -- metal, otherwise its rarity (GODLY, ANCIENT ...) in the rarity's own
        -- colours. It unwraps into the tag while you hover the card.
        if w.chroma then
            badgeParts = chromaBadge(body)
        elseif vRamp then
            badgeParts = Variant.badge(body, variant)
        else
            badgeParts = Variant.pill(body, RARITY_RAMP[w.rarity] or ColorSequence.new(rarity), tostring(w.rarity or ""))
        end
        badgeParts.keepOpen = preview.held     -- stays open while you spin the model
        -- just above the hairline, at the art's bottom-left
        badgeParts.pill.AnchorPoint = Vector2.new(0, 1)
        badgeParts.pill.Position = UDim2.new(0, 8, 1, -(INFO_H + 6))

        -- how many you own: just the number, no bubble, right above the
        -- hairline at the art's bottom right -- the rarity chip's twin on
        -- the left, at its height (the name strip's right is the star's)
        local countBadge = make("Frame", {
            BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -10, 1, -(INFO_H + 6)), Size = UDim2.fromOffset(22, 20),
            Visible = false, ZIndex = 6, Parent = body,
        })
        local countStroke = stroke(countBadge, C.borderHi, 1)
        countStroke.Transparency = 1          -- (kept for the code that tweens it; never shown)
        countBadge.AutomaticSize = Enum.AutomaticSize.None
        local countText = make("TextLabel", { BackgroundTransparency = 1, Text = "", FontFace = geist(FW.Bold), TextSize = 13,
                                 TextColor3 = C.text, Size = UDim2.fromScale(1, 1),
                                 TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center,
                                 ZIndex = 7, Parent = countBadge })
        countText:GetPropertyChangedSignal("TextBounds"):Connect(function()
            countBadge.Size = UDim2.fromOffset(math.max(10, math.ceil(countText.TextBounds.X) + 2), 20)
        end)
        -- the number in the colours of the glow behind the weapon: the
        -- rainbow for a chroma (at the glow's angle), a colour variant's
        -- metal, otherwise its rarity's colours (white underneath, so the
        -- gradient shows true)
        countText.TextColor3 = WHITE
        make("UIGradient", { Color = ownRamp, Rotation = w.chroma and 35 or 90, Parent = countText })

        -- a soft wash (green on success, red on failure) and the green shine
        -- band, both run by shine() / the click handler
        local wash = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = body })
        corner(wash, 12)
        local shineFrame = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
            Visible = false, ZIndex = 8, Parent = body })
        corner(shineFrame, 12)
        local shineGrad = make("UIGradient", { Color = ColorSequence.new(C.greenText), Transparency = SHINE_BAND,
            Rotation = 25, Offset = Vector2.new(-1, 0), Parent = shineFrame })
        local glint = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
            Visible = false, ZIndex = 7, Parent = body })
        corner(glint, 12)
        -- the hover swoosh: white, or a colour variant's own metal
        local glintGrad = make("UIGradient", { Transparency = GLINT_BAND, Rotation = 25, Offset = Vector2.new(-1, 0),
            Color = vRamp or ColorSequence.new(WHITE), Parent = glint })

        local entry = {
            tile = tile, body = body, key = w.key, img = img,
            -- where it sits normally, and where it sits in search results:
            -- chroma guns, chroma knives, guns, knives (then the normal order)
            homeOrder = i * 2, group = group(w),
            searchOrder = ((w.chroma and 0 or 2) + (w.type == "Gun" and 0 or 1)) * 10000 + i, name = name, display = select(2, Variant.of(w.name)), search = w.name:lower(), wash = wash,
            -- also findable by what it is: "chroma", its rarity, "gun" / "knife"
            -- (a colour variant is found by its metal -- "silver", "gold" -- not "unique")
            tags = ((w.chroma and "chroma " or "") .. tostring(vRamp and variant or w.rarity or "") .. " " .. tostring(w.type or "")):lower(),
            shine = shineFrame, shineGrad = shineGrad,
            countBadge = countBadge, countText = countText, countStroke = countStroke,
            preview = preview,
        }
        -- every part a fade touches, with its resting value
        entry.parts = {
            { body, "BackgroundTransparency", 0 }, { edge, "Transparency", EDGE_REST },
            { img, "ImageTransparency", 0 }, { name, "TextTransparency", 0 }, { typeL, "TextTransparency", 0 },
            { sep, "BackgroundTransparency", 0 }, { artGlow, "ImageTransparency", 0.8 },
            { countBadge, "BackgroundTransparency", 1 }, { countText, "TextTransparency", 0 },
            { countStroke, "Transparency", 1 },
        }
        for _, g in ipairs(gridParts) do entry.parts[#entry.parts + 1] = { g, "BackgroundTransparency", 0.955 } end
        for _, part in ipairs(badgeParts) do entry.parts[#entry.parts + 1] = part end
        tile.LayoutOrder = UI.tileOrder(entry, false)        -- a favourite starts on top

        -- While the 3D model is showing, the name, the chroma/variant tag and
        -- the owned count fade away so the model has the whole card; they
        -- come back as the hover ends.
        -- All on one soft timing, each drifting a few pixels away from the
        -- model as it fades (name and tag down, count up), and back the same
        -- way. The info card goes too, and stays away while the model shows.
        -- (the name and type sit below the art now, so only what overlaps the
        -- model goes: the chip and the count)
        -- (the count sits over the art now, so it clears out with the chip)
        local labelParts = { { countText, "TextTransparency", 0 } }
        -- exactly the picture's own fade (tween(img, 0.28, ...)), in place
        local function fadeLabels(hide)
            for _, part in ipairs(labelParts) do tween(part[1], 0.28, { [part[2]] = hide and 1 or part[3] }) end
            if badgeParts.fadeAway then badgeParts.fadeAway(hide) end
        end
        function preview.onReveal()
            if entry.labelsHidden then return end
            entry.labelsHidden = true
            tile:SetAttribute("NoTip", true)
            tooltip.fadeAway()
            fadeLabels(true)
        end
        entry.showLabels = function()
            tile:SetAttribute("NoTip", nil)
            if not entry.labelsHidden then return end
            entry.labelsHidden = false
            fadeLabels(false)
            -- the count went up while you were on the card: roll it now
            local from = entry.rollFrom
            entry.rollFrom = nil
            if from and (entry.count or 0) > from and entry.countBadge.Visible then
                UI.countRoll(entry, from, entry.count)
            end
        end

        -- hover: the tile lifts, the light on its outline glides round and the
        -- art zooms a touch; press settles the art; release springs it back
        local hovered = false
        local TURN = TweenInfo.new(0.7, EASE.Quint, DIR.Out)
        -- a soft glow in the rarity's colour (rainbow for chromas) round the card
        -- on hover: rounded outlines, thin and bright close in, wider and
        -- fainter further out, faded in as one group
        local GLOW_PAD = 10
        local glow = make("CanvasGroup", { Name = "Glow", BackgroundTransparency = 1, GroupTransparency = 1,
            Position = UDim2.fromOffset(-GLOW_PAD, -GLOW_PAD), Size = UDim2.new(1, GLOW_PAD * 2, 1, GLOW_PAD * 2),
            ZIndex = 0, Parent = tile })
        entry.glow = glow          -- switched off with the body while out of view (UI.cullTiles)
        do
            local ramp = ownRamp
            for _, L in ipairs({ { 1.5, 0.35 }, { 3.5, 0.7 }, { 6, 0.86 } }) do
                local f = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(GLOW_PAD, GLOW_PAD),
                    Size = UDim2.new(1, -GLOW_PAD * 2, 1, -GLOW_PAD * 2), Parent = glow })
                corner(f, 12)
                local st = stroke(f, WHITE, L[1], L[2])
                make("UIGradient", { Color = ramp, Rotation = 45, Parent = st })
            end
        end
        -- the pointer can go without a MouseLeave (tabbing out, switching tab,
        -- the window closing, the list scrolling away underneath): a guard
        -- watches while the card is hovered and lets go for it
        local guard, pressed
        local leave
        local function unpress()
            if not pressed then return end
            pressed = false
            tween(body, 0.3, { BackgroundColor3 = C.tile })
            tween(imgScale, 0.45, { Scale = hovered and 1.07 or 1 }, EASE.Back)
        end
        tile.MouseEnter:Connect(function()
            -- back over the card while still spinning its model: it never
            -- counted as left, so no second swoosh (or hover sound)
            if hovered and preview.held() then return end
            hovered = true
            entry.hovered = true
            if entry.starPaint then entry.starPaint() end
            sfx("hover")
            if not guard then
                guard = RunService.RenderStepped:Connect(function()
                    if C.unfocused then preview.release(); leave(); return end
                    if preview.held() then return end        -- spinning it by hand: wait for the release
                    if not C.pointerOn(tile) then leave() end
                end)
            end
            glintGrad.Offset = Vector2.new(-1, 0)
            glint.Visible = true
            local sweep = TweenService:Create(glintGrad, GLINT, { Offset = Vector2.new(1, 0) })
            sweep.Completed:Connect(function(state)
                if state == Enum.PlaybackState.Completed then glint.Visible = false end
            end)
            sweep:Play()
            TweenService:Create(edgeRamp, TURN, { Rotation = 225 }):Play()
            tile.ZIndex = 3        -- above its neighbours, so the glow isn't drawn over
            TweenService:Create(glow, TweenInfo.new(0.35, EASE.Quint, DIR.Out), { GroupTransparency = 0 }):Play()
            aura(true)
            if badgeParts.expand then badgeParts.expand(true) end
            TweenService:Create(edge, HOVER, { Transparency = 0.1 }):Play()      -- the faint outline lights up
            TweenService:Create(imgScale, HOVER, { Scale = 1.07 }):Play()
            -- the weapon turns 10 degrees to the right and holds there
            TweenService:Create(img, TweenInfo.new(0.35, EASE.Quint, DIR.Out), { Rotation = 10 }):Play()
            -- still here after a second: the picture becomes the 3D model
            entry.hoverTok = (entry.hoverTok or 0) + 1
            local tok = entry.hoverTok
            task.delay(0.5, function()
                if hovered and entry.hoverTok == tok and tile.Visible then preview.show() end
            end)
        end)
        function leave()
            if preview.held() then return end            -- (the guard lets go once it's released)
            if guard then guard:Disconnect(); guard = nil end
            unpress()
            if not hovered then return end
            hovered = false
            entry.hovered = false
            if entry.starPaint then entry.starPaint() end
            -- starred (or unstarred) while you were on it: it moves now
            if entry.reorderPending then
                entry.reorderPending = nil
                UI.reorderTiles()
            end
            entry.hoverTok = (entry.hoverTok or 0) + 1
            preview.hide()
            TweenService:Create(edgeRamp, TURN, { Rotation = 45 }):Play()
            TweenService:Create(glow, TweenInfo.new(0.35, EASE.Quint, DIR.Out), { GroupTransparency = 1 }):Play()
            aura(false)
            task.delay(0.35, function() if not hovered then tile.ZIndex = 1 end end)
            if badgeParts.expand then badgeParts.expand(false) end
            TweenService:Create(edge, TweenInfo.new(0.35, EASE.Quint, DIR.Out), { Transparency = entry.edgeRest or EDGE_REST }):Play()
            entry.showLabels()
            TweenService:Create(imgScale, HOVER, { Scale = 1 }):Play()
            TweenService:Create(img, TweenInfo.new(0.4, EASE.Quint, DIR.Out), { Rotation = 0 }):Play()
        end
        tile.MouseLeave:Connect(function() leave() end)
        -- The favourite star, on the right of the name strip, always in view:
        -- a quiet outline, gold once starred. Its click stars the skin (or
        -- takes the star off) -- and is never the card's own click, which
        -- adds the skin.
        local FAV_GOLD, FAV_GOLD_HOT = hex("#fbbf24"), hex("#fcd34d")
        local FAV_GOLDS = { hex("#fbbf24"), hex("#fde68a"), hex("#f59e0b"), hex("#fcd34d"), WHITE }
        -- centred on the type + name block (type at -INFO_H+9, the name ending
        -- at -INFO_H+37: the middle is 23 down from the hairline)
        local STAR_Y = -(INFO_H - 23)
        local star = make("TextButton", {
            Text = UI.favs[w.key] and "★" or "☆", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
            FontFace = geist(FW.Bold), TextSize = 25, TextColor3 = UI.favs[w.key] and FAV_GOLD or C.subtle,
            TextTransparency = 0,
            -- anchored on its own centre: it grows and spins about one point.
            -- (Anchored on its right edge it grew from that edge while it
            -- spun about its middle, so the spin wobbled out sideways.)
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -21, 1, STAR_Y),
            Size = UDim2.fromOffset(30, 30), ZIndex = 10, Parent = body,
        })
        local starScale = make("UIScale", { Parent = star })
        local starPart = { star, "TextTransparency", 0 }
        entry.parts[#entry.parts + 1] = starPart
        local starOver = false
        -- A favourite's outline takes gold into its own colours: gold at the
        -- lit top-left corner, running into the card's own ramp (rarity,
        -- rainbow or metal), and a little brighter at rest so it shows.
        local function rampAt(seq, t)
            local kps = seq.Keypoints
            for n = 2, #kps do
                if t <= kps[n].Time then
                    local a, b = kps[n - 1], kps[n]
                    return a.Value:Lerp(b.Value, (t - a.Time) / math.max(1e-6, b.Time - a.Time))
                end
            end
            return kps[#kps].Value
        end
        local GOLD_RAMP
        do
            local kps = { ColorSequenceKeypoint.new(0, FAV_GOLD), ColorSequenceKeypoint.new(0.22, hex("#fde68a")) }
            for n = 0, 5 do
                kps[#kps + 1] = ColorSequenceKeypoint.new(0.4 + n * 0.12, rampAt(ownRamp, n / 5))
            end
            GOLD_RAMP = ColorSequence.new(kps)
        end
        local FAV_EDGE = 0.4
        local edgePart
        for _, part in ipairs(entry.parts) do if part[1] == edge then edgePart = part end end
        -- the glow behind the weapon takes gold in too: gold from the top
        -- left running into its own colour (a chroma's: into its rainbow).
        -- Everything here blends over (UI.blendGradient), never jumps;
        -- `instant` is only for building a card that's already a favourite.
        local function setGrad(g, to, instant)
            if instant then g.Color = to else UI.blendGradient(g, to, 0.55) end
        end
        local favGlow
        local function favSmoke(fav, instant)
            if glowGrad then
                if not favGlow then
                    local kps = { ColorSequenceKeypoint.new(0, FAV_GOLD), ColorSequenceKeypoint.new(0.2, hex("#fde68a")) }
                    for n = 0, 5 do
                        kps[#kps + 1] = ColorSequenceKeypoint.new(0.35 + n * 0.13, rampAt(RAINBOW, n / 5))
                    end
                    favGlow = ColorSequence.new(kps)
                end
                setGrad(glowGrad, fav and favGlow or RAINBOW, instant)
                return
            end
            -- a one-colour glow: white under a gradient that is flat in its
            -- own colour, or runs in from gold (so the two can blend)
            local g = artGlow:FindFirstChild("FavGlow")
            if not g then
                if not fav then return end
                g = make("UIGradient", { Name = "FavGlow", Rotation = 35, Color = ColorSequence.new(glowColor), Parent = artGlow })
                artGlow.ImageColor3 = WHITE
            end
            setGrad(g, fav and ColorSequence.new({
                ColorSequenceKeypoint.new(0, FAV_GOLD), ColorSequenceKeypoint.new(0.45, FAV_GOLD:Lerp(glowColor, 0.5)),
                ColorSequenceKeypoint.new(1, glowColor) }) or ColorSequence.new(glowColor), instant)
        end
        local function favEdge(fav, t)
            local instant = t == 0
            favSmoke(fav, instant)
            -- and the owned count's number, in the same gold blend
            local cg = countText:FindFirstChildOfClass("UIGradient")
            if cg then setGrad(cg, fav and GOLD_RAMP or ownRamp, instant) end
            setGrad(edgeRamp, fav and GOLD_RAMP or ownRamp, instant)
            local rest = fav and FAV_EDGE or EDGE_REST
            if edgePart then edgePart[3] = rest end
            entry.edgeRest = rest
            if hovered then return end
            if instant then edge.Transparency = rest else tween(edge, t or 0.35, { Transparency = rest }) end
        end
        if UI.favs[w.key] then favEdge(true, 0) end
        -- Starred: the star spins in from nothing and overshoots, a ring of
        -- gold light bursts out of it, a spray of little stars flies off
        -- spinning and fading, and the whole card flashes gold. Unstarred:
        -- the very same, in greys.
        local GREYS = { hex("#d4d4d8"), hex("#a1a1aa"), hex("#71717a"), WHITE, hex("#52525b") }
        local function burst(fav)
            local palette = fav and FAV_GOLDS or GREYS
            local ringColor = fav and FAV_GOLD or hex("#a1a1aa")
            star.Rotation, starScale.Scale = -220, 0.15
            TweenService:Create(star, TweenInfo.new(0.75, EASE.Back, DIR.Out), { Rotation = 0 }):Play()
            TweenService:Create(starScale, TweenInfo.new(0.65, EASE.Back, DIR.Out), { Scale = starOver and 1.2 or 1 }):Play()
            -- (on the layer over the whole window, from the star's spot on
            -- the screen: inside the skin list they were cut off at its edge)
            local layer = UI.fx()
            local sc = unscale()
            local at = star.AbsolutePosition + star.AbsoluteSize / 2 - layer.AbsolutePosition
            local MID = UDim2.fromOffset(at.X, at.Y)
            for k, spec in ipairs({ { 64, 2, 0.6 }, { 40, 1.5, 0.45 } }) do       -- two rings, the second a beat later
                task.delay((k - 1) * 0.08, function()
                    local ring = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = MID, Size = UDim2.fromOffset(6 * sc, 6 * sc), ZIndex = 61, Parent = layer })
                    corner(ring, FULL)
                    local rs = stroke(ring, ringColor, spec[2] * sc)
                    TweenService:Create(ring, TweenInfo.new(spec[3], EASE.Quint, DIR.Out), { Size = UDim2.fromOffset(spec[1] * sc, spec[1] * sc) }):Play()
                    TweenService:Create(rs, TweenInfo.new(spec[3], EASE.Quad, DIR.Out), { Transparency = 1 }):Play()
                    task.delay(spec[3] + 0.05, function() ring:Destroy() end)
                end)
            end
            for k = 1, 12 do
                local ang = (k / 12) * math.pi * 2 + (math.random() - 0.5) * 0.45
                local dist = (24 + math.random() * 26) * sc
                local p = make("TextLabel", { BackgroundTransparency = 1, Text = "★", FontFace = geist(FW.Bold),
                    TextSize = (8 + math.random(0, 7)) * sc, TextColor3 = palette[math.random(1, #palette)],
                    AnchorPoint = Vector2.new(0.5, 0.5), Position = MID, Size = UDim2.fromOffset(16 * sc, 16 * sc),
                    Rotation = math.random(-60, 60), ZIndex = 62, Parent = layer })
                local t = 0.55 + math.random() * 0.3
                TweenService:Create(p, TweenInfo.new(t, EASE.Quint, DIR.Out), {
                    Position = MID + UDim2.fromOffset(math.cos(ang) * dist, math.sin(ang) * dist - 6 * sc),
                    Rotation = p.Rotation + math.random(-260, 260) }):Play()
                TweenService:Create(p, TweenInfo.new(t, EASE.Quad, DIR.In), { TextTransparency = 1 }):Play()
                task.delay(t + 0.05, function() p:Destroy() end)
            end
            wash.BackgroundColor3, wash.BackgroundTransparency = fav and FAV_GOLD or hex("#a1a1aa"), fav and 0.8 or 0.88
            tween(wash, 0.7, { BackgroundTransparency = 1 }, EASE.Quad)
        end
        function entry.starPaint(pop)
            local fav = UI.favs[w.key] and true or false
            star.Text = fav and "★" or "☆"
            favEdge(fav)
            tween(star, 0.2, { TextTransparency = 0,
                TextColor3 = fav and (starOver and FAV_GOLD_HOT or FAV_GOLD) or (starOver and C.text or C.subtle) })
            if pop then
                burst(fav)
            else
                tween(starScale, 0.25, { Scale = starOver and 1.2 or 1 }, EASE.Back, DIR.Out)
            end
        end
        star.MouseEnter:Connect(function()
            starOver = true
            entry.starPaint()
            -- a wiggle that rings out
            star.Rotation = 18
            TweenService:Create(star, TweenInfo.new(0.8, EASE.Elastic, DIR.Out), { Rotation = 0 }):Play()
        end)
        star.MouseLeave:Connect(function() starOver = false; entry.starPaint() end)
        star.MouseButton1Down:Connect(function() entry.starAt = os.clock() end)
        star.MouseButton1Click:Connect(function()
            entry.starAt = os.clock()
            sfx("click")
            UI.toggleFav(entry)
        end)
        -- press: the card greys a step and the art settles; any release lets
        -- go -- over the card or anywhere else -- and so does the guard. On a
        -- spinning model, a press grabs it instead.
        tile.InputBegan:Connect(function(input)
            local t = input.UserInputType
            if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
            -- (a beat later: a press on the star is the star's, not the card's)
            task.defer(function()
            if entry.starAt and os.clock() - entry.starAt < 0.25 then return end
            -- grabbing the spinning model: that's a spin, not a press, so no
            -- grey press state and no ripple while you turn it around
            preview.grab(input)
            if preview.held() then return end
            pressed = true
            C.ripple(body, 12)
            tween(body, 0.08, { BackgroundColor3 = C.tileActive })
            tween(imgScale, 0.1, { Scale = 1 })
            local c; c = input.Changed:Connect(function()
                local s = input.UserInputState
                if s ~= Enum.UserInputState.End and s ~= Enum.UserInputState.Cancel then return end
                c:Disconnect()
                task.defer(unpress)
            end)
            end)
        end)
        tile.MouseButton1Click:Connect(function()
            if entry.starAt and os.clock() - entry.starAt < 0.6 then return end    -- the star's click
            if preview.consumeDrag() then return end     -- that was a spin, not a click
            local ok = pcall(ENGINE.spawn, w.key, 1)
            if ok and ENGINE.equip then pcall(ENGINE.equip, w.key) end   -- and straight into your hand
            if ok then UI.noteSpawn(w.key, 1) end                          -- (for "Restore my skins on join")
            local label = (w.chroma and "Chroma " or "") .. w.name
            if ok then
                sfx("click")
                shine(entry)
                plusOne(body)
                setCount(entry, ownedOf(w.key), true)
                flash(w.name .. (w.chroma and " · Chroma" or "") .. " · added and equipped", SUCCESS)
                notify({ title = "Added and equipped", kind = "success", key = "add:" .. w.key,
                         stack = function(n) return ("+%d %s"):format(n, label) end })
            else
                sfx("error")
                wash.BackgroundColor3 = C.red
                wash.BackgroundTransparency = 0.84
                tween(wash, 0.45, { BackgroundTransparency = 1 }, EASE.Quad)
                flash("Couldn't spawn " .. w.name, C.error)
                notify({ title = "Couldn't spawn", body = label, kind = "error", key = "fail:" .. w.key })
            end
        end)
        -- (no hover info card on the skin cards: each card already shows its
        -- name, tags and count)

        -- the first rows fade in as a diagonal wave; the rest are off screen
        if i <= cols * 6 then
            local parts = table.clone(entry.parts)
            parts[#parts + 1] = { imgScale, "Scale", 1, 0.85 }
            local col, rowN = (i - 1) % cols, math.floor((i - 1) / cols)
            reveal(parts, (col + rowN) * 0.035)
        end

        tiles[#tiles + 1] = entry
    end

    -- the hints: a count, a few favourite skins, and what you can type
    do
        local list = {
            ("Search %d skins!"):format(#items),
            'Try "Gingerscope"',
            "Type a skin name!",
            'Try "Raygun"?',
            'Type "Godly"',
            'Try "Ancient"',
            'Try "Gun" or "Knife"',
        }
        UI.setHints(list)
    end
    searchBox:GetPropertyChangedSignal("Text"):Connect(applySearch)
    -- typed while the skins were still loading: the box was live, but nothing
    -- was listening yet, so that search never ran
    if searchBox.Text ~= "" then task.defer(applySearch) end

    UI.spawnAllBtn.button.MouseButton1Click:Connect(function()
        if busy then return end
        sfx("click")
        lock(UI.spawnAllBtn, UI.despawnAllBtn)
        task.spawn(function()
            -- Each spawn fires MM2's InventoryDataChanged, and its five
            -- listeners (inventory, shop, crafting, emotes) redraw on every
            -- one: ~6ms a skin. Spend at most a few ms per frame so it spreads
            -- over a couple of seconds and the game keeps rendering.
            local total, okCount = #ENGINE.list, 0
            local frameStart = os.clock()
            local job = { title = "Spawning skins", color = C.green, n = 0, total = total }
            C.island.task(job)
            for n, w in ipairs(ENGINE.list) do
                if pcall(ENGINE.spawn, w.key, 1) then
                    okCount += 1
                    settings.skins = type(settings.skins) == "table" and settings.skins or {}
                    settings.skins[w.key] = (tonumber(settings.skins[w.key]) or 0) + 1
                end
                job.n = n
                setProgress(UI.spawnAllBtn, n / total)
                if os.clock() - frameStart > 0.004 then
                    task.wait()
                    frameStart = os.clock()
                end
            end
            UI.saveSkins()                               -- one write for the whole run
            finishProgress(UI.spawnAllBtn)
            C.island.finish(("Spawned %d skins"):format(okCount), C.green)
            unlock()
            refreshCounts(true)
            if okCount == total then
                -- every skin landed: the caption turns into a white -> green
                -- ramp with a check, the hairlines go green, and the tiles ripple
                sfx("click")
                wave()
                flash(("All %d skins spawned"):format(total), SUCCESS)
                notify({ title = "All skins spawned", body = ("%d skins added to your inventory"):format(total),
                         kind = "success" })
            else
                sfx("error")
                flash(("Spawned %d of %d skins"):format(okCount, total), C.amber)
                notify({ title = "Some skins failed", body = ("%d of %d skins were added"):format(okCount, total),
                         kind = "warning" })
            end
        end)
    end)

    UI.despawnAllBtn.button.MouseButton1Click:Connect(function()
        if busy then return end
        sfx("click")
        lock(UI.despawnAllBtn, UI.spawnAllBtn)
        local total                              -- the first callback reports the full count
        local job = { title = "Removing skins", color = C.red, n = 0 }
        C.island.task(job)
        UI.clearSpawns()                             -- back to your real inventory, remembered too
        local ok, removed = pcall(ENGINE.despawnAll, function(left)
            if total == nil then total = left end
            job.total, job.n = total, total - left
            if total > 0 then setProgress(UI.despawnAllBtn, 1 - left / total) end
        end)
        removed = ok and tonumber(removed) or 0
        if removed > 0 then C.island.finish(("Removed %d skins"):format(removed), C.red, ICON.x) else C.island.task(nil) end
        if removed > 0 then
            finishProgress(UI.despawnAllBtn)
        else
            UI.despawnAllBtn.label.Text = "Despawn all"
            C.stopSpin(UI.despawnAllBtn)
        end
        unlock()
        refreshCounts(false)
        local msg = removed > 0
            and ("-%d skins removed, your real inventory is back"):format(removed)
            or "Nothing to despawn"
        if removed > 0 then
            sfx("click")
            -- the same moment as Spawn all's, in red: a white -> red caption
            -- with an X, red hairlines, and a red sweep across the tiles
            wave(C.red)
            flash(msg, { gradient = { C.text, C.red }, icon = ICON.x, iconColor = C.red, hairline = C.redEdge })
        else
            flash(msg)
        end
        if removed > 0 then
            notify({ title = ("Removed %d skins"):format(removed), body = "Your real inventory is back", kind = "neutral" })
        else
            notify({ title = "Nothing to despawn", body = "You haven't spawned any skins yet", kind = "neutral" })
        end
    end)

    -- Roblox only fetches a thumbnail once it is on screen; preload so
    -- scrolling doesn't reveal blank tiles.
    task.spawn(function()
        local imgs = {}
        for _, e in ipairs(tiles) do
            -- the tile's picture (it sits under the body, so a search of the
            -- tile's direct children never found one and nothing was preloaded)
            if e.img then imgs[#imgs + 1] = e.img end
        end
        pcall(function() game:GetService("ContentProvider"):PreloadAsync(imgs) end)
    end)

    -- owned counts: pop in once the tiles have faded in, then stay in sync
    -- with anything that changes your inventory outside this window
    task.delay(0.6, function() refreshCounts(false) end)
    task.spawn(function()
        while gui.Parent do
            task.wait(3)
            if holder.Visible and not busy then refreshCounts(false) end
        end
    end)

    rest()
end

--// Autofarm tab --------------------------------------------------
-- The coin farm, the switches around it, the Discord logger and the box
-- opener. The farm's movement, the fling, Kill All and Performance Mode are
-- the full hub's own proven code; the panel, the round tracking, the box
-- opener and the Discord sender are built fresh for this window.
-- All of it lives inside one function: the main chunk is near Luau's limit
-- of 200 locals, and a function gets a budget of its own.
local function buildAutofarm()
    local Workspace = workspace
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TeleportService = game:GetService("TeleportService")
    local VirtualUser = game:GetService("VirtualUser")
    local CoreGui = game:GetService("CoreGui")
    local Players = game:GetService("Players")
    local UserInputService = UIS
    local rbxSettings = getfenv(0).settings        -- Roblox's own, not this script's settings table
    local playerData = nil                          -- the server's round roster (below)
    local ONX = { conns = {}, el = {} }
    -- MM2's server fires Remotes.Gameplay.PlayerDataChanged to everyone the
    -- moment it deals the roles -- well before the knife and gun are handed
    -- out -- and again as the round changes. It carries every player's Role
    -- and whether they're dead. Kept here, it's what findMurderer falls back
    -- to, and the Fling tab's tags redraw the instant it lands.
    pcall(function()
        local gp = ReplicatedStorage:FindFirstChild("Remotes")
        gp = gp and gp:FindFirstChild("Gameplay")
        local pdc = gp and gp:FindFirstChild("PlayerDataChanged")
        if pdc and pdc:IsA("RemoteEvent") then
            ONX.conns[#ONX.conns + 1] = pdc.OnClientEvent:Connect(function(data)
                if type(data) ~= "table" then return end
                playerData = data
                ONX.rosterAt = os.clock()
                if ONX.onRoster then task.spawn(pcall, ONX.onRoster) end
            end)
        end
    end)
    function ONX.roster() return playerData end

    -- the ported blocks talk to WindUI:Notify; this window's toasts answer
    local KIND_OF = {
        check = "success", x = "error", ["power-off"] = "off", clock = "wait",
        loader = "wait", flame = "flame", shield = "success",
    }
    local WindUI = { Notify = function(_, o)
        if ONX.restoring or type(o) ~= "table" then return end
        notify({ title = o.Title, body = o.Content, kind = KIND_OF[o.Icon] or "info",
                 duration = math.max(2.6, tonumber(o.Duration) or 0) })
    end }

    -- 12345 -> "12,345"; nil -> "?"
    function ONX.comma(n)
        local v = tonumber(n)
        if v == nil then return "?" end
        local sign = v < 0 and "-" or ""
        local s = tostring(math.floor(math.abs(v)))
        return sign .. (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
    end

    -- the hub's engine: network, players, coins, fling, knife, the farm,
    -- the dead-server hop, auto-reset / anti-AFK and Performance Mode
local function makeHttpRequest(url)
    local ok, result = pcall(function()
        if syn and syn.request then
            return HttpService:JSONDecode(syn.request({ Url = url, Method = "GET" }).Body)
        elseif http and http.request then
            return HttpService:JSONDecode(http.request({ Url = url, Method = "GET" }).Body)
        elseif request then
            return HttpService:JSONDecode(request({ Url = url, Method = "GET" }).Body)
        elseif httpget then
            return HttpService:JSONDecode(httpget(url))
        else
            return HttpService:JSONDecode(game:HttpGet(url))
        end
    end)
    if ok then return result end
    return nil
end

    local placeId      = game.PlaceId
    local currentJobId = game.JobId

local function findMurderer()
    for _, i in ipairs(Players:GetPlayers()) do
        -- FindFirstChildOfClass, not i.Backpack: a player who joined a moment
        -- ago has not replicated their Backpack yet, and indexing it throws
        -- "Backpack is not a valid member of Player". That error killed the
        -- loop that calls this, which is why ESP stopped updating for anyone
        -- who joined mid-session.
        local bp = i:FindFirstChildOfClass("Backpack")
        if bp and bp:FindFirstChild("Knife") then return i end
    end
    for _, i in ipairs(Players:GetPlayers()) do
        if i.Character and i.Character:FindFirstChild("Knife") then return i end
    end
    if playerData then
        for player, data in pairs(playerData) do
            if data.Role == "Murderer" and Players:FindFirstChild(player) then
                return Players:FindFirstChild(player)
            end
        end
    end
    return nil
end

function ONX.reclip(store)
    for part in next, store do
        pcall(function() if part.Parent then part.CanCollide = true end end)
    end
    for part in next, store do store[part] = nil end
end

-- Live lobby check. The farm's own `inLobby` is latched: setupAutofarm opens
-- with `if inLobby then return end`, so the first time it evaluates true it
-- can never go back. Now that the config restores Coin Autofarm on load, the
-- farm starts while the script is still loading -- in the lobby, that pinned
-- inLobby true for the whole session, which silently disabled the untoggle
-- teleport and made coinCount read the lobby GUI. Always ask, never cache.
function ONX.inLobbyNow()
    local lp = game:GetService("Players").LocalPlayer
    local pg = lp and lp:FindFirstChild("PlayerGui")
    local main = pg and pg:FindFirstChild("MainGUI")
    local gameGui = main and main:FindFirstChild("Game")
    if not gameGui then return true end
    return gameGui:FindFirstChild("Inventory") == nil
end

-- Coins the farm could not actually reach. Without this the retry watchdog
-- drops the target and nearestCoin hands back the very same coin a tenth of a
-- second later, so the farm rows at an unreachable coin forever -- which is
-- what "stuck when no coins are around" actually is: the only coins left are
-- ones it cannot get to.
ONX.coinFails, ONX.coinSkips = {}, {}

function ONX.coinSkip(coin)
    local until_ = ONX.coinSkips[coin]
    if not until_ then return false end
    if tick() > until_ then
        ONX.coinSkips[coin] = nil
        ONX.coinFails[coin] = nil
        return false
    end
    return true
end

function ONX.coinFailed(coin)
    local n = (ONX.coinFails[coin] or 0) + 1
    ONX.coinFails[coin] = n
    -- two honest attempts before giving up on it for a while
    if n >= 2 then ONX.coinSkips[coin] = tick() + 20 end
end

function ONX.coinReset()
    ONX.coinFails, ONX.coinSkips = {}, {}
end

local flingActive = false
local flingTargetName
-- what the island shows for a fling: one throw, or a loop that's waiting
C.flingNow = function()
    if ONX.flingLoopOn then
        -- one name and how many more ("Flinging elif +2"); hover lists them all
        local who = ONX.flingLoopNames and ONX.flingLoopNames() or {}
        local name = who[1] and who[1].name or "them"
        if #who > 1 then
            if #name > 9 then name = name:sub(1, 8) .. "…" end
            name = ("%s +%d"):format(name, #who - 1)
        end
        return { title = "Flinging " .. name, avatar = who[1] and who[1].id, people = #who > 1 and who or nil }
    end
    if flingActive then return { title = "Flinging " .. (flingTargetName or "them"), avatar = ONX.flingTargetId } end
    return nil
end

local function flingPlayer(targetPlayer, quiet, holdCam)
    if flingActive then
        WindUI:Notify({ Title = "Fling Active!", Content = "Wait for the current fling to finish!", Duration = 1.5, Icon = "clock" })
        return
    end
    if not targetPlayer or not targetPlayer.Character then
        WindUI:Notify({ Title = "Error!", Content = "Could not find that player!", Duration = 1.5, Icon = "x" })
        return
    end
    if not targetPlayer.Character:FindFirstChildOfClass("Humanoid") then return end
    local myChar = LocalPlayer.Character; if not myChar then return end
    local myHum = myChar:FindFirstChildOfClass("Humanoid"); if not myHum then return end
    local myHRP = myHum.RootPart; if not myHRP then return end
    flingActive = true
    flingTargetName = targetPlayer.DisplayName
    ONX.flingTargetId = targetPlayer.UserId

    local savedPos  = myHRP.CFrame
    local savedFPDH = Workspace.FallenPartsDestroyHeight
    -- The fling works by ramming your own character into the target for up to
    -- two seconds. If that target is the murderer, you are standing inside the
    -- knife the whole time -- which is how flinging sometimes killed the
    -- flinger. Bail on the FIRST point of damage instead of waiting to be
    -- dead, so the second hit never lands.
    local myStartHP = myHum.Health
    local tChar = targetPlayer.Character
    local tHum  = tChar:FindFirstChildOfClass("Humanoid")
    local tHRP  = tHum and tHum.RootPart
    local tHead = tChar:FindFirstChild("Head")
    local tAccessory = tChar:FindFirstChildOfClass("Accessory")
    local tHandle = tAccessory and tAccessory:FindFirstChild("Handle")

    if tHum and tHum.Sit then flingActive = false; return end

    -- You see it happen, and you stay upright, facing the way you were -- no
    -- spinning. The throw comes from the velocity trick in throwFrom instead.
    --
    -- The camera rides a stand-in that eases after the action: across to them
    -- as you snap on, along with them for the throw, and back to you after.
    -- Following your own root is what glitched it -- the root hops round
    -- them every frame, and the camera hopped with it. Once they're thrown it
    -- holds still rather than chase them off the map.
    local cam = Workspace.CurrentCamera
    local EYE_UP = Vector3.new(0, 1.5, 0)   -- where the camera looks on a character
    local eye = Instance.new("Part")
    eye.Name, eye.Anchored, eye.CanCollide, eye.CanTouch, eye.CanQuery = "Part", true, false, false, false
    eye.Transparency, eye.Size = 1, Vector3.new(0.2, 0.2, 0.2)
    eye.CFrame = CFrame.new(myHRP.Position + EYE_UP)
    eye.Parent = Workspace
    cam.CameraSubject = eye
    -- holdCam (the Loop): the camera doesn't go anywhere -- it stays on the
    -- spot you're throwing from, which is where you come back to
    local eyeOnThem, eyeHome = not holdCam, false
    local eyeConn = RunService.RenderStepped:Connect(function(dt)
        local goal
        if eyeOnThem then
            -- follows your own character, smoothed: the root hops round them
            -- every frame, and the easing irons that out into one steady
            -- glide over and back (it used to watch them instead)
            if myHRP.Parent then goal = myHRP.Position + EYE_UP end
        elseif holdCam and not eyeHome then
            goal = savedPos.Position + EYE_UP
        elseif myHRP.Parent then
            goal = myHRP.Position + EYE_UP
        end
        if goal then eye.CFrame = CFrame.new(eye.Position:Lerp(goal, 1 - math.exp(-dt * 10))) end
    end)
    local look = savedPos.LookVector * Vector3.new(1, 0, 1)
    local facing = look.Magnitude > 0.01 and CFrame.lookAt(Vector3.zero, look.Unit).Rotation or CFrame.identity
    local touching = {}
    for _, d in ipairs(myChar:GetDescendants()) do
        -- Some maps put a kill volume just over the ceiling to stop roof
        -- glitching -- Mansion 2's starts ~24 studs above the floor -- and a
        -- throw could pop you into it: the "backfire" that only ever
        -- happened there. Your parts stop reporting touches for the throw;
        -- collisions are untouched, so the throw itself works the same.
        if d:IsA("BasePart") and d.CanTouch then
            touching[d] = true
            d.CanTouch = false
        end
    end

    -- Where to stand round them, measured from the way they face (+Z is
    -- behind a character): dead centre (the hardest hit), pressed into their
    -- back, at head and legs, a touch to each side, and where their head goes
    -- when they jump -- a jump their own game started before you saw it.
    local OFFSETS = {
        Vector3.new(0, 0, 0), Vector3.new(0, 0.4, 1.0), Vector3.new(0, 1.8, 0.4), Vector3.new(0, -1.2, 0.6),
        Vector3.new(0.9, 0.3, 0.6), Vector3.new(-0.9, 0.3, 0.6), Vector3.new(0, 2.8, 0),
    }
    -- The velocity trick: right after physics each frame (Heartbeat, which
    -- is what gets sent out) your root carries a huge velocity, and it's
    -- zeroed again before your own frame draws and before the next physics
    -- step. Their game sees you slam into them at that speed and throws
    -- them; on yours you never move or spin.
    local HUGE, SPIN = Vector3.new(9e7, 9e7 * 10, 9e7), Vector3.new(9e8, 9e8, 9e8)
    local G = Vector3.new(0, -Workspace.Gravity, 0)
    local ping = 0.05
    pcall(function() ping = math.clamp(LocalPlayer:GetNetworkPing(), 0, 0.3) end)
    -- How far ahead to aim. The hit happens on THEIR screen, and two delays
    -- stack up before you get there: what you see of them is already late
    -- (their moves travel to you), and where you put yourself shows up late
    -- again on theirs (yours travel to them, and both games smooth other
    -- players over a short buffer) -- about 0.3-0.5s all told. The old aim
    -- topped out near 0.25s, so a runner was always a few studs ahead of it.
    -- Nobody can know the exact delay, so the aim sweeps the whole range.
    local MAX_LEAD = math.clamp(ping * 2 + 0.35, 0.3, 0.8)
    local SWEEP = 12            -- frames for one sweep out and back (~0.2s)
    local flung = false
    local function throwFrom(bp)
        local startT, step = tick(), 0
        -- their last positions on your screen: a remote character's own
        -- velocity reads noisy (often zero), so their speed is measured from
        -- how they've actually moved over the last fifth of a second
        local hist = {}
        RunService.Heartbeat:Wait()
        repeat
            if not myHRP.Parent or not tHum or not flingActive then break end
            step += 1
            local now, pos = os.clock(), bp.Position
            local last = hist[#hist]
            -- thrown: they shot off faster than anyone walks, jumps or falls
            if last and now > last[1] and (pos - last[2]).Magnitude / (now - last[1]) > 250 then flung = true; break end
            hist[#hist + 1] = { now, pos }
            while #hist > 2 and now - hist[1][1] > 0.2 do table.remove(hist, 1) end
            local v = Vector3.zero
            if now - hist[1][1] > 0.03 then v = (pos - hist[1][2]) / (now - hist[1][1]) end
            if v.Magnitude > 120 then v = Vector3.zero end
            -- Jumpers: on the ground their up/down speed is noise, so it's
            -- ignored; in the air the aim follows the arc (gravity pulls the
            -- spot back down). Never aimed below where their feet can go.
            local airborne = tHum.FloorMaterial == Enum.Material.Air
            if not airborne then v = Vector3.new(v.X, 0, v.Z) end
            -- The lead runs from nothing out to MAX_LEAD and back every SWEEP
            -- frames, so whatever the real delay is, one of the next few
            -- frames is on them -- and since their game smooths you from spot
            -- to spot, you sweep right through their path in between. The
            -- spot round them steps on with a different rhythm (7 against
            -- 12), so every lead meets every spot.
            local phase = (step % SWEEP) / SWEEP
            local t = MAX_LEAD * (phase < 0.5 and phase * 2 or (1 - phase) * 2)
            local at = pos + v * t
            if airborne then at += G * (0.5 * t * t) end
            at = Vector3.new(at.X, math.max(at.Y, pos.Y - 3), at.Z)
            -- their facing, flat (a tilted root mid-jump shouldn't tip the pattern)
            local look = bp.CFrame.LookVector * Vector3.new(1, 0, 1)
            local yaw = look.Magnitude > 0.01 and CFrame.lookAt(Vector3.zero, look.Unit) or facing
            myHRP.CFrame = CFrame.new(at + yaw:VectorToWorldSpace(OFFSETS[step % #OFFSETS + 1])) * yaw
            myHRP.Velocity, myHRP.RotVelocity = HUGE, SPIN
            RunService.RenderStepped:Wait()
            if myHRP.Parent then myHRP.Velocity, myHRP.RotVelocity = Vector3.zero, Vector3.zero end
            RunService.Heartbeat:Wait()
        until flung or bp.Velocity.Magnitude > 500 or bp.Parent ~= targetPlayer.Character
            or targetPlayer.Parent ~= Players or myHum.Health <= 0
            or myHum.Health < myStartHP
            or (tHum and tHum.Sit) or tick() > startT + 6 or not flingActive
    end

    Workspace.FallenPartsDestroyHeight = 0/0
    local bv = Instance.new("BodyVelocity")
    bv.Name = "SkidFlingBV"; bv.Parent = myHRP
    bv.Velocity = Vector3.new(0,0,0); bv.MaxForce = Vector3.new(1/0,1/0,1/0)
    myHum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

    -- pcall'd as a unit. throwFrom reads the target's parts for up to 2.5
    -- seconds; if they die or leave mid-fling those reads throw, and the throw
    -- used to escape past the FallenPartsDestroyHeight restore below -- leaving
    -- the void set to NaN for the rest of the session, so nothing ever fell out
    -- of the map again.
    pcall(function()
        if tHRP and tHead then
            if (tHRP.CFrame.p - tHead.CFrame.p).Magnitude <= 5 then throwFrom(tHRP) else throwFrom(tHead) end
        elseif tHRP then throwFrom(tHRP)
        elseif tHead then throwFrom(tHead)
        elseif tHandle then throwFrom(tHandle) end
    end)

    bv:Destroy()
    myHum:SetStateEnabled(Enum.HumanoidStateType.Seated, true)

    -- Same reason as above: dying during the return trip destroys myHRP, and an
    -- error here would skip the restore below just as effectively.
    if savedPos then
        pcall(function()
            for _ = 1, 50 do
                myHRP.CFrame = savedPos * CFrame.new(0,0.5,0)
                pcall(function() myChar:SetPrimaryPartCFrame(savedPos * CFrame.new(0,0.5,0)) end)
                myHum:ChangeState("GettingUp")
                for _, p in ipairs(myChar:GetChildren()) do
                    if p:IsA("BasePart") then p.Velocity = Vector3.zero; p.RotVelocity = Vector3.zero end
                end
                task.wait()
                if (myHRP.Position - savedPos.p).Magnitude < 25 then break end
            end
        end)
    end

    -- unconditional: this was only restored inside the savedPos branch, and a
    -- NaN destroy height left behind means the void stops working entirely
    Workspace.FallenPartsDestroyHeight = savedFPDH

    -- back where you were: let touches through again
    for d in pairs(touching) do if d.Parent then d.CanTouch = true end end
    -- the camera eases home, then goes back to following you as normal
    eyeOnThem, eyeHome = false, true
    task.spawn(function()
        local t0 = os.clock()
        repeat RunService.RenderStepped:Wait()
        until not myHRP.Parent or (eye.Position - (myHRP.Position + EYE_UP)).Magnitude < 0.25 or os.clock() - t0 > 1.2
        eyeConn:Disconnect()
        -- only if this fling's eye still has the camera: a looped fling can
        -- start the next throw before this one's eye got home, and taking
        -- the camera back then yanked it off the new throw mid-flight
        if cam.CameraSubject == eye then
            cam.CameraSubject = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")) or myHum
        end
        eye:Destroy()
    end)

    flingActive = false
    if quiet then return end

    if myHum.Health <= 0 then
        WindUI:Notify({
            Title = "Fling Backfired",
            Content = targetPlayer.Name .. " killed you mid-fling.",
            Duration = 3, Icon = "x",
        })
    elseif myHum.Health < myStartHP then
        WindUI:Notify({
            Title = "Flinged!",
            Content = "Flinged " .. targetPlayer.Name .. " - took a hit, bailed early.",
            Duration = 2, Icon = "flame",
        })
    else
        WindUI:Notify({ Title = "Flinged!", Content = "Flinged " .. targetPlayer.Name .. "!", Duration = 1.5, Icon = "flame" })
    end
end

    local killAll
    do
    local function equippedKnife()
        local char = LocalPlayer.Character
        if not char then return nil end
        local knife = char:FindFirstChild("Knife")
        if knife then return knife, char end
        local bp = LocalPlayer:FindFirstChild("Backpack")
        local tool = bp and bp:FindFirstChild("Knife")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if tool and hum then
            hum:EquipTool(tool)
            task.wait(0.1)
            char = LocalPlayer.Character
            return char and char:FindFirstChild("Knife"), char
        end
        return nil
    end

    local function stabTargets(targets, noEquip)
        local knife
        if noEquip then
            local char = LocalPlayer.Character
            knife = char and char:FindFirstChild("Knife")
        else
            knife = equippedKnife()
        end
        local events = knife and knife:FindFirstChild("Events")
        if not events then return 0 end

        local stabbed = events:FindFirstChild("KnifeStabbed")
        local touched = events:FindFirstChild("HandleTouched")
        if not (stabbed and touched) then return 0 end

        pcall(function() stabbed:FireServer() end)

        local n = 0
        for _, p in ipairs(targets) do
            local ch = p.Character
            local part = ch and (ch:FindFirstChild("HumanoidRootPart")
                or ch:FindFirstChild("Torso") or ch:FindFirstChildWhichIsA("BasePart"))
            if part then
                pcall(function() touched:FireServer(part) end)
                n = n + 1
            end
        end
        return n
    end

    local function alivePlayers(withinRadius)
        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local inRange = true
                    if withinRadius and myHRP then
                        inRange = (hrp.Position - myHRP.Position).Magnitude <= withinRadius
                    end
                    if inRange then list[#list + 1] = p end
                end
            end
        end
        return list
    end

    function killAll()
        if findMurderer() ~= LocalPlayer then
            WindUI:Notify({ Title = "Not Murderer!", Content = "You don't have the knife.", Duration = 2, Icon = "x" })
            return
        end
        local n = stabTargets(alivePlayers(nil))
        WindUI:Notify({
            Title = "Kill All",
            Content = ("Stabbed %d player%s."):format(n, n == 1 and "" or "s"),
            Duration = 2, Icon = "check",
        })
    end

    end

    ONX.farmClipWas = {}
local farmRunning, farmAlive, coinMap, inLobby = false, false, nil, nil
local farmMoving, farmTween, farmCoin = false, nil, nil
local farmCollideConn = nil
-- the slider still reads 25 at the top end; the farm actually runs 23
local farmSpeed = 23
local coinStuckTime, coinStuckTarget = 0, nil

local autoResetOnFull, autoResetRunning = false, false
local antiAfkEnabled, antiAfkConnection = false, nil

local function findChildNamed(parent, name, className)
    for _, v in next, parent:GetChildren() do
        if v.Name == name and (not className or v.ClassName == className) then return v end
    end
end

local function rootOf(plr)
    if plr and plr.Character then
        return findChildNamed(plr.Character, "HumanoidRootPart")
            or findChildNamed(plr.Character, "PrimaryPart")
    end
end

-- The nearest coin that isn't parked -- and when every coin left IS parked
-- (skipped after two misses), the nearest parked one anyway. Parking is for
-- stepping round a coin that keeps failing while there are others to take;
-- with nothing else left, a coin that might fail beats standing still, which
-- is what it used to do: no "free" coin read as the map being cleared.
local function nearestCoin()
    local best, bestDist = nil, math.huge
    local parked, parkedDist = nil, math.huge
    local root = rootOf(LocalPlayer)
    if not root or not coinMap then return nil end
    local container = findChildNamed(coinMap, "CoinContainer")
    if not container then return nil end
    for _, coin in next, container:GetChildren() do
        if coin.Name == "Coin_Server" and not coin:GetAttribute("Collected") then
            local d = (root.Position - coin.Position).Magnitude
            if ONX.coinSkip(coin) then
                if d < parkedDist then parkedDist = d; parked = coin end
            elseif d < bestDist then
                bestDist = d; best = coin
            end
        end
    end
    return best or parked
end

local function roundTime()
    local timer = Workspace:FindFirstChild("RoundTimerPart")
    if timer then return tonumber(timer:GetAttribute("Time")) or 0 end
    return 0
end

-- CoinBags holds one frame per currency -- Coin, Candy, Egg, BeachBall,
-- SnowToken -- and only the one in play is Visible. This used to read Candy
-- outright, which is a seasonal bag: during a normal round it sits at "0"
-- while your coins pile up in Coin. So coinCount() always returned 0, the
-- `coinCount() >= 40` bag-full branch never fired, and with it neither the
-- auto-return nor the fling-when-done ever ran.
--
-- Take the visible bag, fall back to Coin, and treat the bag's own Full label
-- as authoritative -- it flips before the number stops climbing.
local function coinCount()
    local ok, val = pcall(function()
        local container
        if not ONX.inLobbyNow() then
            container = LocalPlayer.PlayerGui.MainGUI.Game.CoinBags.Container
        else
            container = LocalPlayer.PlayerGui.MainGUI.Lobby.Dock.CoinBags.Container
        end
        if not container then return 0 end

        local bag
        for _, kid in next, container:GetChildren() do
            if kid:IsA("GuiObject") and kid:FindFirstChild("CurrencyFrame") then
                if kid.Visible then bag = kid; break end
                if kid.Name == "Coin" and not bag then bag = kid end
            end
        end
        if not bag then return 0 end

        local full = bag:FindFirstChild("Full")
        if full and full.Visible then return 999 end

        local cf = bag:FindFirstChild("CurrencyFrame")
        local icon = cf and cf:FindFirstChild("Icon")
        local coins = icon and icon:FindFirstChild("Coins")
        local text = coins and coins.Text
        if text and (string.lower(text):find("full") or string.lower(text):find("max")) then return 999 end
        return tonumber(text) or 0
    end)
    if ok then return val end
    return 0
end

-- farm noclip: separate from the Player tab's noclip so the two
-- can't clobber each other's connection
local function farmNoclip(on)
    if on then
        if not farmCollideConn then
            -- Stepped, not Heartbeat. Heartbeat runs AFTER the physics step, so
            -- the humanoid had already re-enabled the root and torso parts by
            -- the time we cleared them -- 13 parts went through walls and
            -- HumanoidRootPart, LowerTorso and UpperTorso did not. Stepped is
            -- what the Player tab's noclip uses, and it holds.
            --
            -- Descendants, not children: accessory handles are nested.
            --
            -- Not gated on farmAlive either: that comes from a GetPlayerData
            -- poll, and any stale or failed read handed collisions back
            -- mid-flight and bounced the farm off walls.
            farmCollideConn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if char then
                    for _, v in next, char:GetDescendants() do
                        -- same bookkeeping as the Player tab's noclip: restore
                        -- only what we cleared, so accessory handles keep the
                        -- CanCollide = false they shipped with
                        if v:IsA("BasePart") and v.CanCollide then
                            if ONX.farmClipWas[v] == nil then ONX.farmClipWas[v] = true end
                            v.CanCollide = false
                        end
                    end
                end
            end)
        end
    else
        if farmCollideConn then farmCollideConn:Disconnect(); farmCollideConn = nil end
        ONX.reclip(ONX.farmClipWas)
    end
end

-- While farming, the camera rides a stand-in that eases after you, the same
-- way the fling camera does: the tween steps and the coin-pickup wiggle move
-- your root in little hops, and following the root directly showed every
-- one of them. The stand-in glides; when the farm stops it eases back onto
-- you and the camera follows your character as normal again.
function ONX.farmCam(on)
    local cam = Workspace.CurrentCamera
    local UP = Vector3.new(0, 1.5, 0)
    if on then
        if ONX.farmEye then return end
        local root = rootOf(LocalPlayer); if not root then return end
        local eye = Instance.new("Part")
        eye.Name, eye.Anchored, eye.CanCollide, eye.CanTouch, eye.CanQuery = "Part", true, false, false, false
        eye.Transparency, eye.Size = 1, Vector3.new(0.2, 0.2, 0.2)
        eye.CFrame = CFrame.new(root.Position + UP)
        eye.Parent = Workspace
        cam.CameraSubject = eye
        ONX.farmEye = eye
        ONX.farmEyeConn = RunService.RenderStepped:Connect(function(dt)
            local r = rootOf(LocalPlayer)
            if not r then return end
            local goal = r.Position + UP
            -- a jump across the world (a new round's map, the lobby) is a cut,
            -- not a long sweep; everything else glides, like the fling camera
            if (eye.Position - goal).Magnitude > 60 then
                eye.CFrame = CFrame.new(goal)
            else
                eye.CFrame = CFrame.new(eye.Position:Lerp(goal, 1 - math.exp(-dt * 10)))
            end
            -- Every respawn Roblox hands the camera to the new character, and the
            -- farm never took it back: from the second round on it followed your
            -- root directly again, hop by hop. Take it back -- but only from your
            -- own character (a fling or a spectate keeps theirs).
            local cam2 = Workspace.CurrentCamera
            local sub = cam2 and cam2.CameraSubject
            local char = LocalPlayer.Character
            if cam2 and sub ~= eye and (sub == nil or (char and sub:IsDescendantOf(char))) then
                cam2.CameraSubject = eye
            end
        end)
    else
        local eye, conn = ONX.farmEye, ONX.farmEyeConn
        if not eye then return end
        ONX.farmEye, ONX.farmEyeConn = nil, nil
        task.spawn(function()
            local t0 = os.clock()
            repeat RunService.RenderStepped:Wait()
                local r = rootOf(LocalPlayer)
            until not r or (eye.Position - (r.Position + UP)).Magnitude < 0.25 or os.clock() - t0 > 1
            if conn then conn:Disconnect() end
            -- (a fling may have taken the camera meanwhile: leave it to it)
            if cam.CameraSubject == eye then
                local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if hum then cam.CameraSubject = hum end
            end
            eye:Destroy()
        end)
    end
end

-- the flight rig the farm rides on, anchored to UpperTorso
local function farmRig(on)
    local torso = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("UpperTorso")
    -- no torso (dead, respawning): nothing to rig -- but switching OFF must
    -- still drop the noclip and the farm camera, which used to be skipped and
    -- left the farm eye running (and the next farmCam(true) then did nothing)
    if not torso then
        if not on then pcall(farmNoclip, false); ONX.farmCam(false) end
        return
    end
    local gyro = torso:FindFirstChild("ONX Auto Farm BodyGyro")
    local vel  = torso:FindFirstChild("ONX Auto Farm BodyVelocity")

    if on then
        if gyro or vel then return end
        local root = rootOf(LocalPlayer); if not root then return end
        local hum = LocalPlayer.Character:FindFirstChild("Humanoid"); if not hum then return end
        local cf = root.CFrame
        local flat = CFrame.new(cf.X, cf.Y, cf.Z) * CFrame.Angles(math.rad(90), 0, math.rad(90))
        farmNoclip(true)
        local g = Instance.new("BodyGyro")
        g.Name = "ONX Auto Farm BodyGyro"; g.Parent = torso
        g.P = 90000; g.MaxTorque = Vector3.new(9e9, 9e9, 9e9); g.CFrame = flat
        local v = Instance.new("BodyVelocity")
        v.Name = "ONX Auto Farm BodyVelocity"; v.Parent = torso
        v.Velocity = Vector3.zero; v.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        root.CFrame = flat
        hum.PlatformStand = true
        ONX.farmCam(true)
    else
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            if gyro then gyro:Destroy() end
            if vel then vel:Destroy() end
            hum.PlatformStand = false
            farmNoclip(false)
        end
        ONX.farmCam(false)
    end
end

local function teleportToMapSpawn()
    if not coinMap then return end
    local spawnPart
    for _, v in next, coinMap.Spawns:GetChildren() do
        if v.Name == "Spawn" or v.Name == "PlayerSpawn" or v.Name == "SpawnLocation" then spawnPart = v end
    end
    if not spawnPart then return end
    local cf = spawnPart.CFrame
    local root = rootOf(LocalPlayer)
    if root then
        root.Velocity = Vector3.zero
        root.CFrame = CFrame.new(cf.X, cf.Y + 5, cf.Z)
    end
end

local function setupAutofarm()
    -- recomputed every start; this used to return early when inLobby was
    -- already true, which made the flag permanent for the session
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local main = pg and pg:FindFirstChild("MainGUI")
        local gameGui = main and main:FindFirstChild("Game")
        if gameGui then inLobby = not gameGui:FindFirstChild("Inventory") end
    end)
    for _, v in next, Workspace:GetChildren() do
        if v:FindFirstChild("CoinAreas") or v:FindFirstChild("CoinContainer") then coinMap = v end
    end
    farmMoving, farmTween, farmCoin = false, nil, nil
end

local function stopFarmMovement()
    if farmMoving then
        farmMoving = false
        farmCoin = nil
        if LocalPlayer.Character then
            if farmTween then farmTween:Cancel(); farmTween = nil end
            farmRig(false)
            if roundTime() > 0 and coinMap then teleportToMapSpawn() end
        end
    end
end

local function startAutofarm()
    if farmRunning then return end
    farmRunning = true
    -- This run's number. A loop from an older run -- Stop then Start inside
    -- one tick, or a re-execution -- sees a different number and quits,
    -- instead of farming alongside this one.
    ONX.farmGen = (ONX.farmGen or 0) + 1
    local gen = ONX.farmGen
    setupAutofarm()

    task.spawn(function()
        while farmRunning and gen == ONX.farmGen do
            task.wait(0.1)
            pcall(function()
                -- The toggle can flip during the 0.1s wait above, after this
                -- iteration was already committed. Without this bail-out the
                -- tail iteration re-rigs and tweens you off to a coin right
                -- after stopAutofarm sent you home -- that is the half-second
                -- float. Only ever true when the farm is already off, so it
                -- changes nothing while farming.
                if not farmRunning or gen ~= ONX.farmGen then return end

                -- am I alive this round?
                if not LocalPlayer.Character then
                    farmAlive = false
                else
                    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                    local extras = remotes and remotes:FindFirstChild("Extras")
                    local gpd = extras and extras:FindFirstChild("GetPlayerData")
                    if gpd then
                        local ok, data = pcall(function() return gpd:InvokeServer() end)
                        if ok and data then
                            local info = data[LocalPlayer.Name]
                            farmAlive = info and (not info.Dead and not info.Killed)
                        end
                    end
                end
                -- The call above waits a full server round trip: the farm may
                -- have been stopped, restarted or torn down (re-execution)
                -- meanwhile, and going on re-rigged the character after
                -- cleanup, leaking a noclip and a camera connection.
                if not farmRunning or gen ~= ONX.farmGen then return end

                for _, v in next, Workspace:GetChildren() do
                    if v:FindFirstChild("CoinAreas") or v:FindFirstChild("CoinContainer") then coinMap = v end
                end

                -- A NEW map instance is the earliest and most reliable "new
                -- round" signal there is: the map is parented several seconds
                -- before RoundTimerPart starts counting. Per-round state resets
                -- here rather than when the timer runs out, so a map that
                -- lingers after the round cannot look like a fresh one.
                if coinMap ~= ONX.lastMap then
                    ONX.lastMap = coinMap
                    ONX.sawCoins = false
                    ONX.flingDoneFired = false
                    ONX.killFired = false
                    ONX.coinReset()
                end

                -- Cover as soon as the map exists and its coins have not
                -- spawned -- ahead of the roundTime check, since waiting for
                -- the timer is what left you standing in the open.
                --
                -- farmAlive is required and cannot be dropped: it is true only
                -- while the server lists you as a live player in this round.
                -- Sitting in the lobby while others play still leaves a map in
                -- Workspace and still leaves MainGUI.Game.Inventory present, so
                -- neither of those tells us apart from a real participant --
                -- without this the script yanked you under the map the moment
                -- it loaded in the lobby.
                local hideRoot = rootOf(LocalPlayer)
                if farmAlive and coinMap and hideRoot
                   and not ONX.sawCoins and not nearestCoin() then
                    if ONX.hideUnderMap(hideRoot) then return end
                end

                -- A throw is in progress (the finish fling): hands off. A coin
                -- spawning mid-throw used to re-rig you (noclip, BodyVelocity,
                -- the farm camera) and tween you away, so the throw missed.
                if flingActive then return end

                if roundTime() > 0 then
                    -- bag full? stop and go home
                    if coinCount() >= (LocalPlayer:GetAttribute("Elite") and 50 or 40) then
                        stopFarmMovement()
                        ONX.finishFling()

                        -- Murderer-only, once per round. killAll() already
                        -- refuses when you do not hold the knife, but it says so
                        -- with a notification -- checking first keeps it quiet
                        -- for the innocents this fires for every other round.
                        if ONX.killWhenFull and not ONX.killFired
                           and findMurderer() == LocalPlayer then
                            ONX.killFired = true
                            if C.island then C.island.note("Taking out everyone to end the round", 8) end
                            task.spawn(function() pcall(killAll) end)
                        end

                    elseif farmAlive and LocalPlayer.Character then
                        local root = rootOf(LocalPlayer)
                        local coin = root and nearestCoin()
                        if root and coin then
                            -- proof that coins really did exist this round
                            ONX.sawCoins = true
                            if coin ~= farmCoin or (farmCoin and farmCoin:GetAttribute("Collected")) then
                                -- new target: tween onto it
                                farmCoin = coin
                                farmMoving = true
                                ONX.farmTargetTime = tick()
                                if farmTween then farmTween:Cancel(); farmTween = nil end
                                farmRig(true)
                                local cf = coin.CFrame
                                -- where the coin really is (the wiggle below moves it
                                -- on your screen only)
                                ONX.farmCoinPos = coin.Position
                                local dur = (root.Position - coin.Position).Magnitude / farmSpeed
                                -- (no more "over 15s? do it in 3": that shot you
                                -- across the map at many times the speed you set
                                -- whenever a coin was far or the speed was low)
                                if dur < 0.05 then dur = 0.05 end
                                ONX.farmTargetDur = dur * 1.2
                                root.Velocity = Vector3.zero
                                -- eased in and out (was Linear: full speed from
                                -- the first frame and a dead stop on the coin,
                                -- the jolt at every coin). A touch longer so the
                                -- faster middle stays near the speed you set.
                                farmTween = TweenService:Create(root,
                                    TweenInfo.new(dur * 1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                                    { CFrame = CFrame.new(cf.X, cf.Y - 3.5, cf.Z)
                                        * CFrame.Angles(math.rad(90), 0, math.rad(90)) })
                                farmTween:Play()
                                root.Velocity = Vector3.zero
                            else
                                local dist = (root.Position - coin.Position).Magnitude
                                if dist <= 6 and not coin:GetAttribute("Collected") then
                                    -- The coin is the server's: shuffling it onto you only
                                    -- moves it on YOUR screen, and the server checks its
                                    -- own copy, 3.5 studs above you -- sometimes close
                                    -- enough, sometimes not (the hover with no pickup).
                                    -- So: touch it as well, and if it still hasn't come
                                    -- after a moment, move up beside it.
                                    if firetouchinterest then
                                        local ti = coin:FindFirstChildOfClass("TouchTransmitter")
                                            or coin:FindFirstChildWhichIsA("TouchTransmitter", true)
                                        if ti then
                                            local part = ti.Parent
                                            pcall(firetouchinterest, root, part, 0)
                                            pcall(firetouchinterest, root, part, 1)
                                        end
                                    end
                                    if coinStuckTarget == coin and tick() - coinStuckTime > 0.5 then
                                        root.CFrame = CFrame.new((ONX.farmCoinPos or coin.Position) - Vector3.new(0, 1.2, 0))
                                            * CFrame.Angles(math.rad(90), 0, math.rad(90))
                                    end
                                    -- Wiggle the coin onto the player to force pickup.
                                    --
                                    -- Built from root.POSITION, not root.CFrame. The
                                    -- offset reads as "jitter sideways a little, sweep
                                    -- 0-3 studs up the body", which is only true for an
                                    -- upright root -- and farmRig deliberately rotates
                                    -- this one by Angles(90, 0, 90). Under that rotation
                                    -- local +Y is world -X, so the vertical sweep was
                                    -- actually throwing the coin up to 3 studs SIDEWAYS
                                    -- and the real vertical spread was only the +-0.8
                                    -- from local Z.
                                    --
                                    -- Rolls past ~1.5 therefore put the coin outside
                                    -- touch range: about four ticks in ten missed, and a
                                    -- run of misses is the half-second hover with the
                                    -- coin sitting visibly above you. In world space the
                                    -- whole range lands on the character instead.
                                    coin.CFrame = CFrame.new(root.Position + Vector3.new(
                                        math.random(-80, 80)/100,
                                        math.random(-50, 300)/100,
                                        math.random(-80, 80)/100))
                                    if (coin.Position - root.Position).Magnitude > 0.1 then
                                        root.CFrame = root.CFrame * CFrame.new(0,
                                            math.random(-20, 20)/100,
                                            math.random(-20, 20)/100)
                                    end
                                    -- stuck on the same coin >2s? drop it and retarget
                                    if coinStuckTarget ~= coin then
                                        coinStuckTarget = coin; coinStuckTime = tick()
                                    end
                                    if tick() - coinStuckTime > 2 then
                                        -- in reach but never picked up (the server
                                        -- rejects it): count it too, or it stays the
                                        -- nearest coin and gets retried forever
                                        ONX.coinFailed(coin)
                                        coinStuckTarget = nil; coinStuckTime = 0; farmCoin = nil
                                    end
                                elseif dist > 6 then
                                    -- tween ended but we never got there: blocked,
                                    -- the coin moved, or the tween was cancelled.
                                    -- Nothing else retargets this case, so it used
                                    -- to hover out of reach forever.
                                    --
                                    -- Measured from the trip's own length. A flat 4
                                    -- seconds failed every coin further than 4s away
                                    -- while you were still flying to it -- twice, so
                                    -- it got parked -- and with only far coins left
                                    -- the farm stood there as if the map was clear.
                                    if tick() - ONX.farmTargetTime > (ONX.farmTargetDur or 0) + 3 then
                                        -- count it against this coin, so a coin
                                        -- we simply cannot reach gets parked
                                        -- instead of retried forever
                                        ONX.coinFailed(coin)
                                        farmCoin = nil
                                        coinStuckTarget = nil; coinStuckTime = 0
                                    end
                                end
                            end
                        elseif root then
                            if ONX.sawCoins then
                                -- we cleared the map: drop the rig and wait on
                                -- the ground rather than hovering
                                stopFarmMovement()
                                ONX.finishFling()
                            end
                            -- the pre-coin case never reaches here: the hide
                            -- check above returns out of the tick first
                        end
                    else
                        -- dead, spectating, or no character. Nothing above runs
                        -- in that state, so without this the rig stays bolted on
                        -- and you hang in the air until the round ends.
                        stopFarmMovement()
                    end
                else
                    -- Round over. Deliberately does NOT reset sawCoins here:
                    -- the map often lingers for a few seconds afterwards, and
                    -- clearing the flag made that stale map look like a fresh
                    -- round, so the hide check dived under it. The map-change
                    -- detector at the top of the tick owns those resets now.
                    stopFarmMovement()
                end
            end)
        end
    end)
end

-- A positive RoundTimerPart is NOT enough: the same part counts down the
-- intermission, and out of round it reads -1 only once the map is gone.
-- Deliberately does NOT invoke GetPlayerData -- that remote yields, and this
-- runs on the untoggle path where any yield shows up as a visible delay
-- before the teleport. farmAlive already holds the loop's last reading.
-- Keyed on the map, not the round timer.
--
-- The old version required roundTime() > 0 AND farmAlive. Both are false in
-- exactly the situation where the teleport matters most: parked under the map
-- waiting for coins. The map is parented seconds before the timer starts, and
-- farmAlive lags a GetPlayerData round-trip behind, so untoggling down there
-- failed the check, skipped the teleport and just dropped you.
--
-- A map being present in Workspace already means "a round is set up" -- there
-- is no map during intermission -- so it is the better signal, and a live
-- humanoid is a local, instant stand-in for farmAlive.
function ONX.inActiveRound()
    if ONX.inLobbyNow() then return false end
    -- Same reason as the hide check: a map in Workspace and a present
    -- Inventory frame both look identical whether you are playing the round or
    -- sitting in the lobby watching it. Only the server round entry, which
    -- farmAlive mirrors, actually distinguishes the two.
    if not farmAlive then return false end

    local map
    for _, v in next, Workspace:GetChildren() do
        if v:FindFirstChild("CoinAreas") or v:FindFirstChild("CoinContainer") then map = v end
    end
    if not map then return false end

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end

    coinMap = map
    return true
end

-- Untoggle-only teleport. teleportToMapSpawn is left alone because the farm
-- loop calls it too; this one lands you standing and clear of the pad instead
-- of half-sunk, which is what the leftover PlatformStand ragdoll caused.
function ONX.teleportHome()
    if not coinMap then return end
    local spawns = coinMap:FindFirstChild("Spawns")
    if not spawns then return end

    local spawnPart, anyPart
    for _, v in next, spawns:GetChildren() do
        if v:IsA("BasePart") then
            anyPart = anyPart or v
            if v.Name == "Spawn" or v.Name == "PlayerSpawn" or v.Name == "SpawnLocation" then spawnPart = v end
        end
    end
    spawnPart = spawnPart or anyPart
    if not spawnPart then return end

    local root = rootOf(LocalPlayer)
    if not root then return end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end

    local cf = spawnPart.CFrame
    root.Velocity = Vector3.zero
    root.RotVelocity = Vector3.zero
    -- clear the pad by half its thickness plus head-room, and drop the rig's
    -- 90-degree flat rotation by building an upright CFrame from scratch
    root.CFrame = CFrame.new(cf.X, cf.Y + (spawnPart.Size.Y / 2) + 4, cf.Z)
end

local function stopAutofarm()
    -- original stop path, unchanged
    farmRunning = false
    -- a new run number: the old loop quits for good even if Start is pressed
    -- again inside its 0.1s wait, and the late sweep below can tell a restart
    ONX.farmGen = (ONX.farmGen or 0) + 1
    local stopGen = ONX.farmGen
    if farmTween then pcall(function() farmTween:Cancel() end); farmTween = nil end
    pcall(function() farmRig(false) end)

    -- Everything below is the untoggle teleport, bolted on after the original
    -- stop. Nothing here yields, so the teleport lands on the same frame you
    -- click -- no yielding remote calls, no wait before the move.
    local goHome = false
    pcall(function()
        if not (LocalPlayer.Character and rootOf(LocalPlayer)) then return end
        goHome = ONX.inActiveRound()
        if goHome then ONX.teleportHome() end
    end)

    -- The loop ticks every 0.1s and can be mid-iteration when farmRunning
    -- flips, re-creating the rig right after we removed it -- that's what left
    -- you floating. Sweep again once it has definitely exited. Only re-teleport
    -- if that late tick actually put the rig back, so this never yanks you
    -- after you have started walking.
    task.spawn(function()
        task.wait(0.35)
        -- started again meanwhile: that run's rig and tween are not leftovers
        if farmRunning or ONX.farmGen ~= stopGen then return end
        pcall(function() if farmTween then farmTween:Cancel(); farmTween = nil end end)
        pcall(function() farmRig(false) end)

        local leftovers = false
        pcall(function()
            local char = LocalPlayer.Character
            if not char then return end
            for _, d in next, char:GetDescendants() do
                if d.Name == "ONX Auto Farm BodyGyro" or d.Name == "ONX Auto Farm BodyVelocity" then
                    d:Destroy(); leftovers = true
                end
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.PlatformStand then
                hum.PlatformStand = false
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                leftovers = true
            end
        end)

        if goHome and leftovers then pcall(ONX.teleportHome) end
    end)
end

--// Dead-server hop (autofarm) --------------------------------
-- A server that has emptied out cannot start a round, so the farm sits there
-- earning nothing. This notices and moves.
--
-- Deliberately NOT smallestServerHop: that one hunts the emptiest server, which
-- is the exact thing we are trying to leave. This wants a BUSY one -- but not
-- the busiest, because every farmer running this logic would pile into the same
-- server, so it picks at random from the healthy ones.
ONX.HOP_MIN_PLAYERS = 2   -- "under 2 players" -- i.e. you, alone
ONX.HOP_GRACE = 15        -- seconds the server must stay that empty
ONX.HOP_RETRY = 60        -- seconds before trying again after a failed hop
ONX.HOP_CONFIRM = 6      -- seconds to wait before calling a queued teleport refused
ONX.hopThread = nil
ONX.hopping = false

-- Split in two on purpose: hopAttempt does the work and says whether we are
-- actually leaving, populatedHop owns the ONX.hopping latch and guarantees it
-- is released on every path that is NOT a departure -- including a thrown one.
--
-- Holding the latch is what stops a teleport being re-fired every few seconds
-- at a server already refusing them. But anything that threw between taking
-- the latch and clearing it used to wedge the feature for the rest of the
-- session: the watcher pcalls this, so the error was swallowed, and every
-- later attempt then returned false at the first line with no notification.
function ONX.hopAttempt(reason)
    if reason == "idle" then
        WindUI:Notify({
            Title = "Hopping servers",
            Content = "No round in 6 minutes - finding a server that's playing...",
            Duration = 4, Icon = "loader",
        })
    else
        WindUI:Notify({
            Title = "Server Empty",
            Content = "Under " .. ONX.HOP_MIN_PLAYERS .. " players here - hopping...",
            Duration = 4, Icon = "loader",
        })
    end
    task.wait(0.5)

    -- Matchmaking first, deliberately, and this is the part that took measuring.
    --
    -- The obvious version picks a busy server out of the public list. On this
    -- game that list cannot supply one: asked ascending, the first 300 servers
    -- with room ALL held 1-2 players; asked descending, the first 100 were
    -- 12/12 full. Populated and joinable is very nearly an empty set, so
    -- hand-picking lands you in another dead server -- exactly what we are
    -- trying to leave. A plain Teleport hands the choice to Roblox's own
    -- matchmaker, which fills servers rather than starving them.
    --
    -- Teleport is ASYNCHRONOUS: it queues and returns, so a pcall that does not
    -- throw says nothing about whether we leave. Treating that as a departure
    -- was the bug -- on a refused teleport (rate limit, TeleportInitFailed) the
    -- watcher exited on a hop that never happened and the farm sat in the dead
    -- server for good. If we are still here after the wait it was refused, so
    -- fall through to the list instead of claiming success. On a real teleport
    -- the client is gone part-way through the wait and nothing below runs.
    if pcall(function() TeleportService:Teleport(placeId) end) then
        task.wait(ONX.HOP_CONFIRM)
    end

    -- Fallback for when matchmaking refuses outright: the list, used the only
    -- way it can be -- the most populated server that still has a slot. No
    -- minimum, because on this game a "good" candidate is a 2-player server.
    WindUI:Notify({ Title = "Matchmaking Refused", Content = "Picking from the server list...", Duration = 3, Icon = "x" })

    local best, cursor, pages = nil, "", 0
    while pages < 4 do
        pages = pages + 1
        local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Desc&limit=100"
        if cursor ~= "" then url = url .. "&cursor=" .. cursor end
        local result = makeHttpRequest(url)
        if not result or not result.data then break end
        for _, sv in ipairs(result.data) do
            if sv.id ~= currentJobId and sv.playing and sv.maxPlayers
               and sv.playing < sv.maxPlayers then
                if (not best) or sv.playing > best.playing then best = sv end
            end
        end
        cursor = result.nextPageCursor or ""
        if cursor == "" then break end
    end

    if best then
        WindUI:Notify({
            Title = "Hopping",
            Content = "Joining a server with " .. best.playing .. " players...",
            Duration = 3, Icon = "check",
        })
        task.wait(0.5)
        if pcall(function() TeleportService:TeleportToPlaceInstance(placeId, best.id) end) then
            task.wait(ONX.HOP_CONFIRM)
        end
    end

    -- Still running means neither route took us anywhere.
    return false
end

function ONX.populatedHop(reason)
    if ONX.hopping then return false end
    ONX.hopping = true
    -- which watcher thread holds the latch: task.cancel on it (the farm
    -- switched off mid-hop) skips the release below, so the stop functions
    -- release it for the thread they kill
    ONX.hopOwner = coroutine.running()
    if C.island then
        C.island.note(reason == "idle" and "No round in 6 minutes, rejoining a new server"
                      or "Server emptied out, rejoining a busier one", 60)
    end

    local ok, left = pcall(ONX.hopAttempt, reason)
    if ok and left then return true end

    ONX.hopping, ONX.hopOwner = false, nil
    -- replace the "rejoining..." note, or the island kept saying it for a minute
    if C.island then C.island.note("Hop failed, staying here for now", 5) end
    WindUI:Notify({
        Title = "Hop Failed",
        Content = ok and "The server would not let go. Trying again in a minute."
                     or "Hop errored - trying again in a minute.",
        Duration = 4, Icon = "x",
    })
    return false
end

-- Killing a watcher mid-hop must not leave the latch stuck on for the session.
function ONX.releaseHop(thread)
    if thread and ONX.hopOwner == thread then ONX.hopping, ONX.hopOwner = false, nil end
end

function ONX.stopFarmHopWatch()
    if ONX.hopThread then
        pcall(task.cancel, ONX.hopThread)
        ONX.releaseHop(ONX.hopThread)
        ONX.hopThread = nil
    end
end

-- Grace period rather than an instant trigger: player counts dip for a moment
-- whenever a round ends and half the server rejoins, and hopping on that blip
-- would leave a healthy server for no reason.
function ONX.startFarmHopWatch()
    ONX.stopFarmHopWatch()
    ONX.hopThread = task.spawn(function()
        local low = 0
        while true do
            task.wait(3)
            if not ONX.farmHopOn then low = 0 else
                if #Players:GetPlayers() < ONX.HOP_MIN_PLAYERS then
                    low = low + 3
                    if low >= ONX.HOP_GRACE then
                        low = 0
                        -- Returns true only when we are actually leaving, in
                        -- which case there is nothing left to watch. A failed
                        -- hop keeps the loop alive behind a cooldown, so an
                        -- empty server gets another attempt instead of being
                        -- monitored by a thread that has already exited.
                        local left = false
                        local ok, res = pcall(ONX.populatedHop)
                        if ok then left = res and true or false end
                        if left then return end
                        task.wait(ONX.HOP_RETRY)
                    end
                else
                    low = 0
                end
            end
        end
    end)
end

--// No-round hop (autofarm) -------------------------------------
-- A server can sit in the lobby for good -- too few players to start one, or
-- a round that just never comes -- and the farm earns nothing there. While the
-- farm is on and no round has been live for 5 minutes, a toast counts down the
-- last minute; at 6 it hops. A round starting, or the farm going off, calls it
-- off. Always on with the farm: it's the farm's own "this server is dead".
ONX.IDLE_WARN, ONX.IDLE_HOP = 300, 360
do
    local thread, toast
    local function callOff(title, body, kind)
        if toast and not toast.gone then
            task.spawn(toast.dismiss)
            if title then notify({ title = title, body = body, kind = kind }) end
        end
        toast = nil
    end
    function ONX.stopIdleHopWatch(quiet)
        if thread then pcall(task.cancel, thread); ONX.releaseHop(thread); thread = nil end
        if quiet then callOff() else callOff("Hop called off", "Autofarm is off, so you're staying in this server.", "info") end
    end
    function ONX.startIdleHopWatch()
        if thread then return end
        thread = task.spawn(function()
            local idle, warned = 0, false
            while true do
                task.wait(1)
                if not farmRunning then
                    idle, warned = 0, false
                elseif roundTime() > 0 then
                    if warned then callOff("Round started", "Staying in this server.", "success") end
                    idle, warned = 0, false
                elseif not ONX.hopping then
                    idle += 1
                    local left = ONX.IDLE_HOP - idle
                    if left <= 0 then
                        callOff()
                        local ok, res = pcall(ONX.populatedHop, "idle")
                        if ok and res then thread = nil; return end
                        -- refused: count the last minute down again
                        idle, warned = ONX.IDLE_WARN - 1, false
                    elseif idle >= ONX.IDLE_WARN then
                        local body = ("Moving to a new server in %ds. Turn off Autofarm to stay here."):format(left)
                        if not warned then
                            -- the card's own bar runs down with the clock;
                            -- closing it just hides it, the hop still goes
                            warned = true
                            toast = notify({ title = "No round for 5 minutes", body = body, kind = "wait",
                                             duration = left, key = "idlehop" })
                        elseif toast and not toast.gone then
                            toast.set(nil, body)
                        end
                    end
                end
            end
        end)
    end
end

function ONX.setToggle(el, want, fallback)
    ONX.sfxQuiet = true
    local done = false
    pcall(function()
        if el then
            for _, m in ipairs({ "SetValue", "Set", "UpdateValue" }) do
                if type(el[m]) == "function" then
                    if pcall(function() el[m](el, want) end) then
                        done = true
                        return
                    end
                end
            end
        end
    end)
    if not done and fallback then pcall(fallback, want) end
    ONX.sfxQuiet = false
    return done
end

--// Tuck under the map while waiting for coins ------------------
-- A round starts before its coins do. Standing at the map spawn during that
-- window is the most dangerous place to be, so drop below the floor and hold
-- there until they appear. farmRig gives us exactly what that needs already:
-- noclip to get through the floor, a BodyVelocity pinned at zero so we hang
-- instead of falling, and PlatformStand so the humanoid stops fighting it.
-- Just under the floor, not out in the void. 60 put you so far below the map
-- that you were nowhere near the coins when they spawned.
ONX.underMapDepth = 15

function ONX.underMapCF()
    if not coinMap then return nil end

    local base
    local spawns = coinMap:FindFirstChild("Spawns")
    if spawns then
        for _, v in next, spawns:GetChildren() do
            if v:IsA("BasePart") then base = v.Position; break end
        end
    end
    if not base then
        local ok, pivot = pcall(function() return coinMap:GetPivot() end)
        if ok and pivot then base = pivot.Position end
    end
    if not base then return nil end

    -- well clear of the floor but nowhere near FallenPartsDestroyHeight
    return CFrame.new(base.X, base.Y - ONX.underMapDepth, base.Z)
end

function ONX.hideUnderMap(root)
    local target = ONX.underMapCF()
    if not target then return false end

    farmRig(true)
    -- mark it as movement so an untoggle tears the rig down the usual way
    -- rather than leaving us parked under the map
    farmMoving = true

    if (root.Position - target.Position).Magnitude > 5 then
        root.Velocity = Vector3.zero
        root.CFrame = target
    end
    return true
end

--// Fling the murderer, and make sure it landed ----------------
-- One throw can miss: they dodge, sit, or it backfires and kills you. After
-- each throw it watches for a moment -- murderer dead or gone, or thrown clean
-- off -- and on a miss goes again, after your respawn if you died, up to three
-- throws a round. It used to be one throw and done: flingDoneFired was set
-- before the throw, so a miss or a backfire left the murderer standing.
do
    local TRIES = 3
    local function alive()
        local char = LocalPlayer.Character
        local h = char and char:FindFirstChildOfClass("Humanoid")
        return h ~= nil and h.Health > 0 and char:FindFirstChild("HumanoidRootPart") ~= nil
    end
    local function landed(m)
        if not m or m.Parent ~= Players then return true end
        local c = m.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        local r = h and h.RootPart
        if not r or h.Health <= 0 then return true end
        return r.AssemblyLinearVelocity.Magnitude > 500
    end
    function ONX.flingMurderer(intro)
        ONX.flingDoneFired = true
        task.spawn(function()
            for try = 1, TRIES do
                -- (and the farm still on: it's the farm's finish, and Stop must
                -- call it off -- it used to wait out a respawn and keep trying)
                if not ONX.flingWhenDone or roundTime() <= 0 or not farmRunning then return end
                -- a death (a reset, or the last throw backfiring) means
                -- waiting for the respawn, then a moment for it to settle
                if not alive() then
                    local t0 = tick()
                    repeat task.wait(0.2) until alive() or tick() - t0 > 15
                    if not alive() then return end
                    task.wait(0.8)
                    if not ONX.flingWhenDone or roundTime() <= 0 or not farmRunning then return end
                end
                local m = findMurderer()
                if not m or m == LocalPlayer or not m.Character then return end
                notify({ title = try == 1 and intro or ("Trying again · %d of %d"):format(try, TRIES),
                         body = "Flinging " .. m.Name .. "...", kind = "flame" })
                while flingActive do task.wait(0.1) end
                if not farmRunning or not gui.Parent then return end
                pcall(flingPlayer, m, true)
                local t0 = tick()
                repeat
                    if roundTime() <= 0 then return end
                    if landed(m) then
                        notify({ title = "Flung " .. m.Name, body = "They're off the map.", kind = "success" })
                        return
                    end
                    task.wait(0.2)
                until tick() - t0 > 3
                local ok = alive()
                notify({ title = ok and ("Missed " .. m.Name) or "Fling backfired",
                         body = try == TRIES and "That was the last try this round."
                             or (ok and "Going again." or "Going again once you respawn."),
                         kind = "warning" })
                task.wait(0.4)
            end
        end)
    end
end

--// Shoot the murderer ---------------------------------------
-- Fired the way MM2's own gun fires (GunClient: Gun.Shoot:FireServer(from, to),
-- from the GunRaycastAttachment on your root), with the care a real shot
-- needs: it leads a moving murderer by their speed and your ping, aims at the
-- first body part it can actually see, holds fire while an innocent is in the
-- line, and -- with a wall in the way, or you under the map -- steps in close
-- behind them for a clear one. It keeps going until they're down or the
-- round ends.
function ONX.gunTool()
    local ch = LocalPlayer.Character
    local g = ch and ch:FindFirstChild("Gun")
    if g and g:IsA("Tool") then return g, false end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    g = bp and bp:FindFirstChild("Gun")
    if g and g:IsA("Tool") then return g, true end
    return nil, false
end
ONX.AIM_PARTS = { "UpperTorso", "HumanoidRootPart", "Head", "LowerTorso", "Torso" }
-- where to shoot: the first part with a clear line, led by their motion;
-- nil + why ("innocent" / "wall") when there's no shot
function ONX.aimAt(m, from)
    local mc = m and m.Character
    local mr = mc and mc:FindFirstChild("HumanoidRootPart")
    if not mr then return nil, "gone" end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    params.IgnoreWater = true
    -- the shot lands a round trip late: lead them by that much of their motion
    local ping = 0.08
    pcall(function() ping = LocalPlayer:GetNetworkPing() end)
    local lead = mr.AssemblyLinearVelocity * (ping * 2 + 0.03)
    local blocked = "wall"
    for _, name in ipairs(ONX.AIM_PARTS) do
        local part = mc:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            local target = part.Position + lead
            local hit = Workspace:Raycast(from, target - from, params)
            if not hit or hit.Instance:IsDescendantOf(mc) then return target end
            local other = hit.Instance:FindFirstAncestorOfClass("Model")
            if other and Players:GetPlayerFromCharacter(other) then blocked = "innocent" end
        end
    end
    return nil, blocked
end
function ONX.fireAt(gun, target)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local shoot = gun and gun:FindFirstChild("Shoot")
    if not (root and shoot and shoot:IsA("RemoteEvent")) then return false end
    local att = root:FindFirstChild("GunRaycastAttachment")
    local from = att and att.WorldPosition or root.Position
    return (pcall(function() shoot:FireServer(CFrame.lookAt(from, target), CFrame.new(target)) end))
end
function ONX.shootMurderer(intro)
    if ONX.shooting then return end
    ONX.shooting, ONX.flingDoneFired = true, true
    task.spawn(function()
        local shots, noGunSince = 0, nil
        local m = findMurderer()
        notify({ title = intro, body = "Shooting " .. (m and m.Name or "the murderer") .. "...", kind = "flame" })
        if m and C.island then C.island.note("Shooting " .. m.Name, 6) end
        -- keeps retrying until the murderer is down or the round is over --
        -- a miss, a dodge, an innocent in the line are all just another try
        while roundTime() > 0 and gui.Parent do
            m = findMurderer()
            local mc = m and m ~= LocalPlayer and m.Character
            local mh = mc and mc:FindFirstChildOfClass("Humanoid")
            if not mh or mh.Health <= 0 then
                if shots > 0 then
                    notify({ title = "Murderer down", body = ("%s, in %d shot%s."):format(m and m.Name or "They", shots,
                        shots == 1 and "" or "s"), kind = "success" })
                end
                break
            end
            local ch = LocalPlayer.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            local root = ch and ch:FindFirstChild("HumanoidRootPart")
            local gun, inBag = ONX.gunTool()
            if not (hum and root and gun and hum.Health > 0) then
                -- no gun right now (you died, it dropped): wait a few seconds for it
                -- to come back -- the farm's gun grab may well pick it up again
                noGunSince = noGunSince or tick()
                if tick() - noGunSince > 6 then break end
                task.wait(0.25)
                continue
            end
            noGunSince = nil
            if inBag then hum:EquipTool(gun); task.wait(0.15) end
            local att = root:FindFirstChild("GunRaycastAttachment")
            local target, why = ONX.aimAt(m, att and att.WorldPosition or root.Position)
            if not target and why == "wall" then
                -- no line from here: step in close behind them, facing them
                local mr = mc:FindFirstChild("HumanoidRootPart")
                if mr then
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.CFrame = CFrame.lookAt((mr.CFrame * CFrame.new(0, 1.5, 7)).Position, mr.Position)
                    task.wait(0.12)
                    att = root:FindFirstChild("GunRaycastAttachment")
                    target = ONX.aimAt(m, att and att.WorldPosition or root.Position)
                end
            end
            if target then
                if ONX.fireAt(gun, target) then shots += 1 end
                task.wait(0.55)          -- the gun's own pace between shots
            else
                task.wait(0.12)          -- an innocent in the line: wait for a clear one
            end
        end
        ONX.shooting = false
    end)
end

--// Grab the gun when it drops ---------------------------------
-- Always on while the farm runs (and only then): the moment the sheriff's gun
-- lands on the map it's picked up by touch from where you stand; if that
-- doesn't take, a split-second hop onto it and back. Never as the murderer
-- (it can't hold the gun), never when you have one.
function ONX.grabGun(drop)
    if not farmRunning or ONX.gunTool() or ONX.grabbing then return end
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    if not (hum and root and hum.Health > 0) or findMurderer() == LocalPlayer then return end
    drop = drop or Workspace:FindFirstChild("GunDrop", true)
    if not (drop and drop:IsA("BasePart") and drop.Parent) then return end
    ONX.grabbing = true
    if firetouchinterest then
        for _ = 1, 3 do
            pcall(firetouchinterest, root, drop, 0)
            task.wait()
            pcall(firetouchinterest, root, drop, 1)
            task.wait(0.05)
            if ONX.gunTool() then break end
        end
    end
    if not ONX.gunTool() and drop.Parent and root.Parent then
        local back = root.CFrame
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = drop.CFrame + Vector3.new(0, 2, 0)
        local t0 = tick()
        repeat task.wait(0.05) until ONX.gunTool() or not drop.Parent or tick() - t0 > 0.6
        if root.Parent then root.CFrame = back end
    end
    ONX.grabbing = false
    if ONX.gunTool() then
        notify({ title = "Picked up the gun", body = "It's in your backpack.", kind = "success" })
        if C.island then C.island.note("Picked up the gun", 4) end
    end
end
ONX.conns[#ONX.conns + 1] = Workspace.DescendantAdded:Connect(function(d)
    if d.Name == "GunDrop" and farmRunning then task.delay(0.1, ONX.grabGun, d) end
end)

--// Fling the murderer once the farm is done -------------------
-- "Done" is the two places the loop stops farming on purpose: bag full, and no
-- coins left on the map. Fires once per round -- flingDoneFired resets when the
-- round timer runs out.
--
-- The no-coins-left branch needs the earned check below. It triggers whenever
-- the map has been cleared, which includes the map being cleared by everybody
-- else while you collected nothing -- so it announced "Farm Done!" and flung the
-- murderer over rounds that had not been farmed at all.
function ONX.finishFling()
    if not (ONX.flingWhenDone or ONX.shootWhenFull) then return end
    if ONX.flingDoneFired then return end
    if flingActive then return end

    -- Two sources because they fail in opposite directions: the round tally
    -- survives a reset but needs the logger's watcher, and the bag count is
    -- always present but is emptied by Auto-Reset. Either one being positive
    -- means the farm actually did something.
    -- the larger of the two, like roundFinish: the game's tally sits at 0 for
    -- a while mid-round, and 0 is truthy, so "or" never reached roundCoins
    -- (and the fallback below reads 999 off a full bag)
    local earned = math.max(ONX.roundCoinsAuth or 0, ONX.roundCoins or 0)
    if earned <= 0 and coinCount() <= 0 then return end
    local bag = coinCount()
    if bag >= 999 then bag = LocalPlayer:GetAttribute("Elite") and 50 or 40 end   -- "Full", not a count
    ONX.finishEarned = earned > 0 and earned or bag

    local m = findMurderer()

    -- You drew murderer yourself: there's nobody to fling, but the point of
    -- the switch -- end the round so the next one starts sooner -- still
    -- works by resetting you, since the murderer dying ends it. With Kill all
    -- on, that ends the round the murderer's way instead, so it gets the round.
    if m == LocalPlayer then
        if not ONX.flingWhenDone then return end
        -- Kill all ends the round only from the bag-full branch: when the
        -- coins ran out first (bag not full), nothing would, so reset instead
        if ONX.killWhenFull and coinCount() >= (LocalPlayer:GetAttribute("Elite") and 50 or 40) then return end
        ONX.flingDoneFired = true
        notify({ title = "You're the murderer", body = "Farm's done, so you reset to end the round.", kind = "flame" })
        if C.island then C.island.note("Resetting to end the round", 6) end
        task.spawn(function()
            task.wait(0.4)
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then hum.Health = 0 end
        end)
        return
    end
    if not m or not m.Character then return end

    -- Holding the gun (sheriff, or one you picked up) with Shoot on: shoot --
    -- always, even with the fling on too. No reset first: dying drops the gun.
    if ONX.shootWhenFull and ONX.gunTool() then
        ONX.shootMurderer(("Farm done · %s coins"):format(ONX.comma(ONX.finishEarned)))
        return
    end
    if not ONX.flingWhenDone then return end

    -- With Auto-Reset also on, the reset goes FIRST: it banks the bag, and it
    -- kills you, so throwing beforehand would just get cut off mid-throw.
    -- flingMurderer waits out the respawn before it throws. Only for a full
    -- bag: the map-cleared caller runs with a part-full one, which Auto-Reset
    -- would never have reset.
    if autoResetOnFull and coinCount() >= (LocalPlayer:GetAttribute("Elite") and 50 or 40) then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then hum.Health = 0 end
    end
    ONX.flingMurderer(("Farm done · %s coins"):format(ONX.comma(ONX.finishEarned)))
end

--// Fling after being knocked out of a live round ---------------
-- Dying mid-farm drops you in the lobby while the round carries on without you.
-- That is the same situation finishFling exists for -- out of the round, murderer
-- still alive -- so it runs the same fling off the same switch.
--
-- The flag is set at the MOMENT OF DEATH, not on respawn. By respawn time there
-- is no way to tell "I died during a round" from "the round just started and I
-- spawned in": a murderer is alive in both, so a respawn-only check would fling
-- at the start of every round.
ONX.diedMidRound = false

function ONX.hookDied(char)
    local hum = char and char:WaitForChild("Humanoid", 5)
    if hum then
        ONX.conns[#ONX.conns + 1] = hum.Died:Connect(function()
            -- only a round death counts; in the lobby there is no murderer
            local m = findMurderer()
            ONX.diedMidRound = (m ~= nil and m ~= LocalPlayer)
        end)
    end
end
-- the character you already have when this runs gets the hook too: before,
-- only respawned characters did, so the first mid-round death went unseen
if LocalPlayer.Character then task.spawn(ONX.hookDied, LocalPlayer.Character) end

ONX.conns[#ONX.conns + 1] = LocalPlayer.CharacterAdded:Connect(function(char)
    ONX.hookDied(char)

    if not ONX.diedMidRound then return end
    ONX.diedMidRound = false
    -- a farm feature ("dying mid-farm"): a death while playing by hand is
    -- yours, and firing here also used up the once-a-round flag for the session
    if not farmRunning then return end
    if not ONX.flingWhenDone then return end
    if ONX.flingDoneFired then return end

    task.spawn(function()
        -- flingPlayer drives our own HumanoidRootPart, so let the spawn settle
        -- before yanking ourselves across the map
        task.wait(1.2)
        if not farmRunning or not ONX.flingWhenDone or ONX.flingDoneFired or flingActive then return end
        -- they can die or leave while we are respawning
        local m = findMurderer()
        if not m or m == LocalPlayer or not m.Character then return end
        ONX.flingMurderer("Out of the round")
    end)
end)

local function startAutoReset()
    if autoResetRunning then return end
    autoResetRunning = true
    task.spawn(function()
        while autoResetOnFull do
            task.wait(1)
            pcall(function()
                -- Re-checked after the wait: switching it off mid-wait must not
                -- still reset you. And only while farming -- the switch lives
                -- under "While farming", so a full bag you filled by hand stays.
                if not (autoResetOnFull and farmRunning) then return end
                -- a shot at the murderer pending or under way: dying would drop
                -- the gun -- the reset comes after
                if ONX.shooting or (ONX.shootWhenFull and ONX.gunTool() and not ONX.flingDoneFired) then return end
                -- was hardcoded to the Coin bag's Full label; coinCount now
                -- reports 999 for whichever bag is actually in play, so this
                -- works during events too
                if coinCount() >= 999 then
                    -- Murderer with Kill all on: Kill all ends the round your
                    -- way; resetting first would hand it to the innocents
                    -- (finishFling makes the same exception).
                    if ONX.killWhenFull and findMurderer() == LocalPlayer then return end
                    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 and C.island then C.island.note("Bag full, resetting to bank it", 5) end
                    if hum then hum.Health = 0 end
                end
            end)
        end
        autoResetRunning = false
    end)
end

local function stopAutoReset()
    autoResetOnFull = false
end

-- Anti-AFK fires on Players.LocalPlayer.Idled, NOT on Heartbeat.
--
-- The old version ran CaptureController() + ClickButton2(Vector2.new()) sixty
-- times a second. CaptureController hands mouse and camera input to the
-- VirtualUser, and MM2's WeaponService reads the cursor to decide where a shot
-- goes — so the two fought for it every frame and manual shots flew off toward
-- a screen corner. Hiding the window with RightShift never fixed it, because
-- only a full teardown disconnects the Heartbeat.
--
-- Idled fires after ~20 minutes without input, which is the only moment the
-- nudge is needed. Between those moments it touches nothing.
local function startAntiAfk()
    if antiAfkConnection then return end
    antiAfkConnection = LocalPlayer.Idled:Connect(function()
        if not antiAfkEnabled then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

local function stopAntiAfk()
    if antiAfkConnection then antiAfkConnection:Disconnect(); antiAfkConnection = nil end
end

--// Visuals: the knife on your belt, a gun in each hand -------------
-- Both are only what YOU see: nothing goes to the server, and switching one
-- off hands everything back the way the game had it.
ONX.vis = {
    belt = false, dual = false,
    -- right arm joint -> its left twin (part, Motor6D, part, Motor6D)
    ARM = {
        { "RightUpperArm", "RightShoulder", "LeftUpperArm", "LeftShoulder" },
        { "RightLowerArm", "RightElbow", "LeftLowerArm", "LeftElbow" },
        { "RightHand", "RightWrist", "LeftHand", "LeftWrist" },
    },
}

-- The knife on your belt is MM2's own radio pose: the display is normally
-- pinned to UpperTorso.KnifeBack, and with a radio on your back to
-- LowerTorso.KnifeBelt, at your side. Pinned there locally, the skin comes
-- along (it's welded to the display). Checked every step before physics, so
-- a new display -- a respawn, another knife -- is moved before it's drawn.
function ONX.vis.stepBelt()
    local ch = LocalPlayer.Character
    local ref = ch and ch:FindFirstChild("DisplayRefKnife")
    local d = ref and ref.Value
    local rc = d and d:FindFirstChildWhichIsA("RigidConstraint")
    local lower = ch and ch:FindFirstChild("LowerTorso")
    local belt = lower and lower:FindFirstChild("KnifeBelt")
    if rc and belt and rc.Attachment0 ~= belt then
        -- (a plain table: a weak one lost its entries -- Roblox can drop the
        -- Lua handle of an Instance that still exists -- and switching off
        -- then had nothing to put back, so the knife stayed on your belt)
        ONX.vis.was = ONX.vis.was or {}
        ONX.vis.was[rc] = rc.Attachment0
        rc.Attachment0 = belt
    end
end

-- Off, right now: every knife we moved goes back where the game had it, and
-- whatever knife you're wearing that sits on the belt without a radio goes
-- back to your back (MM2 only belts a knife for a radio).
function ONX.vis.unpinBelt()
    for rc, a0 in pairs(ONX.vis.was or {}) do
        if rc.Parent and a0 and a0.Parent then pcall(function() rc.Attachment0 = a0 end) end
    end
    ONX.vis.was = nil
    local ch = LocalPlayer.Character
    local ref = ch and ch:FindFirstChild("DisplayRefKnife")
    local d = ref and ref.Value
    local rc = d and d:FindFirstChildWhichIsA("RigidConstraint")
    local upper = ch and ch:FindFirstChild("UpperTorso")
    local back = upper and upper:FindFirstChild("KnifeBack")
    if rc and back and rc.Attachment0 and rc.Attachment0.Name == "KnifeBelt" and not ch:FindFirstChild("Radio") then
        rc.Attachment0 = back
    end
end

function ONX.vis.setBelt(on)
    ONX.vis.belt = on
    if ONX.vis.beltConn then ONX.vis.beltConn:Disconnect(); ONX.vis.beltConn = nil end
    if on then
        ONX.vis.beltConn = RunService.Stepped:Connect(function() pcall(ONX.vis.stepBelt) end)
        pcall(ONX.vis.stepBelt)
    else
        pcall(ONX.vis.unpinBelt)
    end
end

-- M * cf * M, M the mirror across the torso's middle (x -> -x): the same
-- pose on the other side of the body. Right arm joint in, left one out.
function ONX.vis.mirrorConj(cf)
    local x, y, z, a, b, c, d, e, f, g, h, i = cf:GetComponents()
    return CFrame.new(-x, y, z, a, -b, -c, -d, e, f, -g, h, i)
end

-- The left-hand copy of a pose (`cf`, in the torso's space): mirrored across
-- the body's middle, then turned about the gun's own sideways axis `k` so it
-- stays a real rotation -- barrel still forward, top still up. That's how a
-- left-handed twin of a (near enough) symmetric gun looks.
function ONX.vis.mirrorPose(cf, k)
    local x, y, z, a, b, c, d, e, f, g, h, i = cf:GetComponents()
    a, b, c = -a, -b, -c
    if k == 1 then a, d, g = -a, -d, -g
    elseif k == 2 then b, e, h = -b, -e, -h
    else c, f, i = -c, -f, -i end
    return CFrame.new(-x, y, z, a, b, c, d, e, f, g, h, i)
end

-- the gun you're showing: the skin when one's set, else your real gun
function ONX.vis.gunName()
    if not ONX.vis.pd then
        local ok, pd = pcall(require, ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData"))
        ONX.vis.pd = ok and type(pd) == "table" and pd or false
    end
    local w = ONX.vis.pd and ONX.vis.pd.Weapons
    local eq = type(w) == "table" and w.Equipped
    return type(eq) == "table" and tostring(eq.Gun or "") or ""
end

function ONX.vis.dropCopy()
    local v = ONX.vis
    if v.copy then pcall(function() v.copy:Destroy() end) end
    if v.copyConns then for _, c in ipairs(v.copyConns) do pcall(function() c:Disconnect() end) end end
    v.copy, v.copyFor, v.copyConns, v.syncs = nil, nil, nil, nil
end

-- A look-only copy of the gun in your hand -- the Handle, with the skin on
-- it -- for the left. Built off the live Handle, so it's whatever you see:
-- your skin, a chroma's colours (kept in step every frame), the real gun.
function ONX.vis.buildCopy(tool)
    local v = ONX.vis
    v.dropCopy()
    local h = tool:FindFirstChild("Handle")
    local ch = LocalPlayer.Character
    local torso = ch and (ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso"))
    if not (h and torso) then return end
    local ok, cp = pcall(function() return h:Clone() end)
    if not ok or not cp then return end
    -- pairs to keep in step (a chroma cycles colours on the original: part
    -- colours, decals, textured meshes' tint, fire), matched before anything
    -- is stripped from the copy. Each child is matched to the copy's child of
    -- the same name and class, never by position: Clone leaves out what it
    -- won't copy -- a knife's TouchInterest, which even calls itself
    -- Archivable -- and pairing by position shifted everything after it, so
    -- the skin itself (KnifeDisplay, with its Chroma decal) was never paired
    -- and the twin's colour stood still.
    local syncs = { h, cp }
    local function pairUp(o, c)
        local pool, used = c:GetChildren(), {}
        for _, oc in ipairs(o:GetChildren()) do
            for i, m in ipairs(pool) do
                if not used[i] and m.Name == oc.Name and m.ClassName == oc.ClassName then
                    used[i] = true
                    if oc:IsA("BasePart") or oc:IsA("Decal") or oc:IsA("SpecialMesh") or oc:IsA("Fire") then
                        syncs[#syncs + 1] = oc; syncs[#syncs + 1] = m
                    end
                    pairUp(oc, m)
                    break
                end
            end
        end
    end
    pairUp(h, cp)
    -- seen only: no scripts, sounds, prompts or touches, and no joint to
    -- anything outside the copy
    for _, d in ipairs(cp:GetDescendants()) do
        if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("TouchTransmitter")
            or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d.Name == "CustomBeam"
            or (d:IsA("JointInstance") and not ((d.Part0 and d.Part0:IsDescendantOf(cp) or d.Part0 == cp)
                and (d.Part1 and d.Part1:IsDescendantOf(cp) or d.Part1 == cp))) then
            pcall(function() d:Destroy() end)
        end
    end
    for _, p in ipairs(cp:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, false, true
        end
    end
    cp.Anchored, cp.CanCollide, cp.CanTouch, cp.CanQuery = true, false, false, false
    cp.Name = tool.Name == "Knife" and "LeftKnife" or "LeftGun"
    cp:SetAttribute("_ov", true)     -- ours, so Performance mode leaves it be
    -- the gun's sideways axis: whichever of its own axes lies most across
    -- the body (read once; it's how the gun sits in the hand)
    local rel = torso.CFrame:ToObjectSpace(h.CFrame)
    local _, _, _, a, b, c = rel:GetComponents()
    local ax, bx, cx = math.abs(a), math.abs(b), math.abs(c)
    v.k = (ax >= bx and ax >= cx) and 1 or (bx >= cx and 2 or 3)
    cp.CFrame = torso.CFrame * v.mirrorPose(rel, v.k)
    -- In the workspace, not your character: in first person the camera
    -- hides every part of your character that isn't in a Tool, so the left
    -- one vanished while the real (Tool) one stayed. It's anchored and placed
    -- every frame, so it needs nothing from the character.
    cp.Parent = workspace
    v.copy, v.copyFor, v.syncs = cp, tool, syncs
    -- the skin landing (or leaving) changes what's on the Handle: copy again
    local function dirty() v.dirtyAt = os.clock() end
    v.copyConns = { h.DescendantAdded:Connect(dirty), h.DescendantRemoving:Connect(dirty) }
    v.dirtyAt = nil
end

-- A joint's two mounting frames. MM2's rigs use AnimationConstraints (the
-- newer avatar joints: part1 = part0 * Attachment0 * Transform *
-- Attachment1^-1); an older rig's Motor6D has the same shape in C0 / C1.
function ONX.vis.jointFrames(j)
    if not j then return nil end
    if j:IsA("AnimationConstraint") then
        local a0, a1 = j.Attachment0, j.Attachment1
        if a0 and a1 then return a0.CFrame, a1.CFrame end
    elseif j:IsA("Motor6D") then
        return j.C0, j.C1
    end
    return nil
end

-- Mirror the right arm onto the left, joint by joint. Runs on Stepped: the
-- Animator has written this frame's pose by then, so this is the last word.
function ONX.vis.stepArms()
    local ch = LocalPlayer.Character
    if not ch then return end
    local v = ONX.vis
    for _, j in ipairs(v.ARM) do
        local rp, lp = ch:FindFirstChild(j[1]), ch:FindFirstChild(j[3])
        local r, l = rp and rp:FindFirstChild(j[2]), lp and lp:FindFirstChild(j[4])
        local r0, r1 = v.jointFrames(r)
        local l0, l1 = v.jointFrames(l)
        if r0 and l0 then
            l.Transform = l0:Inverse() * v.mirrorConj(r0 * r.Transform * r1:Inverse()) * l1
        end
    end
end

function ONX.vis.resetArms()
    local ch = LocalPlayer.Character
    if not ch then return end
    for _, j in ipairs(ONX.vis.ARM) do
        local lp = ch:FindFirstChild(j[3])
        local l = lp and lp:FindFirstChild(j[4])
        if ONX.vis.jointFrames(l) then pcall(function() l.Transform = CFrame.identity end) end
    end
end

-- Both guns fire: when the server reports YOUR shot (WeaponService.GunFired,
-- the event every client draws beams from), a second beam in your gun's beam
-- look leaves the left gun's muzzle for the same spot. Only the right one's
-- shot is real.
function ONX.vis.onGunFired(handle, from, to, hit)
    local v = ONX.vis
    if not (v.armsOn and v.copy and typeof(handle) == "Instance" and typeof(to) == "Vector3") then return end
    local ch = LocalPlayer.Character
    local torso = ch and (ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso"))
    if not (torso and handle:IsDescendantOf(ch)) then return end
    -- where the real shot visibly leaves the gun: a skin with its own muzzle
    -- (Harvester, Raygun, Icepiercer, Snowcannon ...) has its beam moved
    -- there by the engine; every other gun starts where the game says
    local tool = handle:IsA("Tool") and handle or handle:FindFirstAncestorOfClass("Tool")
    local p = tool and UI.engine and UI.engine.muzzleOf and UI.engine.muzzleOf(tool)
    if not p then
        p = typeof(from) == "Vector3" and from
            or (typeof(from) == "Instance" and (from:IsA("Attachment") and from.WorldPosition
                or (from:IsA("BasePart") and from.Position))) or nil
    end
    if not p then return end
    -- the same point, on the left side of your body
    local lp = torso.CFrame:PointToObjectSpace(p)
    local mirrored = torso.CFrame:PointToWorldSpace(Vector3.new(-lp.X, lp.Y, lp.Z))
    task.spawn(pcall, v.drawBeam, handle, mirrored, to)
end

-- MM2's own CreateBeam, redone under another name. Going through CreateBeam
-- made this a "CustomBeam", and the engine moves every new CustomBeam near
-- your gun onto the right gun's muzzle -- so for the skins with a muzzle the
-- second beam landed right on top of the real one.
function ONX.vis.drawBeam(handle, from, to)
    local function point(pos)
        local p = Instance.new("Part")
        p.Transparency, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = 1, true, false, false, false
        p.Size = Vector3.new(1, 1, 1)
        p.CFrame = CFrame.new(pos)
        Instance.new("Attachment", p)
        p.Parent = workspace
        task.delay(1, function() pcall(function() p:Destroy() end) end)
        return p
    end
    local a, z = point(from), point(to)
    local tpl = handle:FindFirstChild("CustomBeam")
    local b
    if tpl and tpl:IsA("Beam") then
        b = tpl:Clone()
    else
        b = Instance.new("Beam")
        b.Width0, b.Width1, b.LightEmission, b.LightInfluence = 0.2, 0.2, 0.5, 0
        b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.202, 0.95), NumberSequenceKeypoint.new(1, 0.6) })
    end
    b.Name = "LeftBeam"
    b.Enabled = true
    b.Attachment0, b.Attachment1 = a:FindFirstChildOfClass("Attachment"), z:FindFirstChildOfClass("Attachment")
    b.FaceCamera = true
    b.Parent = a
    task.wait(0.03)
    TweenService:Create(b, TweenInfo.new(0.1, Enum.EasingStyle.Linear), { Width0 = 0 }):Play()
    TweenService:Create(b, TweenInfo.new(0.2, Enum.EasingStyle.Linear), { Width1 = 0 }):Play()
end

-- Both knives fly: MM2 draws every throw on your own screen -- the server
-- makes a ThrowingKnife (Direction, ThrowSpeed, HandleLink to the knife),
-- and ThrowingKnifeVisuals clones the knife and flies it, spinning, with a
-- trail. For YOUR throw with two knives out, a twin of that flying knife
-- leaves the left hand on the same heading, the same way.
function ONX.vis.onKnifeThrown(obj)
    local v = ONX.vis
    if not (v.armsOn and v.copy and v.copyFor and v.copyFor.Name == "Knife") then return end
    local link = obj:WaitForChild("HandleLink", 3)
    local ch = LocalPlayer.Character
    if not (link and link.Value and ch and link.Value:IsDescendantOf(ch)) then return end
    -- the right one as the game (and the skin engine's fix) leave it
    local vis = obj:WaitForChild("KnifeVisual", 3)
    if not vis then return end
    task.wait()
    task.wait()
    local torso = ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso")
    if not (torso and vis.Parent) then return end
    local ok, twin = pcall(function() return vis:Clone() end)
    if not ok or not twin then return end
    for _, d in ipairs(twin:GetDescendants()) do
        if d:IsA("LuaSourceContainer") or d:IsA("Sound") then pcall(function() d:Destroy() end) end
    end
    twin.Name = "LeftKnifeVisual"
    twin.Anchored, twin.CanCollide, twin.CanTouch, twin.CanQuery = true, false, false, false
    twin:SetAttribute("_ov", true)
    -- the same spot, mirrored onto the left side of your body
    twin.CFrame = torso.CFrame * v.mirrorPose(torso.CFrame:ToObjectSpace(vis.CFrame), v.k or 1)
    local dir = obj:GetAttribute("Direction")
    local speed = obj:GetAttribute("ThrowSpeed") or 96
    if typeof(dir) ~= "Vector3" then twin:Destroy(); return end
    twin.Parent = workspace
    -- a chroma keeps cycling, in flight and in the wall, in step with the
    -- real one: the twin's skin (the overlay the engine stamped "_ov",
    -- carried in the clone) gets the engine's own chroma
    if UI.engine and UI.engine.chromaClone then
        for _, d in ipairs(twin:GetDescendants()) do
            if d:GetAttribute("_ov") then pcall(UI.engine.chromaClone, link.Value.Parent, d); break end
        end
    end
    -- its trail, from the game's own template
    local trailPart
    pcall(function()
        local tpl = LocalPlayer.PlayerScripts.WeaponVisuals.ThrowingKnifeVisuals
        trailPart = Instance.new("Part")
        trailPart.Name, trailPart.Size, trailPart.Transparency = "TrailPart", Vector3.new(1, 1, 1), 1
        trailPart.Anchored, trailPart.CanCollide, trailPart.CanQuery, trailPart.CanTouch = true, false, false, false
        local bottom, top, trail = tpl.Bottom:Clone(), tpl.Top:Clone(), tpl.Trail:Clone()
        trail.Attachment0, trail.Attachment1 = top, bottom
        bottom.Parent, top.Parent, trail.Parent = trailPart, trailPart, trailPart
        trailPart.CFrame = CFrame.new(twin.Position, twin.Position + dir)
        trailPart.Parent = workspace
    end)
    -- The game's flight, frame for frame: a spin about its own X and a
    -- straight line at ThrowSpeed -- checked ahead each frame, so it sticks,
    -- blade first, into the first bit of map it meets (players are flown
    -- through: only the right knife's throw is real).
    local skip = { ch, twin, v.copy, obj }
    if trailPart then skip[#skip + 1] = trailPart end
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then skip[#skip + 1] = pl.Character end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = skip
    local conn, stuck, gone = nil, false, false
    -- where ours hit, the real StuckKnife, and where the real throw hit
    local ourHit, realStuck, realHit
    local function done()
        if gone then return end
        gone = true
        if conn then conn:Disconnect(); conn = nil end
        pcall(function() twin:Destroy() end)
        if trailPart then task.delay(1, function() pcall(function() trailPart:Destroy() end) end) end
    end
    -- Once both have landed, ours takes the real one's exact pose -- the
    -- angle it hangs out of the wall at, and how far it sits from where it
    -- hit -- at the spot where ours hit. (Ours used to set its own blade-first
    -- pose and lay flat along the wall, flickering in it.)
    local function settle()
        if gone or not (ourHit and realStuck and realHit) or not realStuck.Parent then return end
        twin.CFrame = CFrame.new(ourHit + (realStuck.Position - realHit)) * realStuck.CFrame.Rotation
    end
    local function stick(at)
        stuck = true
        ourHit = at
        if conn then conn:Disconnect(); conn = nil end
        -- (holds still where it is until the real one is down)
        if trailPart then task.delay(1, function() pcall(function() trailPart:Destroy() end) end); trailPart = nil end
        settle()
    end
    conn = RunService.PreSimulation:Connect(function(dt)
        if not twin.Parent then done(); return end
        local step = dir * speed * dt
        local hit = workspace:Raycast(twin.Position, step, params)
        if hit and hit.Instance and hit.Instance.CanCollide then stick(hit.Position); return end
        local cf = twin.CFrame * CFrame.Angles(dt * -12.566370614359172, 0, 0) + step
        twin.CFrame = cf
        if trailPart then trailPart.CFrame = CFrame.new(cf.Position, cf.Position + dir) end
    end)
    -- How long it stays is the real one's call. When the real throw ends, the
    -- server leaves a StuckKnife where it landed: ours stays exactly as long
    -- as that one does. No StuckKnife (it hit someone) -- ours goes too.
    local lastReal = vis.Position
    local track = RunService.Heartbeat:Connect(function()
        if vis.Parent then lastReal = vis.Position end
    end)
    obj.Destroying:Once(function()
        track:Disconnect()
        local found
        local watch = workspace.ChildAdded:Connect(function(c)
            if not found and c.Name == "StuckKnife" and c:IsA("BasePart") and (c.Position - lastReal).Magnitude < 10 then
                found = c
            end
        end)
        -- (it may already be there by the time this runs)
        for _, c in ipairs(workspace:GetChildren()) do
            if not found and c.Name == "StuckKnife" and c:IsA("BasePart") and (c.Position - lastReal).Magnitude < 10 then
                found = c
            end
        end
        local t0 = os.clock()
        while not found and os.clock() - t0 < 1 and not gone do task.wait() end
        watch:Disconnect()
        if not found then done(); return end
        found.Destroying:Once(done)
        found.AncestryChanged:Connect(function(_, parent) if not parent then done() end end)
        -- where the real throw met the surface: along its line, past where
        -- it stopped (the stuck knife itself left out of the check)
        realStuck = found
        local p2 = RaycastParams.new()
        p2.FilterType = Enum.RaycastFilterType.Exclude
        local skip2 = table.clone(skip)
        skip2[#skip2 + 1] = found
        p2.FilterDescendantsInstances = skip2
        local u = dir.Unit
        local hit = workspace:Raycast(lastReal - u * 4, u * 14, p2)
        realHit = hit and hit.Position or lastReal
        settle()
        -- still in the air: give it a moment to land on its own, then park it
        task.delay(1.5, function() if not stuck and not gone then stick(twin.Position) end end)
    end)
    -- a throw that never lands anywhere
    task.delay(12, function() if not stuck then done() end end)
end

-- With a gun in each hand there's no reloading one of them: the gun's
-- Reload animation is stopped the moment it starts (only how it looks --
-- the gun's own cooldown is the server's and stays as it is).
function ONX.vis.onAnimPlayed(track)
    local v = ONX.vis
    if not v.armsOn then return end
    local ch = LocalPlayer.Character
    local gun = ch and ch:FindFirstChild("Gun")
    local anims = gun and gun:FindFirstChild("Animations")
    local reload = anims and anims:FindFirstChild("Reload")
    local a = track.Animation
    if (reload and a and a.AnimationId == reload.AnimationId) or track.Name == "Reload" then
        pcall(function() track:Stop(0) end)
    end
end

-- Every frame before drawing: is a gun (not a Gingerscope, a two-handed
-- rifle) or a knife in your hand, with its switch on? Then the copy sits in
-- your left hand as the right one's mirror image, colours in step.
function ONX.vis.renderDual()
    local v = ONX.vis
    local ch = LocalPlayer.Character
    -- this character's animations, watched for the reload
    if ch and v.animChar ~= ch then
        if v.animConn then v.animConn:Disconnect(); v.animConn = nil end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        local an = hum and hum:FindFirstChildOfClass("Animator")
        if an then
            v.animConn = an.AnimationPlayed:Connect(function(t) pcall(v.onAnimPlayed, t) end)
            v.animChar = ch
        end
    end
    -- the gun (Two guns on, and not a Gingerscope) or the knife (Two knives on)
    local tool = ch and v.dual and ch:FindFirstChild("Gun")
    if tool and v.gunName():lower():find("gingerscope") then tool = nil end
    tool = tool or (ch and v.dualKnife and ch:FindFirstChild("Knife"))
    local h = tool and tool:IsA("Tool") and tool:FindFirstChild("Handle")
    local torso = ch and (ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso"))
    if not (h and torso) then
        if v.copy then v.dropCopy() end
        if v.armsOn then v.armsOn = false; pcall(v.resetArms) end
        return
    end
    if v.copyFor ~= tool or not (v.copy and v.copy.Parent)
        or (v.dirtyAt and os.clock() - v.dirtyAt > 0.1) then
        v.buildCopy(tool)
        if not v.copy then return end
    end
    v.armsOn = true
    v.copy.CFrame = torso.CFrame * v.mirrorPose(torso.CFrame:ToObjectSpace(h.CFrame), v.k)
    local s = v.syncs
    for n = 1, #s, 2 do
        local o, c = s[n], s[n + 1]
        if o:IsA("BasePart") then
            if c.Color ~= o.Color then c.Color = o.Color end
            if c.Transparency ~= o.Transparency then c.Transparency = o.Transparency end
        elseif o:IsA("SpecialMesh") then
            if c.VertexColor ~= o.VertexColor then c.VertexColor = o.VertexColor end
        elseif o:IsA("Fire") then
            if c.Color ~= o.Color then c.Color = o.Color end
        elseif c.Color3 ~= o.Color3 or c.Transparency ~= o.Transparency then
            c.Color3, c.Transparency = o.Color3, o.Transparency
        end
    end
end

-- Two guns and Two knives share one copy and one set of hooks: only one
-- weapon is ever in your hand. These hooks run while either is on.
function ONX.vis.setDual(on) ONX.vis.dual = on; ONX.vis.syncDual() end
function ONX.vis.setDualKnife(on) ONX.vis.dualKnife = on; ONX.vis.syncDual() end

function ONX.vis.syncDual()
    local v = ONX.vis
    local on = v.dual or v.dualKnife
    if v.dualConns then for _, c in ipairs(v.dualConns) do pcall(function() c:Disconnect() end) end end
    v.dualConns = nil
    if v.animConn then v.animConn:Disconnect(); v.animConn = nil end
    v.animChar = nil
    v.dropCopy()
    if v.armsOn then v.armsOn = false; pcall(v.resetArms) end
    if on then
        v.dualConns = {
            RunService.RenderStepped:Connect(function() pcall(v.renderDual) end),
            RunService.Stepped:Connect(function() if v.armsOn then pcall(v.stepArms) end end),
        }
        pcall(function()
            local cs = ReplicatedStorage:FindFirstChild("ClientServices")
            local ws = require(cs:FindFirstChild("WeaponService"))
            v.dualConns[#v.dualConns + 1] = ws.GunFired.OnClientEvent:Connect(function(...)
                pcall(v.onGunFired, ...)
            end)
        end)
        v.dualConns[#v.dualConns + 1] = game:GetService("CollectionService")
            :GetInstanceAddedSignal("ThrowingKnife"):Connect(function(obj)
                task.spawn(pcall, v.onKnifeThrown, obj)
            end)
    end
end

function ONX.vis.stopAll()
    pcall(ONX.vis.setBelt, false)
    ONX.vis.dual, ONX.vis.dualKnife = false, false
    pcall(ONX.vis.syncDual)
end

ONX.perf = {
    LIGHTING = game:GetService("Lighting"),
    -- High enough to be no cap on any real display, and never 0: see the FPS
    -- Cap slider for why a literal zero is not an option.
    UNCAPPED = 999,
    -- Every key starts false rather than nil, so the config restore replaying a
    -- saved `false` through ONX.perf.set is recognised as "already off" and skipped
    -- instead of running every feature's restore against an empty stash.
    on = {
        textures = false, effects = false, weaponfx = false, pets = false,
        anims = false, lighting = false, terrain = false,
        sounds = false, quality = false, fpsCounter = false,
    },
    el   = {},   -- feature key -> its toggle element, so the master can move them
    -- One stash per KIND of change rather than one big pile, so a single
    -- feature can be switched off without walking back another one's edits.
    stash = {
        parent   = {},  -- instance    -> old parent   (effects, decals, textures)
        part     = {},  -- BasePart    -> { material, cast, refl }
        texid    = {},  -- SpecialMesh -> old TextureId
        volume   = {},  -- Sound       -> old Volume
        enabled  = {},  -- ParticleEmitter -> old Enabled
        post     = {},  -- Lighting FX -> old Enabled
        light    = nil, -- Lighting's own scalars
        terrain  = nil, -- Terrain's water + grass props
        quality  = nil, -- render QualityLevel
    },
    animConns = {},     -- Animator -> AnimationPlayed conn
    watchConn = nil,    -- the one Workspace.DescendantAdded watcher
    playerConn = nil,   -- LocalPlayer watcher, for tools sitting in the Backpack
    -- Which feature detached what. Two features can want the same
    -- ParticleEmitter gone -- "Remove Particles" and "Remove Weapon Effects"
    -- overlap on an equipped knife -- and without this, switching one off would
    -- hand back instances the other one is still hiding.
    owner = {},         -- detached instance -> feature key that took it
}

-- Never touch our own furniture. The ESP's Highlights and BillboardGuis, the
-- crosshair, the HUD tiles and the skin visualiser's clones all live in
-- Workspace or CoreGui alongside everything else, and a stripper that cannot
-- tell them apart would switch off the very features the user turned on.
-- Walked without a pcall per level on purpose. This runs for every instance
-- that streams into the map, and wrapping each Name read in a closure was
-- allocating half a dozen of them per descendant -- real garbage, in the one
-- feature whose whole job is to stop wasting frames. Reading .Name off a live
-- instance cannot throw, and the loop stops at the first nil Parent.
function ONX.perf.ours(inst)
    local node = inst
    while node do
        if node.Name:sub(1, 4) == "Onyx" then return true end
        -- skin overlays keep the real skin's own name, so they're recognised
        -- by the attribute the engine stamps on them instead
        if node:GetAttribute("_ov") then return true end
        node = node.Parent
    end
    return false
end

--// the strippers, one per class family -----------------------

-- Dynamic lights are in here with the particles on purpose: each one the
-- renderer keeps is another pass over everything it touches, and MM2's knife
-- skins ship them by the handful.
ONX.perf.FX = {
    ParticleEmitter = true, Trail = true, Smoke = true, Fire = true,
    Sparkles = true, Beam = true, Explosion = true,
    PointLight = true, SpotLight = true, SurfaceLight = true,
}

-- Two one-line helpers so the hot paths can use pcall(fn, args) instead of
-- pcall(function() ... end). Same protection, but the closure form allocated a
-- fresh function per instance touched -- roughly 30k allocations for one sweep
-- of a full map, in the feature whose entire purpose is to stop wasting frames.
function ONX.perf.reparent(inst, parent) inst.Parent = parent end
function ONX.perf.restorePart(part, was)
    part.Material, part.CastShadow, part.Reflectance = was[1], was[2], was[3]
end

-- How many instances to touch before giving the frame back.
--
-- Everything below used to run in a single frame. A strip or a restore writes to
-- every part in the map -- measured at over 3.5 seconds in one frame on a loaded
-- map, which is a freeze at best and a dead client at worst. Spread over frames
-- it is unnoticeable, and the work per frame is bounded no matter how big the
-- map gets.
ONX.perf.CHUNK = 75
ONX.perf.sweeping = false

function ONX.perf.breathe(n)
    if n % ONX.perf.CHUNK == 0 then task.wait() end
end

-- Snapshot keys before walking a stash, because these loops now YIELD.
-- Roblox's `next` cannot be trusted across an insertion, and a feature that is
-- still switched on keeps adding to the same stash from its watcher while we
-- walk it -- iterating live would eventually throw "invalid key to next".
-- Snapshotting also scopes a restore to what was stashed when it started.
function ONX.perf.keysOf(tbl)
    local out, n = {}, 0
    for k in next, tbl do n = n + 1; out[n] = k end
    return out, n
end
function ONX.perf.readProp(obj, prop) return obj[prop] end

-- Grass and animated water, as {property, value} pairs rather than a fixed
-- table, so a property missing on this client is skipped instead of fatal.
ONX.perf.TERRAIN = {
    { "Decoration", false },        -- absent on some builds; see the feature
    { "WaterWaveSize", 0 },
    { "WaterWaveSpeed", 0 },
    { "WaterReflectance", 0 },
    { "WaterTransparency", 1 },
}
function ONX.perf.setProp(obj, prop, val) obj[prop] = val end

-- Detach + remember, tagged with the feature that took it. Guarded on the
-- stash rather than on the parent being non-nil, so an instance already
-- unparented by the game is never recorded with a nil "original" that a
-- restore would then re-apply.
function ONX.perf.detach(inst, key)
    if ONX.perf.stash.parent[inst] ~= nil then return end
    local p = inst.Parent
    if not p then return end
    ONX.perf.stash.parent[inst] = p
    ONX.perf.owner[inst] = key
    pcall(ONX.perf.reparent, inst, nil)
end

function ONX.perf.stripTexture(d)
    if d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
        ONX.perf.detach(d, "textures")
    elseif d:IsA("SpecialMesh") then
        -- MeshPart.TextureID is read-only at runtime; SpecialMesh's is not, so
        -- this is the only mesh texture we can actually drop.
        if ONX.perf.stash.texid[d] == nil and d.TextureId ~= "" then
            ONX.perf.stash.texid[d] = d.TextureId
            pcall(ONX.perf.setProp, d, "TextureId", "")
        end
    elseif d:IsA("BasePart") and not d:IsA("Terrain") then
        if ONX.perf.stash.part[d] == nil then
            ONX.perf.stash.part[d] = { d.Material, d.CastShadow, d.Reflectance }
            -- SmoothPlastic is the cheapest material to shade: no normal map,
            -- no roughness pass. CastShadow is the bigger win of the three --
            -- every part dropped out of the shadow map is one the renderer
            -- stops drawing twice. Unprotected individually; the one pcall in
            -- safeApply covers the whole dispatch.
            d.Material    = Enum.Material.SmoothPlastic
            d.CastShadow  = false
            d.Reflectance = 0
        end
    end
end

function ONX.perf.clearEmitter(e) e:Clear() end

-- Unparenting an emitter stops NEW particles. It does nothing about the ones
-- already in flight, which keep drawing for the rest of their lifetime -- and on
-- a long-lived effect that is seconds of particles still on screen after the
-- switch went on. That is what "it did not remove all of them" looks like.
--
-- So: switch it off, Clear() what is already alive, THEN detach. Enabled is
-- stashed like any other overwritten property, because a restore has to hand
-- back an emitter that emits.
function ONX.perf.killFX(d, key)
    if d:IsA("ParticleEmitter") then
        if ONX.perf.stash.enabled[d] == nil then ONX.perf.stash.enabled[d] = d.Enabled end
        d.Enabled = false
        pcall(ONX.perf.clearEmitter, d)
    end
    ONX.perf.detach(d, key)
end

function ONX.perf.stripEffect(d)
    if ONX.perf.FX[d.ClassName] then ONX.perf.killFX(d, "effects") end
end

-- Weapon effects only: the same classes, but scoped to what is inside a Tool.
-- Separate feature because MM2's expensive knife skins are the one thing most
-- people want gone, and they do not want to give up the round's own particles
-- to get it -- and because a Tool waiting in the Backpack is not a Workspace
-- descendant, so the map sweep never reaches it.
function ONX.perf.stripWeaponFX(tool)
    for _, d in ipairs(tool:GetDescendants()) do
        if ONX.perf.FX[d.ClassName] then ONX.perf.killFX(d, "weaponfx") end
    end
end


function ONX.perf.stripSound(d)
    if d:IsA("Sound") and ONX.perf.stash.volume[d] == nil then
        ONX.perf.stash.volume[d] = d.Volume
        pcall(ONX.perf.setProp, d, "Volume", 0)
    end
end

-- Animations are stopped, not removed: there is nothing to unparent, because
-- the cost is the Animator evaluating tracks every frame. Stopping what plays
-- now and refusing what starts later comes to the same thing, and switching
-- the feature off simply stops refusing -- the game re-plays its own idles.
function ONX.perf.hookAnimator(a)
    if ONX.perf.animConns[a] then return end
    pcall(function()
        for _, track in ipairs(a:GetPlayingAnimationTracks()) do track:Stop(0) end
    end)
    local ok, conn = pcall(function()
        return a.AnimationPlayed:Connect(function(track)
            if not ONX.perf.on.anims then return end
            pcall(function() track:Stop(0) end)
        end)
    end)
    if ok and conn then ONX.perf.animConns[a] = conn end
end

-- Single dispatch point, shared by the sweep and the watcher, so a streamed-in
-- part goes through exactly the same code the initial pass used.
function ONX.perf.apply(d)
    if ONX.perf.ours(d) then return end
    if ONX.perf.on.textures then ONX.perf.stripTexture(d) end
    if ONX.perf.on.effects  then ONX.perf.stripEffect(d)  end
    if ONX.perf.on.sounds   then ONX.perf.stripSound(d)   end
    if ONX.perf.on.anims and d:IsA("Animator") then ONX.perf.hookAnimator(d) end

    if ONX.perf.on.weaponfx then
        -- Both directions: the Tool can arrive already carrying its effects
        -- (equip, or a skin swap), or an effect can be added to a Tool that is
        -- already in hand. Only one of the two fires per event.
        if d:IsA("Tool") then
            ONX.perf.stripWeaponFX(d)
        elseif ONX.perf.FX[d.ClassName] and d:FindFirstAncestorWhichIsA("Tool") then
            ONX.perf.killFX(d, "weaponfx")
        end
    end

    -- MM2 parents every equipped pet into one Workspace folder, so this is the
    -- whole feature: keep that folder empty. Checked by the parent's name
    -- rather than the pet's, because a pet model is named after the pet.
    if ONX.perf.on.pets then
        local p = d.Parent
        if p and p.Name == "PetContainer" then ONX.perf.detach(d, "pets") end
    end
end

-- Watchers hand work to a queue; a drain thread does it at a bounded rate.
--
-- Applying inline looked fine and is not: MM2 parents a whole map at once, so
-- DescendantAdded fires thousands of times inside a single frame, and stripping
-- each one as it arrives rebuilds exactly the spike the chunked sweep was
-- written to avoid. The queue turns an unbounded burst into CHUNK per frame,
-- however fast the game parents things.
ONX.perf.queue = {}
ONX.perf.queueN = 0
ONX.perf.drainThread = nil

-- Head index rather than shifting the remainder down each frame. With a map's
-- worth of instances queued, shifting made every frame O(queue) -- the drain
-- would have spent more time moving the backlog than working through it.
ONX.perf.qHead = 1

function ONX.perf.enqueue(d)
    local n = ONX.perf.queueN + 1
    ONX.perf.queueN = n
    ONX.perf.queue[n] = d
end

function ONX.perf.drainStep()
    local q = ONX.perf.queue
    local head, n = ONX.perf.qHead, ONX.perf.queueN
    if head > n then
        -- caught up: reset so the table does not grow forever
        if n > 0 then ONX.perf.queue, ONX.perf.queueN, ONX.perf.qHead = {}, 0, 1 end
        return
    end
    local last = head + ONX.perf.CHUNK - 1
    if last > n then last = n end
    for i = head, last do
        ONX.perf.safeApply(q[i])
        q[i] = nil
    end
    ONX.perf.qHead = last + 1
end

function ONX.perf.stopDrain()
    if ONX.perf.drainThread then
        pcall(task.cancel, ONX.perf.drainThread)
        ONX.perf.drainThread = nil
    end
    -- anything still queued is stale once the watchers are gone
    ONX.perf.queue, ONX.perf.queueN, ONX.perf.qHead = {}, 0, 1
end

function ONX.perf.startDrain()
    ONX.perf.stopDrain()
    ONX.perf.drainThread = task.spawn(function()
        while true do
            task.wait()
            local ok, err = pcall(ONX.perf.drainStep)
        end
    end)
end

-- The only pcall on the strip path. One per instance, wrapping the whole
-- dispatch, so a single read-only property on some odd instance cannot abort
-- the rest of the sweep -- and nothing below it needs its own guard.
function ONX.perf.safeApply(d)
    pcall(ONX.perf.apply, d)
end

function ONX.perf.sweepBody()
    local all = Workspace:GetDescendants()
    for i = 1, #all do
        ONX.perf.safeApply(all[i])
        ONX.perf.breathe(i)
    end
    -- Backpack tools are not under Workspace, so they need their own pass
    if ONX.perf.on.weaponfx then
        local mine = LocalPlayer:GetDescendants()
        for i = 1, #mine do
            local d = mine[i]
            if d:IsA("Tool") then pcall(ONX.perf.stripWeaponFX, d) end
            ONX.perf.breathe(i)
        end
    end
end

-- One sweep at a time -- a chunked pass spans many frames while the pulse keeps
-- firing, so overlapping passes would multiply instead of taking turns.
--
-- But "one at a time" cannot mean "dropped": flipping a switch mid-pass calls
-- this, and simply returning would leave that feature doing nothing until the
-- next pulse, up to PULSE seconds of a toggle that visibly does not work. A
-- request that arrives during a pass is remembered and honoured as soon as it
-- ends, which is also why this is a repeat and not an if.
ONX.perf.resweep = false

function ONX.perf.sweep()
    if ONX.perf.sweeping then
        ONX.perf.resweep = true
        return
    end
    ONX.perf.sweeping = true
    repeat
        ONX.perf.resweep = false
        local ok, err = pcall(ONX.perf.sweepBody)
    until not ONX.perf.resweep
    ONX.perf.sweeping = false
end

-- Rolling re-sweep, on top of the two watchers.
--
-- DescendantAdded catches anything parented into the map, but it cannot catch an
-- emitter that was ALREADY in the map and only starts emitting later, an effect
-- the game re-enables on an instance we have already walked past, or a property
-- the game writes back itself. Those are exactly the leftovers you notice.
--
-- Affordable because a pass is almost all reads: the class checks run over every
-- descendant, but only genuinely new instances get written to, and the stash
-- guards make a second visit to the same instance free.
-- Prune pass, run alongside the pulse.
--
-- Every stash entry keeps a reference to a Roblox instance, and a referenced
-- instance is not collected -- so a session that strips ten rounds in a row was
-- holding ten rounds' worth of dead parts and decals for as long as the switch
-- stayed on. That grows until the client runs out of memory.
--
-- The property stashes are the easy case: they only ever hold instances we did
-- NOT detach, so a nil Parent means the game destroyed it and the entry is
-- dead weight. The detached stash is judged on whether its remembered parent is
-- still part of the game at all -- if it is not, there is nowhere to put the
-- thing back, so keeping it buys nothing.
ONX.perf.PROP_STASHES = { "part", "volume", "texid", "enabled" }

function ONX.perf.prune()
    local dropped = 0
    for _, name in ipairs(ONX.perf.PROP_STASHES) do
        local tbl = ONX.perf.stash[name]
        if tbl then
            local keys, n = ONX.perf.keysOf(tbl)
            for i = 1, n do
                local inst = keys[i]
                local ok, parent = pcall(ONX.perf.readProp, inst, "Parent")
                -- ...except "enabled": killFX saves an emitter's Enabled and then
                -- detaches it, so a nil Parent there is OURS, and dropping the
                -- entry left the emitter dead after it was put back. Keep it
                -- while the detached stash still owns the instance; once that
                -- entry is pruned, a later pass clears this one too.
                if ((not ok) or parent == nil) and ONX.perf.stash.parent[inst] == nil then
                    tbl[inst] = nil
                    dropped = dropped + 1
                end
                ONX.perf.breathe(i)
            end
        end
    end

    local keys, n = ONX.perf.keysOf(ONX.perf.stash.parent)
    for i = 1, n do
        local inst = keys[i]
        local parent = ONX.perf.stash.parent[inst]
        if parent ~= nil then
            local ok, alive = pcall(ONX.perf.inGame, parent)
            if (not ok) or (not alive) then
                -- Out of the game, but maybe only because WE took its top
                -- ancestor out (a pet Remove Pets is holding): that comes back
                -- on restore, and this must go back into it, so keep it.
                local held = false
                pcall(function()
                    local top = parent
                    while top.Parent do top = top.Parent end
                    held = ONX.perf.stash.parent[top] ~= nil
                end)
                if not held then
                    ONX.perf.stash.parent[inst] = nil
                    ONX.perf.owner[inst] = nil
                    dropped = dropped + 1
                end
            end
        end
        ONX.perf.breathe(i)
    end

    -- Hooked Animators of characters that are gone (every respawn, every
    -- round): their entries held the dead Animator and its connection forever.
    local akeys, an = ONX.perf.keysOf(ONX.perf.animConns)
    for i = 1, an do
        local a = akeys[i]
        local ok, parent = pcall(ONX.perf.readProp, a, "Parent")
        if (not ok) or parent == nil then
            local conn = ONX.perf.animConns[a]
            if conn then pcall(function() conn:Disconnect() end) end
            ONX.perf.animConns[a] = nil
            dropped = dropped + 1
        end
        ONX.perf.breathe(i)
    end
    return dropped
end

function ONX.perf.inGame(inst) return inst:IsDescendantOf(game) end

-- 10s rather than 5: a pass is chunked over many frames now, and at 5s a big
-- map spent a fifth of every second re-walking itself for nothing.
ONX.perf.PULSE = 10
ONX.perf.pulseThread = nil

function ONX.perf.stopPulse()
    if ONX.perf.pulseThread then
        pcall(task.cancel, ONX.perf.pulseThread)
        ONX.perf.pulseThread = nil
    end
    -- Cancelling a thread that was mid-sweep leaves the one-at-a-time guard
    -- raised, and every later sweep would return immediately without doing
    -- anything. Cleared here because this is the only place a sweep can be
    -- killed from outside.
    ONX.perf.sweeping = false
end

function ONX.perf.startPulse()
    ONX.perf.stopPulse()
    ONX.perf.pulseThread = task.spawn(function()
        while true do
            task.wait(ONX.perf.PULSE)
            -- pcall'd because this thread has to outlive a bad pass: an
            -- unprotected error here kills the thread outright, and the
            -- re-sweep would stop for the rest of the session in silence.
            local ok, err = pcall(ONX.perf.sweep)
            local pok, perr = pcall(ONX.perf.prune)
        end
    end)
end

-- One watcher for all of them, kept alive only while at least one sweeping
-- feature is on. A connection per feature would mean six handlers racing over
-- every descendant of a loading map.
function ONX.perf.syncWatcher()
    local need = ONX.perf.on.textures or ONX.perf.on.effects 
              or ONX.perf.on.sounds or ONX.perf.on.anims or ONX.perf.on.weaponfx
              or ONX.perf.on.pets
    if need and not ONX.perf.watchConn then
        ONX.perf.watchConn = Workspace.DescendantAdded:Connect(ONX.perf.enqueue)
        ONX.perf.startDrain()
        ONX.perf.startPulse()
    elseif (not need) and ONX.perf.watchConn then
        pcall(function() ONX.perf.watchConn:Disconnect() end)
        ONX.perf.watchConn = nil
        ONX.perf.stopDrain()
        ONX.perf.stopPulse()
    end

    -- Second watcher, only for weapon effects: the Backpack lives on the
    -- player, not in the map, and a knife is re-created there on every respawn.
    if ONX.perf.on.weaponfx and not ONX.perf.playerConn then
        ONX.perf.playerConn = LocalPlayer.DescendantAdded:Connect(ONX.perf.enqueue)
    elseif (not ONX.perf.on.weaponfx) and ONX.perf.playerConn then
        pcall(function() ONX.perf.playerConn:Disconnect() end)
        ONX.perf.playerConn = nil
    end
end

--// restores ---------------------------------------------------

-- Reparenting is the one restore that can genuinely fail: the old parent may
-- have been destroyed with the round it belonged to, and assigning to a
-- destroyed instance throws. Dropped silently in that case -- the thing we
-- were putting back no longer has anywhere to go.
function ONX.perf.restoreOwned(key)
    local keys, n = ONX.perf.keysOf(ONX.perf.stash.parent)
    for i = 1, n do
        local inst = keys[i]
        local parent = ONX.perf.stash.parent[inst]
        if parent ~= nil and ONX.perf.owner[inst] == key then
            -- Tried rather than tested. The obvious guard -- only restore when
            -- parent.Parent is non-nil -- reads as "is this parent still in the
            -- tree", but it also rejects a parent that is alive and merely
            -- detached, which is exactly what a pet model is while Remove Pets
            -- holds it: its parts are fine, so their decals should go back.
            -- Assigning to a genuinely destroyed parent throws, and that is
            -- what this catches.
            pcall(ONX.perf.reparent, inst, parent)
            ONX.perf.stash.parent[inst] = nil
            ONX.perf.owner[inst] = nil
        end
        ONX.perf.breathe(i)
    end
end

-- Runs BEFORE restoreOwned for the same key, because that is what clears the
-- owner tags this filters on.
function ONX.perf.restoreEnabled(key)
    local keys, n = ONX.perf.keysOf(ONX.perf.stash.enabled)
    for i = 1, n do
        local e = keys[i]
        local was = ONX.perf.stash.enabled[e]
        if was ~= nil and ONX.perf.owner[e] == key then
            pcall(ONX.perf.setProp, e, "Enabled", was)
            ONX.perf.stash.enabled[e] = nil
        end
        ONX.perf.breathe(i)
    end
end

function ONX.perf.restoreTextures()
    ONX.perf.restoreOwned("textures")

    local keys, n = ONX.perf.keysOf(ONX.perf.stash.texid)
    for i = 1, n do
        local sm = keys[i]
        local id = ONX.perf.stash.texid[sm]
        if id ~= nil then
            if sm.Parent then pcall(ONX.perf.setProp, sm, "TextureId", id) end
            ONX.perf.stash.texid[sm] = nil
        end
        ONX.perf.breathe(i)
    end

    keys, n = ONX.perf.keysOf(ONX.perf.stash.part)
    for i = 1, n do
        local part = keys[i]
        local was = ONX.perf.stash.part[part]
        if was ~= nil then
            if part.Parent then pcall(ONX.perf.restorePart, part, was) end
            ONX.perf.stash.part[part] = nil
        end
        ONX.perf.breathe(i)
    end
end

--// the feature table -----------------------------------------
-- Keyed, not ordered: the UI below owns the order it shows them in, and the
-- master toggle owns which ones it drives.
ONX.perf.features = {}

--// FPS counter ------------------------------------------------
-- Its own ScreenGui, in CoreGui, outside the window: it has to stay readable
-- with the panel closed, which is the only time the framerate is worth
-- watching. Named to match the HUD tiles' "Onyx*Button" pattern so the
-- load-time CoreGui sweep collects it if a session ever dies mid-run.
ONX.perf.gui, ONX.perf.label, ONX.perf.fpsConn = nil, nil, nil

function ONX.perf.killCounter()
    if ONX.perf.fpsConn then pcall(function() ONX.perf.fpsConn:Disconnect() end); ONX.perf.fpsConn = nil end
    -- the drag listener is on UserInputService, so it outlives the ScreenGui
    if ONX.perf.dragConn then pcall(function() ONX.perf.dragConn:Disconnect() end); ONX.perf.dragConn = nil end
    if ONX.perf.gui then pcall(function() ONX.perf.gui:Destroy() end); ONX.perf.gui = nil end
    ONX.perf.label = nil
end

function ONX.perf.buildCounter()
    ONX.perf.killCounter()

    local sg = Instance.new("ScreenGui")
    sg.Name = "ScreenGui"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 9000  -- above the game, below the crosshair at 10000
    sg.Parent = (gethui and gethui()) or CoreGui

    -- A TextButton rather than a Frame, purely so it reliably receives input for
    -- the drag below: a plain Frame does not take mouse input unless it is
    -- Active, and a button is the shape Roblox already gives that behaviour to.
    local box = Instance.new("TextButton")
    box.AutoButtonColor = false
    box.Text = ""
    box.AnchorPoint = Vector2.new(0.5, 0)
    -- a position dragged earlier this session wins over the default slot
    box.Position = ONX.perf.fpsPos or UDim2.new(0.5, 0, 0, 6)
    box.Size = UDim2.fromOffset(72, 26)
    box.BackgroundColor3 = Color3.fromRGB(10, 10, 13)
    box.BackgroundTransparency = 0.25
    box.BorderSizePixel = 0
    box.Parent = sg
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 0.85
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = box

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.Text = "-- FPS"
    label.TextColor3 = Color3.fromRGB(240, 240, 246)
    label.Parent = box

    ONX.perf.gui, ONX.perf.label = sg, label

    -- Drag, in offsets rather than scale, so the tile stays the size it is and
    -- lands exactly where it was dropped. The moved position is remembered on
    -- ONX.perf.fpsPos, so switching the counter off and on again -- which
    -- rebuilds this whole ScreenGui -- does not throw the placement away.
    local dragging, dragFrom, boxFrom = false, nil, nil
    local function endDrag()
        if not dragging then return end
        dragging = false
        ONX.perf.fpsPos = box.Position
    end
    box.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragFrom, boxFrom = true, input.Position, box.Position
            -- the press's own input ends the drag wherever the release lands:
            -- box.InputEnded never fires for a release off the tile
            local c; c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
                    c:Disconnect()
                    endDrag()
                end
            end)
        end
    end)
    box.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            endDrag()
        end
    end)
    -- Tracked on UserInputService, not on the button: once the pointer moves
    -- faster than the tile follows it, it is outside the button and the
    -- button's own InputChanged stops firing -- which reads as the drag
    -- "sticking" whenever you move quickly.
    ONX.perf.dragConn = UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        -- moving with the button already up: the release went missing
        if input.UserInputType == Enum.UserInputType.MouseMovement and not UserInputService.TouchEnabled
           and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            endDrag()
            return
        end
        local delta = input.Position - dragFrom
        box.Position = UDim2.new(
            boxFrom.X.Scale, boxFrom.X.Offset + delta.X,
            boxFrom.Y.Scale, boxFrom.Y.Offset + delta.Y)
    end)

    -- Counted over a window, not derived from a single frame's delta: 1/dt of
    -- one frame swings by tens of frames between samples and reads as noise.
    local frames, last = 0, os.clock()
    ONX.perf.fpsConn = RunService.RenderStepped:Connect(function()
        frames = frames + 1
        local now = os.clock()
        local span = now - last
        if span < 0.5 then return end
        local fps = math.floor(frames / span + 0.5)
        frames, last = 0, now
        label.Text = fps .. " FPS"
        -- green / amber / red, same palette as the tab icons
        label.TextColor3 = (fps >= 50 and C.green)
                        or (fps >= 30 and C.amber)
                        or C.red
    end)
end

--// switching --------------------------------------------------

-- Idempotent on purpose. The master toggle both moves a sub-switch (which
-- makes WindUI fire that switch's own callback) and calls this directly, so
-- every set is liable to arrive twice; the flag check is what makes the second
-- one free instead of double-stripping.
--
-- ONX.perf.batch is what keeps the master switch from costing eleven passes over
-- every descendant of Workspace. Six of the features do their work by sweeping,
-- and the sweep is one dispatch that reads all the flags at once -- so during a
-- batch each of those only raises its flag, and setAll runs the single pass.
ONX.perf.batch = false

function ONX.perf.set(key, want)
    want = want and true or false
    if ONX.perf.on[key] == want then return end
    local f = ONX.perf.features[key]
    if not f then return end
    -- Flag first, then act: ONX.perf.apply reads ONX.perf.on, and the sweep inside f.on
    -- goes through ONX.perf.apply.
    ONX.perf.on[key] = want
    if ONX.perf.batch and want and f.sweeps then return end
    local ok, err = pcall(want and f.on or f.off)
    ONX.perf.syncWatcher()
end

-- Everything the master switch drives, in the order the UI lists them.
ONX.perf.MASTER = {
    "fpsCounter", "textures", "effects", "weaponfx", "pets", "anims",
    "lighting", "terrain", "sounds", "quality",
}

-- MIRRORS, not one element: the same master switch appears on the Visuals tab
-- and again on Autofarm, because someone who is farming wants the framerate
-- without leaving the tab they are watching. Both are moved on every setAll.
--
-- Which is exactly why the re-entrancy guard below is load-bearing: moving a
-- mirror fires ITS callback, which calls setAll again, which moves the other
-- mirror, which calls setAll... The guard turns that into one pass.
ONX.perf.MIRRORS = { "master", "masterFarm" }
ONX.perf.settingAll = false

function ONX.perf.setAll(want)
    if ONX.perf.settingAll then return end
    ONX.perf.settingAll = true
    -- Onyx's own decorative loops stand still while it's on
    UI.calm = want and true or nil
    -- belt for the same braces as stopPulse: nothing should be able to wedge
    -- the master switch into doing nothing
    ONX.perf.sweeping = false
    ONX.perf.batch = true
    local ok, err = pcall(function()
        for _, key in ipairs(ONX.perf.MASTER) do
            -- Move the switch as well as the state, so the tab cannot end up
            -- disagreeing with what is actually running. Moving it fires that
            -- switch's own callback, which is the call that does the work; the
            -- ONX.perf.set after it is the belt to that braces, and free when the
            -- callback already landed.
            ONX.setToggle(ONX.perf.el[key], want)
            ONX.perf.set(key, want)
        end
    end)
    for _, name in ipairs(ONX.perf.MIRRORS) do
        ONX.setToggle(ONX.perf.el[name], want)
    end
    ONX.perf.batch = false
    ONX.perf.settingAll = false
    -- the one pass the batch deferred -- on its own thread: it breathes a frame
    -- every 75 instances, and restoring a saved Performance mode at load ran
    -- it on the main chunk, holding up the skin grid for seconds
    if want then task.spawn(pcall, ONX.perf.sweep) end
    ONX.perf.syncWatcher()
end

-- Teardown. Called from the unload path, and deliberately NOT routed through
-- the UI: the window is already going away by then.
function ONX.perf.restoreAll()
    ONX.perf.stopPulse()
    ONX.perf.stopDrain()
    for key in next, ONX.perf.features do ONX.perf.set(key, false) end
    ONX.perf.killCounter()
    -- Only if we ever capped it, and never with a 0 -- see the slider below for
    -- what sending a literal zero does to the client.
    if ONX.perf.capped then
        ONX.perf.capped = false
        pcall(function() if setfpscap then setfpscap(ONX.perf.UNCAPPED) end end)
    end
end

-- The Autofarm tab builds its own copy of the master switch long before this
-- block runs, so it parks the element on ONX and this picks it up. It cannot
-- register itself: ONX.perf does not exist yet at the point that tab is built.

    ONX.perf.features.fpsCounter = {
        on  = function() ONX.perf.buildCounter() end,
        off = function() ONX.perf.killCounter() end,
    }
ONX.perf.features.textures = {
    sweeps = true,
    on  = function() ONX.perf.sweep() end,
    off = function() ONX.perf.restoreTextures() end,
}


ONX.perf.features.effects = {
    sweeps = true,
    on  = function() ONX.perf.sweep() end,
    off = function()
        ONX.perf.restoreEnabled("effects")
        ONX.perf.restoreOwned("effects")
    end,
}


ONX.perf.features.weaponfx = {
    sweeps = true,
    on  = function() ONX.perf.sweep() end,
    off = function()
        ONX.perf.restoreEnabled("weaponfx")
        ONX.perf.restoreOwned("weaponfx")
    end,
}

ONX.perf.features.pets = {
    on = function()
        local box = Workspace:FindFirstChild("PetContainer")
        if box then
            for _, pet in ipairs(box:GetChildren()) do ONX.perf.detach(pet, "pets") end
        end
        -- and the watcher keeps it empty from here; see ONX.perf.apply
    end,
    off = function() ONX.perf.restoreOwned("pets") end,
}

ONX.perf.features.anims = {
    sweeps = true,
    on  = function() ONX.perf.sweep() end,
    off = function()
        for a, conn in next, ONX.perf.animConns do
            pcall(function() conn:Disconnect() end)
            ONX.perf.animConns[a] = nil
        end
    end,
}


ONX.perf.features.sounds = {
    sweeps = true,
    on  = function() ONX.perf.sweep() end,
    off = function()
        local keys, n = ONX.perf.keysOf(ONX.perf.stash.volume)
        for i = 1, n do
            local snd = keys[i]
            local vol = ONX.perf.stash.volume[snd]
            if vol ~= nil then
                if snd.Parent then pcall(ONX.perf.setProp, snd, "Volume", vol) end
                ONX.perf.stash.volume[snd] = nil
            end
            ONX.perf.breathe(i)
        end
    end,
}


-- Shadows and the post-processing stack. The three scalars matter as much
-- as GlobalShadows does: EnvironmentDiffuse/SpecularScale are what make a
-- part sample its surroundings, and ShadowSoftness is a blur pass over the
-- whole shadow map.
ONX.perf.features.lighting = {
    on = function()
        if not ONX.perf.stash.light then
            ONX.perf.stash.light = {
                shadows = ONX.perf.LIGHTING.GlobalShadows,
                diffuse = ONX.perf.LIGHTING.EnvironmentDiffuseScale,
                spec    = ONX.perf.LIGHTING.EnvironmentSpecularScale,
                soft    = ONX.perf.LIGHTING.ShadowSoftness,
            }
        end
        pcall(function()
            ONX.perf.LIGHTING.GlobalShadows            = false
            ONX.perf.LIGHTING.EnvironmentDiffuseScale  = 0
            ONX.perf.LIGHTING.EnvironmentSpecularScale = 0
            ONX.perf.LIGHTING.ShadowSoftness           = 0
        end)
        -- Bloom, blur, sun rays, depth of field, colour correction: each
        -- one is a full-screen pass. Atmosphere and Sky have no Enabled
        -- property, so those get the detach treatment instead.
        for _, c in ipairs(ONX.perf.LIGHTING:GetChildren()) do
            if c:IsA("PostEffect") then
                if ONX.perf.stash.post[c] == nil then
                    ONX.perf.stash.post[c] = c.Enabled
                    pcall(function() c.Enabled = false end)
                end
            elseif c:IsA("Atmosphere") then
                ONX.perf.detach(c, "lighting")
            end
        end
        for _, c in ipairs(Workspace.Terrain:GetChildren()) do
            if c:IsA("Clouds") then ONX.perf.detach(c, "lighting") end
        end
    end,
    off = function()
        local was = ONX.perf.stash.light
        if was then
            pcall(function()
                ONX.perf.LIGHTING.GlobalShadows            = was.shadows
                ONX.perf.LIGHTING.EnvironmentDiffuseScale  = was.diffuse
                ONX.perf.LIGHTING.EnvironmentSpecularScale = was.spec
                ONX.perf.LIGHTING.ShadowSoftness           = was.soft
            end)
            ONX.perf.stash.light = nil
        end
        for c, enabled in next, ONX.perf.stash.post do
            pcall(function() if c.Parent then c.Enabled = enabled end end)
        end
        ONX.perf.stash.post = {}
        ONX.perf.restoreOwned("lighting")
    end,
}


-- Grass and animated water. Property by property, and only the ones this
-- client actually HAS.
--
-- The first version read all five into one table and wrote all five inside a
-- single pcall. Terrain.Decoration does not exist on this Roblox build, and
-- the READ threw before the pcall was ever reached -- so switching this on
-- errored out and the other four, which do exist and do help, never got
-- applied. One dead property took the whole feature down with it.
ONX.perf.features.terrain = {
    on = function()
        local t = Workspace.Terrain
        ONX.perf.stash.terrain = ONX.perf.stash.terrain or {}
        for _, row in ipairs(ONX.perf.TERRAIN) do
            local prop, want = row[1], row[2]
            local ok, was = pcall(ONX.perf.readProp, t, prop)
            if ok and ONX.perf.stash.terrain[prop] == nil then
                ONX.perf.stash.terrain[prop] = was
                pcall(ONX.perf.setProp, t, prop, want)
            end
        end
    end,
    off = function()
        local was = ONX.perf.stash.terrain
        if not was then return end
        local t = Workspace.Terrain
        -- keyed by property name, so this restores exactly what was stashed
        for prop, val in next, was do
            pcall(ONX.perf.setProp, t, prop, val)
        end
        ONX.perf.stash.terrain = nil
    end,
}


-- The graphics slider the client itself owns. settings() is level-8 only,
-- so this is the one feature that can quietly do nothing on a weak
-- executor -- hence the pcall on the read as well as the write.
ONX.perf.features.quality = {
    on = function()
        if ONX.perf.stash.quality == nil then
            pcall(function() ONX.perf.stash.quality = rbxSettings().Rendering.QualityLevel end)
        end
        -- the player's own saved Graphics Quality too: it persists across
        -- sessions, so it must come back exactly as it was, not as Automatic
        if ONX.perf.stash.savedQuality == nil then
            pcall(function()
                ONX.perf.stash.savedQuality = UserSettings():GetService("UserGameSettings").SavedQualityLevel
            end)
        end
        pcall(function() rbxSettings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        -- and every mesh drawn at its lowest level of detail
        if ONX.perf.stash.meshDetail == nil then
            pcall(function() ONX.perf.stash.meshDetail = rbxSettings().Rendering.MeshPartDetailLevel end)
        end
        pcall(function() rbxSettings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04 end)
        pcall(function()
            UserSettings():GetService("UserGameSettings").SavedQualityLevel =
                Enum.SavedQualitySetting.QualityLevel1
        end)
    end,
    off = function()
        local was = ONX.perf.stash.quality
        if was ~= nil then
            pcall(function() rbxSettings().Rendering.QualityLevel = was end)
            ONX.perf.stash.quality = nil
        end
        if ONX.perf.stash.meshDetail ~= nil then
            pcall(function() rbxSettings().Rendering.MeshPartDetailLevel = ONX.perf.stash.meshDetail end)
            ONX.perf.stash.meshDetail = nil
        end
        local saved = ONX.perf.stash.savedQuality
        if saved ~= nil then
            pcall(function() UserSettings():GetService("UserGameSettings").SavedQualityLevel = saved end)
            ONX.perf.stash.savedQuality = nil
        end
    end,
}



    --// balances, xp and level, straight off the game's own modules --------
    local function readOwned()
        local ok, pd = pcall(require, ReplicatedStorage.Modules.ProfileData)
        if not ok or type(pd) ~= "table" then return nil end
        local owned = pd.Materials and pd.Materials.Owned
        return type(owned) == "table" and owned or nil
    end
    local function coinsOwned()
        local owned = readOwned()
        return owned and (tonumber(owned.Coins) or 0) or nil
    end
    local function readXP()
        local ok, pd = pcall(require, ReplicatedStorage.Modules.ProfileData)
        return ok and type(pd) == "table" and tonumber(pd.NewXP) or nil
    end
    local function readLevel()
        local xp = readXP()
        if not xp then return nil end
        local ok, lm = pcall(require, ReplicatedStorage.Modules.LevelModule)
        if not ok or type(lm) ~= "table" or type(lm.GetLevel) ~= "function" then return nil end
        local got, lvl = pcall(lm.GetLevel, xp)
        return got and tonumber(lvl) or nil
    end
    local function bagCap() return LocalPlayer:GetAttribute("Elite") and 50 or 40 end

    --// the Discord sender ----------------------------------------------
    -- Everything goes out through one queue: Discord allows about five posts
    -- per two seconds per webhook, so a 429 waits exactly as long as Discord
    -- says and tries again, a 5xx retries, and any other 4xx (a deleted or
    -- revoked webhook) stops the sender rather than retrying forever.
    -- Pictures are public tr.rbxcdn.com links from Roblox's thumbnail API --
    -- the rbxassetid:// ids the game uses only resolve inside Roblox.
    local HTTP = (syn and syn.request) or request or http_request or (http and http.request)
    local hook = {
        url = "", on = false, rounds = true, boxes = true,
        pingGodly = true,      -- a Godly from a box always pings @everyone
        queue = {}, busy = false, dead = false, status = "unset",
        onStatus = nil,        -- the panel's status chip
    }
    local HOSTS = { "discord.com", "discordapp.com", "canary.discord.com", "ptb.discord.com" }
    local function hookUrl() return (tostring(hook.url or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
    local function hookValid()
        local u = hookUrl()
        for _, host in ipairs(HOSTS) do
            if u:find("^https://" .. host:gsub("%.", "%%.") .. "/api/webhooks/%d+/[%w_%-]+$") then return true end
        end
        return false
    end
    local function setHookStatus(st)
        hook.status = st
        if hook.onStatus then pcall(hook.onStatus, st) end
    end
    local function refreshHookStatus()
        if hookUrl() == "" then setHookStatus("unset")
        elseif not hookValid() then setHookStatus("invalid")
        elseif hook.dead then setHookStatus("rejected")
        else setHookStatus("ready") end
    end

    local thumbs = {}
    local function thumbUrl(api)
        if thumbs[api] ~= nil then return thumbs[api] or nil end
        local url, private = nil, false
        pcall(function()
            local res = HTTP and HTTP({ Url = api, Method = "GET" })
            local body = res and tostring(res.Body) or game:HttpGet(api)
            url = body:match('"imageUrl"%s*:%s*"([^"]+)"')
            if url and url:find("PrivateImage", 1, true) then url, private = nil, true end
        end)
        -- only real answers are kept: a failed request, a rate limit or a
        -- "Pending" thumbnail gets asked for again next time (it used to be
        -- cached as "no image" for the whole session); a private image never
        -- changes, so that one is remembered as none
        if url then thumbs[api] = url elseif private then thumbs[api] = false end
        return url
    end
    local function assetPic(id, size)
        id = tostring(id or ""):match("%d+")
        if not id then return nil end
        size = size or 150
        return thumbUrl(("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=%dx%d&format=Png"):format(id, size, size))
    end
    local function avatarPic()
        return thumbUrl(("https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=%d&size=150x150&format=Png&isCircular=false")
            :format(LocalPlayer.UserId))
    end
    local ONYX_MARK, COIN_ICON = "78094309343073", "197012173"
    local COLORS = {
        white = 0xFAFAFA, green = 0x4ADE80, red = 0xF87171, grey = 0x71717A,
        Godly = 0xFF3CBE, Ancient = 0xA550FF, Legendary = 0xE0413A, Rare = 0x3B82F6,
        Uncommon = 0x22C55E, Common = 0x9CA3AF, Vintage = 0xFBBF24, Unique = 0xFFFFFF,
    }
    -- The posts' emoji, built from their code points at run time
    -- (utf8.char): the source holds no emoji bytes or \u escapes for an
    -- obfuscator to mangle. Rarity dots follow the game's colours.
    ONX.EMO = {}
    for k, cps in pairs({
        coin = { 0x1FA99 }, star = { 0x2B50 }, people = { 0x1F465 }, check = { 0x2705 }, signal = { 0x1F4E1 },
        play = { 0x25B6, 0xFE0F }, stop = { 0x23F9, 0xFE0F }, timer = { 0x23F1, 0xFE0F }, hop = { 0x1F500 },
        trophy = { 0x1F3C6 }, skull = { 0x1F480 }, flag = { 0x1F3C1 }, sparkles = { 0x2728 }, gift = { 0x1F381 },
        purse = { 0x1F45B }, box = { 0x1F4E6 }, dot = { 0xB7 }, arrow = { 0x2192 }, cross = { 0x274C },
        ballot = { 0x1F5F3, 0xFE0F }, gold = { 0x1F947 }, silver = { 0x1F948 }, bronze = { 0x1F949 },
        Common = { 0x26AA }, Uncommon = { 0x1F7E2 }, Rare = { 0x1F535 }, Legendary = { 0x1F534 },
        Ancient = { 0x1F7E3 }, Godly = { 0x2728 }, Vintage = { 0x1F7E1 }, Unique = { 0x2B50 },
    }) do ONX.EMO[k] = utf8.char(table.unpack(cps)) end
    -- text that goes into a post as-is: Discord's markdown characters escaped
    function ONX.mdSafe(s) return (tostring(s):gsub("[%*_~`|\\]", "\\%0")) end
    -- a stat: its emoji and name on top, the value in bold underneath --
    -- three to a row in Discord
    local function field(icon, name, value)
        return { name = icon .. "  " .. name, value = "**" .. ONX.mdSafe(value) .. "**", inline = true }
    end

    local function pump()
        if hook.busy then return end
        hook.busy = true
        task.spawn(function()
            while #hook.queue > 0 and not hook.dead and gui.Parent do
                local job = hook.queue[1]
                local code, wait = 0, nil
                local ok, res = pcall(HTTP, {
                    Url = hookUrl(), Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" }, Body = job.body,
                })
                if ok and type(res) == "table" then
                    code = tonumber(res.StatusCode or res.Status) or 0
                    if code == 0 and res.Success == true then code = 204 end
                    if code == 429 then
                        local after = tonumber(tostring(res.Body or ""):match('"retry_after"%s*:%s*([%d%.]+)'))
                        wait = math.min(60, (after or 1) + 0.25)
                    elseif code >= 500 then
                        wait = 5
                    end
                else
                    wait = 5
                end
                if code == 200 or code == 204 then
                    table.remove(hook.queue, 1)
                    job.done, job.ok = true, true
                    task.wait(0.35)
                elseif wait then
                    task.wait(wait)
                else
                    table.remove(hook.queue, 1)
                    job.done, job.ok, job.code = true, false, code
                    if code == 401 or code == 403 or code == 404 then
                        hook.dead = true
                        setHookStatus("rejected")
                        notify({ title = "Webhook rejected", body = "Discord says it was deleted or revoked. Paste a new one.",
                                 kind = "error", duration = 6 })
                    end
                end
            end
            if hook.dead then
                for _, j in ipairs(hook.queue) do j.done, j.ok = true, false end
                hook.queue = {}
            end
            hook.busy = false
        end)
    end

    -- one embed, in the Onyx shape: who, what, the picture, the server
    local function post(e, opts)
        opts = opts or {}
        if not HTTP then return false, "your executor can't send web requests" end
        if not hookValid() then return false, "that isn't a Discord webhook link" end
        if hook.dead then return false, "the webhook was rejected" end
        if not opts.force and not hook.on then return false, "the sender is off" end
        -- only while the farm runs: rounds, boxes and the rest stay quiet
        -- with it off. `always` is for the few that belong to switching
        -- things on and off (logging started, farm stopped).
        if not opts.force and not opts.always and not farmRunning then return false, "the autofarm is off" end
        local embed = {
            title = e.title, description = e.body, color = e.color or COLORS.white,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            author = {
                name = ("%s  (@%s)"):format(LocalPlayer.DisplayName, LocalPlayer.Name),
                url = "https://www.roblox.com/users/" .. LocalPlayer.UserId .. "/profile",
                icon_url = avatarPic(),
            },
            footer = { text = e.footer or "Onyx Autofarm", icon_url = assetPic(ONYX_MARK) },
            fields = e.fields,
        }
        if e.thumb then embed.thumbnail = { url = e.thumb } end
        if e.image then embed.image = { url = e.image } end
        local payload = { username = "Onyx", avatar_url = assetPic(ONYX_MARK, 420), embeds = { embed },
                          allowed_mentions = { parse = {} } }
        if e.ping then
            payload.content = "@everyone"
            payload.allowed_mentions = { parse = { "everyone" } }
        end
        local okJ, body = pcall(HttpService.JSONEncode, HttpService, payload)
        if not okJ then return false, "couldn't build the message" end
        local job = { body = body }
        if #hook.queue >= 40 then table.remove(hook.queue, 1) end
        hook.queue[#hook.queue + 1] = job
        pump()
        if not opts.wait then return true end
        local t0 = os.clock()
        while not job.done and os.clock() - t0 < 25 do task.wait(0.1) end
        if not job.done then return false, "Discord didn't answer" end
        return job.ok, job.ok and "sent" or ("Discord answered " .. tostring(job.code))
    end

    -- (the author line already carries your name and avatar)
    local function helloEmbed(title, icon, body)
        local E = ONX.EMO
        return {
            title = icon .. "  " .. title,
            body = body or ("Watching this server since <t:%d:t>."):format(os.time()),
            color = COLORS.white,
            fields = {
                field(E.coin, "Coins", ONX.comma(coinsOwned())),
                field(E.star, "Level", ONX.comma(readLevel())),
                field(E.people, "Players", #Players:GetPlayers()),
            },
        }
    end

    -- the farm starting or stopping, and a server hop
    local session
    local function farmEmbed(started)
        local E = ONX.EMO
        if started then
            return {
                title = E.play .. "  Autofarm started",
                body = ("Collecting at **%s** m/s."):format(tostring(ONX.farmDial or farmSpeed)),
                color = COLORS.green, thumb = assetPic(COIN_ICON),
                fields = {
                    field(E.coin, "Coins", ONX.comma(coinsOwned())),
                    field(E.star, "Level", ONX.comma(readLevel())),
                    field(E.people, "Players", #Players:GetPlayers()),
                },
            }
        end
        local secs = session.ran()
        return {
            title = E.stop .. "  Autofarm stopped",
            body = ("**+%s** coins in **%d** %s."):format(ONX.comma(session.coins), session.rounds,
                session.rounds == 1 and "round" or "rounds"),
            color = COLORS.grey, thumb = assetPic(COIN_ICON),
            fields = {
                field(E.coin, "Coins", ONX.comma(coinsOwned())),
                field(E.timer, "Ran for", ("%dm %02ds"):format(secs // 60, secs % 60)),
                field(E.star, "Level", ONX.comma(readLevel())),
            },
        }
    end
    do
        local hop = ONX.populatedHop
        ONX.populatedHop = function(reason, ...)
            if hook.on and not ONX.hopping then
                pcall(post, {
                    title = ONX.EMO.hop .. "  Hopping servers",
                    body = reason == "idle" and "No round started here for 6 minutes, so the farm is moving to a new server."
                        or "This server emptied out, so the farm is moving to a busier one.",
                    color = COLORS.grey,
                    fields = { field(ONX.EMO.people, "Players left", #Players:GetPlayers()),
                               field(ONX.EMO.coin, "This session", "+" .. ONX.comma(session.coins)) },
                }, { wait = true })
            end
            return hop(reason, ...)
        end
    end

    --// rounds: the server's own clock ------------------------------------
    -- Workspace.RoundTimerPart's Time attribute goes -1 -> RoundLength when
    -- a round becomes playable and back to -1 when it ends, however it ends.
    -- The game's own per-round roster (CurrentRoundClient.PlayerData) has the
    -- role and the coin tally; VictoryScreen carries the result.
    -- ranSecs banks the time the farm has run; runFrom is set only while it
    -- runs, so the clock pauses on Stop and carries on from there on Start
    -- liveSecs: the farm's earning time only (see the Heartbeat below)
    session = { coins = 0, rounds = 0, ranSecs = 0, runFrom = nil, liveSecs = 0 }
    function session.ran()
        return math.floor(session.ranSecs + (session.runFrom and (os.clock() - session.runFrom) or 0))
    end
    ONX.roundCoins, ONX.roundCoinsAuth = 0, nil
    local round = { live = false, bags = {}, role = nil, endRole = nil, win = nil,
                    len = nil, lastT = nil, start = nil, xp0 = nil, farmed = false }
    -- PER HOUR is paced on the farm's time that can actually earn: in a
    -- round, alive, with room in the bag. Between rounds, dead or with a
    -- full bag it holds still instead of sinking. (The bag is read four
    -- times a second, not every frame.)
    do
        local canEarn, nextLook = false, 0
        ONX.conns[#ONX.conns + 1] = RunService.Heartbeat:Connect(function(dt)
            local now = os.clock()
            if now >= nextLook then
                nextLook = now + 0.25
                canEarn = farmRunning and round.live and farmAlive and coinCount() < bagCap()
            end
            if canEarn then session.liveSecs += dt end
        end)
    end
    local WIN_TEXT = {
        MurdererWin = "Murderer won", MurdererDied = "Innocents won", SheriffWin = "Sheriff won",
        HeroWin = "Hero won", InnocentWin = "Innocents won", MurdererLeft = "Murderer left",
        Time = "Time ran out", TimeRanOut = "Time ran out",
    }
    local function myRoundRec()
        local ok, crc = pcall(require, ReplicatedStorage.Modules.CurrentRoundClient)
        local pd = ok and type(crc) == "table" and type(crc.PlayerData) == "table" and crc.PlayerData
        return pd and pd[LocalPlayer.Name] or nil
    end
    local function snapshot()
        local rec = myRoundRec()
        if type(rec) ~= "table" then return end
        if type(rec.Coins) == "number" then ONX.roundCoinsAuth = rec.Coins end
        if rec.Role ~= nil then
            round.endRole = tostring(rec.Role)
            round.role = round.role or round.endRole
        end
    end
    local function roundBegin(len)
        ONX.roundCoins, ONX.roundCoinsAuth = 0, nil
        round.bags, round.role, round.endRole, round.win = {}, nil, nil, nil
        round.len, round.lastT, round.start = len, len, os.clock()
        round.xp0 = readXP()
        round.live = true
        round.farmed = farmRunning
        snapshot()
    end
    local function roundEmbed(coins, secs, xp)
        local E = ONX.EMO
        local role = round.endRole or round.role
        if round.role and round.endRole and round.role ~= round.endRole then role = round.role .. " " .. E.arrow .. " " .. round.endRole end
        local result = round.win and (WIN_TEXT[round.win] or round.win) or "Round ended"
        local won = round.win and ((round.win == "MurdererWin") == (role == "Murderer"))
        -- the round's own numbers up front; your totals and the session
        -- ride along quietly in the footer
        return {
            title = ("%s  +%s coins"):format(round.win and (won and E.trophy or E.skull) or E.flag, ONX.comma(coins)),
            body = ("%s  %s  you were **%s**"):format(result, E.dot, role or "in the lobby"),
            color = round.win and (won and COLORS.green or COLORS.red) or COLORS.grey,
            thumb = assetPic(COIN_ICON),
            fields = {
                field(E.coin, "Coins", "+" .. ONX.comma(coins)),
                field(E.sparkles, "XP", xp and ("+" .. ONX.comma(xp)) or "?"),
                field(E.timer, "Played", secs and ("%dm %02ds"):format(math.floor(secs / 60), secs % 60) or "?"),
            },
            footer = ("Level %s  %s  %s coins  %s  session +%s in %d %s"):format(ONX.comma(readLevel()), E.dot,
                ONX.comma(coinsOwned()), E.dot, ONX.comma(session.coins), session.rounds, session.rounds == 1 and "round" or "rounds"),
        }
    end
    local function roundFinish()
        if not round.live then return end
        round.live = false
        snapshot()
        -- taken now, before the next round can reset the tallies
        local coins = math.max(ONX.roundCoinsAuth or 0, ONX.roundCoins or 0)
        -- ...and whether THIS round was farmed, decided now: read after the
        -- wait below, Start pressed meanwhile counted (and reported) a round
        -- played by hand, and Stop dropped the report of one that was farmed
        local farmed = round.farmed or farmRunning
        task.spawn(function()
            -- the result and the XP land a few seconds apart; wait for both
            local t0 = os.clock()
            while os.clock() - t0 < 30 do
                if round.win and (readXP() or 0) ~= (round.xp0 or 0) then break end
                task.wait(0.25)
            end
            if farmed then session.rounds += 1 end
            local secs = (round.len and round.lastT) and math.max(0, math.floor(round.len - round.lastT))
                or (round.start and math.floor(os.clock() - round.start)) or nil
            local xpNow = readXP()
            local xp = (xpNow and round.xp0) and math.max(0, math.floor(xpNow - round.xp0)) or nil
            if farmed and hook.on and hook.rounds then pcall(post, roundEmbed(coins, secs, xp), { always = true }) end
        end)
    end
    task.spawn(function()
        local part = Workspace:WaitForChild("RoundTimerPart", 30)
        if not part or not gui.Parent then return end
        local now, len = tonumber(part:GetAttribute("Time")), tonumber(part:GetAttribute("RoundLength"))
        if now and now > 0 then
            roundBegin(len)
            if len then round.start = os.clock() - math.max(0, len - now) end
        end
        ONX.conns[#ONX.conns + 1] = part:GetAttributeChangedSignal("Time"):Connect(function()
            local t = tonumber(part:GetAttribute("Time"))
            if t == nil then return end
            if t > 0 then round.lastT = t end
            if t > 0 and not round.live then roundBegin(tonumber(part:GetAttribute("RoundLength")))
            elseif t <= 0 and round.live then roundFinish() end
            if farmRunning then round.farmed = true end
        end)
        local gp = ReplicatedStorage:FindFirstChild("Remotes")
        gp = gp and gp:FindFirstChild("Gameplay")
        if not gp then return end
        local vs = gp:FindFirstChild("VictoryScreen")
        if vs then
            ONX.conns[#ONX.conns + 1] = vs.OnClientEvent:Connect(function(_, role, cond)
                if type(cond) == "string" then round.win = cond end
                if type(role) == "string" and role ~= "" then round.endRole = role end
            end)
        end
        local cc = gp:FindFirstChild("CoinCollected")
        if cc then
            ONX.conns[#ONX.conns + 1] = cc.OnClientEvent:Connect(function(kind, run)
                local n = tonumber(run)
                if n then
                    local was = round.bags[tostring(kind or "Coin")] or 0
                    round.bags[tostring(kind or "Coin")] = n
                    local sum = 0
                    for _, v in pairs(round.bags) do sum += v end
                    ONX.roundCoins = sum
                    -- the session count moves with every coin as it lands,
                    -- rather than waiting on the round's own tally (which
                    -- the game updates late, so it sat at 0 mid-round)
                    local gain = n - was
                    if gain > 0 then
                        local counted = farmRunning or round.farmed
                        if counted then session.coins += gain end
                        if ONX.onCoin then task.spawn(pcall, ONX.onCoin, n, gain, counted) end
                    end
                end
                snapshot()
            end)
        end
        local pdc = gp:FindFirstChild("PlayerDataChanged")
        if pdc then
            ONX.conns[#ONX.conns + 1] = pdc.OnClientEvent:Connect(function() snapshot() end)
        end
    end)

    --// boxes ---------------------------------------------------------------
    -- One RemoteFunction call per box -- Remotes.Shop.OpenCrate(id, "MysteryBox",
    -- currency) -- and each one is a purchase. Prices are read from the game's
    -- shop database, and boxes are only ever paid for in Coins: Gems are the
    -- paid currency, and a loop left running on them would spend real money.
    local BOXES = {
        { "MysteryBox1", "Mystery Box #1" }, { "MysteryBox2", "Mystery Box #2" },
        { "KnifeBox1", "Knife Box #1" }, { "KnifeBox2", "Knife Box #2" }, { "KnifeBox3", "Knife Box #3" },
        { "KnifeBox4", "Knife Box #4" }, { "KnifeBox5", "Knife Box #5" },
        { "GunBox1", "Gun Box #1" }, { "GunBox2", "Gun Box #2" }, { "GunBox3", "Gun Box #3" },
        { "MLG Box", "Rainbow Box" },
    }
    local boxes = {}          -- id -> { label, on, running, opened, status, onStatus }
    local function boxPrice(id)
        local ok, ns = pcall(require, ReplicatedStorage.Database.Sync.NewShop)
        local e = ok and type(ns) == "table" and ns[id]
        local p = type(e) == "table" and type(e.Price) == "table" and e.Price or nil
        return p and tonumber(p.Coins) or nil
    end
    local function boxImage(id)
        local ok, mb = pcall(require, ReplicatedStorage.Database.Sync.MysteryBox)
        local e = ok and type(mb) == "table" and mb[id]
        return type(e) == "table" and e.Image or nil
    end
    local function openBox(id)
        local r = ReplicatedStorage:FindFirstChild("Remotes")
        r = r and r:FindFirstChild("Shop")
        r = r and r:FindFirstChild("OpenCrate")
        if not r then return nil, "the shop remote is gone" end
        local ok, res = pcall(function() return r:InvokeServer(id, "MysteryBox", "Coins") end)
        if not ok then return nil, tostring(res) end
        return res
    end
    local function boxStatus(b, text)
        b.status = text
        if b.onStatus then pcall(b.onStatus, text) end
    end
    local function boxEmbed(b, itemId)
        local ok, db = pcall(require, ReplicatedStorage.Database.Sync.Item)
        local info = ok and type(db) == "table" and type(db[itemId]) == "table" and db[itemId] or {}
        local name, rarity = tostring(info.ItemName or itemId), tostring(info.Rarity or "Unknown")
        local godly = rarity:lower() == "godly"
        local E = ONX.EMO
        return {
            title = E.gift .. "  Opened " .. b.label,
            body = ("%s **%s**  %s  %s"):format(E[rarity] or E.box, ONX.mdSafe(name), E.dot, rarity),
            color = COLORS[rarity] or COLORS.white,
            thumb = assetPic(tostring(b.image or ""):match("%d+")),
            image = assetPic(info.ItemID, 420),
            ping = godly and hook.pingGodly,
            fields = {
                field(E.coin, "Cost", ONX.comma(b.cost)),
                field(E.purse, "Coins left", ONX.comma(coinsOwned())),
                field(E.box, "Opened", b.opened),
            },
        }
    end
    -- the map vote: who you're voting for (and what else is on it), then who
    -- won and every map's votes, ranked. `pic` is the map's picture.
    function ONX.voteEmbed(pick, pads, win, pic)
        local E = ONX.EMO
        local function votes(n) return n .. (n == 1 and " vote" or " votes") end
        if not win then
            local names = {}
            for _, p in ipairs(pads) do
                names[#names + 1] = p.key == pick.key and ("**" .. ONX.mdSafe(p.name) .. "**") or ONX.mdSafe(p.name)
            end
            return {
                title = E.ballot .. "  Voting for " .. pick.name,
                body = "On the vote: " .. table.concat(names, "  " .. E.dot .. "  "),
                color = COLORS.white, thumb = pic,
            }
        end
        local mine = win.key == pick.key
        local ranked = table.clone(pads)
        table.sort(ranked, function(a, b) return a.votes > b.votes end)
        local medal, lines = { E.gold, E.silver, E.bronze }, {}
        for i, p in ipairs(ranked) do
            lines[i] = ("%s  **%s**  %s  %s"):format(medal[i] or E.dot, ONX.mdSafe(p.name), E.dot, votes(p.votes))
        end
        return {
            title = ("%s  %s won with %s%s"):format(mine and E.check or E.cross, win.name, votes(win.votes), mine and "!" or ""),
            body = table.concat(lines, "\n"),
            color = mine and COLORS.green or COLORS.red,
            image = pic,
        }
    end
    local function runBox(id)
        local b = boxes[id]
        if b.running then return end
        b.running = true
        task.spawn(function()
            while b.on and gui.Parent do
                local cost, have = boxPrice(id), coinsOwned()
                b.cost = cost
                -- Only while the farm runs, like everything on this tab: the
                -- switch arms the box, Start farming sets it opening (and its
                -- Discord posts with it). Stop pauses it again.
                if not farmRunning then
                    if b.status ~= "Waiting for farm" then boxStatus(b, "Waiting for farm") end
                    task.wait(0.5)
                elseif cost and have and have < cost then
                    boxStatus(b, "Needs " .. ONX.comma(cost - have) .. " more coins")
                    task.wait(3)
                else
                    local reward, err = openBox(id)
                    if reward then
                        b.opened += 1
                        boxStatus(b, "Opened " .. b.opened)
                        if hook.on and hook.boxes then task.spawn(pcall, function() post(boxEmbed(b, reward)) end) end
                        task.wait(1)
                    else
                        local now = coinsOwned()
                        if cost and now and now < cost then
                            task.wait(3)       -- lost the race for the balance: just short now
                        else
                            b.on = false
                            if b.setOn then b.setOn(false) end
                            boxStatus(b, "Stopped")
                            notify({ title = b.label, body = (b.opened > 0 and ("Opened " .. b.opened .. ", then stopped: ") or "Couldn't open: ")
                                .. (err or "the shop refused") .. ".", kind = "error", duration = 5 })
                            break
                        end
                    end
                end
            end
            if not b.on and b.status ~= "Stopped" then boxStatus(b, b.opened > 0 and ("Opened " .. b.opened) or "Off") end
            b.running = false
        end)
    end

    --// the panel ---------------------------------------------------------------
    -- the first version of this tab saved under the hub's WindUI flag names
    -- (Toggle_*, Slider_*, Input_*) -- shells and an old webhook copy among
    -- them; none of it is read any more, so it's cleared out
    if type(settings.farm) == "table" then
        local stale = false
        for k in pairs(settings.farm) do
            if type(k) == "string" and (k:find("^Toggle_") or k:find("^Slider_") or k:find("^Input_")) then
                settings.farm[k] = nil
                stale = true
            end
        end
        if stale then saveSettings() end
    end
    local saved = type(settings.farm) == "table" and settings.farm or {}
    local function remember(key, v)
        settings.farm = type(settings.farm) == "table" and settings.farm or {}
        settings.farm[key] = v
        saveSettings()
    end
    local function savedOr(key, default)
        local v = saved[key]
        if v == nil then return default end
        return v
    end

    local api = { hook = hook, boxes = boxes }
    -- Shift lock fights the farm for your character: it turns you to face
    -- the camera every frame while the farm is steering, which throws the
    -- character about. While farming it's switched off (if it was on, it
    -- drops) and Shift does nothing but say why; stopping hands it back.
    do
        local was, guard, keys
        function ONX.blockShiftLock(on)
            if on then
                if guard then return end
                was = LocalPlayer.DevEnableMouseLock
                LocalPlayer.DevEnableMouseLock = false
                guard = LocalPlayer:GetPropertyChangedSignal("DevEnableMouseLock"):Connect(function()
                    if LocalPlayer.DevEnableMouseLock then LocalPlayer.DevEnableMouseLock = false end
                end)
                local told = 0
                keys = UIS.InputBegan:Connect(function(io, typing)
                    if typing or (io.KeyCode ~= Enum.KeyCode.LeftShift and io.KeyCode ~= Enum.KeyCode.RightShift) then return end
                    if os.clock() - told < 4 then return end
                    told = os.clock()
                    notify({ title = "Shift lock is off while farming", body = "It fights the farm for your character. It comes back when you stop.",
                             kind = "info", key = "shiftlock" })
                end)
            else
                if guard then guard:Disconnect(); guard = nil end
                if keys then keys:Disconnect(); keys = nil end
                if was ~= nil then
                    LocalPlayer.DevEnableMouseLock = was
                    was = nil
                end
            end
        end
    end

    -- A spinning ring on a stroke: a gradient, dim most of the way round and
    -- lit at one end, turning once every `period` seconds. Returns set(dim,
    -- lit, t), which blends the colours over rather than snapping them; a
    -- flat colour (dim == lit) hides the turn. The stroke itself stays white
    -- so the gradient's colours show as they are.
    function ONX.ringOn(st, period)
        st.Color = WHITE
        local g = make("UIGradient", { Color = ColorSequence.new(C.border), Parent = st })
        UI.loop(TweenService:Create(g, TweenInfo.new(period or 7, EASE.Linear, DIR.In, -1), { Rotation = 360 }), st.Parent)
        local blend = make("NumberValue", { Value = 1, Parent = st })
        local fromDim, fromLit, dim, lit = C.border, C.border, C.border, C.border
        blend.Changed:Connect(function(a)
            local d, l = fromDim:Lerp(dim, a), fromLit:Lerp(lit, a)
            g.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, d), ColorSequenceKeypoint.new(0.45, d), ColorSequenceKeypoint.new(1, l),
            })
        end)
        return function(newDim, newLit, t)
            local a = blend.Value
            fromDim, fromLit = fromDim:Lerp(dim, a), fromLit:Lerp(lit, a)
            dim, lit = newDim, newLit
            blend.Value = 0
            TweenService:Create(blend, TweenInfo.new(t or 0.25, EASE.Quad, DIR.Out), { Value = 1 }):Play()
        end
    end

    -- The skin grid's back-to-top button, for any tab that scrolls: it rises
    -- in once you're 160px down and glides the page back up, and clicking the
    -- open tab again in the sidebar does the same.
    -- A tab's cards end on one of the background grid's vertical lines
    -- (every 60px, from CONTENT_X): the page is widened -- or narrowed -- by
    -- the few pixels to the nearest line, and again when the window resizes.
    function ONX.snapToGrid(page)
        page.Size = UI.listClip.Size
        return UI.snapPage(page)
    end

    function ONX.addScrollTop(page, scroll, tabId)
        local wrap = make("CanvasGroup", {
            BackgroundTransparency = 1, GroupTransparency = 1, Visible = false, AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -22, 1, -6), Size = UDim2.fromOffset(38, 38), ZIndex = 3, Parent = page,
        })
        local b = make("TextButton", {
            Text = "", AutoButtonColor = false, BackgroundColor3 = C.pill, BorderSizePixel = 0,
            Position = UDim2.fromOffset(1, 1), Size = UDim2.fromOffset(36, 36), ZIndex = 3, Parent = wrap,
        })
        corner(b, FULL)
        local bst = stroke(b, C.toTopEdge)
        C.toTopRing(bst)
        local arrow = image({ Image = ICON.arrowUp, ImageColor3 = C.toTopInk, AnchorPoint = Vector2.new(0.5, 0.5),
                              Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), ZIndex = 3, Parent = b })
        C.toTopFeel(b, arrow)
        b.MouseEnter:Connect(function()
            sfx("hover")
            tween(b, 0.15, { BackgroundColor3 = C.pillHover })
            tween(bst, 0.15, { Color = C.toTopEdgeHot })
            tween(arrow, 0.15, { ImageColor3 = C.toTopInkHot })
        end)
        b.MouseLeave:Connect(function()
            tween(b, 0.2, { BackgroundColor3 = C.pill })
            tween(bst, 0.2, { Color = C.toTopEdge })
            tween(arrow, 0.2, { ImageColor3 = C.toTopInk })
        end)
        local function toTop()
            if scroll.CanvasPosition.Y <= 0 then return end
            tween(scroll, 0.5, { CanvasPosition = Vector2.new(0, 0) }, EASE.Quint, DIR.Out)
        end
        for _, t in ipairs(TABS) do if t.id == tabId then t.toTop = toTop end end
        b.MouseButton1Click:Connect(function()
            sfx("click")
            toTop()
        end)
        local up = false
        scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            local want = scroll.CanvasPosition.Y > 160
            if want == up then return end
            up = want
            if want then
                C.toTopPop(wrap, arrow, true)
            else
                C.toTopPop(wrap, arrow, false).Completed:Connect(function()
                    if not up then wrap.Visible = false end
                end)
            end
        end)
    end

    local function buildPanel()
        local page = make("CanvasGroup", {
            Name = "FarmPage", BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1, Visible = false,
            Position = UI.listClip.Position, Size = UI.listClip.Size, ZIndex = 2, Parent = win,
        })
        corner(page, 12)
        local scroll = make("ScrollingFrame", {
            BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = C.borderHi,
            VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, Parent = page,
        })
        pad(scroll, 2, 6, UI.SEARCH_Y - UI.LIST_TOP, 16)
        make("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 14),
            HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = scroll,
        })
        C.edgeFade(page, scroll)
        for _, t in ipairs(TABS) do if t.id == "farm" then t.page = page end end
        api.page = page
        ONX.addScrollTop(page, scroll, "farm")
        ONX.snapToGrid(page)

        local order = 0
        local function nextOrder() order += 1; return order end
        local GREY = hex("#18181b")

        -- change a label's text with a quick crossfade instead of a jump; the
        -- newest change wins if several land at once
        local swapTok = {}
        local function swap(label, str)
            if label.Text == str and not swapTok[label] then return end
            swapTok[label] = (swapTok[label] or 0) + 1
            local mine = swapTok[label]
            tween(label, 0.1, { TextTransparency = 1 }, EASE.Quad, DIR.In).Completed:Connect(function()
                if swapTok[label] ~= mine then return end
                label.Text = str
                tween(label, 0.22, { TextTransparency = 0 }, EASE.Quad, DIR.Out).Completed:Connect(function()
                    if swapTok[label] == mine then swapTok[label] = nil end
                end)
            end)
        end
        -- a number that counts up (or down) to its new value
        local counters = {}
        local function countTo(label, n, fmt)
            local c = counters[label]
            if not c then
                c = { value = make("NumberValue", { Value = n, Parent = label }) }
                c.value.Changed:Connect(function(v) label.Text = (c.fmt or tostring)(math.floor(v + 0.5)) end)
                counters[label] = c
                -- starts AT n, so the tween below changes nothing and Changed
                -- never fires: write the first value straight in (the label
                -- showed 0 until the next coin otherwise)
                label.Text = (fmt or tostring)(math.floor(n + 0.5))
            end
            c.fmt = fmt
            if c.target == n then return end
            c.target = n
            TweenService:Create(c.value, TweenInfo.new(0.6, EASE.Quint, DIR.Out), { Value = n }):Play()
        end

        -- A section: a heading you can click to fold it away (the chevron
        -- turns, the body closes up) and again to open it. Whatever is built
        -- after section() goes into that section's body. Folded sections are
        -- remembered between runs.
        local current = scroll
        local folded = type(saved.folded) == "table" and saved.folded or {}
        -- (`into`: another page's list, for the Visuals tab)
        local function section(title, into)
            local wrap = make("Frame", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = nextOrder(), Parent = into or scroll,
            })
            -- (the 8px gap between heading and body folds away with the body:
            -- hiding the body at the end used to drop it all at once, and
            -- everything below jumped 8px -- the stutter at the end of a fold)
            local wrapLayout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
                                   HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = wrap })
            local h = make("TextButton", {
                Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, 18),
                LayoutOrder = 1, Parent = wrap,
            })
            local l = text({ Text = title:upper(), FontFace = geist(FW.SemiBold), TextSize = 11, TextColor3 = C.subtle,
                             Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = h })
            local chevron = image({ Image = ICON.chevron, ImageColor3 = C.subtle, AnchorPoint = Vector2.new(1, 0.5),
                                    Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(14, 14), Parent = h })
            local line = make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Parent = h })
            local function fit()
                local w = math.floor(l.AbsoluteSize.X / unscale() + 10)
                line.Position, line.Size = UDim2.new(0, w, 0.5, 0), UDim2.new(1, -(w + 24), 0, 1)
            end
            l:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
            fit()
            -- a CanvasGroup, so a fold can fade what's in it as well as close it
            local body = make("CanvasGroup", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = wrap,
            })
            local bodyPad = pad(body, 0, 0, 2, 2)    -- room for the cards' outlines at the clipped edges
            local layout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
                                                  HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = body })
            local open, token = not folded[title], 0
            -- Closing: what's inside fades out and drifts up a little while the
            -- section closes on a soft in-out curve. Opening: the section
            -- opens on a long ease-out, and its contents rise into place and
            -- fade up a beat behind it.
            local OPEN_T = TweenInfo.new(0.42, EASE.Quint, DIR.Out)
            local CLOSE_T = TweenInfo.new(0.38, EASE.Quart, DIR.InOut)
            local function setOpen(v, instant)
                open = v
                token += 1
                local mine = token
                local FOLD = v and OPEN_T or CLOSE_T
                TweenService:Create(chevron, instant and TweenInfo.new(0) or TweenInfo.new(0.35, EASE.Quint, DIR.Out),
                    { Rotation = v and 0 or -90 }):Play()
                local full = math.floor(layout.AbsoluteContentSize.Y / unscale() + 4)
                if instant then
                    body.AutomaticSize = v and Enum.AutomaticSize.Y or Enum.AutomaticSize.None
                    body.Size = UDim2.new(1, 0, 0, 0)
                    body.Visible = v
                    body.GroupTransparency = v and 0 or 1
                    bodyPad.PaddingTop = UDim.new(0, 2)
                    wrapLayout.Padding = UDim.new(0, v and 8 or 0)
                    return
                end
                TweenService:Create(wrapLayout, FOLD, { Padding = UDim.new(0, v and 8 or 0) }):Play()
                if v then
                    if not body.Visible then bodyPad.PaddingTop = UDim.new(0, -8) end
                    TweenService:Create(body, TweenInfo.new(0.34, EASE.Quad, DIR.Out, 0, false, 0.08), { GroupTransparency = 0 }):Play()
                    TweenService:Create(bodyPad, TweenInfo.new(0.45, EASE.Quint, DIR.Out, 0, false, 0.04), { PaddingTop = UDim.new(0, 2) }):Play()
                else
                    TweenService:Create(body, TweenInfo.new(0.24, EASE.Quad, DIR.In), { GroupTransparency = 1 }):Play()
                    TweenService:Create(bodyPad, CLOSE_T, { PaddingTop = UDim.new(0, -8) }):Play()
                end
                -- mid-fold (clicked again before it finished): carry on from the
                -- height it has now, instead of snapping to 0 / full first
                local midFold = body.Visible and body.AutomaticSize == Enum.AutomaticSize.None
                local from = midFold and math.floor(body.AbsoluteSize.Y / unscale() + 0.5) or (v and 0 or full)
                body.Visible = true
                body.AutomaticSize = Enum.AutomaticSize.None
                body.Size = UDim2.new(1, 0, 0, from)
                local t = TweenService:Create(body, FOLD, { Size = UDim2.new(1, 0, 0, v and full or 0) })
                t:Play()
                t.Completed:Connect(function()
                    if mine ~= token then return end
                    if v then
                        body.AutomaticSize = Enum.AutomaticSize.Y
                        body.Size = UDim2.new(1, 0, 0, 0)
                    else
                        body.Visible = false
                        bodyPad.PaddingTop = UDim.new(0, 2)
                    end
                end)
            end
            h.MouseEnter:Connect(function()
                tween(l, 0.15, { TextColor3 = C.muted })
                tween(chevron, 0.15, { ImageColor3 = C.muted })
            end)
            h.MouseLeave:Connect(function()
                tween(l, 0.2, { TextColor3 = C.subtle })
                tween(chevron, 0.2, { ImageColor3 = C.subtle })
            end)
            h.MouseButton1Click:Connect(function()
                sfx("click")
                setOpen(not open)
                folded[title] = (not open) or nil
                remember("folded", folded)
            end)
            current = body
            task.defer(function() if not open then setOpen(false, true) end end)
        end

        local function card(parent, hoverable)
            local b = make(hoverable == false and "Frame" or "TextButton", {
                BackgroundColor3 = C.tile, BorderSizePixel = 0, Size = UDim2.new(1, -2, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder(), Parent = parent or current,
            })
            if b:IsA("TextButton") then b.Text, b.AutoButtonColor = "", false end
            corner(b, 10)
            local st = stroke(b, C.border)
            pad(b, 14, 14, 12, 12)
            if hoverable ~= false then
                local over = false
                -- (a card with a ring -- OwnEdge -- paints its own outline)
                b.MouseEnter:Connect(function()
                    over = true
                    tween(b, 0.18, { BackgroundColor3 = C.tileHover })
                    if not b:GetAttribute("OwnEdge") then tween(st, 0.18, { Color = C.borderHi }) end
                end)
                b.MouseLeave:Connect(function()
                    over = false
                    tween(b, 0.22, { BackgroundColor3 = C.tile })
                    if not b:GetAttribute("OwnEdge") then tween(st, 0.22, { Color = C.border }) end
                end)
                b.MouseButton1Down:Connect(function() tween(b, 0.08, { BackgroundColor3 = C.tileActive }) end)
                b.MouseButton1Up:Connect(function() tween(b, 0.2, { BackgroundColor3 = over and C.tileHover or C.tile }) end)
            end
            return b, st
        end
        local function words(parent, title, desc, right)
            local col = make("Frame", {
                BackgroundTransparency = 1, Size = UDim2.new(1, -(right or 0), 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y, Parent = parent,
            })
            make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3), Parent = col })
            local t = text({ Text = title, FontFace = geist(FW.SemiBold), TextSize = 13, Size = UDim2.new(1, 0, 0, 16),
                             LayoutOrder = 1, Parent = col })
            if desc and desc ~= "" then
                text({ Text = desc, TextSize = 12, TextColor3 = C.muted, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0),
                       AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = col })
            end
            return col, t
        end
        -- a small switch; returns a painter
        local function switch(parent)
            local track = make("Frame", {
                BackgroundColor3 = C.border, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(36, 20), Parent = parent,
            })
            corner(track, FULL)
            local knob = make("Frame", {
                BackgroundColor3 = C.muted, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(14, 14), Parent = track,
            })
            corner(knob, FULL)
            return function(on, t)
                if t == 0 then
                    track.BackgroundColor3 = on and WHITE or C.border
                    knob.Position, knob.BackgroundColor3 = UDim2.new(0, on and 19 or 3, 0.5, 0), on and C.bg or C.muted
                    return
                end
                tween(track, 0.2, { BackgroundColor3 = on and WHITE or C.border })
                tween(knob, 0.2, { BackgroundColor3 = on and C.bg or C.muted })
                -- the knob springs across, stretching a little on the way
                knob.Size = UDim2.fromOffset(18, 14)
                tween(knob, 0.36, { Position = UDim2.new(0, on and 19 or 3, 0.5, 0) }, EASE.Back, DIR.Out)
                tween(knob, 0.3, { Size = UDim2.fromOffset(14, 14) }, EASE.Quint, DIR.Out)
            end
        end
        -- the ring a switch that's on gets: whitish, turning slowly round its
        -- card (the Fling tab's role outlines' turn); off, the plain edge
        local RING_DIM, RING_LIT = C.border:Lerp(WHITE, 0.1), hex("#d4d4d8")
        local RING_DIM_HOT, RING_LIT_HOT = C.borderHi:Lerp(WHITE, 0.1), WHITE
        -- The switches, in the skin cards' look. In a grid, each is a small
        -- card: the art on top (the faint grid and the feature's icon, white
        -- while it's on), then under a hairline ON / OFF in caps and the
        -- name, with the switch beside them. Its longer explanation is
        -- the hover card. Without a grid (Log to Discord) it's one wide row
        -- on the field's surface. Either way el:Set(v) moves it, saves it and
        -- runs its callback (the WindUI toggle's shape, so ONX.setToggle
        -- drives it too), and a switch that's on gets the slow white ring.
        local TILE_INFO = 44
        local function toggle(o)
            local el = { Value = savedOr(o.key, o.default == true) and true or false }
            local wide = not o.parent
            local b = make("TextButton", {
                Text = "", AutoButtonColor = false, BackgroundColor3 = wide and C.field or C.tile, BorderSizePixel = 0,
                Size = wide and UDim2.new(1, -2, 0, 54) or UDim2.new(), LayoutOrder = nextOrder(), Parent = o.parent or current,
            })
            corner(b, 12)
            local st = stroke(b, C.border)
            local ic, icScale, stateL, swHolder
            if wide then
                ic = image({ Image = o.icon or "", ImageColor3 = C.subtle, AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 16, 0.5, 0), Size = UDim2.fromOffset(16, 16), Parent = b })
                text({ Text = o.title, FontFace = geist(FW.SemiBold), TextSize = 13, Position = UDim2.fromOffset(44, 10),
                    Size = UDim2.new(1, -110, 0, 16), Parent = b })
                text({ Text = o.desc or "", TextSize = 11, TextColor3 = C.subtle, TextTruncate = Enum.TextTruncate.AtEnd,
                    Position = UDim2.fromOffset(44, 28), Size = UDim2.new(1, -110, 0, 14), Parent = b })
                swHolder = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(36, 20), Parent = b })
            else
                local art = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1),
                    Size = UDim2.new(1, -2, 1, -(TILE_INFO + 1)), ClipsDescendants = true, Parent = b })
                corner(art, 11)
                for k = 1, 4 do
                    make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.955, BorderSizePixel = 0,
                        Position = UDim2.new(k / 5, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), Parent = art })
                end
                for k = 1, 2 do
                    make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.955, BorderSizePixel = 0,
                        Position = UDim2.new(0, 0, k / 3, 0), Size = UDim2.new(1, 0, 0, 1), Parent = art })
                end
                ic = image({ Image = o.icon or "", ImageColor3 = C.subtle, AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24), Parent = art })
                icScale = make("UIScale", { Parent = ic })
                make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Position = UDim2.new(0, 10, 1, -TILE_INFO),
                    Size = UDim2.new(1, -20, 0, 1), Parent = b })
                stateL = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 10, 1, -TILE_INFO + 9),
                    Size = UDim2.new(1, -62, 0, 11), FontFace = geist(FW.ExtraBold), TextSize = 10, TextColor3 = C.subtle,
                    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "OFF", Parent = b })
                text({ Text = o.short or o.title, FontFace = geist(FW.SemiBold), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd,
                    Position = UDim2.new(0, 10, 1, -TILE_INFO + 21), Size = UDim2.new(1, -62, 0, 16), Parent = b })
                -- the switch sits in the info strip, right of ON / OFF and the name
                swHolder = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -10, 1, -TILE_INFO / 2), Size = UDim2.fromOffset(36, 20), Parent = b })
                tooltip.attach(b, { title = o.title, detail = o.desc })
            end
            if o.iconCell then ic.ImageRectOffset, ic.ImageRectSize = o.iconCell.offset, o.iconCell.size end
            local paint = switch(swHolder)
            b:SetAttribute("OwnEdge", true)
            local ring = ONX.ringOn(st, 7)
            local over = false
            -- the icon: fades to green while on (lighter under the pointer),
            -- grey while off
            local function iconColor(on)
                return on and (over and C.greenText or C.green) or (over and C.muted or C.subtle)
            end
            local function paintAll(t)
                local on = el.Value
                if on then
                    ring(over and RING_DIM_HOT or RING_DIM, over and RING_LIT_HOT or RING_LIT, t)
                else
                    local c = over and C.borderHi or C.border
                    ring(c, c, t)
                end
                local rest = wide and C.field or C.tile
                tween(b, t or 0.2, { BackgroundColor3 = over and C.tileHover or rest })
                tween(ic, t or 0.2, { ImageColor3 = iconColor(on) })
                if stateL then
                    -- ON / OFF, and when it acts: "ON · WHEN BAG IS FULL" --
                    -- crossfading when it flips, in step with its colour
                    local words = (on and "ON" or "OFF") .. (o.when and (" · " .. o.when) or "")
                    if t == 0 then stateL.Text = words else swap(stateL, words) end
                    tween(stateL, t or 0.2, { TextColor3 = on and C.greenText or C.subtle })
                end
            end
            b.MouseEnter:Connect(function() over = true; paintAll(0.18) end)
            b.MouseLeave:Connect(function() over = false; paintAll(0.22) end)
            function el:Set(v)
                v = v and true or false
                if v == el.Value then return end
                el.Value = v
                paint(v)
                paintAll(0.35)
                -- the icon gives a little hop
                if icScale then
                    icScale.Scale = 0.8
                    TweenService:Create(icScale, TweenInfo.new(0.45, EASE.Back, DIR.Out), { Scale = 1 }):Play()
                end
                remember(o.key, v)
                if o.callback then
                    o.callback(v)
                end
            end
            b.MouseButton1Down:Connect(function() C.ripple(b, 12) end)
            b.MouseButton1Click:Connect(function() sfx("click"); el:Set(not el.Value) end)
            paint(el.Value, 0)
            paintAll(0)
            el.restore = o.callback
            return el
        end
        -- a pill button
        local function button(parent, label, primary, w)
            local b = make("TextButton", {
                Text = "", AutoButtonColor = false, BackgroundColor3 = primary and WHITE or C.secondary, BorderSizePixel = 0,
                Size = UDim2.fromOffset(w or 110, 32), Parent = parent,
            })
            corner(b, 8)
            local st = stroke(b, primary and WHITE or C.border)
            local l = text({ Text = label, FontFace = geist(FW.SemiBold), TextSize = 13,
                             TextColor3 = primary and C.ink or C.text, TextXAlignment = Enum.TextXAlignment.Center,
                             Size = UDim2.fromScale(1, 1), Parent = b })
            local api2 = { button = b, label = l, stroke = st, primary = primary }
            function api2.style(p)
                api2.primary = p
                tween(b, 0.2, { BackgroundColor3 = p and WHITE or C.secondary })
                tween(st, 0.2, { Color = p and WHITE or C.border })
                tween(l, 0.2, { TextColor3 = p and C.ink or C.text })
            end
            b.MouseEnter:Connect(function()
                tween(b, 0.15, { BackgroundColor3 = api2.primary and C.primaryHover or C.secondaryHover })
                if not api2.primary then tween(st, 0.15, { Color = C.borderHi }) end
            end)
            b.MouseLeave:Connect(function()
                tween(b, 0.2, { BackgroundColor3 = api2.primary and WHITE or C.secondary })
                if not api2.primary then tween(st, 0.2, { Color = C.border }) end
            end)
            b.MouseButton1Down:Connect(function() tween(b, 0.06, { BackgroundColor3 = api2.primary and C.primaryPress or C.secondaryPress }) end)
            b.MouseButton1Up:Connect(function() tween(b, 0.15, { BackgroundColor3 = api2.primary and C.primaryHover or C.secondaryHover }) end)
            return api2
        end
        -- a status chip: dot and word
        local function chip(parent)
            local f = make("Frame", {
                BackgroundColor3 = GREY, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 22),
                AutomaticSize = Enum.AutomaticSize.X, Parent = parent,
            })
            corner(f, FULL)
            local st = stroke(f, C.border)
            pad(f, 8, 9)
            hlist(f, 6)
            local dot = make("Frame", { BackgroundColor3 = C.subtle, BorderSizePixel = 0, Size = UDim2.fromOffset(6, 6), LayoutOrder = 1, Parent = f })
            corner(dot, FULL)
            local l = text({ Text = "", FontFace = geist(FW.SemiBold), TextSize = 11, TextColor3 = C.muted,
                             Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = f })
            return function(word, ink, bg, edge)
                if l.Text == "" then l.Text = word else swap(l, word) end
                tween(l, 0.2, { TextColor3 = ink })
                tween(dot, 0.2, { BackgroundColor3 = ink })
                tween(f, 0.2, { BackgroundColor3 = bg or GREY })
                tween(st, 0.2, { Color = edge or C.border })
            end, f
        end

        --// FARM ------------------------------------------------------------
        section("Farm")

        -- The farm card: what the farm is doing (its dot and the state, a
        -- line on it underneath) with Start / Stop beside it, then under a
        -- hairline the bag.
        -- Its outline carries the state's colour, turning slowly.
        local hero = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, 249),
            LayoutOrder = nextOrder(), Parent = current })
        local bagCard = make("Frame", { BackgroundColor3 = C.tile, BorderSizePixel = 0, ClipsDescendants = true,
            Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 0, 96), Parent = hero })
        corner(bagCard, 12)
        local heroSt = stroke(bagCard, C.border)
        local statusField = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 8),
            Size = UDim2.new(1, -(UI.BAR_W + 8), 0, 40), Parent = bagCard })
        local dot = make("Frame", {
            BackgroundColor3 = C.subtle, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 17, 0, 12), Size = UDim2.fromOffset(8, 8), Parent = statusField,
        })
        corner(dot, FULL)
        local dotGlow = stroke(dot, C.subtle, 3, 0.75)
        local statusL = text({ Text = "Autofarm is off", FontFace = geist(FW.SemiBold), TextSize = 13,
                               Position = UDim2.fromOffset(35, 3), Size = UDim2.new(1, -41, 0, 17), Parent = statusField })
        -- the word on it, on its own line under the state
        local detailL = text({ Text = "Walks you to every coin, every round.", TextSize = 12,
                               TextColor3 = C.subtle, TextTruncate = Enum.TextTruncate.AtEnd,
                               Position = UDim2.fromOffset(35, 21), Size = UDim2.new(1, -41, 0, 15), Parent = statusField })
        -- Start / Stop: the field's surface inside the card, its own outline
        -- lighting up and turning on hover, a ripple on press; the colour is
        -- the icon's alone -- green play to start, red square to stop
        local startBtn = make("TextButton", {
            Text = "", AutoButtonColor = false, BackgroundColor3 = C.field, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -9, 0, 9), Size = UDim2.fromOffset(UI.BAR_W - 10, 38), Parent = bagCard,
        })
        corner(startBtn, 10)
        local sst = stroke(startBtn, C.border)
        local sPill = make("Frame", { BackgroundColor3 = UI.PILL_HOVER, BackgroundTransparency = 1, BorderSizePixel = 0,
                                      Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), Parent = startBtn })
        corner(sPill, 8)
        local sRing = UI.hoverRing(startBtn, 10, 0)     -- on its own edge: the real outline lights up
        local sInner = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = startBtn })
        hlist(sInner, 7, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
        local sIcon = image({ Image = ICON.farmStart, ImageColor3 = C.green, Size = UDim2.fromOffset(14, 14), LayoutOrder = 1, ZIndex = 2, Parent = sInner })
        local sIconScale = make("UIScale", { Parent = sIcon })
        local sLabel = text({ Text = "Start farming", FontFace = geist(FW.SemiBold), TextSize = 13, TextColor3 = C.muted,
                              Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 2, Parent = sInner })
        local sOver = false

        make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Position = UDim2.new(0, 16, 0, 56),
            Size = UDim2.new(1, -32, 0, 1), Parent = bagCard })
        local bagRow = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(17, 57), Size = UDim2.new(1, -34, 0, 39), Parent = bagCard })
        -- BAG, or ELITE BAG for Elite players (theirs holds 50, not 40); the
        -- bar runs from the word right up to the count
        local bagName = text({ Text = "BAG", FontFace = C.STAT_FONT, TextSize = 11, TextColor3 = WHITE, Size = UDim2.new(0, 0, 1, 0),
                               AutomaticSize = Enum.AutomaticSize.X, Parent = bagRow })
        make("UIGradient", { Rotation = 90, Color = C.STAT_SILVER, Parent = bagName })
        local bagL = text({ Text = "0 / 40", FontFace = C.STAT_FONT, TextSize = 14, TextColor3 = WHITE, AnchorPoint = Vector2.new(1, 0),
                            Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
                            TextXAlignment = Enum.TextXAlignment.Right, Parent = bagRow })
        make("UIGradient", { Rotation = 90, Color = C.STAT_SILVER, Parent = bagL })
        local bagTrack = make("Frame", {
            BackgroundColor3 = C.border, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 36, 0.5, 0), Size = UDim2.new(1, -116, 0, 6), Parent = bagRow,
        })
        local function fitBag()
            local a = math.floor(bagName.AbsoluteSize.X / unscale()) + 14
            local b2 = math.floor(bagL.AbsoluteSize.X / unscale()) + 14
            bagTrack.Position = UDim2.new(0, a, 0.5, 0)
            bagTrack.Size = UDim2.new(1, -(a + b2), 0, 6)
        end
        bagName:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBag)
        bagL:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBag)
        fitBag()
        corner(bagTrack, FULL)
        local bagFill = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = bagTrack })
        corner(bagFill, FULL)
        -- white where it starts, warming to green as the bag nears full
        local bagGrad = make("UIGradient", { Parent = bagFill })

        -- this session, then your account
        -- (odometers: every number rolls its digits to the new value)
        local acct, acctCells = C.statCard({ parent = hero, odo = true, position = UDim2.fromOffset(1, 105), size = UDim2.new(1, -2, 0, 68),
            specs = { { "COLLECTED", "0" }, { "LEVEL", "-" } } })
        local run = C.statCard({ parent = hero, odo = true, position = UDim2.fromOffset(1, 181), size = UDim2.new(1, -2, 0, 68),
            specs = { { "PER HOUR", "-" }, { "TOTAL COINS", "-" }, { "UPTIME", "0m 00s" } } })
        -- statL[1] stays the session's coins: the coin flash below lights it up
        local statL = { acct[1] }

        local farmEl = { Value = false }
        -- Stop is light too, a soft grey a step below Start's pure white, so
        -- the two read as a pair and you can still tell them apart
        local STOP_BG, STOP_BG_HOT = hex("#d4d4d8"), hex("#e0e0e4")
        local STOP_EDGE, STOP_EDGE_HOT = hex("#d4d4d8"), hex("#e0e0e4")
        local STOP_INK = C.ink
        local function paintStart(t)
            t = t or 0.25
            local on = farmEl.Value
            -- hover stays soft: the outline and the word only lift partway
            -- towards white
            tween(sst, t, { Color = sOver and C.border:Lerp(C.borderHi, 0.45) or C.border }, EASE.Quint)
            tween(sPill, t, { BackgroundTransparency = 1 }, EASE.Quint)
            tween(sLabel, t, { TextColor3 = sOver and C.muted:Lerp(C.text, 0.55) or C.muted }, EASE.Quint)
            tween(sIcon, t, { ImageColor3 = on and C.red or C.green }, EASE.Quint)
        end
        local iconTok = 0
        local function paintFarm()
            paintStart()
            swap(sLabel, farmEl.Value and "Stop farming" or "Start farming")
            iconTok += 1
            local mine = iconTok
            -- (rotation does not draw inside the page's CanvasGroup, so the
            -- swap shrinks and pops instead of turning)
            tween(sIcon, 0.1, { ImageTransparency = 1 }, EASE.Quad, DIR.In)
            tween(sIconScale, 0.1, { Scale = 0.5 }, EASE.Quad, DIR.In).Completed:Connect(function()
                if mine ~= iconTok then return end
                sIcon.Image = farmEl.Value and ICON.farmStop or ICON.farmStart
                tween(sIcon, 0.3, { ImageTransparency = 0 }, EASE.Quint, DIR.Out)
                tween(sIconScale, 0.4, { Scale = sOver and 1.18 or 1 }, EASE.Back, DIR.Out)
            end)
        end
        startBtn.MouseEnter:Connect(function()
            sOver = true
            sfx("hover")
            sRing(true)
            paintStart()
            tween(sIconScale, 0.45, { Scale = 1.18 }, EASE.Back, DIR.Out)
        end)
        startBtn.MouseLeave:Connect(function()
            sOver = false
            sRing(false)
            paintStart()
            tween(sIconScale, 0.45, { Scale = 1 }, EASE.Back, DIR.Out)
            tween(sInner, 0.45, { Position = UDim2.new() }, EASE.Back, DIR.Out)
        end)
        startBtn.MouseButton1Down:Connect(function()
            C.ripple(startBtn, 10)
            tween(sInner, 0.08, { Position = UDim2.fromOffset(0, 1) }, EASE.Quad)
        end)
        startBtn.MouseButton1Up:Connect(function()
            tween(sInner, 0.45, { Position = UDim2.new() }, EASE.Back, DIR.Out)
            paintStart(0.15)
        end)
        function farmEl:Set(v)
            v = v and true or false
            -- every call is newer than a Start still waiting out a throw
            farmEl.setTok = (farmEl.setTok or 0) + 1
            local tok = farmEl.setTok
            if v == farmEl.Value then return end
            -- The fling loop and the farm both drive your character (the
            -- farm's rig pins you and noclips you, which is what made a throw
            -- do nothing), so they never run together: the loop stops the
            -- farm when it starts, and starting the farm stops the loop --
            -- then waits out a throw that's still in the air before it goes.
            if v and ONX.flingLoopOn and ONX.stopFlingLoop then ONX.stopFlingLoop() end
            -- any throw, a loop's or a one-off from the Fling button (that one
            -- used to be ignored, so both ran at once)
            if v and flingActive then
                notify({ title = "Starting after the throw", body = "Autofarm starts as soon as the fling lands.", kind = "wait" })
                task.spawn(function()
                    local t0 = os.clock()
                    while flingActive and os.clock() - t0 < 6 do task.wait(0.1) end
                    -- only if nothing changed meanwhile: no newer click, still
                    -- off, still open, and the throw really is over
                    if farmEl.setTok == tok and not farmEl.Value and gui.Parent and not flingActive then
                        farmEl:Set(true)
                    end
                end)
                return
            end
            farmEl.Value = v
            remember("farm", v)
            paintFarm()
            if v then
                session.runFrom = session.runFrom or os.clock()
                startAutofarm()
                task.spawn(ONX.grabGun)        -- a gun already lying on the map
                pcall(ONX.blockShiftLock, true)
                ONX.startFarmHopWatch()
                ONX.startIdleHopWatch()
                if not ONX.restoring then notify({ title = "Autofarm started", body = "Collecting coins every round.", kind = "success" }) end
                if hook.on then task.spawn(function() pcall(function() post(farmEmbed(true)) end) end) end
            else
                if session.runFrom then
                    session.ranSecs += os.clock() - session.runFrom
                    session.runFrom = nil
                end
                stopAutofarm()
                pcall(ONX.blockShiftLock, false)
                ONX.stopFarmHopWatch()
                ONX.stopIdleHopWatch()
                -- The rig's own teardown only drops noclip when the character
                -- still has its UpperTorso (it bails out after a death), which
                -- left you walking through walls after Stop. Switch it off
                -- directly -- now, and once more after the farm loop's last
                -- tick has definitely finished.
                pcall(farmNoclip, false)
                task.delay(0.5, function()
                    if not farmRunning then pcall(farmNoclip, false) end
                end)
                notify({ title = "Autofarm stopped", body = ("%s coins over %d rounds this session."):format(ONX.comma(session.coins), session.rounds), kind = "off" })
                if hook.on then task.spawn(function() pcall(function() post(farmEmbed(false), { always = true }) end) end) end
            end
        end
        startBtn.MouseButton1Click:Connect(function() sfx("click"); farmEl:Set(not farmEl.Value) end)
        api.farmEl = farmEl

        -- what the farm is doing right now, read off its own state
        local function farmState()
            if not farmRunning then return "off" end
            if ONX.inLobbyNow() or roundTime() <= 0 then return "lobby" end
            if not farmAlive then return "out" end
            if coinCount() >= bagCap() then return "full" end
            if farmMoving and farmCoin then return "farming" end
            if not ONX.sawCoins then return "hiding" end
            return "clear"
        end
        -- each state: its words, the dot's colour, and a soft matching
        -- outline for the card (grey when the farm is off)
        local EDGE_GREEN = C.greenEdge:Lerp(C.border, 0.35)
        local EDGE_AMBER = C.amberEdge:Lerp(C.border, 0.45)
        local STATES = {
            off     = { "Autofarm is off", "Walks you to every coin, every round.", C.subtle, C.border },
            lobby   = { "Waiting for the next round", "Starts on its own when a round begins.", C.amber, EDGE_AMBER },
            out     = { "Out of this round", "Dead or spectating - back next round.", C.amber, EDGE_AMBER },
            full    = { "Bag full", "Every coin this round is yours.", C.green, EDGE_GREEN },
            farming = { "Collecting coins", "Moving from coin to coin.", C.green, EDGE_GREEN },
            hiding  = { "Waiting for coins", "Under the map until they spawn.", C.amber, EDGE_AMBER },
            clear   = { "Map cleared", "No coins left - waiting for the end.", C.green, EDGE_GREEN },
        }
        -- The card's outline: a glow in the status colour that circles the
        -- border (a gradient on the stroke, bright at one end, turning once
        -- every 4 seconds). Changing state blends the colours over instead
        -- of snapping; with the farm off it settles to a plain grey edge.
        heroSt.Color = WHITE
        local ring = make("UIGradient", { Color = ColorSequence.new(C.border), Parent = heroSt })
        UI.loop(TweenService:Create(ring, TweenInfo.new(4, EASE.Linear, DIR.In, -1), { Rotation = 360 }), heroSt.Parent)
        local ringDim, ringLit = C.border, C.border
        local ringBlend = make("NumberValue", { Value = 1, Parent = heroSt })
        local fromDim, fromLit = C.border, C.border
        ringBlend.Changed:Connect(function(a)
            local dim, lit = fromDim:Lerp(ringDim, a), fromLit:Lerp(ringLit, a)
            ring.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, dim), ColorSequenceKeypoint.new(0.5, dim), ColorSequenceKeypoint.new(1, lit),
            })
        end)
        local function setRing(dim, lit)
            local a = ringBlend.Value
            fromDim, fromLit = fromDim:Lerp(ringDim, a), fromLit:Lerp(ringLit, a)
            ringDim, ringLit = dim, lit
            ringBlend.Value = 0
            TweenService:Create(ringBlend, TweenInfo.new(0.45, EASE.Quad, DIR.Out), { Value = 1 }):Play()
        end

        -- the pill's farm card (shown under it while the window is closed)
        -- reads the same state
        C.farmHud = function()
            local st = farmState()
            local s = STATES[st]
            local cap, n = bagCap(), coinCount()
            if n >= 999 then n = cap end
            if not round.live then n = 0 end
            local secs = session.ran()
            local total = coinsOwned()
            return {
                running = farmRunning, title = s[1], detail = s[2], color = s[3], n = math.min(n, cap), cap = cap,
                coins = ONX.comma(session.coins), rounds = tostring(session.rounds),
                total = total and ONX.comma(total) or "-",
                -- coins an hour at this session's earning pace, from its first few
                -- seconds on (frozen in the lobby, dead or bag full: its clock stops)
                perHour = session.liveSecs >= 5 and ONX.comma(math.floor(session.coins * 3600 / session.liveSecs + 0.5)) or "-",
                ran = secs >= 3600 and ("%dh %02dm"):format(secs // 3600, (secs % 3600) // 60)
                      or ("%dm %02ds"):format(secs // 60, secs % 60),
            }
        end

        local shown
        local function tick()
            local st = farmState()
            if st ~= shown then
                shown = st
                local s = STATES[st]
                swap(statusL, s[1])
                swap(detailL, s[2])
                tween(dot, 0.25, { BackgroundColor3 = s[3] })
                tween(dotGlow, 0.25, { Color = s[3] })
                if st == "off" then setRing(C.border, C.border)
                else setRing(s[4], s[3]:Lerp(s[4], 0.25)) end
            end
            local cap, n = bagCap(), coinCount()
            bagName.Text = cap > 40 and "ELITE BAG" or "BAG"
            if n >= 999 then n = cap end
            if not farmRunning and not round.live then n = 0 end
            bagL.Text = ("%d / %d"):format(math.min(n, cap), cap)
            local frac = math.clamp(n / cap, 0, 1)
            bagGrad.Color = ColorSequence.new(WHITE, WHITE:Lerp(C.green, frac))
            tween(bagFill, 0.3, { Size = UDim2.fromScale(frac, 1), BackgroundColor3 = WHITE })
            statL[1].set(ONX.comma(session.coins))
            local hud = C.farmHud()
            run[1].set(hud.perHour)
            run[2].set(hud.total)
            run[3].set(hud.ran, false, 1)           -- time only ever rolls up
            local lvl = readLevel()
            acct[2].set(lvl and ONX.comma(lvl) or "-")
        end
        task.spawn(function()
            UI.pulse(dotGlow)
            while gui.Parent do
                -- (a minimised window leaves the page Visible: check the window too)
                if page.Visible and holder.Visible then pcall(tick) end
                task.wait(0.25)
            end
        end)

        -- A coin landing in the bag gets the same green moment as a skin
        -- landing in your inventory: the card washes green with a band of
        -- light sweeping across it, a "+1" floats off the session count, the
        -- count, its box and the bag flash green, and the caption turns into
        -- the white -> green ramp with the bag's new total.
        do
            -- over the farm card
            local wash = make("Frame", { BackgroundColor3 = C.greenText, BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = bagCard })
            corner(wash, 12)
            local band = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false,
                Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = bagCard })
            corner(band, 12)
            local bandGrad = make("UIGradient", { Color = ColorSequence.new(C.greenText), Transparency = SHINE_BAND,
                Rotation = 25, Offset = Vector2.new(-1, 0), Parent = band })
            local coinO = statL[1]
            local coinCell = acctCells[1]
            local coinEdge = coinCell:FindFirstChildOfClass("UIStroke")
            local RISE = TweenInfo.new(0.65, EASE.Quad, DIR.Out)

            -- Bag full: a small pop of confetti from the "40 / 40" count that
            -- falls back around it -- a tight burst that stays well inside the
            -- window. It lives on the window frame, not in the page's
            -- CanvasGroup (which can't draw rotation), and is only shown while
            -- the Autofarm tab is: switch away mid-burst and it's gone.
            local CONFETTI = { C.greenText, C.green, WHITE, hex("#fbbf24"), hex("#60a5fa"), hex("#f472b6") }
            local celebrated = false
            local function confetti()
                -- only where the bag bar can actually be seen: bursting out of
                -- a folded section, or from a bar scrolled out of the page,
                -- threw confetti out of nowhere over whatever was there
                local mid = bagL.AbsolutePosition + bagL.AbsoluteSize / 2
                local node = bagL
                while node and node ~= win do
                    if node:IsA("GuiObject") then
                        if not node.Visible then return end
                        if node.ClipsDescendants or node:IsA("ScrollingFrame") or node:IsA("CanvasGroup") then
                            local p, s = node.AbsolutePosition, node.AbsoluteSize
                            if mid.X < p.X or mid.Y < p.Y or mid.X > p.X + s.X or mid.Y > p.Y + s.Y then return end
                        end
                    end
                    node = node.Parent
                end
                local sc = unscale()
                local box = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = win })
                local cx = (bagL.AbsolutePosition.X + bagL.AbsoluteSize.X / 2 - win.AbsolutePosition.X) / sc
                local cy = (bagL.AbsolutePosition.Y + bagL.AbsoluteSize.Y / 2 - win.AbsolutePosition.Y) / sc
                local bits = {}
                for i = 1, 18 do
                    local round = math.random() < 0.3
                    local f = make("Frame", {
                        BackgroundColor3 = CONFETTI[math.random(#CONFETTI)], BorderSizePixel = 0,
                        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), ZIndex = 50, Parent = box,
                        Size = round and UDim2.fromOffset(4, 4) or UDim2.fromOffset(3, math.random(6, 8)),
                    })
                    if round then corner(f, FULL) end
                    -- a narrow fan straight up, soft enough to stay close
                    local a = math.rad(math.random(245, 295))
                    local sp = math.random(70, 150)
                    bits[i] = {
                        f = f, p = Vector2.new(cx + math.random(-10, 10), cy),
                        v = Vector2.new(math.cos(a), math.sin(a)) * sp,
                        r = math.random(0, 360), vr = math.random(-540, 540),
                        sway = math.random() * 6.28,
                    }
                end
                local t = 0
                local conn
                conn = RunService.RenderStepped:Connect(function(dt)
                    t += dt
                    box.Visible = page.Visible
                    for _, b in ipairs(bits) do
                        -- gravity, air drag and a small flutter sideways
                        b.v = (b.v + Vector2.new(math.sin(t * 7 + b.sway) * 20, 420) * dt) * (1 - 1.4 * dt)
                        b.p = b.p + b.v * dt
                        b.r += b.vr * dt
                        b.f.Position = UDim2.fromOffset(b.p.X, b.p.Y)
                        b.f.Rotation = b.r
                        if t > 0.9 then b.f.BackgroundTransparency = math.min(1, (t - 0.9) / 0.5) end
                    end
                    if t > 1.45 or not gui.Parent then
                        conn:Disconnect()
                        box:Destroy()
                    end
                end)
            end

            ONX.onCoin = function(n, gain, counted)
                local cap = bagCap()
                -- once per fill; a new round's first coins re-arm it -- kept
                -- up to date even while nobody's looking, or a round that
                -- started off-screen never re-armed it
                local full = n >= cap
                local celebrate = full and not celebrated
                celebrated = full
                -- only when it can be seen: a minimised window keeps the page
                -- "Visible", and all of this ran for nobody on every coin
                if not (page.Visible and holder.Visible) or not gui.Parent then return end
                -- the bag bar lights green and fades back as it grows
                bagFill.BackgroundColor3 = C.greenText
                pcall(tick)
                wash.BackgroundTransparency = 0.88
                tween(wash, 0.6, { BackgroundTransparency = 1 }, EASE.Quad)
                bandGrad.Offset = Vector2.new(-1, 0)
                band.Visible = true
                tween(bandGrad, 0.75, { Offset = Vector2.new(1, 0) }, EASE.Quad).Completed:Connect(function()
                    if bandGrad.Offset.X > 0.99 then band.Visible = false end
                end)
                -- the session count only lights up (and floats a "+1") for a coin
                -- it actually counted -- one picked up by hand with the farm off
                -- isn't added to it
                if counted ~= false then
                    -- only the number lights up green (the box itself stays put)
                    coinO.flash(C.greenText, WHITE, 0.6)
                    local plus = text({ Text = "+" .. (gain or 1), FontFace = geist(FW.SemiBold), TextSize = 14, TextColor3 = C.greenText,
                        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 19), Size = UDim2.fromOffset(40, 17),
                        TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 9, Parent = coinCell })
                    TweenService:Create(plus, RISE, { Position = UDim2.new(1, -10, 0, 11), TextTransparency = 1 }):Play()
                    task.delay(0.7, function() plus:Destroy() end)
                end
                flash(full and ("Bag full · %d / %d"):format(cap, cap)
                    or ("Coin collected · %d / %d"):format(n, cap), SUCCESS, false, 1.5)
                if celebrate then task.delay(0.15, confetti) end     -- once the bar has reached the end
            end
        end

        -- the speed
        do
            -- on the stat cards' surface: FARM SPEED and its value, the rail
            -- under them (lower is safer, higher is quicker)
            local b = make("Frame", { BackgroundColor3 = C.field, BorderSizePixel = 0, Size = UDim2.new(1, -2, 0, 66),
                LayoutOrder = nextOrder(), Parent = current })
            corner(b, 12)
            stroke(b, C.border)
            local capL = text({ Text = "FARM SPEED", FontFace = C.STAT_FONT, TextSize = 11, TextColor3 = WHITE,
                Position = UDim2.fromOffset(16, 14), Size = UDim2.new(0.5, 0, 0, 13), Parent = b })
            make("UIGradient", { Rotation = 90, Color = C.STAT_SILVER, Parent = capL })
            -- the value rolls its digits as you drag, up or down with the speed
            local valueO = C.odometer({ parent = b, font = C.STAT_FONT, size = 13, height = 15, color = WHITE,
                gradient = C.STAT_SILVER, anchor = Vector2.new(1, 0), position = UDim2.new(1, -14, 0, 13) })
            local rail = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 34),
                Size = UDim2.new(1, -32, 0, 20), Parent = b })
            local track = make("Frame", {
                BackgroundColor3 = C.border, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 0, 0.5, 3), Size = UDim2.new(1, 0, 0, 4), Parent = rail,
            })
            corner(track, FULL)
            local fill = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track })
            corner(fill, FULL)
            local knob = make("Frame", {
                BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(14, 14), ZIndex = 2, Parent = track,
            })
            corner(knob, FULL)
            stroke(knob, C.bg, 2)
            local MIN, MAX = 5, 25
            local value = math.clamp(tonumber(savedOr("speed", 25)) or 25, MIN, MAX)
            local function set(n, t)
                n = math.clamp(math.floor(n + 0.5), MIN, MAX)
                local a = (n - MIN) / (MAX - MIN)
                -- a tick for every number the knob lands on, climbing in
                -- pitch with the speed: deep at 5, bright at 25
                local changed = n ~= value
                if changed then sfx("tick", 0.55 * (2.2 / 0.55) ^ a) end   -- 0.55x to 2.2x, two octaves, even steps
                value = n
                -- the engine tops out at 23 (25 on the dial is 23): a cap, so
                -- 24 no longer ran faster than 25 did
                farmSpeed = math.min(n, 23)
                ONX.farmDial = n                           -- what the dial says, for the reports
                -- Live: the trip already under way was timed at the old
                -- speed, so drop it and let the farm's next tick set off
                -- again from right here at the new one -- otherwise the
                -- change only showed from the next coin.
                if changed and farmTween then
                    pcall(function() farmTween:Cancel() end)
                    farmTween, farmCoin = nil, nil
                end
                tween(fill, t or 0.08, { Size = UDim2.fromScale(a, 1) })
                tween(knob, t or 0.08, { Position = UDim2.fromScale(a, 0.5) })
                valueO.set(n .. " M/S", t == 0)
            end
            set(value, 0)
            local dragging = false
            local function fromX(x)
                set(MIN + math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1) * (MAX - MIN))
            end
            rail.InputBegan:Connect(function(input)
                local t = input.UserInputType
                if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                    dragging = true
                    tween(knob, 0.12, { Size = UDim2.fromOffset(17, 17) })
                    fromX(input.Position.X)
                end
            end)
            conns[#conns + 1] = UIS.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch) then fromX(input.Position.X) end
            end)
            conns[#conns + 1] = UIS.InputEnded:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch) then
                    dragging = false
                    tween(knob, 0.15, { Size = UDim2.fromOffset(14, 14) })
                    remember("speed", value)
                end
            end)
        end

        --// WHILE FARMING -----------------------------------------------------
        section("While farming")
        local toggles = {}
        -- three across, like the skin grid
        local optGrid = make("Frame", {
            BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = nextOrder(), Parent = current,
        })
        pad(optGrid, 1, 1, 1, 1)
        make("UIGridLayout", {
            CellPadding = UDim2.fromOffset(8, 8), CellSize = UDim2.new(1 / 3, -6, 0, 118),
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder, Parent = optGrid,
        })
        ONX.perf.el.masterFarm = toggle({
            key = "perf", short = "Performance", icon = ICON.monitor, title = "Performance mode", parent = optGrid,
            desc = "Strips textures and effects for more frames. It all comes back when off.",
            callback = function(on) ONX.perf.setAll(on) end,
        })
        toggles[#toggles + 1] = ONX.perf.el.masterFarm
        -- Anti-AFK isn't a switch any more: it's simply always on
        antiAfkEnabled = true
        startAntiAfk()
        toggles[#toggles + 1] = toggle({
            key = "autoReset", when = "WHEN BAG IS FULL", short = "Auto reset", icon = ICON.power, title = "Reset when the bag is full", default = true, parent = optGrid,
            desc = "Banks your coins by resetting as soon as the bag fills up.",
            callback = function(on)
                autoResetOnFull = on
                if on then startAutoReset() else stopAutoReset() end
            end,
        })
        toggles[#toggles + 1] = toggle({
            key = "hop", when = "WHEN EMPTY", short = "Server hop", icon = ICON.tabPlayer, title = "Hop when the server empties", default = true, parent = optGrid,
            desc = "Moves to a busier server when this one can't start rounds.",
            callback = function(on) ONX.farmHopOn = on end,
        })
        -- From the saved value, not a constant: the restore pass only replays
        -- switches that are ON, so a saved OFF would otherwise never reach here.
        ONX.farmHopOn = toggles[#toggles].Value
        toggles[#toggles + 1] = toggle({
            key = "fling", when = "WHEN BAG IS FULL", short = "Fling murderer", icon = ICON.tabFling, title = "Fling the murderer when done", parent = optGrid,
            desc = "Once your bag is full or the coins run out. As the murderer, you reset instead.",
            callback = function(on)
                ONX.flingWhenDone = on
                if on then ONX.flingDoneFired = false end
            end,
        })
        toggles[#toggles + 1] = toggle({
            key = "shoot", when = "WHEN BAG IS FULL", short = "Shoot murderer", icon = ICON.tabCrosshair,
            title = "Shoot the murderer when done", parent = optGrid,
            desc = "Once your bag is full, shoots the murderer if you hold the gun. With Fling on too, the shot wins.",
            callback = function(on)
                ONX.shootWhenFull = on
                if on then ONX.flingDoneFired = false end
            end,
        })
        toggles[#toggles + 1] = toggle({
            key = "killAll", when = "WHEN BAG IS FULL", short = "Kill all", icon = ICON.sword, title = "Kill all when the bag is full", parent = optGrid,
            desc = "Stabs everyone once your bag fills. Only as the murderer.",
            callback = function(on)
                ONX.killWhenFull = on
                if on then ONX.killFired = false end
            end,
        })

        -- Rows of three instead of the grid, so a row that comes up short
        -- (seven tiles: one left over) sits centred under the others
        do
            local tiles = {}
            for _, c in ipairs(optGrid:GetChildren()) do
                if c:IsA("GuiButton") then tiles[#tiles + 1] = c end
            end
            table.sort(tiles, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
            local gl = optGrid:FindFirstChildOfClass("UIGridLayout")
            if gl then gl:Destroy() end
            make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = optGrid })
            local rowF
            for i, t in ipairs(tiles) do
                if (i - 1) % 3 == 0 then
                    rowF = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 118), LayoutOrder = i, Parent = optGrid })
                    hlist(rowF, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
                end
                t.Size = UDim2.new(1 / 3, -16 / 3, 1, 0)
                t.Parent = rowF
            end
        end

        --// MAP VOTE ----------------------------------------------------------
        -- MM2 counts a vote when your character steps on a lobby pad, and a
        -- new character counts again -- so a reset is another vote. This puts
        -- you on the pad of whichever offered map ranks highest in your list,
        -- and (if you want) resets and votes again until the vote closes.
        section("Map vote")
        do
            -- biggest map first, smallest last: the default order, measured in
            -- Studio (studio/maps.json) -- the footprint of the area people play
            -- in (the box around its coin areas), not the map model's own box:
            -- Factory's skyline makes that 1222 x 1490 for a 146 x 184 map
            -- (the third field: the map's picture on the MM2 wiki)
            local MAPS = {
                { "BioLab", "Bio Lab", "f/ff/BiolabSq.png" },                              -- 196 x 280
                { "MilBase", "Mil Base", "e/ea/Mil_Base_MM2_Preview.jpg" },                -- 195 x 280
                { "ResearchFacility", "Research Facility", "2/20/Research.png" },          -- 151 x 239
                { "Mansion2", "Mansion 2", "b/bd/Mansion_2_MM2_Preview.jpg" },             -- 179 x 155
                { "Factory", "Factory", "2/24/Factory_MM2_Preview.jpg" },                  -- 146 x 184
                { "PoliceStation", "Police Station", "6/60/PoliceStationIcon.png" },       -- 143 x 181
                { "Workplace", "Workplace", "3/3d/Workplace_MM2_Preview.jpg" },            -- 144 x 145
                { "Office3", "Office 3", "d/d6/Office3Icon.png" },                         -- 129 x 157
                { "House2", "House 2", "d/d9/House_2_MM2_Preview.jpg" },                   -- 106 x 177
                { "Hotel", "Hotel", "2/24/HotelSq.png" },                                  -- 238 x 77
                { "Bank2", "Bank 2", "3/32/Bank_2_MM2_Preview.jpg" },                      -- 104 x 126
                { "Hospital3", "Hospital 3", "8/8b/Hospital3Icon.png" },                   --  99 x 115
            }
            -- Map pictures: fetched once from the wiki (up to 1200px wide, in its
            -- own format -- the default is WebP, which Roblox can't show),
            -- kept in OnyxV2/maps and loaded from there ever after
            local picOf = {}
            for _, m in ipairs(MAPS) do picOf[(m[1]:lower())] = m[3] end
            -- width and file tag: 1200px for the card's picture ("_hd")
            local function mapPicture(key, img, width, tag, show)
                local path = picOf[key]
                if not (path and writefile and isfile and getcustomasset) then return end
                local ext = path:match("%.(%w+)$") or "png"
                local file = "OnyxV2/maps/" .. key .. "_" .. tag .. "." .. ext
                task.spawn(function()
                    if not isfile(file) then
                        local http = (syn and syn.request) or request or http_request
                        if not http then return end
                        local ok, res = pcall(http, { Url = "https://static.wikia.nocookie.net/murder-mystery-2/images/" .. path
                                .. "/revision/latest/scale-to-width-down/" .. width .. "?format=original",
                            Method = "GET", Headers = { ["User-Agent"] = "Mozilla/5.0", ["Referer"] = "https://murder-mystery-2.fandom.com/",
                                ["Accept"] = "image/png,image/jpeg" } })
                        if not (ok and res and res.StatusCode == 200 and #res.Body > 200) then return end
                        pcall(makefolder, "OnyxV2/maps")
                        pcall(writefile, file, res.Body)
                    end
                    local okA, id = pcall(getcustomasset, file)
                    if okA and id and img.Parent then
                        img.Image = id
                        tween(img, 0.5, { ImageTransparency = show or 0 }, EASE.Quad, DIR.Out)     -- fades in as it arrives
                    end
                end)
            end
            -- pads read "House 2", the game's own key is "House2": compared without spaces or case
            local function norm(str) return (tostring(str or ""):lower():gsub("[^%w]", "")) end
            local nameOf = {}
            for _, m in ipairs(MAPS) do nameOf[norm(m[1])] = m[2] end
            -- your saved order first, then any map it doesn't have yet
            local order, seen = {}, {}
            -- (an order saved before the measured default is dropped once)
            local savedOrder = saved.mapOrderV == 3 and type(saved.mapOrder) == "table" and saved.mapOrder or {}
            if saved.mapOrderV ~= 3 then remember("mapOrderV", 3) end
            for _, k in ipairs(savedOrder) do
                k = norm(k)
                if nameOf[k] and not seen[k] then order[#order + 1], seen[k] = k, true end
            end
            for _, m in ipairs(MAPS) do
                local k = norm(m[1])
                if not seen[k] then order[#order + 1], seen[k] = k, true end
            end

            -- The switch and the map list share a holder: the list opens out
            -- under the switch while it's on and folds away when it's off
            -- (the gap between them folds with it, so nothing jumps at the end)
            local holderV = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder(), Parent = current })
            local holderLayout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
                HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = holderV })
            local ROW, GAP = 56, 6
            local LIST_H = #order * (ROW + GAP) - GAP
            -- the list unfolds as its own card: 14px in on every side
            local PICK_H = 1 + 14 + 14 + 10 + LIST_H + 14 + 1
            local picker = make("CanvasGroup", { BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, PICK_H),
                LayoutOrder = 1e6, Parent = holderV })      -- always under the switch
            local setPicker
            local outer = current
            current = holderV
            -- one switch: vote for your top map, then keep voting with fresh
            -- characters until the vote closes
            local voteEl = toggle({
                key = "autoVote", title = "Win the map vote", icon = ICON.check,
                desc = "While farming, votes for your highest map below, then keeps voting until the vote closes.",
                callback = function(on) if setPicker then setPicker(on) end end,
            })
            current = outer
            local cascade
            function setPicker(on, instant)
                if on and not instant and cascade then cascade() end
                local info = instant and TweenInfo.new(0) or (on and TweenInfo.new(0.45, EASE.Quint, DIR.Out)
                    or TweenInfo.new(0.38, EASE.Quart, DIR.InOut))
                TweenService:Create(picker, info, { Size = UDim2.new(1, -2, 0, on and PICK_H or 0) }):Play()
                TweenService:Create(holderLayout, info, { Padding = UDim.new(0, on and 8 or 0) }):Play()
                TweenService:Create(picker, instant and TweenInfo.new(0) or (on and TweenInfo.new(0.34, EASE.Quad, DIR.Out, 0, false, 0.08)
                    or TweenInfo.new(0.22, EASE.Quad, DIR.In)), { GroupTransparency = on and 0 or 1 }):Play()
            end

            local pickCard = make("Frame", { BackgroundColor3 = C.tile, BorderSizePixel = 0, Position = UDim2.fromOffset(1, 1),
                Size = UDim2.new(1, -2, 0, PICK_H - 2), Parent = picker })
            corner(pickCard, 12)
            stroke(pickCard, C.border)
            text({ Text = "Drag the maps into your order. #1 wins whenever it's one of the three on the vote.",
                   TextSize = 12, TextColor3 = C.subtle, TextTruncate = Enum.TextTruncate.AtEnd,
                   Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0, 14), Parent = pickCard })
            -- the list: rows placed by hand (not a layout), so a dragged row can
            -- follow the pointer while the rest glide out of its way
            local list = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 38),
                Size = UDim2.new(1, -28, 0, LIST_H), Parent = pickCard })
            local rows, drag = {}, nil
            local function slotY(i) return (i - 1) * (ROW + GAP) end
            local function relayoutRows(skip, instant, settle)
                for i, k in ipairs(order) do
                    local r = rows[k]
                    local txt = "#" .. i
                    if r.rank.Text ~= txt then
                        r.rank.Text = txt
                        -- a new place: the number pops
                        if not instant and r.rankScale then
                            r.rankScale.Scale = 1.35
                            TweenService:Create(r.rankScale, TweenInfo.new(0.4, EASE.Back, DIR.Out), { Scale = 1 }):Play()
                        end
                    end
                    if r ~= skip then
                        if instant then r.frame.Position = UDim2.fromOffset(0, slotY(i))
                        elseif settle == r then
                            -- the card you let go of settles in with a little spring
                            TweenService:Create(r.frame, TweenInfo.new(0.45, EASE.Back, DIR.Out),
                                { Position = UDim2.fromOffset(0, slotY(i)) }):Play()
                        else tween(r.frame, 0.3, { Position = UDim2.fromOffset(0, slotY(i)) }, EASE.Quint, DIR.Out) end
                    end
                end
            end
            for _, k in ipairs(order) do
                local f = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.field, BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, ROW), Parent = list })
                corner(f, 10)
                local st = stroke(f, C.border)
                -- the map itself fills the card, under a dark fade from the left
                -- so the rank and name read clearly over it. Picture and fade sit
                -- in a rounded clip (a CanvasGroup keeps to its corners; a plain
                -- clip is square), so the hover zoom never shows past them.
                local artClip = make("CanvasGroup", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = f })
                corner(artClip, 10)
                local pic = image({ Image = "", ImageTransparency = 1, ScaleType = Enum.ScaleType.Crop,
                    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromScale(1, 1), Parent = artClip })
                local picScale = make("UIScale", { Parent = pic })      -- the slow zoom on hover
                -- the whole card is the picture; the words carry a soft dark
                -- outline so they read on bright maps too
                local shade = make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = artClip })
                mapPicture(k, pic, 1200, "hd")
                local fScale = make("UIScale", { Parent = f })
                local rank = text({ Text = "", FontFace = C.STAT_FONT, TextSize = 12, TextColor3 = WHITE,
                    TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.45,
                    Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 34, 1, 0), Parent = f })
                make("UIGradient", { Rotation = 90, Color = C.STAT_SILVER, Parent = rank })
                local rankScale = make("UIScale", { Parent = rank })
                local NAME_X = 52
                local nameL = text({ Text = nameOf[k], FontFace = geist(FW.SemiBold), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd,
                    TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.45,
                    Position = UDim2.fromOffset(NAME_X, 0), Size = UDim2.new(1, -190, 1, 0), Parent = f })
                -- "ON THE VOTE" while it's one of the three on the pads
                local live = make("TextLabel", { BackgroundTransparency = 1, Text = "ON THE VOTE", FontFace = geist(FW.ExtraBold),
                    TextSize = 10, TextColor3 = C.greenText, TextTransparency = 1, AnchorPoint = Vector2.new(1, 0),
                    Position = UDim2.new(1, -40, 0, 0), Size = UDim2.new(0, 120, 1, 0),
                    TextXAlignment = Enum.TextXAlignment.Right, Parent = f })
                -- the grip: three short lines, the row's "you can drag me"
                local grip = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(14, 10), Parent = f })
                local gripBars = {}
                for j = 0, 2 do
                    gripBars[#gripBars + 1] = make("Frame", { BackgroundColor3 = C.subtle, BorderSizePixel = 0,
                        Position = UDim2.fromOffset(0, j * 4), Size = UDim2.new(1, 0, 0, 2), Parent = grip })
                end
                local r = { key = k, frame = f, stroke = st, rank = rank, rankScale = rankScale, live = live,
                    scale = fScale, onVote = false }
                rows[k] = r
                local over = false
                -- Hovered: the picture slowly zooms in, the fade lifts a little,
                -- the name slides over and the grip lights up. Held: brighter
                -- still, with a white edge.
                local function paint(t)
                    local held = drag and drag.row == r
                    local hot = over or held
                    tween(f, t or 0.2, { BackgroundColor3 = hot and C.tileHover or C.field })
                    tween(st, t or 0.2, { Color = held and C.borderHi:Lerp(WHITE, 0.5)
                        or (r.onVote and C.greenEdge:Lerp(C.border, 0.3)) or (hot and C.borderHi or C.border) })
                    for _, bar in ipairs(gripBars) do tween(bar, t or 0.2, { BackgroundColor3 = hot and C.text or C.subtle }) end
                    tween(picScale, hot and 0.9 or 0.6, { Scale = hot and 1.08 or 1 }, EASE.Quint, DIR.Out)
                    tween(nameL, 0.35, { Position = UDim2.fromOffset(hot and NAME_X + 4 or NAME_X, 0) }, EASE.Quint, DIR.Out)
                end
                r.paint = paint
                f.MouseEnter:Connect(function() over = true; paint(0.15) end)
                f.MouseLeave:Connect(function() over = false; paint(0.2) end)
                f.MouseButton1Down:Connect(function()
                    drag = { row = r, fromMouse = UIS:GetMouseLocation().Y, fromY = f.Position.Y.Offset }
                    f.ZIndex = 5
                    -- (no growing: a bigger card ran past the list's own card --
                    -- the white edge and the lighter fade say it's held)
                    paint(0.15)
                end)
            end
            relayoutRows(nil, true)
            -- each card rises into its slot a beat after the one above it
            function cascade()
                for i, kk in ipairs(order) do
                    local fr = rows[kk].frame
                    fr.Position = UDim2.fromOffset(0, slotY(i) + 14)
                    task.delay(0.06 + i * 0.035, function()
                        if fr.Parent and not drag then
                            tween(fr, 0.5, { Position = UDim2.fromOffset(0, slotY(i)) }, EASE.Quint, DIR.Out)
                        end
                    end)
                end
            end
            setPicker(voteEl.Value, true)
            conns[#conns + 1] = UIS.InputChanged:Connect(function(input)
                if not drag or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
                local r = drag.row
                local y = drag.fromY + (UIS:GetMouseLocation().Y - drag.fromMouse) / unscale()
                y = math.clamp(y, 0, slotY(#order))
                r.frame.Position = UDim2.fromOffset(0, y)
                local want = math.clamp(math.floor(y / (ROW + GAP) + 0.5) + 1, 1, #order)
                local now = table.find(order, r.key)
                if now and want ~= now then
                    table.remove(order, now)
                    table.insert(order, want, r.key)
                    sfx("tick", 1.2)
                    relayoutRows(r)
                end
            end)
            conns[#conns + 1] = UIS.InputEnded:Connect(function(input)
                if not drag or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
                local r = drag.row
                drag = nil
                r.frame.ZIndex = 1
                relayoutRows(nil, false, r)
                r.paint(0.2)
                remember("mapOrder", order)
            end)

            -- the vote itself
            local function votePads()
                local lobby = Workspace:FindFirstChild("RegularLobby")
                local dets = lobby and lobby:FindFirstChild("VotePads")
                if not dets then return nil end
                local pads = {}
                for i = 1, 3 do
                    local m = lobby:FindFirstChild("VotePad" .. i)
                    local info = m and m:FindFirstChild("VoteInfoGui")
                    local det = dets:FindFirstChild("Detector" .. i)
                    if not (info and info.Enabled and det) then return nil end
                    local nm = info:FindFirstChild("MapName", true)
                    local vt = info:FindFirstChild("Votes", true)          -- "Votes: 3"
                    pads[i] = { key = nm and norm(nm.Text) or "", name = nm and nm.Text or "?", det = det,
                                votes = vt and tonumber(vt.Text:match("%d+")) or 0 }
                end
                return pads
            end
            -- The server counts who is AT a pad (it ignores touches reported
            -- from far away, and leaving takes the vote back), so you have to be
            -- there -- but hidden: parked just under the pad, inside the floor,
            -- anchored, with the top of you reaching into its detector. When the
            -- vote closes you go back exactly where you were.
            local touch = firetouchinterest
            local homeCF, homeChar = nil, nil
            -- standing on the pad: dropped onto its middle, feet on the floor
            local function onPad(root, det)
                local bottom = det.Position.Y - det.Size.Y / 2
                root.AssemblyLinearVelocity = Vector3.zero
                root.CFrame = CFrame.new(det.Position.X, bottom + 3, det.Position.Z)
                if touch then pcall(touch, root, det, 0) end
            end
            local function goHome()
                local char = homeChar
                local root = char and char.Parent and char:FindFirstChild("HumanoidRootPart")
                if root then
                    root.Anchored = false
                    if homeCF then root.CFrame = homeCF end
                end
                homeCF, homeChar = nil, nil
            end
            task.spawn(function()
                local lastStep, announced, votedChar, votedKey = 0, nil, nil, nil
                -- the vote we're in: our pick, the pads as last seen (their
                -- counts), and a token so an old result can't land on a new vote
                local pick, lastPads, voteTok = nil, nil, 0
                local function mapPic(key)
                    local p = picOf[key]
                    return p and ("https://static.wikia.nocookie.net/murder-mystery-2/images/" .. p) or nil
                end
                -- That vote closed: which map won? The one that loads next is
                -- one of the three (its model's name is the pad's key), so wait
                -- for it; if it never shows, the one with the most votes. Then
                -- the island says so, and Discord.
                local function resolve(pads, ours, tok)
                    local byKey = {}
                    for _, p in ipairs(pads) do byKey[p.key] = p end
                    local win
                    local t0 = os.clock()
                    while not win and os.clock() - t0 < 12 do
                        if voteTok ~= tok or votePads() then return end     -- a new vote, or not closed after all
                        for _, v in ipairs(Workspace:GetChildren()) do
                            local p = byKey[norm(v.Name)]
                            if p and (v:FindFirstChild("CoinContainer") or v:FindFirstChild("CoinAreas")) then win = p; break end
                        end
                        if not win then task.wait(0.25) end
                    end
                    if not win then
                        for _, p in ipairs(pads) do if not win or p.votes > win.votes then win = p end end
                    end
                    local mine = win.key == ours.key
                    if C.island then
                        C.island.result(("%s won with %d %s%s"):format(win.name, win.votes, win.votes == 1 and "vote" or "votes",
                            mine and "!" or ""), mine and C.green or C.red, not mine and ICON.x or nil)
                    end
                    if hook.on then pcall(post, ONX.voteEmbed(ours, pads, win, mapPic(win.key))) end
                end
                -- one pass of the watcher; run under pcall, so a single error
                -- (a pad mid-rebuild, a character half gone) can't end it
                local function step()
                    local pads = votePads()
                    if pads and announced then lastPads = pads end
                    -- the list's live tags
                    local on = {}
                    if pads then for _, p in ipairs(pads) do on[p.key] = true end end
                    for k, r in pairs(rows) do
                        if r.onVote ~= (on[k] == true) then
                            r.onVote = on[k] == true
                            if r.pulse then r.pulse:Cancel(); r.pulse = nil end
                            if r.onVote then
                                -- fades up, then breathes softly while it's on the vote
                                r.live.TextTransparency = 1
                                tween(r.live, 0.3, { TextTransparency = 0 }).Completed:Connect(function()
                                    if r.onVote and not r.pulse then
                                        r.pulse = TweenService:Create(r.live, TweenInfo.new(0.9, EASE.Sine, DIR.InOut, -1, true),
                                            { TextTransparency = 0.45 })
                                        r.pulse:Play()
                                    end
                                end)
                            else
                                tween(r.live, 0.25, { TextTransparency = 1 })
                            end
                            r.paint(0.25)
                        end
                    end
                    -- a vote closed: the next one starts from scratch, even for
                    -- the same character and the same map
                    if not pads then
                        if announced and lastPads and pick then task.spawn(pcall, resolve, lastPads, pick, voteTok) end
                        announced, votedChar, votedKey = nil, nil, nil
                        pick, lastPads = nil, nil
                        if homeChar then goHome() end
                    end
                    -- Only while the farm runs, like everything on this tab: the
                    -- switch arms it, Start farming sets it going. And never
                    -- mid-round: only while you're actually in the lobby, near
                    -- the pads -- a round's map is far away. (MM2's
                    -- Inventory-button test read "not in the lobby" all through
                    -- the vote, so with the farm on it never voted.)
                    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    local inLobby = myRoot and pads and (myRoot.Position - pads[2].det.Position).Magnitude < 300
                    if pads and voteEl.Value and farmRunning and inLobby then
                        local best
                        for _, k in ipairs(order) do
                            for _, p in ipairs(pads) do if p.key == k then best = p; break end end
                            if best then break end
                        end
                        best = best or pads[1]
                        if announced ~= best.key then
                            -- a vote starts for us: the island shows it (the light
                            -- running along its bar) until the result, and Discord
                            announced, pick, lastPads = best.key, best, pads
                            voteTok += 1
                            if C.island then C.island.task({ title = "Voting for " .. best.name, color = C.amber }) end
                            if hook.on then
                                task.spawn(pcall, post, ONX.voteEmbed(best, pads, nil, mapPic(best.key)))
                            end
                        end
                        local char = LocalPlayer.Character
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        -- straight off the character: Humanoid.RootPart reads nil on
                        -- MM2's characters, and every vote was skipped right here
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        if root and hum and hum.Health > 0 then
                            if votedChar ~= char or votedKey ~= best.key then
                                -- remember where this character stood (the first
                                -- time only), then under the pad
                                if homeChar ~= char then
                                    homeChar, homeCF = char, (homeCF and homeChar == char) and homeCF or root.CFrame
                                end
                                onPad(root, best.det)
                                votedChar, votedKey = char, best.key
                                lastStep = os.clock()
                            elseif os.clock() - lastStep > 0.25 then
                                -- counted: a fresh character votes once more -- quietly
                                -- (the death sound is muted for these resets only)
                                local died = root:FindFirstChild("Died")
                                if died and died:IsA("Sound") then died.Volume = 0 end
                                hum.Health = 0
                                lastStep = os.clock() + 5
                            end
                        end
                    end
                end
                -- quick while a vote is open (a new character votes the moment
                -- it can), easy the rest of the time
                while gui.Parent do
                    pcall(step)
                    task.wait(votePads() and 0.05 or 0.4)
                end
            end)
        end

        --// DISCORD -----------------------------------------------------------
        section("Discord")
        do
            -- the Skin Changer's top row again: the link in a field like its
            -- search box (Discord's mark where the magnifier is), Send test
            -- where Spawn all sits -- and the test's result shows on it
            local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, 40),
                LayoutOrder = nextOrder(), Parent = current })
            -- Send test is only as wide as it needs to be; the link gets the rest
            local TEST_W = 140
            local field = make("Frame", { BackgroundColor3 = C.field, BorderSizePixel = 0, Position = UDim2.fromOffset(1, 1),
                Size = UDim2.new(1, -(TEST_W + 10), 0, 38), Parent = row })
            corner(field, 11)
            local fst = stroke(field, C.border)
            local fRing = UI.hoverRing(field, 11, 0)
            local dIcon = image({ Image = ICON.discord, ImageRectOffset = UI.DISCORD_CELL.offset, ImageRectSize = UI.DISCORD_CELL.size,
                ImageColor3 = C.subtle, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0),
                Size = UDim2.fromOffset(16, 16), Parent = field })
            local box = make("TextBox", {
                BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -54, 1, 0),
                FontFace = geist(FW.Medium), TextSize = 12, TextColor3 = C.text, PlaceholderColor3 = C.subtle,
                PlaceholderText = "Paste a Discord webhook link", Text = "", ClearTextOnFocus = false,
                TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = field,
            })
            -- Send test, in the bar's style -- and alive. Under the pointer a
            -- faint blurple wash comes up and the arrow lifts, hopping now and
            -- then; a press squeezes the whole button and it springs back. The
            -- arrow stays put on the left and the words have their own space
            -- beside it, so new words never shove anything along. The button
            -- takes the colour of what's happening: amber with a light running
            -- across while sending, green for Sent, red for a failure.
            local tBtn = make("TextButton", {
                Text = "", AutoButtonColor = false, BackgroundColor3 = C.field, BorderSizePixel = 0,
                -- (centred, so the press squeezes it about its middle)
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -1 - TEST_W / 2, 0, 20),
                Size = UDim2.fromOffset(TEST_W, 38), Parent = row,
            })
            corner(tBtn, 11)
            local tst = stroke(tBtn, C.border)
            local tRing = UI.hoverRing(tBtn, 11, 0)
            local fx = { mode = "rest", over = false, scale = make("UIScale", { Parent = tBtn }) }
            fx.wash = make("Frame", { BackgroundColor3 = C.blurple, BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.fromScale(1, 1), Parent = tBtn })
            corner(fx.wash, 11)
            make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.6, 0), Parent = fx.wash })
            -- sending: a soft light running across, over and over
            fx.sweep = make("Frame", { BackgroundColor3 = C.amber, BorderSizePixel = 0, Visible = false,
                Size = UDim2.fromScale(1, 1), Parent = tBtn })
            corner(fx.sweep, 11)
            fx.sweepGrad = make("UIGradient", { Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 1), NumberSequenceKeypoint.new(0.5, 0.86),
                NumberSequenceKeypoint.new(0.7, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = fx.sweep })
            fx.sweepRun = TweenService:Create(fx.sweepGrad, TweenInfo.new(1.1, EASE.Sine, DIR.InOut, -1), { Offset = Vector2.new(1, 0) })
            local tInner = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = tBtn })
            -- the icon moves inside its own little box, pinned on the left: the
            -- arrow can fly up out of it while sending
            local tIconBox = make("Frame", { BackgroundTransparency = 1, ClipsDescendants = true, AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 13, 0.5, 0), Size = UDim2.fromOffset(18, 18), ZIndex = 2, Parent = tInner })
            local ICON_HOME = UDim2.fromScale(0.5, 0.5)
            local tIcon = image({ Image = ICON.arrowUp, ImageColor3 = C.blurpleText or C.muted, AnchorPoint = Vector2.new(0.5, 0.5),
                Position = ICON_HOME, Size = UDim2.fromOffset(14, 14), ZIndex = 2, Parent = tIconBox })
            local tIconScale = make("UIScale", { Parent = tIcon })
            -- the result, the way Spawn all shows its own: a bold check (or X)
            -- in the middle of the button
            fx.mark = image({ Image = ICON.check, ImageColor3 = C.greenText, ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), ZIndex = 3, Parent = tInner })
            C.bolden(fx.mark, 0.6)
            -- the words: centred on the button itself (their space keeps the
            -- icon's width clear on both sides; "Sending", the longest, is
            -- 58px of the 72)
            fx.words = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -68, 1, 0),
                ZIndex = 2, Parent = tInner })
            local tLabel = text({ Text = "Send test", FontFace = geist(FW.SemiBold), TextSize = 13, TextColor3 = C.muted,
                TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 16),
                ZIndex = 2, Parent = fx.words })
            fx.home = tLabel.Position
            -- new words: the old ones lift and fade, the new rise in from below
            function fx.say(str)
                fx.sayTok = (fx.sayTok or 0) + 1
                local mine = fx.sayTok
                tween(tLabel, 0.12, { TextTransparency = 1, Position = fx.home + UDim2.fromOffset(0, -5) }, EASE.Quad, DIR.In)
                    .Completed:Connect(function()
                        if fx.sayTok ~= mine then return end
                        tLabel.Text = str
                        tLabel.Position = fx.home + UDim2.fromOffset(0, 7)
                        tween(tLabel, 0.42, { TextTransparency = 0, Position = fx.home })
                    end)
            end
            -- the colours for what's happening, and whether the pointer is on it
            fx.TINT = { sending = C.amber, ok = C.green, bad = C.red }
            fx.INK = { sending = C.amberText, ok = C.greenText, bad = C.red:Lerp(WHITE, 0.3) }
            function fx.paint(t)
                local tint = fx.TINT[fx.mode]
                tween(tLabel, t, { TextColor3 = fx.INK[fx.mode] or fx.over and C.text or C.muted })
                tween(tst, t, { Color = tint and tint:Lerp(C.border, 0.5) or fx.over and C.borderHi or C.border })
                tween(fx.wash, t, { BackgroundColor3 = tint or C.blurple, BackgroundTransparency = (tint or fx.over) and 0.9 or 1 })
            end
            -- the arrow under the pointer: brighter, a touch bigger, lifted --
            -- then a small hop every so often, as if it wants to go
            function fx.float(on)
                if fx.bob then fx.bob:Cancel(); fx.bob = nil end
                if not on then
                    tween(tIcon, 0.25, { ImageColor3 = C.blurpleText or C.muted })
                    TweenService:Create(tIconScale, TweenInfo.new(0.4, EASE.Back, DIR.Out), { Scale = 1 }):Play()
                    TweenService:Create(tIcon, TweenInfo.new(0.45, EASE.Back, DIR.Out), { Position = ICON_HOME }):Play()
                    return
                end
                tween(tIcon, 0.2, { ImageColor3 = (C.blurpleText or C.muted):Lerp(WHITE, 0.45) })
                TweenService:Create(tIconScale, TweenInfo.new(0.45, EASE.Back, DIR.Out), { Scale = 1.12 }):Play()
                local lift = TweenService:Create(tIcon, TweenInfo.new(0.4, EASE.Back, DIR.Out), { Position = ICON_HOME + UDim2.fromOffset(0, -2) })
                fx.bob = lift
                lift:Play()
                lift.Completed:Connect(function(state)
                    if fx.bob ~= lift or state ~= Enum.PlaybackState.Completed then return end
                    fx.bob = TweenService:Create(tIcon, TweenInfo.new(0.22, EASE.Quad, DIR.Out, -1, true, 0.9),
                        { Position = ICON_HOME + UDim2.fromOffset(0, -5) })
                    fx.bob:Play()
                end)
            end
            -- no: the X shakes its head once, smoothly dying out
            function fx.shake()
                if fx.shaking then fx.shaking:Disconnect() end
                local t0 = os.clock()
                fx.shaking = RunService.RenderStepped:Connect(function()
                    local t = os.clock() - t0
                    if t > 0.5 or not tInner.Parent then
                        fx.shaking:Disconnect()
                        fx.shaking = nil
                        tInner.Position = UDim2.new()
                        return
                    end
                    tInner.Position = UDim2.fromOffset(math.floor(5 * math.exp(-t * 7) * math.sin(t * 42) + 0.5), 0)
                end)
            end
            function fx.release()
                TweenService:Create(fx.scale, TweenInfo.new(0.5, EASE.Back, DIR.Out), { Scale = 1 }):Play()
            end
            tBtn.MouseEnter:Connect(function()
                sfx("hover")
                tRing(true)
                fx.over = true
                fx.paint(0.25)
                if fx.mode == "rest" then fx.float(true) end
            end)
            tBtn.MouseLeave:Connect(function()
                tRing(false)
                fx.over = false
                fx.paint(0.25)
                if fx.mode == "rest" then fx.float(false) end
                if fx.scale.Scale < 1 then fx.release() end
            end)
            tBtn.MouseButton1Down:Connect(function()
                C.ripple(tBtn, 11)
                tween(fx.scale, 0.1, { Scale = 0.95 }, EASE.Quad)
            end)
            tBtn.MouseButton1Up:Connect(fx.release)
            local test = { button = tBtn, label = tLabel }

            -- Send test tells you how it went, on itself: Sending in amber,
            -- then the result the way Spawn all shows its own -- the words and
            -- the arrow fade, and a bold check (Sent) or X (Failed / No link)
            -- springs in, centred, turning into place -- then back to Send test.
            -- The arrow while sending crouches, then keeps flying up out of its
            -- box and rising back in from below; back to Send test it pops in.
            local resultTok, tLoop = 0, nil
            local function popIcon(icon, color)
                if tLoop then tLoop:Cancel(); tLoop = nil end      -- a flight still under way
                if fx.bob then fx.bob:Cancel(); fx.bob = nil end
                tIcon.Image = icon
                tIcon.ImageColor3 = color
                tIcon.Position = ICON_HOME
                tIcon.ImageTransparency = 1
                tIconScale.Scale = 0.4
                tween(tIcon, 0.2, { ImageTransparency = 0 }, EASE.Quad, DIR.Out)
                TweenService:Create(tIconScale, TweenInfo.new(0.5, EASE.Back, DIR.Out), { Scale = 1 }):Play()
            end
            local function showOnTest(word, icon, color, hold)
                resultTok += 1
                local mine = resultTok
                if hold == nil then
                    -- sending: a crouch, then up and out, in again from below,
                    -- until it's answered
                    fx.say(word)
                    fx.mode = "sending"
                    fx.paint(0.25)
                    if fx.bob then fx.bob:Cancel(); fx.bob = nil end
                    tIcon.Image = icon
                    tween(tIcon, 0.2, { ImageColor3 = color })
                    fx.sweepGrad.Offset = Vector2.new(-1, 0)
                    fx.sweep.BackgroundTransparency = 1
                    fx.sweep.Visible = true
                    tween(fx.sweep, 0.3, { BackgroundTransparency = 0 })
                    fx.sweepRun:Play()
                    task.spawn(function()
                        local crouch = TweenService:Create(tIcon, TweenInfo.new(0.12, EASE.Quad, DIR.Out),
                            { Position = ICON_HOME + UDim2.fromOffset(0, 2) })
                        tLoop = crouch
                        TweenService:Create(tIconScale, TweenInfo.new(0.12, EASE.Quad, DIR.Out), { Scale = 0.82 }):Play()
                        crouch:Play()
                        crouch.Completed:Wait()
                        while resultTok == mine and tIcon.Parent do
                            TweenService:Create(tIconScale, TweenInfo.new(0.25, EASE.Back, DIR.Out), { Scale = 1 }):Play()
                            local up = TweenService:Create(tIcon, TweenInfo.new(0.26, EASE.Quad, DIR.In),
                                { Position = ICON_HOME + UDim2.fromOffset(0, -15), ImageTransparency = 1 })
                            tLoop = up
                            up:Play()
                            up.Completed:Wait()
                            if resultTok ~= mine then return end
                            tIcon.Position = ICON_HOME + UDim2.fromOffset(0, 15)
                            local back = TweenService:Create(tIcon, TweenInfo.new(0.34, EASE.Quint, DIR.Out),
                                { Position = ICON_HOME, ImageTransparency = 0 })
                            tLoop = back
                            back:Play()
                            back.Completed:Wait()
                            task.wait(0.08)
                        end
                    end)
                    return
                end
                fx.mode = icon == ICON.check and "ok" or "bad"
                fx.paint(0.2)
                if fx.sweep.Visible then
                    tween(fx.sweep, 0.25, { BackgroundTransparency = 1 }).Completed:Connect(function()
                        if fx.mode ~= "sending" then fx.sweepRun:Cancel(); fx.sweep.Visible = false end
                    end)
                end
                -- the words and the arrow make way...
                if tLoop then tLoop:Cancel(); tLoop = nil end
                if fx.bob then fx.bob:Cancel(); fx.bob = nil end
                fx.sayTok = (fx.sayTok or 0) + 1        -- (no words still on their way in)
                tween(tLabel, 0.12, { TextTransparency = 1 })
                tween(tIcon, 0.12, { ImageTransparency = 1 })
                -- ...and the mark grows in from nothing, turning into place
                local mark = fx.mark
                mark.Image, mark.ImageColor3 = icon, icon == ICON.check and C.greenText or C.red
                mark.Size, mark.Rotation, mark.ImageTransparency = UDim2.fromOffset(0, 0), -40, 0
                task.delay(0.14, function()
                    if resultTok == mine then tween(mark, 0.5, { Size = UDim2.fromOffset(18, 18), Rotation = 0 }, EASE.Back, DIR.Out) end
                end)
                if icon == ICON.x then
                    task.delay(0.5, function() if resultTok == mine then fx.shake() end end)
                end
                task.delay(hold, function()
                    if resultTok ~= mine then return end
                    fx.mode = "rest"
                    fx.paint(0.35)
                    tween(mark, 0.2, { ImageTransparency = 1 }, EASE.Quad, DIR.Out)
                    task.delay(0.1, function()
                        if resultTok ~= mine then return end
                        tLabel.Text, tLabel.Position = "Send test", fx.home
                        tween(tLabel, 0.25, { TextTransparency = 0 })
                        popIcon(ICON.arrowUp, C.blurpleText or C.muted)
                        -- still under the pointer: once it has landed, it lifts again
                        task.delay(0.35, function()
                            if resultTok == mine and fx.over and fx.mode == "rest" then fx.float(true) end
                        end)
                    end)
                end)
            end
            hook.url = tostring(savedOr("webhook", ""))
            box.Text = hook.url
            refreshHookStatus()
            box.Focused:Connect(function()
                fRing(true)
                tween(fst, 0.15, { Color = C.borderHi })
                tween(dIcon, 0.15, { ImageColor3 = C.muted })
            end)
            box.FocusLost:Connect(function()
                fRing(false)
                tween(fst, 0.2, { Color = C.border })
                tween(dIcon, 0.2, { ImageColor3 = C.subtle })
                if box.Text ~= hook.url then
                    hook.url, hook.dead = box.Text, false
                    remember("webhook", hook.url)
                    refreshHookStatus()
                end
            end)
            local testing = false
            test.button.MouseButton1Click:Connect(function()
                if testing then return end
                sfx("click")
                if not hookValid() then
                    showOnTest(hookUrl() == "" and "No link" or "Invalid link", ICON.x, C.red, 1.4)
                    notify({ title = "No webhook yet", body = "Paste a Discord webhook link first.", kind = "error" })
                    return
                end
                testing = true
                setHookStatus("sending")
                showOnTest("Sending", ICON.arrowUp, C.amber, nil)
                task.spawn(function()
                    local ok, why = post(helloEmbed("Onyx is connected", ONX.EMO.check,
                        "Your webhook works. Rounds, boxes and the farm will post here."), { force = true, wait = true })
                    refreshHookStatus()
                    showOnTest(ok and "Sent" or "Failed", ok and ICON.check or ICON.x, ok and C.green or C.red, 1.4)
                    testing = false
                    notify({ title = ok and "Test sent" or "Test failed",
                             body = ok and "Check your Discord channel." or tostring(why), kind = ok and "success" or "error" })
                end)
            end)
        end
        local senderEl = toggle({
            key = "sender", title = "Log to Discord", icon = ICON.discord, iconCell = UI.DISCORD_CELL,
            desc = "Posts everything while it's on: every round's results, every box you open, map votes, the farm "
                .. "starting and stopping, and server hops.",
            callback = function(on)
                hook.on = on
                if on and not ONX.restoring then
                    task.spawn(function()
                        local ok, why = post(helloEmbed("Logging started", ONX.EMO.signal), { wait = true, always = true })
                        if not ok then
                            notify({ title = "Couldn't start logging", body = tostring(why), kind = "error", duration = 5 })
                            ONX.setToggle(api.senderEl, false)
                        end
                    end)
                end
            end,
        })
        api.senderEl = senderEl
        toggles[#toggles + 1] = senderEl

        --// BOXES -------------------------------------------------------------
        section("Auto-open boxes")
        text({ Text = "Opens a box whenever you can afford one. Coins only - never Gems.", TextSize = 12,
               TextColor3 = C.subtle, Size = UDim2.new(1, -2, 0, 14), LayoutOrder = nextOrder(), Parent = current })
        -- The boxes as skin cards: the box on the faint grid with a soft glow
        -- (green while it's on), then under a hairline its price in caps -- or
        -- what it's doing -- and its name, with its switch beside them.
        -- Rows of three; a last row that comes up short shares its width
        -- between the boxes it has (two at half each, one full), so the grid
        -- always ends flush instead of leaving an empty slot.
        local boxGrid = make("Frame", {
            BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = nextOrder(), Parent = current,
        })
        pad(boxGrid, 1, 1, 1, 1)
        make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = boxGrid })
        local savedBoxes = type(saved.boxes) == "table" and saved.boxes or {}
        local shownBoxes = {}
        for i, row in ipairs(BOXES) do
            local cost, art = boxPrice(row[1]), boxImage(row[1])
            if cost or art then shownBoxes[#shownBoxes + 1] = { i = i, id = row[1], label = row[2], cost = cost, art = art } end
        end
        local boxRows = {}
        for r = 1, math.ceil(#shownBoxes / 3) do
            boxRows[r] = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 150), LayoutOrder = r, Parent = boxGrid })
            hlist(boxRows[r], 8)
        end
        for k, e in ipairs(shownBoxes) do
            local r = math.ceil(k / 3)
            local inRow = math.min(3, #shownBoxes - (r - 1) * 3)
            local i, id, label, cost, art = e.i, e.id, e.label, e.cost, e.art
            do
                local b = { label = label, on = false, running = false, opened = 0, status = "", image = art, cost = cost }
                boxes[id] = b
                local priceText = cost and (ONX.comma(cost) .. " COINS") or "?"
                local tile = make("TextButton", {
                    Text = "", AutoButtonColor = false, BackgroundColor3 = C.tile, BorderSizePixel = 0,
                    Size = UDim2.new(1 / inRow, -(8 * (inRow - 1)) / inRow, 1, 0), LayoutOrder = i, Parent = boxRows[r],
                })
                corner(tile, 12)
                local st = stroke(tile, C.border)
                tile:SetAttribute("OwnEdge", true)
                local ring = ONX.ringOn(st, 7)
                local artF = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1),
                    Size = UDim2.new(1, -2, 1, -(TILE_INFO + 1)), ClipsDescendants = true, Parent = tile })
                corner(artF, 11)
                local glow = image({ Image = ICON.shadow, ImageColor3 = WHITE, ImageTransparency = 0.9,
                    ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(99, 99, 99, 99),
                    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromScale(1, 1.2), Parent = artF })
                for k = 1, 4 do
                    make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.955, BorderSizePixel = 0,
                        Position = UDim2.new(k / 5, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), Parent = artF })
                end
                for k = 1, 3 do
                    make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.955, BorderSizePixel = 0,
                        Position = UDim2.new(0, 0, k / 4, 0), Size = UDim2.new(1, 0, 0, 1), Parent = artF })
                end
                local pic = image({ Image = art or "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54),
                                    Size = UDim2.fromOffset(62, 62), Parent = artF })
                local picScale = make("UIScale", { Parent = pic })
                -- the switch sits in the info strip, right of the price and name
                local swHolder = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -10, 1, -TILE_INFO / 2), Size = UDim2.fromOffset(36, 20), Parent = tile })
                local paintSw = switch(swHolder)
                make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Position = UDim2.new(0, 10, 1, -TILE_INFO),
                    Size = UDim2.new(1, -20, 0, 1), Parent = tile })
                local statusT = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 10, 1, -TILE_INFO + 9),
                    Size = UDim2.new(1, -62, 0, 11), FontFace = geist(FW.ExtraBold), TextSize = 10, TextColor3 = C.subtle,
                    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = priceText, Parent = tile })
                text({ Text = label, FontFace = geist(FW.SemiBold), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd,
                    Position = UDim2.new(0, 10, 1, -TILE_INFO + 21), Size = UDim2.new(1, -62, 0, 16), Parent = tile })
                local over = false
                local function paint(t)
                    if b.on then
                        ring(over and RING_DIM_HOT or RING_DIM, over and RING_LIT_HOT or RING_LIT, t)
                    else
                        local c = over and C.borderHi or C.border
                        ring(c, c, t)
                    end
                    tween(tile, t or 0.25, { BackgroundColor3 = over and C.tileHover or C.tile })
                    tween(glow, t or 0.3, { ImageColor3 = b.on and C.greenText or WHITE, ImageTransparency = b.on and 0.8 or 0.9 })
                    tween(statusT, t or 0.25, { TextColor3 = b.on and C.greenText or C.subtle })
                end
                -- what it's doing, in caps where the price sits; the price again when it's off
                b.onStatus = function(t)
                    local word = (t ~= "" and t ~= "Off" and t) or (b.on and "Starting..." or nil)
                    swap(statusT, word and string.upper(word) or priceText)
                end
                function b.setOn(v)
                    v = v and true or false
                    b.on = v
                    savedBoxes[id] = v or nil
                    remember("boxes", savedBoxes)
                    paintSw(v)
                    paint(0.3)
                    -- the box gives a little hop
                    picScale.Scale = v and 0.86 or 0.92
                    -- lands at the hover size when the pointer is still on it
                    TweenService:Create(picScale, TweenInfo.new(0.45, EASE.Back, DIR.Out), { Scale = over and 1.06 or 1 }):Play()
                    if v then
                        boxStatus(b, "Starting...")
                        runBox(id)
                    elseif not b.running then
                        boxStatus(b, "Off")
                    end
                end
                tile.MouseEnter:Connect(function()
                    over = true
                    paint(0.18)
                    TweenService:Create(picScale, TweenInfo.new(0.25, EASE.Quint, DIR.Out), { Scale = 1.06 }):Play()
                end)
                tile.MouseLeave:Connect(function()
                    over = false
                    paint(0.22)
                    TweenService:Create(picScale, TweenInfo.new(0.3, EASE.Quint, DIR.Out), { Scale = 1 }):Play()
                end)
                tile.MouseButton1Down:Connect(function() C.ripple(tile, 12) end)
                tile.MouseButton1Click:Connect(function() sfx("click"); b.setOn(not b.on) end)
                paintSw(false, 0)
                paint(0)
                if savedBoxes[id] then b.setOn(true) end
            end
        end
        api.toggles = toggles

        --// Visuals tab -----------------------------------------------------
        -- Its own page, built from this tab's sections and switch tiles so
        -- it looks the same; this tab's `current` is put back afterwards.
        do
            local vPage = make("CanvasGroup", {
                Name = "VisualsPage", BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1, Visible = false,
                Position = UI.listClip.Position, Size = UI.listClip.Size, ZIndex = 2, Parent = win,
            })
            corner(vPage, 12)
            local vScroll = make("ScrollingFrame", {
                BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = C.borderHi,
                VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, Parent = vPage,
            })
            pad(vScroll, 2, 6, UI.SEARCH_Y - UI.LIST_TOP, 16)
            make("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 14),
                HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = vScroll,
            })
            C.edgeFade(vPage, vScroll)
            for _, t in ipairs(TABS) do if t.id == "visuals" then t.page = vPage end end
            ONX.addScrollTop(vPage, vScroll, "visuals")
            ONX.snapToGrid(vPage)
            local keep = current
            section("Weapons", vScroll)
            -- three across, the same tiles as While farming
            local vGrid = make("Frame", {
                BackgroundTransparency = 1, Size = UDim2.new(1, -2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = nextOrder(), Parent = current,
            })
            pad(vGrid, 1, 1, 1, 1)
            make("UIGridLayout", {
                CellPadding = UDim2.fromOffset(8, 8), CellSize = UDim2.new(1 / 3, -6, 0, 118),
                HorizontalAlignment = Enum.HorizontalAlignment.Left,
                SortOrder = Enum.SortOrder.LayoutOrder, Parent = vGrid,
            })
            -- (each also repaints its twin in the Skin Changer's Wear card)
            local function paintWear(key, on)
                if UI.wearPaint then pcall(UI.wearPaint, key, on) end
            end
            local vToggles = {
                toggle({
                    key = "visBelt", short = "Knife on belt", icon = ICON.sword, title = "Wear your knife on your belt", parent = vGrid,
                    desc = "Your knife hangs at your side instead of your back, the way a radio moves it. Only on your screen.",
                    callback = function(on) ONX.vis.setBelt(on); paintWear("belt", on) end,
                }),
                toggle({
                    key = "visDual", short = "Two guns", icon = ICON.tabCrosshair, title = "A gun in each hand", parent = vGrid,
                    desc = "Holding your gun, a second one sits in your left hand, skin and all. Not for Gingerscopes. Only on your screen.",
                    callback = function(on) ONX.vis.setDual(on); paintWear("guns", on) end,
                }),
                toggle({
                    key = "visDualKnife", short = "Two knives", icon = ICON.sword, title = "A knife in each hand", parent = vGrid,
                    desc = "Holding your knife, a second one sits in your left hand, skin and all. Only on your screen.",
                    callback = function(on) ONX.vis.setDualKnife(on); paintWear("knives", on) end,
                }),
            }
            current = keep
            -- the Skin Changer's Wear card drives these same switches
            UI.wearEl = { belt = vToggles[1], guns = vToggles[2], knives = vToggles[3] }
            for key, el in pairs(UI.wearEl) do paintWear(key, el.Value) end
            -- on last time: on again now. And off is applied too, so nothing
            -- is left over from before (a knife still on the belt)
            for _, el in ipairs(vToggles) do
                if el.restore then pcall(el.restore, el.Value) end
            end
        end
    end

    --// Fling & Teleport tab (testing) -----------------------------------
    -- Pick a player off the list, then Fling: the same throw the farm uses on
    -- the murderer, so it can be tried on anyone (your own alts). The list
    -- keeps itself current as people join and leave, and tags the murderer.
    function ONX.buildFlingPage()
        local page = make("CanvasGroup", {
            Name = "FlingPage", BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1, Visible = false,
            Position = UI.listClip.Position, Size = UI.listClip.Size, ZIndex = 2, Parent = win,
        })
        corner(page, 12)
        -- no scrollbar: its lane pushed the whole page a few px left (it still
        -- scrolls), and the same 2px on both sides so it sits centred
        local scroll = make("ScrollingFrame", {
            BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 0,
            VerticalScrollBarInset = Enum.ScrollBarInset.None, Parent = page,
        })
        pad(scroll, 2, 2, UI.SEARCH_Y - UI.LIST_TOP, 16)
        -- cards scrolling past the top or bottom melt away (C.edgeFade)
        C.edgeFade(page, scroll)
        make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
                               HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = scroll })
        for _, t in ipairs(TABS) do if t.id == "fling" then t.page = page end end
        ONX.addScrollTop(page, scroll, "fling")
        ONX.snapToGrid(page)


        local card = make("Frame", {
            BackgroundColor3 = C.tile, BorderSizePixel = 0, Size = UDim2.new(1, -2, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = scroll,
        })
        corner(card, 10)
        stroke(card, C.border)
        pad(card, 12, 12, 12, 12)       -- 12 all round, the same as the gaps between cards
        make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12), Parent = card })

        -- The controls: one bar per picked player, stacked in the order they
        -- were picked -- picture, name, @name, then Teleport | Fling and Loop,
        -- each bar its own. With nobody picked, a single hint bar says what to
        -- do. Bars open and close by growing / shrinking their row.
        local bars = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
                                     AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = card })
        -- (the rows' gap comes from the layout; a negative padding used to trim
        -- the last one, and it threw the whole panel's height off by 8px --
        -- no room under the cards)
        make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = bars })
        local BAR_ROW = 36        -- 1px room for outlines, the 34px bar, 1px

        -- a round picture with a person icon behind it until the photo loads
        local function portrait(parent)
            local pfp = make("ImageLabel", {
                BackgroundColor3 = C.field, BorderSizePixel = 0, Image = "", AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 1, 0.5, 0), Size = UDim2.fromOffset(34, 34), Parent = parent,
            })
            corner(pfp, FULL)
            local edge = stroke(pfp, C.border)
            local icon = image({ Image = ICON.tabPlayer, ImageColor3 = C.subtle, AnchorPoint = Vector2.new(0.5, 0.5),
                                 Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), Parent = pfp })
            return pfp, edge, icon
        end
        -- one button: a label and an icon on the dark surface
        local function actionButton(parent, label, icon, width, right)
            local b = make("TextButton", {
                Text = "", AutoButtonColor = false, BackgroundColor3 = C.field, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, right, 0.5, 0), Size = UDim2.fromOffset(width, 32), Parent = parent,
            })
            corner(b, 9)
            local st = stroke(b, C.border)
            local inner = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = b })
            hlist(inner, 7, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
            local ic = image({ Image = icon, ImageColor3 = C.subtle, Size = UDim2.fromOffset(14, 14), LayoutOrder = 1, Parent = inner })
            local l = text({ Text = label, FontFace = geist(FW.SemiBold), TextSize = 13, TextColor3 = C.subtle,
                             Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = inner })
            return b, st, inner, ic, l
        end

        -- the hint bar, shown while nobody's picked
        local hintRow = make("CanvasGroup", { BackgroundTransparency = 1, BorderSizePixel = 0,
                                              Size = UDim2.new(1, 0, 0, BAR_ROW), LayoutOrder = 0, Parent = bars })
        do
            local top = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1),
                                        Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 34), Parent = hintRow })
            portrait(top)
            text({ Text = "Pick players", FontFace = geist(FW.SemiBold), TextSize = 14,
                   Position = UDim2.fromOffset(47, 0), Size = UDim2.new(1, -60, 0, 18), Parent = top })
            text({ Text = "Click one or more cards below. Each one gets its own controls here.", TextSize = 12,
                   TextColor3 = C.muted, Position = UDim2.fromOffset(47, 18), Size = UDim2.new(1, -60, 0, 14),
                   TextTruncate = Enum.TextTruncate.AtEnd, Parent = top })
        end

        -- the players: a grid of small cards, four to a row -- picture, display
        -- name, @name and their role this round
        -- a hairline between the controls and the cards, running the card's
        -- full width
        local rule = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 1), LayoutOrder = 2, Parent = card })
        make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Position = UDim2.fromOffset(-12, 0),
                        Size = UDim2.new(1, 24, 0, 1), Parent = rule })
        local list = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
                                     AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = card })
        -- rows of up to four, each centred, so a short last row sits in the
        -- middle instead of hugging the left (a grid layout can't do that)
        -- one gap everywhere: between cards, between rows, and the same 12 the
        -- panel leaves above and below them
        local GAP = 12
        local lines = {}
        local reorder
        local empty = text({ Text = "No one else is in this server.", TextSize = 12, TextColor3 = C.subtle,
                             TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 36),
                             LayoutOrder = 4, Visible = false, Parent = card })

        local rows, picked, barSeq = {}, {}, 0
        -- Player cards, "banner profile": a dark rounded card with a banner
        -- across the top in the role's colour (fading to a deep shade of it),
        -- the round headshot sitting on the banner's edge in a ring of the
        -- card's own colour, then the name and the role underneath. Picked:
        -- a white outline and a white check on the banner.
        local ROLE_COL = { murderer = hex("#ff3b30"), sheriff = hex("#3b8cff"), innocent = hex("#34c76a"), lobby = hex("#71717a") }
        local ROLE_NAME = { murderer = "Murderer", sheriff = "Sheriff", innocent = "Innocent", lobby = "Lobby", dead = "Lobby" }
        local BANNER, CARD_W, CARD_H, CARD_GAP = 40, 148, 128, 10
        local function paintRow(r, t)
            t = t or 0.18
            local on = picked[r.player] ~= nil
            local bg = on and C.tile:Lerp(WHITE, 0.05) or (r.over and C.tileHover or C.tile)
            tween(r.body, t, { BackgroundColor3 = bg })
            tween(r.faceRing, t, { Color = bg })
            -- the name sits grey, lighting up when hovered or picked
            if r.nameL then tween(r.nameL, t, { TextColor3 = (on or r.over) and WHITE or C.muted:Lerp(WHITE, 0.45) }) end
            if r.nameGlow then
                local gt = math.max(t, 0.3)
                tween(r.nameGlow, gt, { GroupTransparency = on and 0.7 or 1 })
                tween(r.roleGlow, gt, { Transparency = on and 0.85 or 1 })
                tween(r.chipGlow, gt, { ImageTransparency = on and 0.82 or 1 })
                tween(r.roleChip, gt, { BackgroundTransparency = on and 0.75 or 0.82 })
                tween(r.roleChipEdge, gt, { Transparency = on and 0.35 or 0.6 })
            end
            tween(r.edge, t, { Thickness = on and 1.5 or 1 })
            -- picked, the face stays at its hover size
            if r.faceScale then tween(r.faceScale, 0.3, { Scale = (on or r.over) and 1.14 or 1 }, EASE.Quint, DIR.Out) end
            tween(r.glow, t + 0.1, { GroupTransparency = on and 0 or 1 })
            tween(r.spot, t, { ImageTransparency = on and 0.25 or (r.over and 0.35 or 0.5) })
            -- macOS-style edge: a white hairline lit along the top; picked,
            -- the role's colours as a ring
            if r.ramp then
                if on then
                    r.edgeGrad.Color = r.pickRamp
                    r.edgeGrad.Transparency = NumberSequence.new(0)
                else
                    r.edgeGrad.Color = ColorSequence.new(WHITE)
                    r.edgeGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, r.over and 0.5 or 0.68),
                        NumberSequenceKeypoint.new(0.35, 0.9), NumberSequenceKeypoint.new(1, 0.93) })
                end
            end
            tween(r.pick, t, { BackgroundTransparency = on and 0 or 1 })
            tween(r.check, t, { ImageTransparency = on and 0 or 1 })
        end

        -- the farm pins and noclips your character, which leaves a throw with
        -- nothing to hit with; switch it off and give the rig a moment to
        -- come off before throwing
        local function farmOff()
            if api.farmEl and api.farmEl.Value then
                api.farmEl:Set(false)
                task.wait(0.6)
            end
        end
        local function anyLoop()
            for _, B in pairs(picked) do if B.loopOn then return true end end
            return false
        end
        -- who's on a loop, for the Dynamic Island: { name, id } A-Z
        function ONX.flingLoopNames()
            local out = {}
            for _, B in pairs(picked) do
                if B.loopOn and B.player then out[#out + 1] = { name = B.player.DisplayName, id = B.player.UserId } end
            end
            table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
            return out
        end
        -- The rows' layout, all at once: the hint while nobody's picked, then
        -- the bars in the order they were picked. Every row eases to its
        -- height together (a row's 8px gap above it is part of its height, the
        -- first has none), and fades in or out with it -- a new bar opens as
        -- the rest make room, and nothing jumps.
        local ROW_EASE = TweenInfo.new(0.38, EASE.Quint, DIR.Out)
        local function relayout()
            local shown = {}
            local bs = {}
            for _, B in pairs(picked) do bs[#bs + 1] = B end
            table.sort(bs, function(a, b) return a.seq < b.seq end)
            if #bs == 0 then shown[1] = hintRow end
            for _, B in ipairs(bs) do shown[#shown + 1] = B.wrap end
            for i, w in ipairs(shown) do
                TweenService:Create(w, ROW_EASE, { Size = UDim2.new(1, 0, 0, BAR_ROW + (i > 1 and 8 or 0)), GroupTransparency = 0 }):Play()
            end
            if #bs > 0 then
                TweenService:Create(hintRow, ROW_EASE, { Size = UDim2.new(1, 0, 0, 0), GroupTransparency = 1 }):Play()
            end
        end

        -- one player's bar
        local function makeBar(pl)
            barSeq += 1
            local B = { player = pl, seq = barSeq, busy = false, loopOn = false, loopTok = 0, bOver = false, tOver = false, lOver = false }
            B.wrap = make("CanvasGroup", { BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1,
                                           Size = UDim2.new(1, 0, 0, 0), LayoutOrder = barSeq, Parent = bars })
            local top = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1),
                                        Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 34), Parent = B.wrap })
            local pfp, pfpEdge, pfpIcon = portrait(top)
            pfpEdge.Color = C.borderHi
            local titleL = text({ Text = pl.DisplayName, FontFace = geist(FW.SemiBold), TextSize = 14,
                                  Position = UDim2.fromOffset(47, 0), Size = UDim2.new(1, -433, 0, 18),
                                  TextTruncate = Enum.TextTruncate.AtEnd, Parent = top })
            local hintL = text({ Text = "@" .. pl.Name, TextSize = 12, TextColor3 = C.muted,
                                 Position = UDim2.fromOffset(47, 18), Size = UDim2.new(1, -433, 0, 14),
                                 TextTruncate = Enum.TextTruncate.AtEnd, Parent = top })
            -- right to left: close, Loop, Fling, the divider, Teleport, Spectate
            local close = make("TextButton", {
                Text = "", AutoButtonColor = false, BackgroundColor3 = C.field, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -1, 0.5, 0), Size = UDim2.fromOffset(32, 32), Parent = top,
            })
            corner(close, 9)
            local cst = stroke(close, C.border)
            local cIcon = image({ Image = ICON.x, ImageColor3 = C.subtle, AnchorPoint = Vector2.new(0.5, 0.5),
                                  Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), Parent = close })
            close.MouseEnter:Connect(function()
                sfx("hover")
                tween(close, 0.15, { BackgroundColor3 = C.tileHover })
                tween(cst, 0.15, { Color = C.borderHi })
                tween(cIcon, 0.15, { ImageColor3 = C.text })
            end)
            close.MouseLeave:Connect(function()
                tween(close, 0.2, { BackgroundColor3 = C.field })
                tween(cst, 0.2, { Color = C.border })
                tween(cIcon, 0.2, { ImageColor3 = C.subtle })
            end)
            close.MouseButton1Down:Connect(function() tween(close, 0.08, { BackgroundColor3 = C.tileActive }) end)
            -- unpicks the player: the bar closes and their card lets go
            close.MouseButton1Click:Connect(function()
                sfx("click")
                if B.onClose then B.onClose() end
            end)
            local loop = make("TextButton", {
                Text = "", AutoButtonColor = false, BackgroundColor3 = C.field, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -41, 0.5, 0), Size = UDim2.fromOffset(86, 32), Parent = top,
            })
            corner(loop, 9)
            local lst = stroke(loop, C.border)
            local lInner = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = loop })
            hlist(lInner, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
            local lLabel = text({ Text = "Loop", FontFace = geist(FW.SemiBold), TextSize = 13, TextColor3 = C.text,
                                  Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = lInner })
            local track = make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, Size = UDim2.fromOffset(26, 14),
                                          LayoutOrder = 2, Parent = lInner })
            corner(track, FULL)
            local knob = make("Frame", { BackgroundColor3 = C.subtle, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
                                         Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(10, 10), Parent = track })
            corner(knob, FULL)
            local fb, fst, fInner, fIcon, fLabel = actionButton(top, "Fling", ICON.tabFling, 100, -135)
            local divider = make("Frame", { BackgroundColor3 = C.border, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
                            Position = UDim2.new(1, -245, 0.5, 0), Size = UDim2.fromOffset(1, 18), Parent = top })
            local tp, tst, tInner, tIcon, tLabel = actionButton(top, "Teleport", ICON.tabPlayer, 104, -256)
            local spB, spSt, spInner, spIcon, spLabel = actionButton(top, "Spectate", ICON.tabEsp, 104, -368)
            -- Laid out from the bar's real width. The window can be as narrow
            -- as 560 (about 270 in here), where the fixed layout ran over
            -- itself: there the buttons drop their words, then the Loop its
            -- label, and the names take whatever room is left. At full width
            -- this lands exactly on the original offsets.
            local function fit(animate)
                local w = top.AbsoluteSize.X / unscale()
                if w < 1 then return end
                -- each button as wide as its own words need (icon 14, gap 7,
                -- 12 either side), measured, so a wider face never spills
                local function need(l) return math.ceil(l.TextBounds.X / unscale()) + 45 end
                -- Words or icons is decided on each button's RESTING word
                -- (Fling, Spectate), remembered while it shows. A fling
                -- starting -- Flinging / Looping -- or Watching only widens
                -- its own button, out of the name's room (the name truncates
                -- a little meanwhile); it used to tip Teleport and Spectate
                -- down to their icons for as long as the fling ran.
                if fLabel.Text == "Fling" then B.fRest = need(fLabel) end
                if spLabel.Text == "Spectate" then B.sRest = need(spLabel) end
                local fRest, sRest = B.fRest or need(fLabel), B.sRest or need(spLabel)
                local NAME_MIN = 72
                local full = 41 + 86 + 8 + fRest + 10 + 11 + need(tLabel) + 8 + sRest + 20
                local mid = 41 + 86 + 8 + fRest + 10 + 11 + 36 + 8 + 36 + 20
                -- all the words when they fit; then Teleport / Spectate go to
                -- their icons; then Fling too; the Loop keeps its word longest
                local mode = (w - 47 - full >= NAME_MIN and "full") or (w - 47 - mid >= NAME_MIN and "mid") or "compact"
                local tight = mode == "compact" and w < 400
                local loopW = tight and 44 or 86
                local fW = mode == "compact" and 36 or need(fLabel)
                local tW = mode == "full" and need(tLabel) or 36
                local sW = mode == "full" and need(spLabel) or 36
                -- a word change glides the buttons to their new widths; a
                -- resize just places them
                local function place(o, goal)
                    if animate then tween(o, 0.28, goal, EASE.Quint, DIR.Out)
                    else for k, v in pairs(goal) do o[k] = v end end
                end
                local x = 41 + loopW + 8
                loop.Size = UDim2.fromOffset(loopW, 32)
                lLabel.Visible = not tight
                place(fb, { Position = UDim2.new(1, -x, 0.5, 0), Size = UDim2.fromOffset(fW, 32) })
                x = x + fW + 10
                place(divider, { Position = UDim2.new(1, -x, 0.5, 0) })
                x = x + 11
                place(tp, { Position = UDim2.new(1, -x, 0.5, 0), Size = UDim2.fromOffset(tW, 32) })
                x = x + tW + 8
                place(spB, { Position = UDim2.new(1, -x, 0.5, 0), Size = UDim2.fromOffset(sW, 32) })
                x = x + sW + 20
                fLabel.Visible = mode ~= "compact"
                tLabel.Visible, spLabel.Visible = mode == "full", mode == "full"
                place(titleL, { Size = UDim2.new(1, -(x + 47), 0, 18) })
                place(hintL, { Size = UDim2.new(1, -(x + 47), 0, 14) })
            end
            -- (the words' widths change as the face loads and as Fling reads
            -- Flinging / Looping, and Spectate reads Watching)
            fLabel:GetPropertyChangedSignal("TextBounds"):Connect(function() fit(true) end)
            tLabel:GetPropertyChangedSignal("TextBounds"):Connect(function() fit(true) end)
            spLabel:GetPropertyChangedSignal("TextBounds"):Connect(function() fit(true) end)
            top:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() fit(false) end)
            task.defer(fit, false)

            function B.paint(t)
                t = t or 0.2
                -- while the loop runs it does the flinging, so the button rests
                -- (greyed, "Looping") and doesn't take clicks
                local ready = not B.busy and not B.loopOn
                -- Fling: the colour carried by its red zap; a soft lift on hover
                tween(fb, t, { BackgroundColor3 = ready and B.bOver and C.tileHover or C.field })
                tween(fst, t, { Color = ready and (B.bOver and C.red:Lerp(C.border, 0.35) or C.red:Lerp(C.border, 0.6)) or C.border })
                tween(fLabel, t, { TextColor3 = ready and C.text or C.subtle })
                tween(fIcon, t, { ImageColor3 = ready and C.red or C.subtle })
                fLabel.Text = B.busy and "Flinging" or (B.loopOn and "Looping" or "Fling")
                tween(tp, t, { BackgroundColor3 = B.tOver and C.tileHover or C.field })
                tween(tst, t, { Color = B.tOver and C.borderHi:Lerp(WHITE, 0.2) or C.borderHi })
                tween(tLabel, t, { TextColor3 = C.text })
                tween(tIcon, t, { ImageColor3 = C.text })
                -- Spectate: like Teleport; while you're watching them it stays
                -- lit (a brighter edge) and reads Watching
                local watching = ONX.spectating == B
                tween(spB, t, { BackgroundColor3 = (B.sOver or watching) and C.tileHover or C.field })
                tween(spSt, t, { Color = watching and C.borderHi:Lerp(WHITE, 0.5)
                    or (B.sOver and C.borderHi:Lerp(WHITE, 0.2) or C.borderHi) })
                tween(spLabel, t, { TextColor3 = C.text })
                tween(spIcon, t, { ImageColor3 = watching and WHITE or C.text })
                spLabel.Text = watching and "Watching" or "Spectate"
                -- Loop: white track and a dark knob to the right when on
                tween(loop, t, { BackgroundColor3 = B.lOver and C.tileHover or C.field })
                tween(lst, t, { Color = B.loopOn and C.borderHi:Lerp(WHITE, 0.3) or C.borderHi })
                tween(track, t, { BackgroundColor3 = B.loopOn and WHITE or C.border })
                tween(knob, t, { BackgroundColor3 = B.loopOn and C.ink or C.subtle,
                                 Position = B.loopOn and UDim2.new(1, -12, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) }, EASE.Quint, DIR.Out)
            end
            function B.hint()
                -- just the name: the Loop switch and the Looping button already
                -- say it's on (a status here got cut off on long names)
                hintL.Text = "@" .. pl.Name
                local r = rows[pl]
                pfp.Image = r and r.face.Image or ""
                pfpIcon.Visible = pfp.Image == ""
            end

            -- Loop: fling them again and again until it's switched off, they're
            -- unpicked, or they leave. Only throws at someone standing (alive,
            -- on their feet, not already flying), so between throws your
            -- character is left alone. Several loops take turns, one throw
            -- at a time.
            function B.setLoop(v, quiet)
                if v == B.loopOn then return end
                B.loopOn = v
                ONX.flingLoopOn = anyLoop()
                B.loopTok += 1
                local mine = B.loopTok
                B.paint()
                B.hint()
                if not v then
                    if not quiet then notify({ title = "Fling loop off", body = pl.DisplayName, kind = "off" }) end
                    return
                end
                notify({ title = "Fling loop on", body = "Flinging " .. pl.DisplayName .. " until you turn it off."
                             .. (api.farmEl and api.farmEl.Value and " Autofarm is off while it runs." or ""), kind = "flame" })
                task.spawn(function()
                    farmOff()
                    while B.loopOn and B.loopTok == mine and not B.dead and gui.Parent do
                        local ch = pl.Character
                        local h = ch and ch:FindFirstChildOfClass("Humanoid")
                        local root = h and h.RootPart
                        if root and h.Health > 0 and not h.Sit and root.AssemblyLinearVelocity.Magnitude < 60
                           and not flingActive then
                            B.busy = true
                            B.paint()
                            pcall(flingPlayer, pl, true)       -- camera rides with you, like a single fling
                            B.busy = false
                            if not B.dead then B.paint() end
                            task.wait(1.2)      -- let the throw land, and hand you back your character
                        else
                            task.wait(0.25)
                        end
                    end
                end)
            end

            -- press feel shared by the three
            local function feel(button, inner, key)
                button.MouseEnter:Connect(function() B[key] = true; B.paint(0.15); sfx("hover") end)
                button.MouseLeave:Connect(function()
                    B[key] = false
                    B.paint(0.2)
                    if inner then tween(inner, 0.3, { Position = UDim2.new() }, EASE.Back, DIR.Out) end
                end)
                button.MouseButton1Down:Connect(function()
                    tween(button, 0.08, { BackgroundColor3 = C.tileActive })
                    if inner then tween(inner, 0.08, { Position = UDim2.fromOffset(0, 1) }) end
                end)
                button.MouseButton1Up:Connect(function()
                    if inner then tween(inner, 0.3, { Position = UDim2.new() }, EASE.Back, DIR.Out) end
                    B.paint(0.15)
                end)
            end
            feel(fb, fInner, "bOver")
            feel(tp, tInner, "tOver")
            feel(spB, spInner, "sOver")
            feel(loop, nil, "lOver")

            fb.MouseButton1Click:Connect(function()
                if B.busy or B.loopOn then return end
                if flingActive then
                    notify({ title = "Already flinging", body = "Wait for the current throw to finish.", kind = "wait" })
                    return
                end
                sfx("click")
                B.busy = true
                B.paint()
                task.spawn(function()
                    farmOff()
                    pcall(flingPlayer, pl)
                    B.busy = false
                    if not B.dead then B.paint() end
                end)
            end)
            loop.MouseButton1Click:Connect(function()
                sfx("click")
                B.setLoop(not B.loopOn)
            end)
            -- Spectate: your camera follows them -- through their respawns and
            -- anything else that moves it -- until you click again, watch
            -- someone else, close their bar, or they leave. Then it's back on you.
            local function camTo(p)
                local ch = p and p.Character
                local h = ch and ch:FindFirstChildOfClass("Humanoid")
                local cam = workspace.CurrentCamera
                if h and cam then cam.CameraSubject = h end
            end
            function B.setSpectate(v)
                if v == (ONX.spectating == B) then return end
                if not v then
                    ONX.spectating = nil
                    camTo(LocalPlayer)
                    B.paint()
                    notify({ title = "Back to you", body = "Stopped spectating " .. pl.DisplayName .. ".", kind = "off" })
                    return
                end
                local was = ONX.spectating
                ONX.spectating = B
                if was and not was.dead then was.paint() end
                B.paint()
                notify({ title = "Spectating " .. pl.DisplayName, body = "Click Watching to come back to you.", kind = "success" })
                task.spawn(function()
                    while ONX.spectating == B and not B.dead and pl.Parent == Players and gui.Parent do
                        local ch = pl.Character
                        local h = ch and ch:FindFirstChildOfClass("Humanoid")
                        local cam = workspace.CurrentCamera
                        if h and cam and cam.CameraSubject ~= h then cam.CameraSubject = h end
                        task.wait(0.2)
                    end
                    -- ended on its own (closed, left, Onyx shut): the camera comes home
                    if ONX.spectating == B then
                        ONX.spectating = nil
                        camTo(LocalPlayer)
                    end
                    if not B.dead then B.paint() end
                end)
            end
            spB.MouseButton1Click:Connect(function()
                sfx("click")
                B.setSpectate(ONX.spectating ~= B)
            end)

            -- Teleport: drop in just behind them, facing the way they face
            -- If either of you has no character (dead, respawning), it waits for
            -- the respawn -- up to 15 seconds -- and goes then, instead of
            -- just refusing. One wait at a time per bar.
            local function rootOfP(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
            tp.MouseButton1Click:Connect(function()
                if B.tpWaiting then return end
                if flingActive then
                    notify({ title = "Already flinging", body = "Wait for the current throw to finish.", kind = "wait" })
                    return
                end
                sfx("click")
                task.spawn(function()
                    if not (rootOfP(pl) and rootOfP(LocalPlayer)) then
                        B.tpWaiting = true
                        notify({ title = "Waiting to teleport", kind = "wait", key = "tpwait:" .. pl.UserId,
                                 body = rootOfP(LocalPlayer) and ("Going as soon as " .. pl.DisplayName .. " respawns.")
                                     or "Going as soon as you respawn." })
                        local t0 = os.clock()
                        -- (and not after Onyx was closed or re-run meanwhile)
                        repeat task.wait(0.2)
                        until (rootOfP(pl) and rootOfP(LocalPlayer)) or os.clock() - t0 > 15 or B.dead or pl.Parent ~= Players
                            or not gui.Parent
                        B.tpWaiting = false
                        if B.dead or pl.Parent ~= Players or not gui.Parent then return end
                        if not (rootOfP(pl) and rootOfP(LocalPlayer)) then
                            sfx("error")
                            notify({ title = "Couldn't teleport", body = pl.DisplayName .. " didn't respawn in time.", kind = "error" })
                            return
                        end
                        task.wait(0.4)      -- let the spawn settle
                    end
                    -- a running farm would drag you straight back to its coin
                    -- (or under the map): switch it off first, like Fling does
                    farmOff()
                    local them, me = rootOfP(pl), rootOfP(LocalPlayer)
                    if not (them and me) or flingActive or not gui.Parent then return end
                    me.AssemblyLinearVelocity = Vector3.zero
                    me.CFrame = them.CFrame * CFrame.new(0, 0, 3)
                    notify({ title = "Teleported", body = "You're right behind " .. pl.DisplayName .. ".", kind = "success" })
                end)
            end)

            B.paint(0)
            B.hint()
            return B            -- relayout() opens it
        end
        local function dropBar(pl, quiet)
            local B = picked[pl]
            if not B then return end
            picked[pl] = nil
            if B.loopOn then B.setLoop(false, quiet) end
            ONX.flingLoopOn = anyLoop()
            B.dead = true
            local out = TweenService:Create(B.wrap, ROW_EASE, { Size = UDim2.new(1, 0, 0, 0), GroupTransparency = 1 })
            out.Completed:Connect(function() B.wrap:Destroy() end)
            out:Play()
            relayout()
        end
        local function togglePick(pl)
            if picked[pl] then
                dropBar(pl)
            else
                picked[pl] = makeBar(pl)
                picked[pl].onClose = function() if picked[pl] then togglePick(pl) end end
                relayout()
            end
            if rows[pl] then paintRow(rows[pl]) end
        end
        ONX.stopFlingLoop = function()
            for _, B in pairs(picked) do
                if B.loopOn then B.setLoop(false) end
            end
            ONX.flingLoopOn = false
        end

        -- Rows of fixed-size cards, each row centred -- a short last row sits
        -- in the middle too. Players are spread evenly over the rows (5 on a
        -- 4-wide panel are 3 + 2, not 4 + 1).
        make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, CARD_GAP),
                               HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = list })
        make("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 1), Parent = list })
        local cardLines = {}
        local lastW
        -- cards changing places glide there: each one's old spot and width are
        -- noted first, and after the relayout its body starts from there
        local SLIDE = TweenInfo.new(0.45, EASE.Quint, DIR.Out)
        function reorder()
            local all = {}
            for _, r in pairs(rows) do all[#all + 1] = r end
            local us = unscale()
            local before = {}
            for _, r in ipairs(all) do
                if r.btn.Parent and r.btn.Parent.Parent == list then
                    local bp = r.body.Position
                    before[r] = { r.btn.AbsolutePosition / us + Vector2.new(bp.X.Offset, bp.Y.Offset),
                                  r.btn.AbsoluteSize.X / us + r.body.Size.X.Offset }
                end
            end
            local RANK = { sheriff = 1, murderer = 2, innocent = 3 }
            table.sort(all, function(x, y)
                local ra, rb = RANK[x.role] or 4, RANK[y.role] or 4
                if ra ~= rb then return ra < rb end
                return x.player.DisplayName:lower() < y.player.DisplayName:lower()
            end)
            local W = list.AbsoluteSize.X / unscale()
            lastW = W
            local cols = math.clamp(math.floor((W + CARD_GAP) / (CARD_W + CARD_GAP)), 1, 3)
            local n = #all
            -- the sheriff and the murderer share a full-width row on top (one
            -- alone fills it); everyone else in rows of 3, a short last row stretched to
            -- the same width
            local fullW = cols * CARD_W + (cols - 1) * CARD_GAP
            local groups, rest, top = {}, {}, {}
            for _, r in ipairs(all) do
                if r.role == "sheriff" or r.role == "murderer" then top[#top + 1] = r
                else rest[#rest + 1] = r end
            end
            if #top > 0 then groups[1] = top end
            for i = 1, #rest, cols do
                local g = {}
                for j = i, math.min(#rest, i + cols - 1) do g[#g + 1] = rest[j] end
                groups[#groups + 1] = g
            end
            local nrows = math.max(1, #groups)
            for i = 1, nrows do
                if not cardLines[i] then
                    cardLines[i] = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, CARD_H), LayoutOrder = i, Parent = list })
                    make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
                                           SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, CARD_GAP), Parent = cardLines[i] })
                end
            end
            local idx = 0
            for line, g in ipairs(groups) do
                local k = #g
                local w = math.floor((fullW - (k - 1) * CARD_GAP) / k)
                for _, r in ipairs(g) do
                    idx += 1
                    r.btn.Size = UDim2.fromOffset(w, CARD_H)
                    if r.fitGrid then r.fitGrid(w) end
                    r.btn.LayoutOrder = idx
                    r.btn.Parent = cardLines[line]
                end
            end
            -- (cards moved out first, so dropping a spare row never takes one with it)
            for i = #cardLines, nrows + 1, -1 do
                cardLines[i]:Destroy()
                cardLines[i] = nil
            end
            if cardLines[1] then cardLines[1].Visible = n > 0 end
            empty.Visible = n == 0
            for r, old in pairs(before) do
                if r.btn.Parent then
                    local now = r.btn.AbsolutePosition / us
                    local w = r.btn.AbsoluteSize.X / us
                    local d = old[1] - now
                    local dw = old[2] - w
                    if d.Magnitude > 0.5 or math.abs(dw) > 0.5 then
                        r.body.Position = UDim2.fromOffset(d.X, d.Y)
                        r.body.Size = UDim2.new(1, dw, 1, 0)
                        if r.fitGrid then r.fitGrid(math.max(w, old[2])) end
                        -- two tweens, not one: a hover tween on Position cancels
                        -- a whole running tween, and took the Size part with it,
                        -- leaving the body stuck at the old card's width
                        TweenService:Create(r.body, SLIDE, { Size = UDim2.fromScale(1, 1) }):Play()
                        TweenService:Create(r.body, SLIDE, { Position = UDim2.fromOffset(0, r.over and -2 or 0) }):Play()
                        local fit = r.fitGrid
                        task.delay(0.45, function() if fit and r.btn.Parent then fit(r.btn.AbsoluteSize.X / unscale()) end end)
                    end
                end
            end
        end
        list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            local W = list.AbsoluteSize.X / unscale()
            if lastW and math.abs(W - lastW) < 1 then return end
            reorder()
        end)

        -- Each card's role this round, as a tag: red Murderer, blue Sheriff
        -- (the sheriff, or the hero who picked the gun up), green Innocent --
        -- and Lobby for anyone not in the round, or knocked out of it.
        local ROLES = {
            murderer = { "Murderer", C.redBg, C.red:Lerp(C.border, 0.6), C.red },
            sheriff  = { "Sheriff", hex("#0f1b2e"), hex("#60a5fa"):Lerp(C.border, 0.6), hex("#60a5fa") },
            innocent = { "Innocent", C.greenBg, C.greenEdge, C.greenText },
            dead     = { "Dead", C.field, C.border, C.subtle },
            lobby    = { "Lobby", C.field, C.border, C.subtle },
        }
        -- A card's outline is a ring (ONX.ringOn), turning once every 7
        -- seconds (the Autofarm card's turns in 4). Most get a flat colour, so
        -- the turn doesn't show; the murderer's and sheriff's glow in their
        -- colour as it goes round.
        local function ringOn(st) return ONX.ringOn(st, 7) end

        local function sheriffOf()
            for _, pl in ipairs(Players:GetPlayers()) do
                local bp = pl:FindFirstChildOfClass("Backpack")
                if (bp and bp:FindFirstChild("Gun")) or (pl.Character and pl.Character:FindFirstChild("Gun")) then return pl end
            end
            -- the server's roster first (it knows before the gun is handed out)
            local roster = ONX.roster()
            if type(roster) == "table" then
                for name, data in pairs(roster) do
                    if type(data) == "table" and (data.Role == "Sheriff" or data.Role == "Hero") and not data.Dead then
                        local pl = Players:FindFirstChild(name)
                        if pl then return pl end
                    end
                end
            end
            local ok, pd = pcall(function()
                return require(ReplicatedStorage.Modules.CurrentRoundClient).PlayerData
            end)
            if ok and type(pd) == "table" then
                for name, data in pairs(pd) do
                    if type(data) == "table" and (data.Role == "Sheriff" or data.Role == "Hero") and not data.Dead then
                        return Players:FindFirstChild(name)
                    end
                end
            end
        end
        -- one read of the round, then a quick lookup per player
        local function rolesNow()
            local m, sh = findMurderer(), sheriffOf()
            local ok, pd = pcall(function()
                return require(ReplicatedStorage.Modules.CurrentRoundClient).PlayerData
            end)
            pd = (ok and type(pd) == "table") and pd or {}
            -- the roster is newer than the round clock: roles are dealt a good
            -- while before the timer starts, so a fresh roster that has a live
            -- murderer in it counts as a round under way -- unless a round
            -- has only just ended (its closing update would otherwise show
            -- the old roles in the lobby). Judged by when the roster ARRIVED:
            -- measured from now, the closing roster turned "live" again 12s
            -- after the round ended and the old roles came back.
            local roster = ONX.roster()
            local rosterLive = false
            if type(roster) == "table" and ONX.rosterAt and os.clock() - ONX.rosterAt < 30
               and ONX.rosterAt - (ONX.roundEndedAt or -1e9) > 5 then
                for _, d in pairs(roster) do
                    if type(d) == "table" and d.Role == "Murderer" and not d.Dead then rosterLive = true break end
                end
            end
            if rosterLive then pd = roster end
            local live = roundTime() > 0 or rosterLive
            return function(pl)
                -- between rounds everyone's in the lobby, whatever they're
                -- still holding while the game tidies up
                if not live then return "lobby" end
                if pl == m then return "murderer" end
                if pl == sh then return "sheriff" end
                local d = pd[pl.Name]
                -- knocked out of the round = back in the lobby
                if live and type(d) == "table" then return d.Dead and "lobby" or "innocent" end
                return "lobby"
            end
        end
        -- A role change wipes across the card: a snapshot of the card as it
        -- was sits on top and is cut away from the left, with a bright band
        -- in the new role's colour riding the cut -- the new role uncovered
        -- behind it while the other half still shows the old one.
        -- (the card's own swoosh, run across the snapshot and the card in step,
        -- and the snapshot cut away right behind it)
        local function wipeRole(r)
            if not (r.body and r.body.Parent and r.btn.Parent and r.glintGrad) then return end
            local w, h = r.btn.AbsoluteSize.X / unscale(), r.btn.AbsoluteSize.Y / unscale()
            if w < 2 then return end
            -- The old look rides INSIDE the body: reorder() snaps the button to
            -- its new slot at once and only the body glides there, so a clip on
            -- the button jumped ahead while the real card was still sliding.
            local snap = r.body:Clone()
            local clip = make("Frame", { BackgroundTransparency = 1, ClipsDescendants = true, AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = r.body })
            snap.AnchorPoint = Vector2.new(1, 0)
            snap.Position = UDim2.fromScale(1, 0)   -- (the body already carries the hover lift)
            snap.Size = UDim2.fromOffset(w, h)
            snap.Parent = clip
            local sweeps = {}
            local snapGlint = snap:FindFirstChild("Glint")
            for _, gl in ipairs({ r.glint, snapGlint }) do
                local g = gl and gl:FindFirstChildOfClass("UIGradient")
                if g then
                    g.Offset = Vector2.new(-1, 0)
                    gl.Visible = true
                    sweeps[#sweeps + 1] = TweenService:Create(g, GLINT, { Offset = Vector2.new(1, 0) })
                end
            end
            local cut = TweenService:Create(clip, GLINT, { Size = UDim2.fromScale(0, 1) })
            cut.Completed:Connect(function()
                clip:Destroy()
                if r.glint then r.glint.Visible = false end
            end)
            for _, sw in ipairs(sweeps) do sw:Play() end
            cut:Play()
        end
        local function setRole(r, role, t)
            if r.role and r.role ~= role and t ~= 0 then
                pcall(wipeRole, r)
                t = 0          -- the new look is there at once, under the wipe
            end
            r.role = role
            local c = ROLE_COL[(role == "dead") and "lobby" or role] or ROLE_COL.lobby
            r.bannerGrad.Color = ColorSequence.new(c, c:Lerp(BLACK, 0.55))
            -- the name: near-white, washed with the role's colour across it
            if r.nameGrad then
                r.nameGrad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, c:Lerp(WHITE, 0.8)),
                    ColorSequenceKeypoint.new(0.5, c:Lerp(WHITE, 0.55)), ColorSequenceKeypoint.new(1, c:Lerp(WHITE, 0.8)) })
            end
            for _, ln in ipairs(r.gridLines) do ln.BackgroundColor3 = c end
            for _, g in ipairs(r.glowStrokes) do g.Color = c end
            r.spot.ImageColor3 = c
            -- the outline carries the banner's colour, the way a skin's carries its rarity
            r.ramp = ColorSequence.new({ ColorSequenceKeypoint.new(0, c:Lerp(WHITE, 0.35)), ColorSequenceKeypoint.new(0.45, c),
                                         ColorSequenceKeypoint.new(1, c:Lerp(BLACK, 0.55)) })
            -- picked: a ring in the role's own colour (it used to start at pure
            -- white and read as a thick white outline), just lit a touch at the top
            r.pickRamp = ColorSequence.new({ ColorSequenceKeypoint.new(0, c:Lerp(WHITE, 0.25)), ColorSequenceKeypoint.new(0.5, c),
                                             ColorSequenceKeypoint.new(1, c:Lerp(BLACK, 0.25)) })
            r.roleL.Text = ROLE_NAME[role] or "Lobby"
            tween(r.roleL, t or 0.3, { TextColor3 = c:Lerp(WHITE, 0.35) })
            tween(r.roleChip, t or 0.3, { BackgroundColor3 = c })
            tween(r.roleChipEdge, t or 0.3, { Color = c })
            if r.nameGlow then
                -- (the lobby's grey is too dark to glow on the dark card: its
                -- glow is a light silver instead)
                local gc = (c == ROLE_COL.lobby) and c:Lerp(WHITE, 0.6) or c
                for _, gp in ipairs(r.nameGlowParts) do
                    if gp[2] then gp[1].TextColor3 = gc; gp[2].Color = gc else gp[1].ImageColor3 = gc end
                end
                tween(r.roleGlow, t or 0.3, { Color = gc })
                tween(r.chipGlow, t or 0.3, { ImageColor3 = gc })
            end
            if r.glint then r.glint.BackgroundColor3 = c:Lerp(WHITE, 0.55) end   -- the swoosh, lightly in the role's colour
            paintRow(r, t or 0.3)
        end

        local function addRow(pl)
            if rows[pl] then return end
            if pl == LocalPlayer and #Players:GetPlayers() > 1 then return end
            local b = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0 })
            -- picked: a glow in the role's colour round the card
            local GP = 12
            local glow = make("CanvasGroup", { BackgroundTransparency = 1, GroupTransparency = 1, ZIndex = 0,
                Position = UDim2.fromOffset(-GP, -GP), Size = UDim2.new(1, GP * 2, 1, GP * 2), Parent = b })
            local glowStrokes = {}
            for _, L in ipairs({ { 2, 0.2 }, { 4.5, 0.6 }, { 8, 0.82 } }) do
                local f = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(GP, GP),
                                          Size = UDim2.new(1, -GP * 2, 1, -GP * 2), Parent = glow })
                corner(f, 16)
                glowStrokes[#glowStrokes + 1] = stroke(f, WHITE, L[1], L[2])
            end
            local shadow = image({ Image = ICON.shadow, ImageColor3 = BLACK, ImageTransparency = 0.55,
                ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(99, 99, 99, 99), SliceScale = 0.3,
                Position = UDim2.fromOffset(-12, -6), Size = UDim2.new(1, 24, 1, 26), ZIndex = 0, Parent = b })
            local body = make("Frame", { Name = "Body", BackgroundColor3 = C.tile, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = b })
            corner(body, 16)
            local edge = stroke(body, WHITE, 1)
            local edgeGrad = make("UIGradient", { Rotation = 90, Parent = edge })
            -- the banner, clipped to the card's rounded top by a CanvasGroup
            local bannerClip = make("CanvasGroup", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = body })
            corner(bannerClip, 16)
            -- no fill: just the grid, drawn in the role's colour
            local banner = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bannerClip })
            local bannerGrad = make("UIGradient", { Parent = banner })
            -- a fine grid over it, like the window's backdrop: thin white lines,
            -- the vertical ones fading out downwards, the horizontal ones at the sides
            local gridLines, vLines = {}, {}
            do
                -- A 3D grid: a floor in perspective running back to a horizon
                -- LINE near the top (not a single point) -- the rails narrow
                -- towards it without meeting, the rows bunch up against it,
                -- and it's all strongest near the front, fading into the
                -- distance. The name underneath stays clear.
                local CX, HY, BY = CARD_W / 2, 8, 74
                local function seg(x1, y1, x2, y2, t0, t1)
                    local dx, dy = x2 - x1, y2 - y1
                    local len = math.sqrt(dx * dx + dy * dy)
                    local f = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2), Size = UDim2.fromOffset(len, 1),
                        Rotation = math.deg(math.atan2(dy, dx)), Parent = banner })
                    -- faded at both ends: into the distance, and out at the front
                    make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, t0),
                        NumberSequenceKeypoint.new(0.6, t1), NumberSequenceKeypoint.new(1, 1) }), Parent = f })
                    gridLines[#gridLines + 1] = f
                end
                -- rails: spread at the front, narrower at the horizon line
                -- flat: straight, evenly spaced lines, big cells
                -- (none right against the card's edges, where they read as a
                -- second, mismatched outline)
                for i = -12, 12 do
                    seg(CX + i * 22, 0, CX + i * 22, BY, 1, 0.3)
                    local f = gridLines[#gridLines]
                    f.Position = UDim2.new(0.5, i * 22, 0, BY / 2)
                    vLines[#vLines + 1] = { f, math.abs(i * 22) }
                end
                -- rows: bunched against the horizon, wider apart towards the front
                for k = 1, 3 do
                    local y = k * 22
                    local f = y / BY
                    local a = 1 - 0.7 * math.sin(f * math.pi)
                    local w = CARD_W
                    local r = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.new(1, 0, 0, 1), Parent = banner })
                    make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
                        NumberSequenceKeypoint.new(0.3, a), NumberSequenceKeypoint.new(0.7, a), NumberSequenceKeypoint.new(1, 1) }), Parent = r })
                    gridLines[#gridLines + 1] = r
                end
            end
            -- a soft spotlight in the role's colour behind the face
            local spot = make("ImageLabel", { BackgroundTransparency = 1, Image = ICON.shadow, ImageColor3 = WHITE, ImageTransparency = 0.45,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, BANNER), Size = UDim2.fromOffset(130, 110),
                ZIndex = 2, Parent = body })
            local bannerLit = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0,
                                              Size = UDim2.fromScale(1, 1), Parent = banner })
            -- the headshot on the banner's edge, ringed in the card's colour
            local face = make("ImageLabel", { BackgroundColor3 = hex("#1c1c1f"), BorderSizePixel = 0, Image = "",
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, BANNER), Size = UDim2.fromOffset(60, 60),
                ZIndex = 3, Parent = body })
            corner(face, FULL)
            local faceRing = stroke(face, C.tile, 3)
            local faceScale = make("UIScale", { Parent = face })
            -- name and role
            local nameL = text({ Text = pl.DisplayName, FontFace = geist(FW.SemiBold), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center,
                   TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 8, 0, BANNER + 35), Size = UDim2.new(1, -16, 0, 18),
                   TextColor3 = C.muted, ZIndex = 3, Parent = body })
            local nameGrad = make("UIGradient", { Parent = nameL })
            -- picked: the name and the role glow in the role's colour -- a soft
            -- halo round the letters and a light behind the pill
            -- (the name's: copies of it behind, in the role's colour, with
            -- widening faint strokes -- a soft bloom round the letters)
            local nameGlow = make("CanvasGroup", { BackgroundTransparency = 1, GroupTransparency = 1,
                Position = UDim2.new(0, 0, 0, BANNER + 29), Size = UDim2.new(1, 0, 0, 30), ZIndex = 2, Parent = body })
            local nameGlowParts = {}
            for _, L in ipairs({ { 1, 0.55 }, { 2.5, 0.78 }, { 4.5, 0.9 } }) do
                local g = text({ Text = pl.DisplayName, FontFace = geist(FW.SemiBold), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center,
                    TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 18),
                    TextColor3 = WHITE, TextTransparency = L[2], Parent = nameGlow })
                local st = make("UIStroke", { Thickness = L[1], Transparency = L[2], LineJoinMode = Enum.LineJoinMode.Round, Color = WHITE, Parent = g })
                nameGlowParts[#nameGlowParts + 1] = { g, st }
            end
            local spotName = make("ImageLabel", { BackgroundTransparency = 1, Image = ICON.shadow, ImageColor3 = WHITE, ImageTransparency = 0.75,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.8, 0, 0, 40), Parent = nameGlow })
            nameGlowParts[#nameGlowParts + 1] = { spotName }
            local chipGlow = make("ImageLabel", { BackgroundTransparency = 1, Image = ICON.shadow, ImageColor3 = WHITE, ImageTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, BANNER + 65), Size = UDim2.fromOffset(110, 44),
                ZIndex = 2, Parent = body })
            local roleChip = make("Frame", { BackgroundColor3 = C.subtle, BackgroundTransparency = 0.82, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, BANNER + 56), Size = UDim2.fromOffset(0, 18),
                AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = body })
            corner(roleChip, FULL)
            local roleChipEdge = stroke(roleChip, C.subtle, 1, 0.6)
            pad(roleChip, 8, 8)
            local roleL = text({ Text = "Lobby", FontFace = geist(FW.SemiBold), TextSize = 11, TextColor3 = C.subtle,
                                 TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(0, 0, 1, 0),
                                 AutomaticSize = Enum.AutomaticSize.X, ZIndex = 4, Parent = roleChip })
            local roleGlow = make("UIStroke", { Thickness = 1, Transparency = 1, LineJoinMode = Enum.LineJoinMode.Round, Parent = roleL })
            -- picked: a white check on the banner, top-right
            local pick = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -7, 0, 7), Size = UDim2.fromOffset(18, 18), ZIndex = 4, Parent = body })
            corner(pick, FULL)
            local check = image({ Image = ICON.check, ImageColor3 = C.ink, ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(11, 11), ZIndex = 5, Parent = pick })
            -- (none right against the card's edges, whatever its width)
            local function fitGrid(w)
                for _, v in ipairs(vLines) do v[1].Visible = v[2] <= w / 2 - 20 end
            end
            fitGrid(CARD_W)
            local r = { player = pl, btn = b, fitGrid = fitGrid, nameL = nameL, nameGrad = nameGrad, body = body, edge = edge, edgeGrad = edgeGrad, bannerGrad = bannerGrad, gridLines = gridLines, glow = glow, glowStrokes = glowStrokes, spot = spot, face = face, faceRing = faceRing,
                        roleL = roleL, roleChip = roleChip, roleChipEdge = roleChipEdge, nameGlow = nameGlow, nameGlowParts = nameGlowParts, roleGlow = roleGlow, chipGlow = chipGlow, shadow = shadow, pick = pick, check = check, over = false }
            rows[pl] = r
            r.faceScale = faceScale
            -- the skin cards' swoosh across the whole card on hover
            local glint = make("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
                                          Visible = false, ZIndex = 6, Parent = body })
            corner(glint, 16)
            local glintGrad = make("UIGradient", { Transparency = GLINT_BAND, Rotation = 25, Offset = Vector2.new(-1, 0), Parent = glint })
            r.glint = glint           -- tinted with the role's colour in setRole
            r.glintGrad = glintGrad
            glint.Name = "Glint"
            local SOFTI = TweenInfo.new(0.3, EASE.Quint, DIR.Out)
            b.MouseEnter:Connect(function()
                r.over = true
                sfx("hover")
                paintRow(r, 0.15)
                glintGrad.Offset = Vector2.new(-1, 0)
                glint.Visible = true
                local sweep = TweenService:Create(glintGrad, GLINT, { Offset = Vector2.new(1, 0) })
                sweep.Completed:Connect(function(state) if state == Enum.PlaybackState.Completed then glint.Visible = false end end)
                sweep:Play()
                -- the card lifts a touch, the banner brightens, the face leans in
                TweenService:Create(body, SOFTI, { Position = UDim2.fromOffset(0, -2) }):Play()
                TweenService:Create(bannerLit, SOFTI, { BackgroundTransparency = 0.88 }):Play()
                TweenService:Create(shadow, SOFTI, { ImageTransparency = 0.3, Position = UDim2.fromOffset(-12, -2) }):Play()
                tween(faceScale, 0.3, { Scale = 1.14 }, EASE.Quint, DIR.Out)   -- the face grows (no tilt)
            end)
            b.MouseLeave:Connect(function()
                r.over = false
                paintRow(r, 0.2)
                TweenService:Create(body, SOFTI, { Position = UDim2.new() }):Play()
                TweenService:Create(bannerLit, SOFTI, { BackgroundTransparency = 1 }):Play()
                TweenService:Create(shadow, SOFTI, { ImageTransparency = 0.55, Position = UDim2.fromOffset(-12, -6) }):Play()
                -- a picked card keeps its face at the hover size
                tween(faceScale, 0.25, { Scale = picked[pl] and 1.14 or 1 }, EASE.Quint, DIR.Out)
            end)
            b.MouseButton1Down:Connect(function()
                C.ripple(body, 12)
                tween(body, 0.08, { BackgroundColor3 = C.tileActive })
                tween(faceScale, 0.1, { Scale = 1 })
            end)
            b.MouseButton1Up:Connect(function()
                paintRow(r, 0.15)
                tween(faceScale, 0.45, { Scale = (r.over or picked[pl]) and 1.14 or 1 }, EASE.Back, DIR.Out)
            end)
            b.MouseButton1Click:Connect(function()
                if pl == LocalPlayer then return end      -- your own preview card
                -- leaving (shrinking away): a click now would make a bar for a
                -- player who's already gone, and nothing would ever remove it
                if rows[pl] ~= r then return end
                sfx("click")
                togglePick(pl)
            end)
            task.spawn(function()
                local ok, url = pcall(function()
                    return Players:GetUserThumbnailAsync(pl.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
                end)
                if ok and face.Parent then
                    face.Image = url
                    if picked[pl] then picked[pl].hint() end
                end
            end)
            setRole(r, rolesNow()(pl), 0)
            reorder()
            -- joining: the card pops in (and gives its swoosh); its shadow
            -- sits outside the scaled body, so it fades in alongside
            local pop = make("UIScale", { Scale = 0.6, Parent = body })
            TweenService:Create(pop, TweenInfo.new(0.5, EASE.Back, DIR.Out), { Scale = 1 }):Play()
            shadow.ImageTransparency = 1
            TweenService:Create(shadow, TweenInfo.new(0.4, EASE.Quint, DIR.Out), { ImageTransparency = 0.55 }):Play()
            r.pop = pop
            task.delay(0.12, function()
                if not (glint.Parent and r.glintGrad) then return end
                r.glintGrad.Offset = Vector2.new(-1, 0)
                glint.Visible = true
                local sw = TweenService:Create(r.glintGrad, GLINT, { Offset = Vector2.new(1, 0) })
                sw.Completed:Connect(function() if not r.over then glint.Visible = false end end)
                sw:Play()
            end)
        end
        local function dropRow(pl)
            local r = rows[pl]
            if not r then return end
            rows[pl] = nil
            dropBar(pl)
            -- leaving: the card shrinks away, then the rest close the gap. Its
            -- shadow and pick glow live outside the scaled body, so they fade
            -- with it instead of vanishing in one frame at the end
            if r.pop and r.btn.Parent then
                if r.shadow then TweenService:Create(r.shadow, TweenInfo.new(0.2, EASE.Quad, DIR.In), { ImageTransparency = 1 }):Play() end
                if r.glow then TweenService:Create(r.glow, TweenInfo.new(0.2, EASE.Quad, DIR.In), { GroupTransparency = 1 }):Play() end
                local out = TweenService:Create(r.pop, TweenInfo.new(0.25, EASE.Back, DIR.In), { Scale = 0.5 })
                out.Completed:Connect(function()
                    r.btn:Destroy()
                    reorder()
                end)
                out:Play()
            else
                r.btn:Destroy()
                reorder()
            end
        end
        for _, pl in ipairs(Players:GetPlayers()) do addRow(pl) end
        ONX.conns[#ONX.conns + 1] = Players.PlayerAdded:Connect(function(pl)
            if rows[LocalPlayer] then dropRow(LocalPlayer) end
            addRow(pl)
        end)
        ONX.conns[#ONX.conns + 1] = Players.PlayerRemoving:Connect(function(pl)
            dropRow(pl)
            task.defer(function() if #Players:GetPlayers() <= 1 then addRow(LocalPlayer) end end)
        end)
        reorder()

        -- the roles follow the round: every second, and at once whenever the
        -- server's roster lands
        local function refreshRoles()
            -- nothing to repaint while the window is minimised (the page itself
            -- stays Visible); the 1s loop catches up as soon as it's back
            if not (page.Visible and holder.Visible) then return end
            local roleOf = rolesNow()
            local moved = false
            for pl, r in pairs(rows) do
                local role = roleOf(pl)
                if role ~= r.role then
                    setRole(r, role)
                    moved = true
                end
            end
            if moved then reorder() end
        end
        ONX.onRoster = refreshRoles
        local wasLive = roundTime() > 0
        task.spawn(function()
            while gui.Parent do
                local liveNow = roundTime() > 0
                if wasLive and not liveNow then ONX.roundEndedAt = os.clock() end
                wasLive = liveNow
                refreshRoles()
                task.wait(1)
            end
        end)

    end

    ONX.restoring = true
    local okP, errP = pcall(buildPanel)
    okP, errP = pcall(ONX.buildFlingPage)
    -- switches that load on run their callbacks now, quietly; the farm last
    for _, el in ipairs(api.toggles or {}) do
        if el.Value and el.restore then
            local ok, err = pcall(el.restore, true)
        end
    end
    if api.farmEl and savedOr("farm", false) then api.farmEl:Set(true) end
    ONX.restoring = false

    -- Re-running the script tears the old copy down first: every loop stops,
    -- every hook is dropped, the rig comes off and Performance Mode hands the
    -- map back, so the new copy starts clean instead of two farms fighting.
    conns[#conns + 1] = { Disconnect = function()
        local wasFarming = farmRunning
        farmRunning = false
        ONX.farmGen = (ONX.farmGen or 0) + 1      -- any tick still in flight quits
        pcall(function() if farmTween then farmTween:Cancel() end end)
        pcall(farmRig, false)
        pcall(farmNoclip, false)
        -- the rig was what held you up: parked under the map (waiting for the
        -- coins) you'd now drop into the void, so go back up like Stop does
        -- (only when the farm had you -- never while you're playing yourself)
        if wasFarming then
            pcall(function() if ONX.inActiveRound() then ONX.teleportHome() end end)
        end
        pcall(ONX.blockShiftLock, false)
        ONX.onCoin = nil
        pcall(ONX.stopFarmHopWatch)
        pcall(ONX.stopIdleHopWatch, true)
        for _, b in pairs(boxes) do b.on = false end
        autoResetOnFull = false
        pcall(stopAntiAfk)
        ONX.flingWhenDone, ONX.killWhenFull = false, false
        hook.on, hook.dead = false, true
        for _, c in ipairs(ONX.conns) do pcall(function() c:Disconnect() end) end
        pcall(ONX.perf.restoreAll)
        pcall(ONX.vis.stopAll)          -- the knife back where it was, the second gun gone
    end }
end
buildAutofarm()

-- MM2's own screens and a broken picture: Chroma Ornament's database image
-- (rbxassetid://74528014775455) doesn't load, so its tile in the inventory,
-- the equipped slot, crafting and trades all sit blank. Wherever the game
-- shows that id, show our own copy instead -- now, whenever a screen builds a
-- new tile, and whenever it sets that image again.
do
    local BROKEN = { ["74528014775455"] = "BaubleKnifeChroma" }
    local function fix(img)
        local id = img.Image:match("^rbxassetid://(%d+)")
        local key = id and BROKEN[id]
        if not key then return end
        local pic = UI.localPicture(key)
        if pic and img.Image ~= pic then img.Image = pic end
    end
    local watched = setmetatable({}, { __mode = "k" })
    local function watch(d)
        if not (d:IsA("ImageLabel") or d:IsA("ImageButton")) or watched[d] then return end
        watched[d] = true
        fix(d)
        -- kept in conns so a re-execution tears it down: these sit on MM2's own
        -- images, which outlive us, and every run used to add another copy
        conns[#conns + 1] = d:GetPropertyChangedSignal("Image"):Connect(function() fix(d) end)
    end
    -- the pictures arrive with the skin engine (they live in modelfetch.txt),
    -- after the images on screen were first looked at: look again then
    function UI.refixPictures()
        for d in pairs(watched) do pcall(fix, d) end
    end
    -- The equipped slots hide their tags under the weapon picture, so a
    -- chroma knife or gun shows no Chroma tag there. Put an exact copy of the
    -- inventory grid's own Chroma tag on the slot -- same pixel size, sitting
    -- on the name bar's top edge, bottom-left, like in the grid -- whenever
    -- the equipped weapon is a chroma. The game's tags are left as they are.
    local function slotTiles(pg)
        local ok, eq = pcall(function() return pg.MainGUI.Game.Inventory.Main.Weapons.Equipped.Container end)
        if not ok or not eq then return {} end
        local out = {}
        for _, n in ipairs({ "Knife", "Gun" }) do
            local tile = eq:FindFirstChild(n) and eq[n]:FindFirstChild("Container")
            if tile then out[#out + 1] = tile end
        end
        return out
    end
    local function gridChroma(pg)
        local ok, items = pcall(function() return pg.MainGUI.Game.Inventory.Main.Weapons.Items end)
        if not ok or not items then return nil end
        for _, d in ipairs(items:GetDescendants()) do
            if d.Name == "Chroma" and d:IsA("Frame") and d.Visible and d.Parent and d.Parent.Name == "Tags" then return d end
        end
        return nil
    end
    local function paintSlotTag(pg, tile)
        local tags = tile:FindFirstChild("Tags")
        local real = tags and tags:FindFirstChild("Chroma")
        local want = real and real.Visible
        local mine = tile:FindFirstChild("ChromaBadge")
        local tileW, tileH = tile.AbsoluteSize.X, tile.AbsoluteSize.Y
        if tileH <= 0 then return end
        local name = tile:FindFirstChild("ItemName")
        local nameTop = name and (name.AbsolutePosition.Y - tile.AbsolutePosition.Y) or tileH
        if want and not mine then
            local src = gridChroma(pg)
            if src then
                mine = src:Clone()
                mine.Name = "ChromaBadge"
                mine.Visible = true
                -- same stacking as the original: background, then the word on top
                for _, d in ipairs(mine:GetDescendants()) do
                    if d:IsA("GuiObject") then d.ZIndex = d:IsA("TextLabel") and 7 or 6 end
                end
                mine.ZIndex = 6
                mine:SetAttribute("SrcW", src.AbsoluteSize.X)
                mine:SetAttribute("SrcH", src.AbsoluteSize.Y)
                mine.Parent = tile
            end
        elseif not want and mine then
            mine:Destroy()
            mine = nil
        end
        local tagH = 0
        if mine then
            -- sized and placed in fractions of the tile, so it holds at any UI scale
            local w, h = mine:GetAttribute("SrcW") or 50, mine:GetAttribute("SrcH") or 16
            tagH = h
            mine.AnchorPoint = Vector2.new(0, 1)
            mine.Size = UDim2.fromScale(w / tileW, h / tileH)
            mine.Position = UDim2.fromScale(0, nameTop / tileH)
        end
        if tags then
            -- the game's own tag column, lifted over the picture and moved up
            -- so its badges (the snowflake + year) sit just above our Chroma tag
            -- -- or just above the name bar when there's no Chroma tag. Its own
            -- Chroma tag is squeezed to nothing: ours stands in for it.
            tags.ZIndex = 3
            tags.Position = UDim2.fromScale(0, -((tileH - nameTop) + tagH) / tileH)
            if real then
                if real:GetAttribute("_sz") == nil then real:SetAttribute("_sz", real.Size.X.Scale .. "," .. real.Size.Y.Scale) end
                real.Size = UDim2.new()
            end
        end
    end
    local function watchSlots(pg)
        for _, tile in ipairs(slotTiles(pg)) do
            local real = tile:FindFirstChild("Tags") and tile.Tags:FindFirstChild("Chroma")
            paintSlotTag(pg, tile)
            if real then
                conns[#conns + 1] = real:GetPropertyChangedSignal("Visible"):Connect(function() paintSlotTag(pg, tile) end)
            end
            conns[#conns + 1] = tile:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() paintSlotTag(pg, tile) end)
        end
    end
    -- the first version of this moved the game's own tags around with guards
    -- that outlived a reload; take those off and put the slots back
    local function undoOldGuards(pg)
        for _, tile in ipairs(slotTiles(pg)) do
            local tags = tile:FindFirstChild("Tags")
            if tags and getconnections then
                for _, c in ipairs(getconnections(tags:GetPropertyChangedSignal("ZIndex"))) do pcall(function() c:Disconnect() end) end
                tags.ZIndex = 1
                for _, f in ipairs(tags:GetChildren()) do
                    if f:IsA("GuiObject") then
                        for _, c in ipairs(getconnections(f:GetPropertyChangedSignal("Visible"))) do pcall(function() c:Disconnect() end) end
                        for _, c in ipairs(getconnections(f:GetPropertyChangedSignal("LayoutOrder"))) do pcall(function() c:Disconnect() end) end
                    end
                end
                local ch = tags:FindFirstChild("Chroma")
                if ch then ch.LayoutOrder = 1 end
                -- (The FX tag and the event badges are left to MM2: forcing them
                -- visible here showed an FX tag and a Christmas year on every
                -- weapon, whatever was equipped.)
            end
        end
    end
    task.spawn(function()
        local pg = LocalPlayer:WaitForChild("PlayerGui", 30)
        if not pg or not gui.Parent then return end
        for _, d in ipairs(pg:GetDescendants()) do watch(d) end
        conns[#conns + 1] = pg.DescendantAdded:Connect(watch)
        pcall(undoOldGuards, pg)
        pcall(watchSlots, pg)
        conns[#conns + 1] = { Disconnect = function()
            for _, tile in ipairs(slotTiles(pg)) do
                local t = tile:FindFirstChild("ChromaBadge")
                if t then t:Destroy() end
                local tags = tile:FindFirstChild("Tags")
                if tags then
                    tags.ZIndex, tags.Position = 1, UDim2.new()
                    local real = tags:FindFirstChild("Chroma")
                    local sz = real and real:GetAttribute("_sz")
                    if sz then
                        local x, y = sz:match("([^,]+),([^,]+)")
                        real.Size = UDim2.fromScale(tonumber(x) or 0.5, tonumber(y) or 0.125)
                        real:SetAttribute("_sz", nil)
                    end
                end
            end
        end }
    end)
end

-- Background so loading the mesh data never delays the window.
task.spawn(function()
    -- The spawner drops this thread to identity 2 (needed to require MM2's
    -- modules); identity 2 can't create instances under gethui(), so restore
    -- whatever we came in with before touching any UI.
    local identity = getthreadidentity and getthreadidentity() or nil
    local ok, res = pcall(initSpawner)

    pcall(function()
        WEAPON_DB = require(game:GetService("ReplicatedStorage").Database.Sync).Weapons
    end)

    if identity and setthreadidentity then pcall(setthreadidentity, identity) end
    if ok and UI.refixPictures then pcall(UI.refixPictures) end
    if not gui.Parent then                      -- closed while loading
        -- the cleanup hook ran before the engine had a destroy, so the engine
        -- (its hooks, poll loop and overlays) is still alive: finish the job
        if ok and type(res) == "table" and res.destroy then pcall(res.destroy) end
        if type(res) == "table" and UI.store.engine == res.tok then UI.store.engine, UI.store.engineDestroy = nil, nil end
        return
    end

    if not ok or not res then
        sfx("error")
        UI.baseCaption = { text = "SKINS FAILED TO LOAD", color = C.error }
        flash("Couldn't load skins: " .. UI.cutText(res, 60), C.error, true)
        UI.setHints({ "Skins failed to load" })
        return
    end
    ENGINE = res
    UI.engine = res
    UI.baseCaption = nil          -- loaded: the caption rests on the usual hint again
    buildGrid()
    -- "Restore my skins on join": once per server, then keep the equipped
    -- pair up to date (you can also equip from MM2's own inventory)
    task.spawn(function()
        pcall(UI.restoreSkins)
        pcall(refreshCounts)
        local last
        while gui.Parent do
            task.wait(5)
            if settings.restoreSkins and ENGINE and ENGINE.equipped then
                local now = tostring(ENGINE.equipped("Knife")) .. "|" .. tostring(ENGINE.equipped("Gun"))
                if now ~= last then last = now; pcall(UI.saveSkins) end
            end
        end
    end)
end)
