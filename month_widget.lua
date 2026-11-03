-- month_widget.lua -- the month grid: weekday header, optional ISO week
-- column, 6 weeks of days. Today is black, the selected day framed, public
-- holidays on grey, days of the neighbouring months in grey, principal moon
-- phases as a small disc in the corner. Tap a day to select it; swipe left
-- or right for the next or previous month.

local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")

local Screen = Device.screen

local function drawText(bb, face, text, x, y, w, h, color, bold)
    local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, bold)
    local v = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, "8", true, bold)
    local tx = x + math.floor((w - m.x) / 2)
    local baseline = y + math.floor((h - (v.y_top + v.y_bottom)) / 2) + v.y_top
    RenderText:renderUtf8Text(bb, tx, baseline, face, text, true, bold, color)
end

-- A moon disc of radius r centred at cx, cy: kind new (filled), full
-- (ring), first (right half lit, as seen from the northern hemisphere),
-- last (left half lit).
local function drawMoon(bb, cx, cy, r, kind, fg, bg)
    for dy = -r, r do
        local half = math.floor(math.sqrt(r * r - dy * dy) + 0.5)
        for dx = -half, half do
            local edge = (dx * dx + dy * dy) >= (r - 1.6) * (r - 1.6)
            local dark
            if kind == "new" then dark = true
            elseif kind == "full" then dark = edge
            elseif kind == "first" then dark = edge or dx < 0
            else dark = edge or dx > 0 end
            bb:setPixel(cx + dx, cy + dy, dark and fg or bg)
        end
    end
end

local MonthWidget = InputContainer:extend{
    width = 600, height = 500,
    grid = nil,          -- dates.monthGrid rows
    month = nil,         -- the month shown (other months' days in grey)
    today = nil,         -- {y, m, d}
    selected = nil,      -- {y, m, d}
    weekday_labels = nil,-- 7 short names in display order
    week_numbers = true,
    week_of = nil,       -- function(row) -> ISO week number of that row
    is_holiday = nil,    -- function(y, m, d) -> bool
    moon_of = nil,       -- function(y, m, d) -> kind or nil
    is_weekend = nil,    -- function(col) -> bool
    on_select = nil, on_swipe = nil, on_hold = nil,
}

function MonthWidget:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.week_w = self.week_numbers and math.floor(self.width * 0.09) or 0
    self.cell_w = (self.width - self.week_w) / 7
    self.head_h = math.floor(math.min(self.height * 0.08, Screen:scaleBySize(36)))
    self.cell_h = (self.height - self.head_h) / 6
    self.day_face  = self:fit("28", self.cell_w * 0.62, self.cell_h * 0.42)
    self.head_face = self:fit("Mer", self.cell_w * 0.8, self.head_h * 0.5)
    self.week_face = self:fit("53", self.week_w * 0.75, self.cell_h * 0.28)
    local range = function() return self.dimen end
    self.ges_events = {
        Tap   = { GestureRange:new{ ges = "tap",   range = range } },
        Hold  = { GestureRange:new{ ges = "hold",  range = range } },
        Swipe = { GestureRange:new{ ges = "swipe", range = range } },
    }
end

-- Largest cfont face whose rendering of `sample` fits w x h (pixels).
function MonthWidget:fit(sample, w, h)
    local lo, hi, best = 6, 120, 6
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), Font:getFace("cfont", mid), sample, true, true)
        if m.x <= w and (m.y_top + m.y_bottom) <= h then best = mid; lo = mid + 1 else hi = mid - 1 end
    end
    return Font:getFace("cfont", best)
end

function MonthWidget:getSize() return self.dimen end

local function same(a, b) return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

function MonthWidget:cellRect(r, c)
    local x = self.dimen.x + self.week_w + math.floor((c - 1) * self.cell_w)
    local y = self.dimen.y + self.head_h + math.floor((r - 1) * self.cell_h)
    local w = math.floor(c * self.cell_w) - math.floor((c - 1) * self.cell_w)
    local h = math.floor(r * self.cell_h) - math.floor((r - 1) * self.cell_h)
    return x, y, w, h
end

function MonthWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local BLACK, WHITE = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
    local GREY, LIGHT, DARK = Blitbuffer.COLOR_GRAY, Blitbuffer.COLOR_LIGHT_GRAY, Blitbuffer.COLOR_DARK_GRAY
    bb:paintRect(x, y, self.width, self.height, WHITE)
    -- header
    for c = 1, 7 do
        local cx = x + self.week_w + math.floor((c - 1) * self.cell_w)
        local cw = math.floor(c * self.cell_w) - math.floor((c - 1) * self.cell_w)
        drawText(bb, self.head_face, self.weekday_labels[c], cx, y, cw, self.head_h,
            self.is_weekend and self.is_weekend(c) and DARK or BLACK, true)
    end
    bb:paintRect(x, y + self.head_h - 2, self.width, 2, BLACK)
    for r = 1, 6 do
        local row = self.grid[r]
        if self.week_numbers then
            local _x, ry, _w, rh = self:cellRect(r, 1)
            drawText(bb, self.week_face, tostring(self.week_of(row) or ""), x, ry, self.week_w, rh, GREY, false)
        end
        for c = 1, 7 do
            local day = row[c]
            local cx, cy, cw, ch = self:cellRect(r, c)
            local in_month = day[2] == self.month
            local is_today = same(day, self.today)
            local hol = self.is_holiday and self.is_holiday(day[1], day[2], day[3])
            local fg = in_month and BLACK or GREY
            local pad = 3
            if is_today then
                bb:paintRect(cx + pad, cy + pad, cw - 2 * pad, ch - 2 * pad, BLACK)
                fg = WHITE
            elseif hol then
                bb:paintRect(cx + pad, cy + pad, cw - 2 * pad, ch - 2 * pad, in_month and LIGHT or Blitbuffer.COLOR_GRAY_E)
            end
            drawText(bb, self.day_face, tostring(day[3]), cx, cy, cw, ch, fg, in_month and (hol or is_today))
            if same(day, self.selected) then
                local t = math.max(3, math.floor(math.min(cw, ch) * 0.06))
                bb:paintBorder(cx + 1, cy + 1, cw - 2, ch - 2, t, is_today and DARK or BLACK)
            end
            local kind = in_month and self.moon_of and self.moon_of(day[1], day[2], day[3])
            if kind then
                local rad = math.max(4, math.floor(math.min(cw, ch) * 0.1))
                drawMoon(bb, cx + cw - rad - 2 * pad - 2, cy + rad + 2 * pad + 1, rad, kind,
                    is_today and WHITE or BLACK, is_today and BLACK or (hol and LIGHT or WHITE))
            end
        end
        -- thin separators between weeks
        if r < 6 then
            local _x, ry, _w, rh = self:cellRect(r, 1)
            bb:paintRect(x + self.week_w, ry + rh - 1, self.width - self.week_w, 1, LIGHT)
        end
    end
    if self.week_numbers then
        bb:paintRect(x + self.week_w - 1, y + self.head_h, 1, self.height - self.head_h, LIGHT)
    end
end

function MonthWidget:dayAt(ges)
    local px, py = ges.pos.x - self.dimen.x - self.week_w, ges.pos.y - self.dimen.y - self.head_h
    if px < 0 or py < 0 then return nil end
    local c = math.floor(px / self.cell_w) + 1
    local r = math.floor(py / self.cell_h) + 1
    if r >= 1 and r <= 6 and c >= 1 and c <= 7 then return self.grid[r][c] end
end

function MonthWidget:onTap(_arg, ges)
    local day = self:dayAt(ges)
    if day and self.on_select then self.on_select(day) end
    return true
end

function MonthWidget:onHold(_arg, ges)
    local day = self:dayAt(ges)
    if day and self.on_hold then self.on_hold(day) end
    return true
end

function MonthWidget:onSwipe(_arg, ges)
    if not self.on_swipe then return false end
    local dir = ges.direction
    if dir == "west" or dir == "north" then self.on_swipe(1); return true end
    if dir == "east" or dir == "south" then self.on_swipe(-1); return true end
    return false
end

return MonthWidget
