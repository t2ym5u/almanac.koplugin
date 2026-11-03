local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local ButtonDialog    = require("ui/widget/buttondialog")
local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local InputDialog     = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Widget          = require("ui/widget/widget")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase = require("screen_base")

local D           = lrequire("dates")
local H           = lrequire("holidays")
local N           = lrequire("names")
local Calc        = lrequire("calc")
local MonthWidget = lrequire("month_widget")

local DScreen = Device.screen

local HELP_EN = [[
Month view
Swipe left or right (or use the arrows) to change month; tap the month name to go to any date or year. Today is shown in black, public holidays on grey, the selected day framed. The small discs are the moon's principal phases: ● new moon, ◐ first quarter, ○ full moon, ◑ last quarter. The left column gives the ISO week numbers.

Tap a day to see its weekday, day of the year, week, holidays and moon phase.

Public holidays
☰ → Holidays picks the country (France, United Kingdom, United States, Germany, Spain, Belgium, Switzerland, Canada). Only national holidays are shown: regional ones (German Länder, Spanish regions, Swiss cantons, Canadian provinces, US states) vary too much. For France, the Alsace-Moselle option adds Good Friday and St Stephen's Day.

Date calculator
• Days between two dates, with or without the end day, and working days (Monday to Friday, without the holidays of the chosen country).
• A date plus or minus days, weeks, months or years: type +10, -3w, 2m, 1y.
• The weekday of any date.
• An age from a birth date, and the next birthday.
Dates are typed day first (03/11/2026) or as 2026-11-03; month first when the country is the United States.

The moon phases are computed (Meeus' algorithms) and accurate to a few minutes; times are in the reader's time zone.]]

local HELP_FR = [[
Vue du mois
Balayez vers la gauche ou la droite (ou utilisez les flèches) pour changer de mois ; touchez le nom du mois pour aller à une date ou une année. Aujourd'hui est en noir, les jours fériés sur fond gris, le jour sélectionné encadré. Les petits disques sont les phases principales de la lune : ● nouvelle lune, ◐ premier quartier, ○ pleine lune, ◑ dernier quartier. La colonne de gauche donne les numéros de semaine ISO.

Touchez un jour pour voir son jour de la semaine, son rang dans l'année, sa semaine, les fêtes et la phase de la lune.

Jours fériés
☰ → Jours fériés choisit le pays (France, Royaume-Uni, États-Unis, Allemagne, Espagne, Belgique, Suisse, Canada). Seuls les jours fériés nationaux sont indiqués : les jours régionaux (Länder, communautés autonomes, cantons, provinces, États américains) varient trop. Pour la France, l'option Alsace-Moselle ajoute le Vendredi saint et la Saint-Étienne.

Calculs de dates
• Nombre de jours entre deux dates, avec ou sans le dernier jour, et jours ouvrés (du lundi au vendredi, sans les jours fériés du pays choisi).
• Une date plus ou moins des jours, semaines, mois ou années : tapez +10, -3s, 2m, 1a.
• Le jour de la semaine de n'importe quelle date.
• Un âge à partir d'une date de naissance, et le prochain anniversaire.
Les dates se tapent jour d'abord (03/11/2026) ou sous la forme 2026-11-03 ; mois d'abord si le pays choisi est les États-Unis.

Les phases de la lune sont calculées (algorithmes de Meeus) à quelques minutes près ; les heures sont celles du fuseau horaire de la liseuse.]]

-- Seconds east of UTC at Unix time t, in the reader's time zone. os.date
-- cannot go past 2038 on a 32-bit reader, so t is clamped (the offset of
-- the same season is kept, near enough for a moon phase time).
local function tzOffset(t)
    local tt = math.max(86400 * 2, math.min(t, 2147483647 - 86400 * 2))
    local ok, off = pcall(function()
        local u = os.date("!*t", tt)
        u.isdst = os.date("*t", tt).isdst
        return tt - os.time(u)
    end)
    return ok and off or 0
end

-- ---------------------------------------------------------------------------
-- Info panel: the selected day's lines, first one bold.
-- ---------------------------------------------------------------------------

local InfoPanel = Widget:extend{ width = 300, height = 200, lines = nil }

function InfoPanel:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
end

function InfoPanel:getSize() return self.dimen end

function InfoPanel:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    local lines = self.lines or {}
    local head = TextBoxWidget:new{
        text = lines[1] or "", face = Font:getFace("cfont", 24), bold = true,
        width = self.width, alignment = "center",
    }
    local rest = TextBoxWidget:new{
        text = table.concat(lines, "\n", 2), face = Font:getFace("cfont", 19),
        width = self.width, alignment = "center",
        height = math.max(10, self.height - head:getSize().h - 6), height_adjust = true,
    }
    head:paintTo(bb, x, y)
    rest:paintTo(bb, x, y + head:getSize().h + 6)
    head:free(); rest:free()
end

-- ---------------------------------------------------------------------------
-- Screen
-- ---------------------------------------------------------------------------

local AlmanacScreen = ScreenBase:extend{
    vertical_align = "top",
}

local function todayYMD()
    local t = os.date("*t")
    return { t.year, t.month, t.day }
end

function AlmanacScreen:init()
    self.today = todayYMD()
    self.selected = { self.today[1], self.today[2], self.today[3] }
    self.view_y, self.view_m = self.today[1], self.today[2]
    ScreenBase.init(self)
end

function AlmanacScreen:serializeState() return nil end

-- Settings ------------------------------------------------------------------

function AlmanacScreen:lang()
    local l = _.lang()
    if l == "fr" or l == "de" or l == "es" then return l end
    return "en"
end

function AlmanacScreen:country()
    local c = self.plugin:getSetting("country")
    if c and H.COUNTRY_NAMES[c] then return c end
    local full = G_reader_settings and G_reader_settings:readSetting("language") or "en"
    return H.defaultCountry(full)
end

function AlmanacScreen:firstWeekday()
    local f = self.plugin:getSetting("first_day", "auto")
    if f == 1 or f == 7 then return f end
    -- Sunday for the US and English Canada (English's default country is
    -- the US), Monday everywhere else -- the UK and French Canada too.
    local c = self:country()
    return ((c == "us" or c == "ca") and self:lang() ~= "fr") and 7 or 1
end

function AlmanacScreen:ctx()
    local country = self:country()
    return {
        lang = self:lang(), country = country, us = country == "us",
        hol_opts = { alsace = country == "fr" and self.plugin:getSetting("alsace", false) },
        tr = _, offset = tzOffset,
    }
end

-- Layout --------------------------------------------------------------------

function AlmanacScreen:buildLayout()
    local sw, sh = self.dimen.w, self.dimen.h
    local g = self:getGutter()
    local landscape = self:isLandscape()
    local ctx = self:ctx()
    self.cur_ctx = ctx
    local title_bar = self:buildTitleBar(_("Calendar"), function() return self:menuItems() end)
    local cw = sw - 2 * g
    local avail_h = sh - title_bar:getSize().h - 2 * g

    local side_w = landscape and math.floor((cw - g) * 0.42) or cw
    local grid_w = landscape and (cw - side_w - g) or cw
    local bh = DScreen:scaleBySize(56)

    local nav = ButtonTable:new{
        width = side_w,
        buttons = { {
            { icon = "chevron.left", width = math.floor(side_w * (landscape and 0.15 or 0.18)), height = bh,
              callback = function() self:shiftMonth(-1) end },
            { text = N.monthTitle(self.view_y, self.view_m, ctx.lang), height = bh, font_size = landscape and 20 or 24, font_bold = true,
              callback = function() self:askGoto() end },
            { icon = "chevron.right", width = math.floor(side_w * (landscape and 0.15 or 0.18)), height = bh,
              callback = function() self:shiftMonth(1) end },
        } },
    }
    local actions = ButtonTable:new{
        width = side_w,
        buttons = { {
            { text = _("Today"), height = bh, font_size = landscape and 18 or 21, callback = function() self:goToday() end },
            { text = _("Date calculator"), height = bh, font_size = landscape and 18 or 21, callback = function() self:openCalculator() end },
        } },
    }

    local info_h = landscape and (avail_h - nav:getSize().h - actions:getSize().h - 2 * g)
        or DScreen:scaleBySize(190)
    local info = InfoPanel:new{ width = side_w, height = info_h,
        lines = Calc.dayInfo(self.selected[1], self.selected[2], self.selected[3], ctx, self.today) }

    local grid_h = landscape and avail_h
        or (avail_h - nav:getSize().h - info_h - actions:getSize().h - 3 * g)
    local month = self:buildMonth(grid_w, grid_h, ctx)

    local content
    if landscape then
        content = HorizontalGroup:new{
            align = "top",
            month,
            HorizontalSpan:new{ width = g },
            VerticalGroup:new{ align = "center", nav, VerticalSpan:new{ width = g }, info,
                VerticalSpan:new{ width = g }, actions },
        }
    else
        content = VerticalGroup:new{
            align = "center",
            nav, VerticalSpan:new{ width = g }, month, VerticalSpan:new{ width = g },
            info, VerticalSpan:new{ width = g }, actions,
        }
    end
    self.layout = VerticalGroup:new{ align = "center", title_bar, VerticalSpan:new{ width = g }, content }
    self[1] = self.layout
end

function AlmanacScreen:buildMonth(w, h, ctx)
    local first = self:firstWeekday()
    local grid = D.monthGrid(self.view_y, self.view_m, first)
    local labels = {}
    for c = 1, 7 do
        local wd = (first - 1 + c - 1) % 7 + 1
        labels[c] = N.cap(N.shortWeekday(wd, ctx.lang))
    end
    local z0 = D.toDays(grid[1][1][1], grid[1][1][2], grid[1][1][3])
    local phases = Calc.phasesByDay(z0, z0 + 41, ctx)
    return MonthWidget:new{
        width = w, height = h, grid = grid, month = self.view_m,
        today = self.today, selected = self.selected,
        weekday_labels = labels,
        week_numbers = self.plugin:getSetting("week_numbers", true),
        week_of = function(row)
            for _i, day in ipairs(row) do
                if D.weekday(day[1], day[2], day[3]) == 1 then
                    local _y, wk = D.isoWeek(day[1], day[2], day[3]); return wk
                end
            end
        end,
        is_holiday = function(y, m, d) return H.isDayOff(ctx.country, y, m, d, ctx.hol_opts) end,
        moon_of = function(y, m, d)
            local ev = phases[D.toDays(y, m, d)]
            return ev and ev.kind
        end,
        is_weekend = function(c)
            local wd = (first - 1 + c - 1) % 7 + 1
            return wd >= 6
        end,
        on_select = function(day) self:select(day) end,
        on_hold = function(day) self:select(day); self:openCalculator() end,
        on_swipe = function(dir) self:shiftMonth(dir) end,
    }
end

function AlmanacScreen:redraw()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- Navigation ---------------------------------------------------------------

function AlmanacScreen:select(day)
    self.selected = { day[1], day[2], day[3] }
    if day[1] ~= self.view_y or day[2] ~= self.view_m then
        self.view_y, self.view_m = day[1], day[2]
    end
    self:redraw()
end

function AlmanacScreen:shiftMonth(n)
    local y, m = D.addMonths(self.view_y, self.view_m, 1, n)
    if y < 1 or y > 9999 then return end
    self.view_y, self.view_m = y, m
    -- keep the same day number selected in the new month (clamped)
    self.selected = { y, m, math.min(self.selected[3], D.daysInMonth(y, m)) }
    self:redraw()
end

function AlmanacScreen:goToday()
    self.today = todayYMD()
    self:select(self.today)
end

function AlmanacScreen:dateHint()
    return self:country() == "us" and _("mm/dd/yyyy") or _("dd/mm/yyyy")
end

function AlmanacScreen:parseDate(text)
    return D.parse(text, self:country() == "us")
end

function AlmanacScreen:askGoto()
    local dlg
    dlg = InputDialog:new{
        title = _("Go to date"),
        description = T(_("A date (%1), a month (11/2026) or a year (1969)."), self:dateHint()),
        input = "",
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            { text = _("Show"), is_enter_default = true, callback = function()
                local s = dlg:getInputText():gsub("^%s+", ""):gsub("%s+$", "")
                local y, m, d = self:parseDate(s)
                if not y then
                    local mm, yy = s:match("^(%d%d?)[/.-](%d%d%d%d)$")
                    if mm and tonumber(mm) >= 1 and tonumber(mm) <= 12 then
                        y, m, d = tonumber(yy), tonumber(mm), 1
                    elseif s:match("^%d%d?%d?%d?$") and tonumber(s) >= 1 then
                        y, m, d = tonumber(s), self.view_m, 1
                    end
                end
                if not y then
                    UIManager:show(InfoMessage:new{ text = _("Could not read that date."), timeout = 3 })
                    return
                end
                UIManager:close(dlg)
                self:select({ y, m, math.min(d, D.daysInMonth(y, m)) })
            end },
        } },
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

-- Date calculator ------------------------------------------------------------

function AlmanacScreen:showResult(title, text)
    UIManager:show(InfoMessage:new{ text = title .. "\n\n" .. text, show_icon = false })
end

-- fields: { { description, text }, ... }; on_ok(values) returns an error
-- message or nil.
function AlmanacScreen:askFields(title, fields, on_ok)
    local dlg
    local specs = {}
    for i, f in ipairs(fields) do
        specs[i] = { description = f[1], text = f[2] or "", hint = f[3] or "" }
    end
    dlg = MultiInputDialog:new{
        title = title,
        fields = specs,
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            { text = _("Calculate"), is_enter_default = true, callback = function()
                local err = on_ok(dlg:getFields())
                if err then
                    UIManager:show(InfoMessage:new{ text = err, timeout = 3 })
                else
                    UIManager:close(dlg)
                end
            end },
        } },
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function AlmanacScreen:openCalculator()
    local ctx = self:ctx()
    local us = ctx.us
    local sel = N.numeric(self.selected[1], self.selected[2], self.selected[3], us)
    local today = N.numeric(self.today[1], self.today[2], self.today[3], us)
    local hint = self:dateHint()
    local bad = _("Could not read that date.")
    local dlg
    local function op(fn) return function() UIManager:close(dlg); fn() end end
    dlg = ButtonDialog:new{
        title = _("Date calculator"),
        buttons = {
            { { text = _("Days between two dates"), callback = op(function()
                self:askFields(_("Days between two dates"), {
                    { T(_("From (%1)"), hint), sel }, { T(_("To (%1)"), hint), today },
                }, function(v)
                    local a = { self:parseDate(v[1]) }
                    local b = { self:parseDate(v[2]) }
                    if not a[1] or not b[1] then return bad end
                    self:showResult(_("Days between two dates"), Calc.between(a, b, ctx))
                end)
            end) } },
            { { text = _("Add or subtract"), callback = op(function()
                self:askFields(_("Add or subtract"), {
                    { T(_("Date (%1)"), hint), sel },
                    { _("Amount: +10, -3, 2w, -1m, 1y (days by default)"), "+30" },
                }, function(v)
                    local a = { self:parseDate(v[1]) }
                    if not a[1] then return bad end
                    local n, unit = D.parseOffset(v[2])
                    if not n then return _("Could not read that amount.") end
                    local text, r = Calc.add(a, n, unit, ctx)
                    if not D.valid(r[1], r[2], r[3]) then return bad end
                    self:select(r)
                    self:showResult(_("Add or subtract"), text)
                end)
            end) } },
            { { text = _("Weekday of a date"), callback = op(function()
                self:askFields(_("Weekday of a date"), {
                    { T(_("Date (%1)"), hint), sel },
                }, function(v)
                    local y, m, d = self:parseDate(v[1])
                    if not y then return bad end
                    -- The panel under the grid tells everything about it.
                    self:select({ y, m, d })
                end)
            end) } },
            { { text = _("Age from a birth date"), callback = op(function()
                self:askFields(_("Age from a birth date"), {
                    { T(_("Birth date (%1)"), hint), "" }, { T(_("On (%1)"), hint), today },
                }, function(v)
                    local b = { self:parseDate(v[1]) }
                    local o = { self:parseDate(v[2]) }
                    if not b[1] or not o[1] then return bad end
                    self:showResult(_("Age from a birth date"), Calc.age(b, o, ctx))
                end)
            end) } },
        },
    }
    UIManager:show(dlg)
end

-- Menu ----------------------------------------------------------------------

function AlmanacScreen:chooseCountry()
    local dlg
    local buttons = {}
    local cur = self:country()
    local lang = self:lang() == "fr" and "fr" or "en"
    for _i, c in ipairs(H.COUNTRIES) do
        buttons[#buttons + 1] = { {
            text = (c == cur and "✓ " or "") .. H.COUNTRY_NAMES[c][lang],
            callback = function()
                UIManager:close(dlg)
                self.plugin:saveSetting("country", c)
                self:redraw()
            end,
        } }
    end
    dlg = ButtonDialog:new{ title = _("Public holidays"), buttons = buttons }
    UIManager:show(dlg)
end

function AlmanacScreen:menuItems()
    local p = self.plugin
    local lang = self:lang() == "fr" and "fr" or "en"
    local items = {
        { text = _("Today"), callback = function() self:goToday() end },
        { text = _("Go to date…"), callback = function() self:askGoto() end },
        { text = _("Date calculator"), callback = function() self:openCalculator() end },
        { text = T(_("Holidays: %1"), H.COUNTRY_NAMES[self:country()][lang]), callback = function() self:chooseCountry() end },
    }
    if self:country() == "fr" then
        items[#items + 1] = {
            text = p:getSetting("alsace", false) and _("Alsace-Moselle holidays: on") or _("Alsace-Moselle holidays: off"),
            callback = function() p:saveSetting("alsace", not p:getSetting("alsace", false)); self:redraw() end,
        }
    end
    local f = p:getSetting("first_day", "auto")
    local flabel = f == 1 and _("Monday") or f == 7 and _("Sunday") or _("automatic")
    items[#items + 1] = { text = T(_("Week starts on: %1"), flabel), callback = function()
        local nxt = ({ auto = 1, [1] = 7, [7] = "auto" })[f] or "auto"
        p:saveSetting("first_day", nxt); self:redraw()
    end }
    items[#items + 1] = {
        text = p:getSetting("week_numbers", true) and _("Week numbers: on") or _("Week numbers: off"),
        callback = function() p:saveSetting("week_numbers", not p:getSetting("week_numbers", true)); self:redraw() end,
    }
    items[#items + 1] = { text = _("Help"), callback = function()
        self:showRules((_.lang() == "fr" and HELP_FR) or HELP_EN, { title = _("Help") })
    end }
    return items
end

-- The reader was rotated: rebuild for the new width and height.
function AlmanacScreen:onSetDimensions(dimen)
    self.dimen.w, self.dimen.h = dimen.w, dimen.h
    self:redraw()
end

function AlmanacScreen:updateStatus() end

return AlmanacScreen
