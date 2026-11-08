-- The window, which stands on its own: it can open anywhere on saved prices. At an auction house the game's frame has
-- to stay shown (hiding it closes the auction house), so while this window is up the game's panes are hidden through
-- the frame's display mode, and the rest of that frame is invisible and takes no clicks. A tab's parts are built the
-- first time it's picked.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Win = {}
S.Window = Win

-- What the window is doing: "closed"; "saved", open away from an auction house on saved prices; at an auction house,
-- "liveOurs" with this window up and the game's out of sight, or "liveGame" with the game's window up. Open, Close,
-- ToggleSaved, ShowGame and ShowOurs move between them.
Win.mode = "closed"
function Win.IsLive() return Win.mode == "liveOurs" or Win.mode == "liveGame" end

local HST = ns.HST
local W = ns.Widgets
local N = S.Net
local K = S.Kit
local P

local TAB_ORDER = { "shopping", "selling", "auctions", "history", "prices" }
local TAB_NAMES = { shopping = "Shopping", selling = "Selling", auctions = "Auctions", history = "History", prices = "Prices" }
local HEAD = 42
local FOOT = 36
local BAR_SPEED = 5
local BAR_HOLD = 0.6
local NO_PANES = {}
-- Tabs that need an auction house.
local LIVE_ONLY = { selling = true, auctions = true }
local SAVED_STATUS = "Saved prices from your last scan."

local function Modules()
    return { shopping = S.Shopping, selling = S.Selling, auctions = S.Auctions, history = S.History, prices = S.Scan }
end

local function HideGamePanes()
    local game = AuctionHouseFrame
    if game and game.SetDisplayMode then
        game:SetDisplayMode(NO_PANES)
    end
end

-- Sets the bar along the bottom. Text is what's going on right now.
function Win.Status(text)
    if Win.status then Win.status:SetText(text or "") end
end

local function UpdateMoney()
    if Win.money then Win.money:SetText(K.Money(GetMoney(), 13)) end
end

---------------------------------------------------------------------------
-- The bar along the bottom that fills as a scan runs. It only has a frame handler while it's showing.
---------------------------------------------------------------------------
local function MoveScanBar(track, elapsed)
    local now = track.now + (track.goal - track.now) * math.min(1, elapsed * BAR_SPEED)
    if track.goal - now < 0.002 then now = track.goal end
    track.now = now
    local width = math.max(1, math.floor((track:GetWidth() or 1) * now))
    if width ~= track.width then
        track.width = width
        track.bar:SetWidth(width)
    end
    if track.finishing and now >= 1 then
        track.hold = track.hold - elapsed
        if track.hold <= 0 then track:Hide() end
    end
end

local function BuildScanBar(foot)
    local track = CreateFrame("Frame", nil, foot)
    track:SetPoint("BOTTOMLEFT")
    track:SetPoint("BOTTOMRIGHT")
    track:SetHeight(3)
    W.Fill(track, P.wash, "BACKGROUND"):SetAllPoints()
    track.bar = W.Fill(track, P.accent, "ARTWORK")
    track.bar:SetPoint("TOPLEFT")
    track.bar:SetPoint("BOTTOMLEFT")
    track.bar:SetWidth(1)
    track:SetScript("OnUpdate", MoveScanBar)
    track:SetScript("OnHide", function(self) self.finishing = false end)
    track:Hide()
    Win.scanBar = track
end

local function SetScanBar(fraction)
    local track = Win.scanBar
    if not track:IsShown() or track.finishing then
        track.now, track.goal, track.finishing, track.width = 0, 0, false, 1
        track.bar:SetWidth(1)
        track:Show()
    end
    track.goal = math.max(track.goal, fraction)
end

-- A scan finished: the bar fills, stays a moment and goes.
function Win.FinishScanBar()
    local track = Win.scanBar
    if not track:IsShown() then return end
    track.goal, track.finishing, track.hold = 1, true, BAR_HOLD
end

local function PaintAutoScan()
    local p = S.db.profile
    Win.autoScan:SetStyle(p.autoScan and "primary" or nil)
    Win.autoScan.tipText = "Scans when you open the auction house, if the last scan is over "
        .. p.autoScanMinutes .. " minutes old."
end

function Win.UpdateScanLine()
    if not Win.scanLine then return end
    local last = S.Prices.LastScan()
    local running = S.Scan.IsRunning()
    Win.scanButton:SetText(running and "Stop" or "Scan")
    if running then
        SetScanBar(S.Scan.Fraction())
    elseif not Win.scanBar.finishing then
        Win.scanBar:Hide()
    end
    if running then
        Win.scanLine:SetText(S.Scan.ProgressText())
    elseif last and last > 0 then
        local minutes = math.floor((time() - last) / 60)
        if minutes < 1 then
            Win.scanLine:SetText("Scanned just now")
        elseif minutes < 60 then
            Win.scanLine:SetText("Scanned " .. minutes .. K.Plural(minutes, " minute ago", " minutes ago"))
        else
            local hours = math.floor(minutes / 60)
            if hours < 48 then
                Win.scanLine:SetText("Scanned " .. hours .. K.Plural(hours, " hour ago", " hours ago"))
            else
                Win.scanLine:SetText("Scanned " .. math.floor(hours / 24) .. " days ago")
            end
        end
    else
        Win.scanLine:SetText("Not scanned yet")
    end
end

local function PaintTab(b)
    local on = Win.current == b.key
    local off = Win.mode == "saved" and LIVE_ONLY[b.key]
    W.Paint(b.label, off and P.disabled or on and P.accent or b.lit and P.text or P.muted)
    b.mark:SetShown(on)
end

local function BuildTabs(head)
    Win.tabs = {}
    local previous
    for _, key in ipairs(TAB_ORDER) do
        local b = CreateFrame("Button", nil, head)
        b.key = key
        b:SetHeight(HEAD)
        b.label = K.Text(b, "GameFontNormal", P.muted, "CENTER")
        b.label:SetPoint("CENTER")
        b.label:SetText(TAB_NAMES[key])
        b:SetWidth(math.floor(b.label:GetStringWidth() + 28))
        b.mark = W.Fill(b, P.accent, "ARTWORK")
        b.mark:SetPoint("BOTTOMLEFT", 10, 0)
        b.mark:SetPoint("BOTTOMRIGHT", -10, 0)
        b.mark:SetHeight(2)
        b.mark:Hide()
        if previous then b:SetPoint("LEFT", previous, "RIGHT", 2, 0) else b:SetPoint("LEFT", head, "LEFT", 8, 0) end
        previous = b
        b:SetScript("OnClick", function() Win.Select(key) end)
        b:SetScript("OnEnter", function(self) self.lit = true; PaintTab(self) end)
        b:SetScript("OnLeave", function(self) self.lit = false; PaintTab(self) end)
        Win.tabs[key] = b
    end
end

-- What this window hid of the game's frame, to show again.
local hiddenParts = {}

-- Takes the game's frame out of sight and out of the way of clicks. Its panes go first, so only the rest (tabs, border,
-- money, title, close button) is remembered.
local function HideGameFrame()
    local game = AuctionHouseFrame
    HideGamePanes()
    game:SetAlpha(0)
    game:EnableMouse(false)
    for _, child in ipairs({ game:GetChildren() }) do
        if child ~= Win.back and child:IsShown() then
            child:Hide()
            hiddenParts[child] = true
        end
    end
end

local function ShowGameFrame()
    local game = AuctionHouseFrame
    if not game then return end
    for child in pairs(hiddenParts) do child:Show() end
    wipe(hiddenParts)
    game:SetAlpha(1)
    game:EnableMouse(true)
end

-- The game's window back as it was, in a real display mode: this window left it with none.
local function RestoreGame()
    ShowGameFrame()
    if AuctionHouseFrame and AuctionHouseFrameDisplayMode then
        AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
    end
end

-- liveOurs to liveGame.
local function ShowGame()
    if Win.mode ~= "liveOurs" then return end
    Win.mode = "liveGame"
    Win.frame:Hide()
    RestoreGame()
    Win.back:Show()
end

local function TakeOver()
    Win.frame:Show()
    Win.back:Hide()
    HideGameFrame()
end

-- liveGame to liveOurs.
local function ShowOurs()
    if Win.mode ~= "liveGame" then return end
    Win.mode = "liveOurs"
    TakeOver()
end

-- What changes between the live window and saved prices. Only away from an auction house does Escape have to close it
-- by name.
local chromeSaved
local function PaintChrome()
    local offline = Win.mode == "saved"
    if chromeSaved == offline then return end
    chromeSaved = offline
    S.Shopping.ModeChanged()
    Win.gameButton:SetShown(not offline)
    Win.lock:ClearAllPoints()
    Win.lock:SetPoint("RIGHT", offline and Win.settingsButton or Win.gameButton, "LEFT", -2, 0)
    Win.scanButton:SetDisabled(offline)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == Win.frame:GetName() then table.remove(UISpecialFrames, i) end
    end
    if offline then table.insert(UISpecialFrames, Win.frame:GetName()) end
    for _, b in pairs(Win.tabs) do PaintTab(b) end
end

-- Where the window goes: where it was dragged, kept in screen units so a new scale leaves it there, else over the
-- game's frame, or mid-screen away from an auction house.
local function Place()
    local p = S.db.profile
    local f = Win.frame
    f:ClearAllPoints()
    if p.posX and p.posY then
        local scale = f:GetEffectiveScale()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.posX / scale, p.posY / scale)
    elseif Win.mode == "saved" or not AuctionHouseFrame then
        f:SetPoint("CENTER", UIParent, "CENTER")
    else
        f:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 0, 0)
    end
end

local function FitToScreen()
    local p = S.db.profile
    local f = Win.frame
    f:SetScale(p.scale)
    local width = math.min(p.width, (UIParent:GetWidth() or p.width) / p.scale - 30)
    local height = math.min(p.height, (UIParent:GetHeight() or p.height) / p.scale - 60)
    f:SetSize(math.max(900, width), math.max(570, height))
    Place()
end

local function StartDrag()
    if S.db.profile.locked or Win.dragging then return end
    Win.dragging = true
    Win.frame:StartMoving()
end

local function StopDrag()
    if not Win.dragging then return end
    Win.dragging = false
    local f = Win.frame
    f:StopMovingOrSizing()
    -- The saved position is this tweak's, not the game's layout file.
    f:SetUserPlaced(false)
    local p = S.db.profile
    local scale = f:GetEffectiveScale()
    p.posX, p.posY = f:GetLeft() * scale, f:GetTop() * scale
    Place()
end

local function Draggable(bar)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", StartDrag)
    bar:SetScript("OnDragStop", StopDrag)
end

local function PaintLock()
    if not Win.lock then return end
    local locked = S.db.profile.locked
    Win.lock:ShowIcon(locked and 1 or 2)
    Win.lock.tipTitle = locked and "Unlock the window" or "Lock the window"
end

function Win.ResetPosition()
    local p = S.db.profile
    p.posX, p.posY = nil, nil
    if Win.frame then Place() end
end

local function Build()
    P = K.Palette()
    local f = CreateFrame("Frame", "HSTSuperAuctionHouse", UIParent)
    Win.frame = f
    f:Hide()
    -- Over the game's panels, under its popups and menus.
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function() end)
    W.Fill(f, P.window):SetAllPoints()
    W.Border(f, P.border)

    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(HEAD)
    Draggable(head)
    W.Fill(head, P.titlebar, "BACKGROUND", 1):SetAllPoints()
    local rule = W.Fill(head, P.border, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    BuildTabs(head)

    local close = K.HeadClose(head)
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function()
        if Win.mode == "saved" then f:Hide() else HideUIPanel(AuctionHouseFrame) end
    end)
    local settings = K.HeadButton(head, { W.ART .. "Cog" })
    settings.tipTitle = "Settings"
    Win.settingsButton = settings
    settings:SetPoint("RIGHT", close, "LEFT", -2, 0)
    settings:SetScript("OnClick", function() HST:OpenSettings("SuperAuctionHouse") end)
    Win.gameButton = K.Button(head, "Game's window", "ghost")
    Win.gameButton:Fit(40)
    Win.gameButton:SetPoint("RIGHT", settings, "LEFT", -2, 0)
    Win.gameButton:SetScript("OnClick", ShowGame)
    Win.lock = K.HeadButton(head, { W.ART .. "Lock", W.ART .. "Unlock" })
    Win.lock:SetPoint("RIGHT", Win.gameButton, "LEFT", -2, 0)
    Win.lock:SetScript("OnClick", function()
        local p = S.db.profile
        p.locked = not p.locked
        PaintLock()
        W.ShowTooltip(Win.lock, Win.lock.tipTitle, nil, "ANCHOR_BOTTOM")
        HST:RefreshSettings()
    end)
    PaintLock()
    Win.money = K.Text(head, "GameFontHighlight", P.bright, "RIGHT")
    Win.money:SetPoint("RIGHT", Win.lock, "LEFT", -8, 0)

    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(FOOT)
    Draggable(foot)
    W.Fill(foot, P.titlebar, "BACKGROUND", 1):SetAllPoints()
    local footRule = W.Fill(foot, P.border, "ARTWORK")
    footRule:SetPoint("TOPLEFT")
    footRule:SetPoint("TOPRIGHT")
    footRule:SetHeight(1)
    Win.status = K.Text(foot, "GameFontHighlightSmall", P.text)
    Win.status:SetPoint("LEFT", 12, 0)
    Win.status:SetPoint("RIGHT", -360, 0)
    Win.status:SetWordWrap(false)
    Win.scanButton = K.Button(foot, "Scan", "primary")
    Win.scanButton:SetWidth(62)
    Win.scanButton:SetPoint("RIGHT", -12, 0)
    Win.scanButton:SetScript("OnClick", function()
        if S.Scan.IsRunning() then S.Scan.Stop() else S.Scan.Start() end
    end)
    Win.autoScan = K.Button(foot, "Auto-scan")
    Win.autoScan:Fit(76)
    Win.autoScan:SetPoint("RIGHT", Win.scanButton, "LEFT", -6, 0)
    Win.autoScan:SetScript("OnClick", function()
        local p = S.db.profile
        p.autoScan = not p.autoScan
        PaintAutoScan()
        HST:RefreshSettings()
    end)
    PaintAutoScan()
    Win.scanLine = K.Text(foot, "GameFontHighlightSmall", P.muted, "RIGHT")
    Win.scanLine:SetPoint("RIGHT", Win.autoScan, "LEFT", -12, 0)
    BuildScanBar(foot)

    Win.body = CreateFrame("Frame", nil, f)
    Win.body:SetPoint("TOPLEFT", 1, -HEAD - 1)
    Win.body:SetPoint("BOTTOMRIGHT", -1, FOOT + 1)

    FitToScreen()
    N.On("PLAYER_MONEY", UpdateMoney)
    -- Shift-clicking an item with no chat line open searches for it.
    local function linked(text)
        if not f:IsShown() or not text then return end
        if ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow() then return end
        if Win.current == "shopping" and S.Shopping.frame then S.Shopping.FromLink(text) end
    end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", linked)
    elseif ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", linked)
    end
    S.Selling.InstallBagShortcut()
    f:SetScript("OnHide", function()
        -- Closed by its button or Escape.
        if Win.mode == "saved" then Win.mode = "closed" end
        StopDrag()
        local module = Modules()[Win.current]
        if module and module.OnHide then module.OnHide() end
        K.CloseDialog()
    end)
    f:SetScript("OnShow", function()
        local module = Modules()[Win.current]
        if module and module.OnShow then module.OnShow() end
        UpdateMoney()
        Win.UpdateScanLine()
    end)
end

-- What ties the window to the game's frame, the first time an auction house opens. That frame doesn't exist before then.
local function HookGame()
    if Win.back then return end
    local game = AuctionHouseFrame
    -- On the game's window: the way back. After the game's last tab along the bottom.
    local back = K.Button(game, "Super Auction House", "primary")
    back:Fit(140)
    back:SetFrameLevel(game:GetFrameLevel() + 20)
    local tabs = game.Tabs
    if tabs and tabs[#tabs] then
        back:SetPoint("LEFT", tabs[#tabs], "RIGHT", 8, 0)
    else
        back:SetPoint("TOPLEFT", game, "BOTTOMLEFT", 300, -2)
    end
    back:SetScript("OnClick", ShowOurs)
    back:Hide()
    Win.back = back
    -- The game sets its panes as its frame shows, which can come after this tweak's handler for the same event.
    game:HookScript("OnShow", function() if Win.mode == "liveOurs" then HideGameFrame() end end)
    -- A right-click on an item in your bags goes to the game's frame: bring it to the Selling tab instead.
    hooksecurefunc(game, "SetPostItem", function(self, location)
        if Win.mode ~= "liveOurs" then return end
        self:ClearPostItem()
        HideGamePanes()
        Win.Select("selling")
        S.Selling.SelectLocation(location)
    end)
end

function Win.Select(key)
    if not TAB_NAMES[key] then key = "shopping" end
    if Win.mode == "closed" then return end
    if Win.mode == "saved" and LIVE_ONLY[key] then return Win.Status("This tab needs an auction house.") end
    local modules = Modules()
    if Win.current and Win.current ~= key then
        local leaving = modules[Win.current]
        if leaving.frame then leaving.frame:Hide() end
        if leaving.OnHide then leaving.OnHide() end
    end
    if Win.mode == "liveGame" then ShowOurs() end
    Win.current = key
    S.db.profile.lastTab = key
    local module = modules[key]
    if not module.frame then
        module.frame = CreateFrame("Frame", nil, Win.body)
        module.frame:SetAllPoints()
        module.Build(module.frame)
    end
    module.frame:Show()
    for _, b in pairs(Win.tabs) do PaintTab(b) end
    Win.Status(Win.mode == "saved" and SAVED_STATUS or "")
    if module.OnShow then module.OnShow() end
end

-- Away from an auction house: closed to saved, or saved to closed.
function Win.ToggleSaved()
    if not Win.frame then Build() end
    local f = Win.frame
    if Win.mode == "saved" then return f:Hide() end
    if Win.mode ~= "closed" then return end
    Win.mode = "saved"
    PaintChrome()
    FitToScreen()
    if Win.current and LIVE_ONLY[Win.current] then
        local leaving = Modules()[Win.current]
        if leaving.frame then leaving.frame:Hide() end
        Win.current = nil
    end
    f:Show()
    Win.Select(Win.current or "shopping")
    S.Prices.FillNames()
end

-- An auction house opened: closed or saved to liveOurs, or to liveGame when that's what opens.
function Win.Open()
    if not Win.frame then Build() end
    HookGame()
    -- Up on saved prices, the window is now the live one.
    local openOn = S.db.profile.openOn
    Win.mode = openOn == "game" and "liveGame" or "liveOurs"
    PaintChrome()
    FitToScreen()
    if openOn == "game" then
        Win.frame:Hide()
        ShowGameFrame()
        Win.back:Show()
        return
    end
    if openOn == "last" then openOn = S.db.profile.lastTab end
    TakeOver()
    Win.Select(openOn)
    UpdateMoney()
    Win.UpdateScanLine()
end

-- The auction house closed, or the tweak turned off with it open (turnedOff), when the game's window is what's left.
function Win.Close(turnedOff)
    S.Search.Stop()
    Win.mode = "closed"
    if Win.frame then
        K.CloseDialog()
        Win.scanBar:Hide()
        if Win.back then Win.back:Hide() end
        Win.frame:Hide()
        if turnedOff then RestoreGame() else ShowGameFrame() end
    end
    if S.Selling.frame then S.Selling.OnClosed() end
    if S.Auctions.frame then S.Auctions.OnClosed() end
    if S.Buy.frame then S.Buy.OnClosed() end
end

-- Settings changed while the window exists.
function Win.Apply()
    FitToScreen()
    PaintLock()
    PaintAutoScan()
    if S.Selling.frame then S.Selling.Apply() end
    if S.Shopping.frame then S.Shopping.Apply() end
end
