-- The Shopping tab: a search box with filters, the results, and beside them shopping lists, recent searches and the
-- game's categories. A click on a result opens the buy screen. Lists are shared by all your characters, except temporary
-- ones, which last until you log out or keep them.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Sh = {}
S.Shopping = Sh

local W = ns.Widgets
local K = S.Kit
local T = S.Terms
local P

local RECENT_LIMIT = 30
local AUTOCOMPLETE_ROWS = 8
local AUTOCOMPLETE_OWN = 3
local AUTOCOMPLETE_MIN = 2
local SIDE_WIDTH = 250

local selected, expanded = nil, {}
local category -- the chosen category, as a path like "Armor/Plate/Feet"

local function Lists() return S.db.global.lists end
local function Recents() return S.db.global.recents end
local function Status(text) S.Window.Status(text) end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------
local function FindList(name)
    for i, list in ipairs(Lists()) do
        if list.name == name then return list, i end
    end
end
Sh.FindList = FindList

local function SortLists()
    table.sort(Lists(), function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
end

local function CreateList(name, terms, temporary)
    local list = FindList(name)
    if list then
        if terms then list.terms = terms end
        return list
    end
    list = { name = name, terms = terms or {}, temporary = temporary or nil }
    table.insert(Lists(), list)
    SortLists()
    return list
end
Sh.CreateList = CreateList

local function DeleteList(list)
    local lists = Lists()
    for i = #lists, 1, -1 do
        if lists[i] == list then table.remove(lists, i) end
    end
    if selected == list then selected = nil end
    expanded[list] = nil
end
Sh.DeleteList = DeleteList

local function AddRecent(text)
    if text == "" then return end
    local recents = Recents()
    for i = #recents, 1, -1 do if recents[i] == text then table.remove(recents, i) end end
    table.insert(recents, 1, text)
    while #recents > RECENT_LIMIT do recents[#recents] = nil end
end

---------------------------------------------------------------------------
-- The side panel
---------------------------------------------------------------------------
-- The game's categories as a tree, open along the chosen one's branch as the game's own list is.
local function AddCategories(entries, categories, up, depth)
    for _, c in ipairs(categories) do
        local path = up and (up .. "/" .. c.name) or c.name
        local wowToken = c.flags and c.flags.WOW_TOKEN_FLAG
        if not wowToken and (c.filters or c.subCategories) then
            entries[#entries + 1] = { kind = "category", path = path, up = up, name = c.name, depth = depth,
                searches = c.filters ~= nil, parent = c.subCategories ~= nil }
            if c.subCategories and category and (category == path or category:sub(1, #path + 1) == path .. "/") then
                AddCategories(entries, c.subCategories, path, depth + 1)
            end
        end
    end
end

local function SideEntries()
    local entries = {}
    if S.db.profile.shoppingView == "categories" then
        -- Saved prices don't hold an item's category, so there's nothing to search by away from an auction house.
        if S.Window.IsLive() and AuctionCategories then AddCategories(entries, AuctionCategories, nil, 0) end
    elseif S.db.profile.shoppingView == "recents" then
        for i, text in ipairs(Recents()) do
            entries[i] = { kind = "recent", text = text, name = T.Pretty(text) }
        end
    else
        for _, list in ipairs(Lists()) do
            entries[#entries + 1] = { kind = "list", list = list,
                name = list.temporary and (list.name .. " (temporary)") or list.name, count = #list.terms }
            if expanded[list] then
                for i, text in ipairs(list.terms) do
                    entries[#entries + 1] = { kind = "term", list = list, index = i, text = text, name = T.Pretty(text) }
                end
            end
        end
    end
    return entries
end

local function RefreshSide()
    if not Sh.side then return end
    local needsHouse = S.db.profile.shoppingView == "categories" and not S.Window.IsLive()
    Sh.side.emptyText:SetText(needsHouse and "Categories need an auction house." or "Nothing here yet.")
    Sh.side:SetEntries(SideEntries(), true)
end
Sh.RefreshSide = RefreshSide

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
local function PaintSearchButton()
    if Sh.searchButton then Sh.searchButton:SetText(S.Search.IsRunning() and "Stop" or "Search") end
end

local function ResultsChanged()
    Sh.results:SetEntries(Sh.entries, true)
end

-- While results arrive: drawn and sorted a few times a second, however many came.
local resultsQueued
local function DrawQueued()
    resultsQueued = false
    ResultsChanged()
end
local function ResultsSoon()
    if resultsQueued then return end
    resultsQueued = true
    C_Timer.After(0.1, DrawQueued)
end

local function Finished(run)
    PaintSearchButton()
    Sh.progress:SetProgress(nil)
    Sh.results:SetLoading(false)
    Sh.entries = run.results
    -- Counted before the rows for what wasn't found join them.
    local count = #run.results
    if S.db.profile.missingTerms then
        for _, text in ipairs(run.missing) do
            Sh.entries[#Sh.entries + 1] = { name = T.Pretty(text), missing = true, term = text, keyString = "?" .. text }
        end
    end
    ResultsChanged()
    Status(count .. K.Plural(count, " result", " results"))
end

---------------------------------------------------------------------------
-- Away from an auction house: results come from saved prices
---------------------------------------------------------------------------
local SAVED_LIMIT = 500

local function SavedEntry(key, name, quality)
    local price = S.Prices.Get(key)
    if not price then return nil end
    local days = S.Prices.ReadHistory(key)
    return { saved = true, key = key, keyString = tostring(key), name = name, quality = quality, price = price,
        icon = S.Prices.IconOf(key), available = days[1] and days[1].available, age = S.Prices.Age(key),
        link = type(key) == "number" and ("item:" .. key) or nil }
end

-- Item level, category and crafted level aren't saved with a price, so those parts of a term don't narrow it here.
local function SavedMatches(term, entry)
    if term.exact and entry.name:lower() ~= (term.query or ""):lower() then return false end
    if term.minGold and entry.price < term.minGold * 10000 then return false end
    if term.maxGold and entry.price > term.maxGold * 10000 then return false end
    if term.quality and entry.quality ~= term.quality then return false end
    return true
end

local function RunSaved(terms)
    local entries, seen = {}, {}
    for _, text in ipairs(terms) do
        local term = T.Parse(text)
        if term.query ~= "" then
            for _, key in ipairs(S.Prices.FindNames(term.query, SAVED_LIMIT)) do
                if not seen[key] then
                    local name, quality = S.Prices.NameOf(key)
                    local entry = SavedEntry(key, name, quality)
                    if entry and SavedMatches(term, entry) then
                        seen[key] = true
                        entries[#entries + 1] = entry
                    end
                end
            end
        end
    end
    Sh.entries = entries
    ResultsChanged()
    Status(#entries .. K.Plural(#entries, " saved price", " saved prices"))
end

-- Runs a list of terms. Results replace what's showing, and the buy screen closes.
function Sh.Run(terms)
    if #terms == 0 then return end
    if S.Window.mode == "saved" then return RunSaved(terms) end
    if S.Scan.HoldsBrowse() then S.Scan.Stop() end
    if S.Buy.IsOpen() then S.Buy.Close() end
    Sh.entries = {}
    Sh.results:SetLoading(true)
    Sh.results:SetEntries(Sh.entries)
    Sh.progress:SetProgress(0.03)
    Status("Searching.")
    S.Search.Start(terms, {
        onResults = function(run)
            Sh.entries = run.results
            ResultsSoon()
        end,
        onProgress = function(done, total)
            Sh.progress:SetProgress(done / total)
            if total > 1 then Status("Searching, " .. done .. " of " .. total) end
        end,
        onDone = Finished,
        onStop = function(run)
            PaintSearchButton()
            Sh.progress:SetProgress(nil)
            Sh.results:SetLoading(false)
            Sh.entries = run.results
            ResultsChanged()
            Status("Stopped.")
        end,
    })
    PaintSearchButton()
end

local function AskForText()
    Sh.box.edit:SetFocus()
    Status("Type an item name first.")
end

-- Searches for what's in the box. While the Categories view shows a chosen category, the search stays inside it, and
-- an empty box finds everything there. exact: the box holds one item's name, so the category is let go.
local function SearchBox(exact)
    local typed = Sh.box:GetText()
    if exact and category then
        category = nil
        RefreshSide()
    end
    local text = typed
    if category and S.db.profile.shoppingView == "categories" and S.Window.IsLive() then
        local term = T.Parse(typed)
        term.category = category
        text = T.Compose(term)
    elseif typed == "" then
        return AskForText()
    end
    if typed ~= "" then
        AddRecent(text)
        if S.db.profile.shoppingView == "recents" then RefreshSide() end
    end
    Sh.Run({ text })
end

local function SearchList(list)
    selected = list
    expanded[list] = true
    RefreshSide()
    if #list.terms > 0 then Sh.Run(list.terms) end
end
Sh.SearchList = SearchList

-- Shift-clicking an item fills the box and searches.
function Sh.FromLink(link)
    local name = link:match("%[(.+)%]")
    if not name then return end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    Sh.box:SetText(name)
    SearchBox(true)
end

---------------------------------------------------------------------------
-- Add to a list, rename, import and export
---------------------------------------------------------------------------
local function AskName(title, current, done)
    K.Dialog({ title = title, input = true, inputText = current or "", confirm = "Save",
        onConfirm = function(_, text)
            text = strtrim(text or "")
            if text ~= "" then done(text) end
        end })
end

local function NewListWith(term)
    AskName("New list", nil, function(name)
        local list = CreateList(name)
        if term then table.insert(list.terms, term) end
        SortLists()
        selected = list
        expanded[list] = true
        RefreshSide()
    end)
end

local function AddToListMenu(owner, term)
    K.Menu(owner, function(root)
        for _, list in ipairs(Lists()) do
            root:CreateButton(list.name, function()
                table.insert(list.terms, term)
                expanded[list] = true
                RefreshSide()
                Status(T.Pretty(term) .. " added to " .. list.name .. ".")
            end)
        end
        root:CreateButton("New list", function() NewListWith(term) end)
    end)
end

local function ExportText(lists)
    local lines = {}
    for _, list in ipairs(lists) do
        lines[#lines + 1] = list.name .. "^" .. table.concat(list.terms, "^")
    end
    return table.concat(lines, "\n")
end

local function ShowExport(lists)
    if #lists == 0 then return Status("No lists to export.") end
    K.Dialog({ title = "Copy this text", multiline = true, inputText = ExportText(lists), focus = true, wide = true,
        confirm = "Close", hideCancel = true })
end

-- Reads text in three shapes: "name^term^term" lines, "**name" lines followed by a term per line, and group strings of
-- "i:itemID" and "p:speciesID" parts, which become a temporary list once their names are known.
local NAME_TRIES, NAME_GAP = 10, 0.5 -- an item's name can take a moment to load
local function PetName(speciesID)
    return C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID and (C_PetJournal.GetPetInfoBySpeciesID(speciesID)) or nil
end
local function ImportGroupString(text)
    local items, pets = {}, {}
    for itemID in text:gmatch("i:(%d+)") do items[#items + 1] = tonumber(itemID) end
    for speciesID in text:gmatch("p:(%d+)") do pets[#pets + 1] = tonumber(speciesID) end
    if #items == 0 and #pets == 0 then return false end
    local list = CreateList("Imported", nil, true)
    for _, id in ipairs(pets) do
        local name = PetName(id)
        if name then table.insert(list.terms, '"' .. name .. '"') end
    end
    local waiting, lost = #items, 0
    local function finished()
        RefreshSide()
        if lost > 0 then Status(lost .. K.Plural(lost, " item's name didn't load.", " items' names didn't load.")) end
    end
    local function addName(id, tries)
        local name = C_Item.GetItemNameByID(id)
        if not name and tries > 0 then
            return C_Timer.After(NAME_GAP, function() addName(id, tries - 1) end)
        end
        if name then table.insert(list.terms, '"' .. name .. '"') else lost = lost + 1 end
        waiting = waiting - 1
        if waiting <= 0 then finished() end
    end
    for _, id in ipairs(items) do
        if not C_Item.GetItemNameByID(id) then C_Item.RequestLoadItemDataByID(id) end
        addName(id, NAME_TRIES)
    end
    if #items == 0 then finished() end
    expanded[list] = true
    return true
end

function Sh.Import(text)
    text = (text or ""):gsub("\r", "")
    local imported = 0
    if text:find("^%s*[ip]:%d+") or text:find("^%s*group:") then
        if ImportGroupString(text) then imported = 1 end
    elseif text:find("^%s*%*%*") then
        local list
        for line in (text .. "\n"):gmatch("(.-)\n") do
            local name = line:match("^%*%*(.+)$")
            if name then
                list = CreateList(strtrim(name), {})
                imported = imported + 1
            elseif list and strtrim(line) ~= "" then
                table.insert(list.terms, strtrim(line))
            end
        end
    else
        for line in (text .. "\n"):gmatch("(.-)\n") do
            if strtrim(line) ~= "" then
                local parts = { strsplit("^", line) }
                local name = table.remove(parts, 1)
                local terms = {}
                for _, part in ipairs(parts) do if part ~= "" then terms[#terms + 1] = part end end
                CreateList(strtrim(name), terms)
                imported = imported + 1
            end
        end
    end
    SortLists()
    RefreshSide()
    Status(imported .. K.Plural(imported, " list imported.", " lists imported."))
    return imported
end

local function ShowImport()
    K.Dialog({ title = "Paste lists to import", multiline = true, inputText = "", focus = true, wide = true, confirm = "Import",
        onConfirm = function(_, text) Sh.Import(text) end })
end

local function ShowCsv()
    -- In the order the table shows them.
    local shown = Sh.results.entries
    if #shown == 0 then return Status("No results to export.") end
    local lines = { "Name,Item level,Price,Available,Yours" }
    for _, e in ipairs(shown) do
        if not e.missing then
            lines[#lines + 1] = string.format('"%s",%d,%d,%d,%s', (e.name or ""):gsub('"', '""'), e.level or 0, e.price or 0,
                e.available or 0, e.owned and "yes" or "no")
        end
    end
    K.Dialog({ title = "Copy this text", multiline = true, inputText = table.concat(lines, "\n"), focus = true, wide = true,
        confirm = "Close", hideCancel = true })
end

---------------------------------------------------------------------------
-- Side panel clicks
---------------------------------------------------------------------------
local function MoveInList(list, from, to)
    if to < 1 or to > #list.terms then return end
    local term = table.remove(list.terms, from)
    table.insert(list.terms, to, term)
    RefreshSide()
end

local function ListMenu(owner, list)
    K.Menu(owner, function(root)
        root:CreateButton("Search", function() SearchList(list) end)
        root:CreateButton("Rename", function()
            AskName("Rename list", list.name, function(name)
                local other = FindList(name)
                if other and other ~= list then return Status("There's already a list called " .. name .. ".") end
                list.name = name
                SortLists()
                RefreshSide()
            end)
        end)
        if list.temporary then
            root:CreateButton("Keep this list", function() list.temporary = nil; RefreshSide() end)
        end
        root:CreateButton("Export", function() ShowExport({ list }) end)
        root:CreateButton("Delete", function()
            K.Dialog({ title = "Delete " .. list.name .. "?", confirm = "Delete", onConfirm = function()
                DeleteList(list)
                RefreshSide()
            end })
        end)
    end)
end

local function TermMenu(owner, list, index, text)
    K.Menu(owner, function(root)
        root:CreateButton("Search", function() Sh.Run({ text }) end)
        root:CreateButton("Edit", function() Sh.OpenFilters(text, list, index) end)
        root:CreateButton("Move up", function() MoveInList(list, index, index - 1) end)
        root:CreateButton("Move down", function() MoveInList(list, index, index + 1) end)
        root:CreateButton("Delete", function()
            table.remove(list.terms, index)
            RefreshSide()
        end)
    end)
end

local function RecentMenu(owner, text)
    K.Menu(owner, function(root)
        root:CreateButton("Search", function()
            Sh.box:SetText(text)
            Sh.Run({ text })
        end)
        root:CreateButton("Add to list", function() AddToListMenu(owner, text) end)
        root:CreateButton("Delete", function()
            local recents = Recents()
            for i = #recents, 1, -1 do if recents[i] == text then table.remove(recents, i) end end
            RefreshSide()
        end)
    end)
end

local function CategoryMenu(owner, path)
    local text = T.Compose({ category = path })
    K.Menu(owner, function(root)
        root:CreateButton("Search", function() Sh.Run({ text }) end)
        root:CreateButton("Add to list", function() AddToListMenu(owner, text) end)
    end)
end

local function SideClick(e, button, row)
    if e.kind == "category" then
        if button == "RightButton" then
            if e.searches then CategoryMenu(row, e.path) end
            return
        end
        -- A click chooses a category and opens it; a click on the chosen one goes back to the one above. One with
        -- nothing under it is searched at once, and the rest wait for Search: all of Armor is a long search.
        local chosen = category ~= e.path
        category = chosen and e.path or e.up
        RefreshSide()
        if chosen and e.searches and not e.parent then SearchBox() end
    elseif e.kind == "list" then
        if button == "RightButton" then return ListMenu(row, e.list) end
        local wasSelected = selected == e.list
        selected = e.list
        if wasSelected or not S.db.profile.autoListSearch then
            expanded[e.list] = not expanded[e.list] or nil
            RefreshSide()
        else
            SearchList(e.list)
        end
    elseif e.kind == "term" then
        if button == "RightButton" then return TermMenu(row, e.list, e.index, e.text) end
        Sh.box:SetText(e.text)
        Sh.Run({ e.text })
    else
        if button == "RightButton" then return RecentMenu(row, e.text) end
        Sh.box:SetText(e.text)
        Sh.Run({ e.text })
    end
end

---------------------------------------------------------------------------
-- Autocomplete
---------------------------------------------------------------------------
-- Your own searches that start with the text, then items whose names hold it. A suggestion searches for exactly that item.
local function Suggestions(text)
    local found, seen = {}, {}
    local prefix = text:lower()
    local function consider(term)
        if #found < AUTOCOMPLETE_OWN and not seen[term] and term:lower():sub(1, #prefix) == prefix then
            seen[term] = true
            found[#found + 1] = { value = term, label = T.Pretty(term) }
        end
    end
    for _, term in ipairs(Recents()) do consider(term) end
    for _, list in ipairs(Lists()) do
        for _, term in ipairs(list.terms) do consider(term) end
    end
    if #text >= AUTOCOMPLETE_MIN then
        for _, key in ipairs(S.Prices.FindNames(text, AUTOCOMPLETE_ROWS)) do
            if #found >= AUTOCOMPLETE_ROWS then break end
            local name, quality = S.Prices.NameOf(key)
            local term = '"' .. name .. '"'
            if not seen[term] then
                seen[term] = true
                found[#found + 1] = { value = term, label = K.QualityCode(quality) .. name .. "|r", icon = S.Prices.IconOf(key),
                    price = S.Prices.Get(key) }
            end
        end
    end
    return found
end

local function PaintSuggestion()
    local flyout = Sh.flyout
    for i, row in ipairs(flyout.rows) do row.tint:SetShown(i == flyout.at or row.over) end
end

local function ShowSuggestions(text)
    local flyout = Sh.flyout
    local found = text ~= "" and Suggestions(text) or {}
    flyout.at = nil
    flyout.count = #found
    if #found == 0 or (#found == 1 and found[1].value == text) then return flyout:Hide() end
    for i, row in ipairs(flyout.rows) do
        local item = found[i]
        row.value = item and item.value
        row:SetShown(item ~= nil)
        if item then
            row.label:SetText(item.label)
            row.icon:SetTexture(item.icon)
            row.icon:SetShown(item.icon ~= nil)
            row.price:SetMoney(item.price)
        end
    end
    PaintSuggestion()
    flyout:SetHeight(#found * 24 + 6)
    flyout:Show()
end

local function ChooseSuggestion(row)
    Sh.box:SetText(row.value)
    Sh.flyout:Hide()
    Sh.box.edit:ClearFocus()
    SearchBox(true)
end

-- Up and down walk the suggestions; Enter takes the one lit.
local function MoveSuggestion(direction)
    local flyout = Sh.flyout
    if not flyout:IsShown() or flyout.count == 0 then return end
    local at = (flyout.at or (direction > 0 and 0 or flyout.count + 1)) + direction
    if at < 1 then at = flyout.count elseif at > flyout.count then at = 1 end
    flyout.at = at
    PaintSuggestion()
end

local function BuildFlyout()
    local flyout = CreateFrame("Frame", nil, Sh.frame)
    flyout:SetFrameLevel(Sh.frame:GetFrameLevel() + 30)
    flyout:SetPoint("TOPLEFT", Sh.box, "BOTTOMLEFT", 0, -2)
    flyout:SetPoint("TOPRIGHT", Sh.box, "BOTTOMRIGHT", 0, -2)
    K.Box(flyout, P.card, P.line)
    flyout.rows = {}
    for i = 1, AUTOCOMPLETE_ROWS do
        local row = CreateFrame("Button", nil, flyout)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * 24)
        row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * 24)
        row.tint = W.Tint(row, P.hover, K.TINT)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 5, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.price = W.MoneyText(row, "GameFontHighlightSmall", P.text)
        row.price:SetPoint("RIGHT", -8, 0)
        row.label = K.Text(row, "GameFontHighlight", P.text)
        row.label:SetPoint("LEFT", 28, 0)
        row.label:SetPoint("RIGHT", row.price, "LEFT", -8, 0)
        row.label:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self.over = true; PaintSuggestion() end)
        row:SetScript("OnLeave", function(self) self.over = false; PaintSuggestion() end)
        row:SetScript("OnClick", ChooseSuggestion)
        flyout.rows[i] = row
    end
    flyout:Hide()
    Sh.flyout = flyout
end

---------------------------------------------------------------------------
-- Filters: every part of a term
---------------------------------------------------------------------------
local QUALITY_VALUES, QUALITY_ORDER = { [""] = "Any" }, { "" }
for q = 0, 6 do
    QUALITY_VALUES[q] = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
    QUALITY_ORDER[#QUALITY_ORDER + 1] = q
end

local function ExpansionEntries()
    local values, order = { [""] = "Any" }, { "" }
    for i = 0, (LE_EXPANSION_LEVEL_CURRENT or 0) do
        local name = _G["EXPANSION_NAME" .. i]
        if name then
            values[i] = name
            order[#order + 1] = i
        end
    end
    return values, order
end

local function CategoryEntries()
    local values, order = { [""] = "Any" }, { "" }
    for _, path in ipairs((T.Categories())) do
        values[path] = path
        order[#order + 1] = path
    end
    return values, order
end

local RANGES = {
    { "minItemLevel", "maxItemLevel", "Item level" }, { "minLevel", "maxLevel", "Required level" },
    { "minCrafted", "maxCrafted", "Crafted level" }, { "minGold", "maxGold", "Price (gold)" },
}

local function BuildFilters()
    local v = CreateFrame("Frame", nil, S.Window.frame)
    v:SetAllPoints()
    v:SetFrameLevel(S.Window.frame:GetFrameLevel() + 50)
    v:EnableMouse(true)
    W.Fill(v, P.veil, "BACKGROUND"):SetAllPoints()
    local card = CreateFrame("Frame", nil, v)
    card:SetSize(460, 438)
    card:SetPoint("CENTER")
    K.Box(card, P.window, P.line)
    local title = K.Text(card, "GameFontNormal", P.title)
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Filters")
    local y = -40
    local function caption(text)
        local c = K.Text(card, "GameFontHighlightSmall", P.muted)
        c:SetPoint("TOPLEFT", 16, y - 5)
        c:SetWidth(118)
        c:SetText(text)
        return c
    end
    local draft = {}
    v.draft = draft
    caption("Name")
    v.query = K.Input(card, {})
    v.query:SetPoint("TOPLEFT", 134, y)
    v.query:SetPoint("RIGHT", -16, 0)
    y = y - 30
    caption("Match whole name")
    v.exact = W.Switch(card)
    v.exact:SetPoint("TOPLEFT", 134, y - 2)
    v.exact.onClick = function(on)
        v.exactOn = on
        v.exact:SetOn(on, true)
    end
    y = y - 30
    caption("Category")
    v.category = K.Select(card, CategoryEntries, function() return draft.category or "" end,
        function(key) draft.category = key ~= "" and key or nil end)
    v.category:SetPoint("TOPLEFT", 134, y)
    v.category:SetPoint("RIGHT", -16, 0)
    y = y - 30
    v.ranges = {}
    for _, range in ipairs(RANGES) do
        caption(range[3])
        local low = K.Input(card, { numeric = true, placeholder = "From", width = 100 })
        low:SetPoint("TOPLEFT", 134, y)
        local high = K.Input(card, { numeric = true, placeholder = "To", width = 100 })
        high:SetPoint("LEFT", low, "RIGHT", 8, 0)
        v.ranges[range[1]], v.ranges[range[2]] = low, high
        y = y - 30
    end
    caption("Quality")
    v.quality = K.Select(card, function() return QUALITY_VALUES, QUALITY_ORDER end,
        function() return draft.quality or "" end, function(key) draft.quality = key ~= "" and key or nil end)
    v.quality:SetPoint("TOPLEFT", 134, y)
    v.quality:SetPoint("RIGHT", -16, 0)
    y = y - 30
    caption("Expansion")
    v.expansion = K.Select(card, ExpansionEntries, function() return draft.expansion or "" end,
        function(key) draft.expansion = key ~= "" and key or nil end)
    v.expansion:SetPoint("TOPLEFT", 134, y)
    v.expansion:SetPoint("RIGHT", -16, 0)
    y = y - 30
    caption("Quantity to buy")
    v.quantity = K.Input(card, { numeric = true, width = 100 })
    v.quantity:SetPoint("TOPLEFT", 134, y)

    local function compose()
        local term = {}
        term.query = strtrim(v.query:GetText())
        term.exact = v.exactOn
        term.category, term.quality, term.expansion = draft.category, draft.quality, draft.expansion
        for key, input in pairs(v.ranges) do
            local number = tonumber(input:GetText())
            if number then term[key] = number end
        end
        local quantity = tonumber(v.quantity:GetText())
        if quantity and quantity > 0 then term.quantity = quantity end
        term.tier = draft.tier
        return T.Compose(term)
    end
    local go = K.Button(card, "Search", "primary")
    go:SetWidth(90)
    go:SetPoint("BOTTOMRIGHT", -16, 14)
    go:SetScript("OnClick", function()
        local text = compose()
        if v.editList then
            v.editList.terms[v.editIndex] = text
            v.editList = nil
            RefreshSide()
        end
        v:Hide()
        Sh.box:SetText(text)
        SearchBox()
    end)
    local add = K.Button(card, "Add to list")
    add:Fit(90)
    add:SetPoint("RIGHT", go, "LEFT", -6, 0)
    add:SetScript("OnClick", function(self)
        local text = compose()
        if v.editList then
            v.editList.terms[v.editIndex] = text
            v.editList = nil
            RefreshSide()
            v:Hide()
        else
            AddToListMenu(self, text)
        end
    end)
    v.add = add
    local cancel = K.Button(card, "Cancel")
    cancel:SetWidth(70)
    cancel:SetPoint("BOTTOMLEFT", 16, 14)
    cancel:SetScript("OnClick", function() v.editList = nil; v:Hide() end)
    local clear = K.Button(card, "Clear")
    clear:SetWidth(70)
    clear:SetPoint("LEFT", cancel, "RIGHT", 6, 0)
    clear:SetScript("OnClick", function() Sh.FillFilters("") end)
    v:Hide()
    Sh.filters = v
end

function Sh.FillFilters(text)
    local v = Sh.filters
    local term = T.Parse(text or "")
    local draft = v.draft
    draft.category, draft.quality, draft.expansion, draft.tier = term.category, term.quality, term.expansion, term.tier
    v.query:SetText(term.query or "")
    v.exactOn = term.exact and true or false
    v.exact:SetOn(v.exactOn)
    for key, input in pairs(v.ranges) do input:SetText(term[key] or "") end
    v.quantity:SetText(term.quantity or "")
    v.category:Refresh()
    v.quality:Refresh()
    v.expansion:Refresh()
end

-- Opens the filters on a term; with a list and index, saving changes that term.
function Sh.OpenFilters(text, list, index)
    if not Sh.filters then BuildFilters() end
    local v = Sh.filters
    v.editList, v.editIndex = list, index
    v.add:SetText(list and "Save" or "Add to list")
    Sh.FillFilters(text)
    v:Show()
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local function ResultClick(e, button, row)
    if e.missing then return end
    if e.saved then
        if e.link and IsModifiedClick() and HandleModifiedItemClick(e.link) then return end
        return S.Scan.ShowHistory(e.key, e.name)
    end
    if IsShiftKeyDown() and button == "LeftButton" then
        local chatting = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
        local link = e.link or select(2, C_Item.GetItemInfo(e.itemKey.itemID))
        if chatting and link then
            HandleModifiedItemClick(link)
        else
            Sh.box:SetText(e.name)
        end
        return
    end
    if IsModifiedClick("DRESSUP") and button == "LeftButton" then
        local link = e.link or select(2, C_Item.GetItemInfo(e.itemKey.itemID))
        if link then HandleModifiedItemClick(link) end
        return
    end
    if button == "RightButton" then
        local key = S.Prices.KeyForLink(e.link)
        if not key then key = e.isPet and e.itemKey.battlePetSpeciesID and ("p:" .. e.itemKey.battlePetSpeciesID) or e.itemKey.itemID end
        S.Scan.ShowHistory(key, e.name)
        return
    end
    S.Buy.Open(e)
end

function Sh.Build(frame)
    P = K.Palette()
    -- Side panel
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", 10, -10)
    side:SetPoint("BOTTOMLEFT", 10, 10)
    side:SetWidth(SIDE_WIDTH)
    K.Box(side, P.card, P.border)
    local views = { { "lists", "Lists" }, { "recents", "Recent" }, { "categories", "Categories" } }
    local view = K.Pills(side, views, function(key)
        S.db.profile.shoppingView = key
        RefreshSide()
    end, 26, true)
    view:SetPoint("TOPLEFT", 8, -8)
    view:SetPoint("TOPRIGHT", -8, -8)
    view:Choose(S.db.profile.shoppingView)
    Sh.view = view
    local newList = K.Button(side, "New")
    newList:SetPoint("BOTTOMLEFT", 8, 8)
    newList:SetWidth(70)
    newList:SetScript("OnClick", function() NewListWith() end)
    local import = K.Button(side, "Import")
    import:SetPoint("LEFT", newList, "RIGHT", 4, 0)
    import:SetWidth(76)
    import:SetScript("OnClick", ShowImport)
    local export = K.Button(side, "Export")
    export:SetPoint("LEFT", import, "RIGHT", 4, 0)
    export:SetWidth(76)
    export:SetScript("OnClick", function() ShowExport(selected and { selected } or Lists()) end)
    export.tipText = "The selected list, or all lists when none is selected."
    Sh.side = K.Table(side, { rowHeight = 24, empty = "Nothing here yet.", noHeader = true,
        columns = {
            { key = "name", title = "", fill = 1, noSort = true,
              indent = function(e) return e.kind == "term" and 12 or (e.depth or 0) * 12 end,
              color = function(e) return (e.kind == "list" or e.depth == 0) and P.bright or P.text end },
            { key = "count", title = "", width = 34, justify = "RIGHT", noSort = true,
              color = function() return P.muted end },
        },
        isSelected = function(e)
            if e.kind == "category" then return e.path == category end
            return e.kind == "list" and e.list == selected
        end,
        onClick = SideClick,
        onEnter = function() end,
        onLeave = function() end,
    })
    Sh.side:SetPoint("TOPLEFT", 6, -42)
    Sh.side:SetPoint("BOTTOMRIGHT", -6, 38)

    -- Search row
    local main = CreateFrame("Frame", nil, frame)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, 0)
    main:SetPoint("BOTTOMRIGHT", -10, 10)
    Sh.main = main
    local more = K.Button(main, "More")
    more:Fit(56)
    more:SetPoint("TOPRIGHT")
    more:SetScript("OnClick", function(self)
        K.Menu(self, function(root)
            if S.Crafting.CanSearchTracked() then
                root:CreateButton("Search tracked recipes", function() S.Crafting.SearchTracked() end)
            end
            root:CreateButton("Export results as CSV", ShowCsv)
        end)
    end)
    local addTerm = K.Button(main, "Add to list")
    addTerm:Fit(80)
    addTerm:SetPoint("RIGHT", more, "LEFT", -4, 0)
    addTerm:SetScript("OnClick", function(self)
        local text = Sh.box:GetText()
        if text == "" then return AskForText() end
        AddToListMenu(self, text)
    end)
    local search = K.Button(main, "Search", "primary")
    search:SetWidth(80)
    search:SetPoint("RIGHT", addTerm, "LEFT", -8, 0)
    search:SetScript("OnClick", function()
        if S.Search.IsRunning() then S.Search.Stop() else SearchBox() end
    end)
    Sh.searchButton = search
    local filters = K.Button(main, "Filters")
    filters:Fit(64)
    filters:SetPoint("RIGHT", search, "LEFT", -4, 0)
    filters:SetScript("OnClick", function() Sh.OpenFilters(Sh.box:GetText()) end)
    Sh.box = K.Input(main, { placeholder = "Search for an item",
        onChange = ShowSuggestions,
        onEnter = function()
            local flyout = Sh.flyout
            local lit = flyout:IsShown() and flyout.at and flyout.rows[flyout.at]
            flyout:Hide()
            if lit then ChooseSuggestion(lit) else SearchBox() end
        end,
        onFocus = function(on)
            if not on then C_Timer.After(0.15, function() if Sh.flyout then Sh.flyout:Hide() end end) end
        end,
    })
    Sh.box:SetPoint("TOPLEFT")
    Sh.box:SetPoint("RIGHT", filters, "LEFT", -6, 0)
    Sh.box.edit:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then MoveSuggestion(-1) elseif key == "DOWN" then MoveSuggestion(1) end
    end)
    BuildFlyout()

    -- Results
    Sh.progress = K.Progress(main)
    Sh.progress:SetPoint("TOPLEFT", 0, -28)
    Sh.progress:SetPoint("TOPRIGHT", 0, -28)
    local body = CreateFrame("Frame", nil, main)
    body:SetPoint("TOPLEFT", 0, -34)
    body:SetPoint("BOTTOMRIGHT")
    K.Box(body, P.card, P.border)
    Sh.results = K.Table(body, {
        id = "shopping", rowHeight = 26, empty = "Search for an item, or pick a list.",
        columns = {
            { key = "name", title = "Name", fill = 1, icon = function(e) return e.icon end,
              text = function(e) return K.QualityCode(e.quality) .. (e.name or "") .. "|r" end },
            { key = "level", title = "Item level", width = 70, justify = "RIGHT",
              text = function(e) return (e.level and e.level > 0) and e.level or "" end },
            { key = "price", title = "Price", width = 150, justify = "RIGHT", money = function(e) return e.price end },
            { key = "owned", title = "Yours", width = 50, justify = "CENTER", sort = function(e) return e.owned and 1 or 0 end,
              text = function(e) return e.owned and "Yes" or "" end, hide = function() return S.Window.mode == "saved" end },
            { key = "available", title = "Available", width = 80, justify = "RIGHT",
              text = function(e) return e.available and FormatLargeNumber(e.available) or "" end },
            { key = "age", title = "Last seen", width = 90, justify = "RIGHT", hide = function() return S.Window.mode ~= "saved" end,
              text = function(e)
                  if not e.age then return "" end
                  if e.age == 0 then return "Today" end
                  return e.age .. K.Plural(e.age, " day ago", " days ago")
              end },
        },
        dim = function(e) return e.missing end,
        onClick = ResultClick,
        onEnter = function(e, row)
            if e.missing or (e.saved and not e.link) then return end
            K.ItemTip(row, e.link, e.itemKey, true)
        end,
    })
    Sh.results:SetPoint("TOPLEFT", 6, -4)
    Sh.results:SetPoint("BOTTOMRIGHT", -2, 4)
    Sh.results:SortBy("price")
    Sh.entries = {}

    -- The buy screen sits over the results and search row.
    S.Buy.frame = CreateFrame("Frame", nil, main)
    S.Buy.frame:SetAllPoints()
    S.Buy.frame:SetFrameLevel(main:GetFrameLevel() + 20)
    S.Buy.frame:EnableMouse(true)
    W.Fill(S.Buy.frame, P.window, "BACKGROUND", -1):SetAllPoints()
    S.Buy.Build(S.Buy.frame)

    -- Temporary lists from an earlier session are gone.
    local lists = Lists()
    for i = #lists, 1, -1 do if lists[i].temporary then table.remove(lists, i) end end
    SortLists()
    RefreshSide()
    local default = S.db.profile.defaultList
    if default ~= "" then
        local list = FindList(default)
        if list then
            selected = list
            expanded[list] = true
            RefreshSide()
        end
    end
end

function Sh.OnShow()
    if Sh.frame then RefreshSide() end
end

-- Between live and saved prices, what's showing no longer applies.
function Sh.ModeChanged()
    RefreshSide() -- the categories come and go with the auction house
    if not Sh.results then return end
    if S.Buy.IsOpen() then S.Buy.Close() end
    Sh.entries = {}
    Sh.results:Layout()
    Sh.results:SetEntries(Sh.entries)
end

function Sh.Apply() end

-- A search asked for from elsewhere (reagents, other addons), as a temporary list.
function Sh.External(name, terms)
    S.Window.Select("shopping")
    -- A list of your own with that name keeps its searches: these run without a list.
    local own = FindList(name)
    if own and not own.temporary then return Sh.Run(terms) end
    local list = CreateList(name, terms, true)
    S.db.profile.shoppingView = "lists"
    Sh.view:Choose("lists")
    SearchList(list)
end

-- Lets the Selling tab search for an item by name.
function Sh.SearchExact(name)
    S.Window.Select("shopping")
    local text = '"' .. name .. '"'
    Sh.box:SetText(text)
    Sh.Run({ text })
end
