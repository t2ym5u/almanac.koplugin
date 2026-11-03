-- dates.lua -- proleptic Gregorian calendar arithmetic on plain {y, m, d}.
-- Pure Lua, no KOReader dependency, no os.time (which cannot reach before
-- 1970 or past 2038 on some readers): everything goes through a day number.

local D = {}

function D.isLeap(y)
    return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
end

local MDAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function D.daysInMonth(y, m)
    if m == 2 and D.isLeap(y) then return 29 end
    return MDAYS[m]
end

function D.valid(y, m, d)
    return type(y) == "number" and type(m) == "number" and type(d) == "number"
        and y == math.floor(y) and m == math.floor(m) and d == math.floor(d)
        and y >= 1 and y <= 9999 and m >= 1 and m <= 12 and d >= 1 and d <= D.daysInMonth(y, m)
end

-- Days since 1970-01-01 (H. Hinnant's days_from_civil). Negative before.
function D.toDays(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

function D.fromDays(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    return y, m, d
end

-- ISO weekday: 1 = Monday ... 7 = Sunday. (1970-01-01 was a Thursday.)
function D.weekday(y, m, d)
    return (D.toDays(y, m, d) + 3) % 7 + 1
end

function D.dayOfYear(y, m, d)
    return D.toDays(y, m, d) - D.toDays(y, 1, 1) + 1
end

function D.daysInYear(y) return D.isLeap(y) and 366 or 365 end

-- ISO 8601 week: returns week-year, week (1..53). The week belongs to the
-- year its Thursday falls in.
function D.isoWeek(y, m, d)
    local days = D.toDays(y, m, d)
    local wd = (days + 3) % 7 + 1
    local thursday = days - wd + 4
    local ty = D.fromDays(thursday)
    local week = math.floor((thursday - D.toDays(ty, 1, 1)) / 7) + 1
    return ty, week
end

function D.addDays(y, m, d, n)
    return D.fromDays(D.toDays(y, m, d) + n)
end

-- Calendar months; the day is clamped to the end of the target month
-- (31 January + 1 month = 28/29 February).
function D.addMonths(y, m, d, n)
    local idx = y * 12 + (m - 1) + n
    local ny, nm = math.floor(idx / 12), idx % 12 + 1
    return ny, nm, math.min(d, D.daysInMonth(ny, nm))
end

-- b - a in days.
function D.diff(ay, am, ad, by, bm, bd)
    return D.toDays(by, bm, bd) - D.toDays(ay, am, ad)
end

-- Working days from a to b (in either order): Monday to Friday that are
-- not in `is_holiday(y, m, d)`. Counts a, and b only when include_end.
function D.workingDays(a, b, is_holiday, include_end)
    local da, db = D.toDays(a[1], a[2], a[3]), D.toDays(b[1], b[2], b[3])
    local sign = 1
    if db < da then da, db, sign = db, da, -1 end
    local last = include_end and db or db - 1
    local n = 0
    for z = da, last do
        local wd = (z + 3) % 7 + 1
        if wd <= 5 then
            local y, m, d = D.fromDays(z)
            if not (is_holiday and is_holiday(y, m, d)) then n = n + 1 end
        end
    end
    return n * sign
end

-- Age on `on` of someone born on `birth`: years, months, days (each >= 0),
-- or nil when `on` is before `birth`. Someone born on 29 February has a
-- birthday on 28 February in common years (the clamp of addMonths).
function D.age(birth, on)
    local by, bm, bd = birth[1], birth[2], birth[3]
    local oy, om, od = on[1], on[2], on[3]
    if D.toDays(oy, om, od) < D.toDays(by, bm, bd) then return nil end
    local months = (oy - by) * 12 + (om - bm)
    local y, m, d = D.addMonths(by, bm, bd, months)
    if D.toDays(y, m, d) > D.toDays(oy, om, od) then
        months = months - 1
        y, m, d = D.addMonths(by, bm, bd, months)
    end
    local days = D.diff(y, m, d, oy, om, od)
    return math.floor(months / 12), months % 12, days
end

-- Next birthday on or after `on`: y, m, d and days until it.
function D.nextBirthday(birth, on)
    local years = on[1] - birth[1]
    for k = years, years + 1 do
        local y, m, d = D.addMonths(birth[1], birth[2], birth[3], 12 * k)
        local n = D.diff(on[1], on[2], on[3], y, m, d)
        if n >= 0 then return y, m, d, n, k end
    end
end

-- Parses a typed date. Accepts ISO "2026-11-03" always, and day first
-- ("3/11/2026", "03.11.2026", "3-11-2026") -- or month first when
-- month_first (US). A two-digit year is read as 19xx/20xx around `pivot`
-- (default: 2000 + 30 → 1931..2030). Returns y, m, d or nil.
function D.parse(text, month_first, pivot)
    if type(text) ~= "string" then return nil end
    local s = text:gsub("^%s+", ""):gsub("%s+$", "")
    local y, m, d = s:match("^(%d%d%d%d)[-/.](%d%d?)[-/.](%d%d?)$")
    if y then
        y, m, d = tonumber(y), tonumber(m), tonumber(d)
    else
        local a, b, c = s:match("^(%d%d?)[-/.%s](%d%d?)[-/.%s](%d+)$")
        if not a then return nil end
        a, b, c = tonumber(a), tonumber(b), tonumber(c)
        if month_first then m, d = a, b else d, m = a, b end
        y = c
        if #s:match("(%d+)$") <= 2 then
            local p = pivot or 30
            y = (c <= p) and (2000 + c) or (1900 + c)
        end
    end
    if not D.valid(y, m, d) then return nil end
    return y, m, d
end

-- Parses "+10", "-3", "2w", "-1m", "1y", "10 days", "3 semaines" ...
-- Returns count, unit ("d", "w", "m", "y") or nil.
local UNITS = {
    d = "d", day = "d", days = "d", j = "d", jour = "d", jours = "d",
    w = "w", wk = "w", week = "w", weeks = "w", s = "w", sem = "w", semaine = "w", semaines = "w",
    m = "m", mo = "m", month = "m", months = "m", mois = "m",
    y = "y", yr = "y", year = "y", years = "y", a = "y", an = "y", ans = "y", ["année"] = "y", ["années"] = "y",
}
function D.parseOffset(text)
    if type(text) ~= "string" then return nil end
    local s = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local sign, n, u = s:match("^([+-]?)%s*(%d+)%s*(%S*)$")
    if not n then return nil end
    local unit = u == "" and "d" or UNITS[u]
    if not unit then return nil end
    n = tonumber(n)
    if sign == "-" then n = -n end
    return n, unit
end

function D.addOffset(y, m, d, n, unit)
    if unit == "d" then return D.addDays(y, m, d, n) end
    if unit == "w" then return D.addDays(y, m, d, 7 * n) end
    if unit == "m" then return D.addMonths(y, m, d, n) end
    return D.addMonths(y, m, d, 12 * n)
end

-- The grid of a month view: 6 rows of 7 {y, m, d}, starting on the
-- week's first day (1 = Monday, 7 = Sunday).
function D.monthGrid(y, m, first_wd)
    local wd = D.weekday(y, m, 1)
    local lead = (wd - first_wd) % 7
    local start = D.toDays(y, m, 1) - lead
    local rows = {}
    for r = 1, 6 do
        local row = {}
        for c = 1, 7 do
            local yy, mm, dd = D.fromDays(start + (r - 1) * 7 + c - 1)
            row[c] = { yy, mm, dd }
        end
        rows[r] = row
    end
    return rows
end

return D
