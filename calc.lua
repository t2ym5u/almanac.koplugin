-- calc.lua -- the texts of the day panel and of the date calculator.
-- Pure: translation (ctx.tr) and the local time-zone offset (ctx.offset)
-- come in through ctx, so the specs run without KOReader.
--
-- ctx = { lang = "fr"|"en"|..., us = bool (month-first dates),
--         country = "fr", hol_opts = { alsace = bool },
--         tr = function(s) -> s, offset = function(unix_t) -> seconds east of UTC }

local _dir = (debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])")) or "./"
local function lload(name)
    local key = _dir .. name
    if not package.loaded[key] then package.loaded[key] = dofile(_dir .. name .. ".lua") end
    return package.loaded[key]
end
local D    = lload("dates")
local H    = lload("holidays")
local Moon = lload("moon")
local N    = lload("names")

local C = {}

local function tpl(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(i) return tostring(args[tonumber(i)]) end))
end
C.tpl = tpl

-- 13291 -> "13 291" (fr) / "13,291" (en)
function C.thousands(n, lang)
    local s = tostring(math.abs(n))
    local sep = (lang == "fr") and "\u{202F}" or (lang == "de" or lang == "es") and "." or ","
    s = s:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
    if s:sub(1, #sep) == sep then s = s:sub(#sep + 1) end
    return (n < 0 and "-" or "") .. s
end

local function hname(h, lang) return lang == "fr" and h.fr or h.en end

function C.holidayNames(y, m, d, ctx)
    local out = {}
    for _i, h in ipairs(H.on(ctx.country, y, m, d, ctx.hol_opts)) do out[#out + 1] = hname(h, ctx.lang) end
    return out
end

function C.isDayOff(ctx)
    return function(y, m, d) return H.isDayOff(ctx.country, y, m, d, ctx.hol_opts) end
end

function C.longDate(y, m, d, ctx, capital)
    return N.longDate(y, m, d, D.weekday(y, m, d), ctx.lang, ctx.us, capital)
end

local function hhmm(t, off)
    local s = math.floor(t + off) % 86400
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60)
end

local PHASE_LABELS = {
    new = "New moon", first = "First quarter", full = "Full moon", last = "Last quarter",
    waxing_crescent = "Waxing crescent", waxing_gibbous = "Waxing gibbous",
    waning_gibbous = "Waning gibbous", waning_crescent = "Waning crescent",
}
C.PHASE_LABELS = PHASE_LABELS

-- Principal moon phases on each local day of [first_day, last_day] (day
-- numbers): { [day number] = { kind, t } }.
function C.phasesByDay(first_day, last_day, ctx)
    local off0 = ctx.offset(first_day * 86400)
    local evs = Moon.eventsBetween(first_day * 86400 - off0 - 86400, (last_day + 1) * 86400 - off0 + 86400)
    local out = {}
    for _i, ev in ipairs(evs) do
        local z = math.floor((ev.t + ctx.offset(ev.t)) / 86400)
        if z >= first_day and z <= last_day then out[z] = ev end
    end
    return out
end

-- The moon on a local day: a principal phase that day (with its time), or
-- the phase at local noon with its illumination.
function C.moonLine(y, m, d, ctx)
    local tr = ctx.tr
    local z = D.toDays(y, m, d)
    local ev = C.phasesByDay(z, z, ctx)[z]
    if ev then
        return tpl(tr("Moon: %1 at %2"), tr(PHASE_LABELS[ev.kind]), hhmm(ev.t, ctx.offset(ev.t)))
    end
    local noon = z * 86400 + 43200 - ctx.offset(z * 86400 + 43200)
    local age, illum = Moon.ageAt(noon)
    local _a, _b, frac = Moon.ageAt(noon)
    local kind
    if frac < 0.25 then kind = "waxing_crescent" elseif frac < 0.5 then kind = "waxing_gibbous"
    elseif frac < 0.75 then kind = "waning_gibbous" else kind = "waning_crescent" end
    return tpl(tr("Moon: %1, %2% lit, %3 days old"), tr(PHASE_LABELS[kind]),
        math.floor(illum * 100 + 0.5), math.floor(age + 0.5))
end

-- Lines describing a day: long date, day of year and week, how far from
-- today, holidays, moon.
function C.dayInfo(y, m, d, ctx, today)
    local tr = ctx.tr
    local lines = { C.longDate(y, m, d, ctx, true) }
    local wy, wk = D.isoWeek(y, m, d)
    lines[#lines + 1] = tpl(tr("Day %1 of %2 · week %3"), D.dayOfYear(y, m, d), D.daysInYear(y),
        wy == y and wk or (wk .. " (" .. wy .. ")"))
    if today then
        local n = D.diff(today[1], today[2], today[3], y, m, d)
        if n == 0 then lines[#lines + 1] = tr("Today")
        elseif n == 1 then lines[#lines + 1] = tr("Tomorrow")
        elseif n == -1 then lines[#lines + 1] = tr("Yesterday")
        elseif n > 0 then lines[#lines + 1] = tpl(tr("In %1 days"), C.thousands(n, ctx.lang))
        else lines[#lines + 1] = tpl(tr("%1 days ago"), C.thousands(-n, ctx.lang)) end
    end
    local hs = C.holidayNames(y, m, d, ctx)
    if #hs > 0 then lines[#lines + 1] = table.concat(hs, " · ") end
    lines[#lines + 1] = C.moonLine(y, m, d, ctx)
    return lines
end

-- ---------------------------------------------------------------------------
-- Date calculator
-- ---------------------------------------------------------------------------

function C.between(a, b, ctx)
    local tr = ctx.tr
    local n = D.diff(a[1], a[2], a[3], b[1], b[2], b[3])
    local abs = math.abs(n)
    local lines = {
        tpl(tr("From %1"), C.longDate(a[1], a[2], a[3], ctx)),
        tpl(tr("to %1"), C.longDate(b[1], b[2], b[3], ctx)),
        "",
        tpl(tr("%1 days (end day not counted)"), C.thousands(abs, ctx.lang)),
        tpl(tr("%1 days counting both ends"), C.thousands(abs + 1, ctx.lang)),
    }
    if abs >= 7 then
        lines[#lines + 1] = tpl(tr("= %1 weeks and %2 days"), math.floor(abs / 7), abs % 7)
    end
    local lo, hi = a, b
    if n < 0 then lo, hi = b, a end
    local off = C.isDayOff(ctx)
    lines[#lines + 1] = ""
    lines[#lines + 1] = tpl(tr("Working days: %1 (%2 counting the end day)"),
        C.thousands(D.workingDays(lo, hi, off, false), ctx.lang),
        C.thousands(D.workingDays(lo, hi, off, true), ctx.lang))
    lines[#lines + 1] = tpl(tr("Monday to Friday, without the public holidays of %1."),
        H.COUNTRY_NAMES[ctx.country][ctx.lang == "fr" and "fr" or "en"])
    return table.concat(lines, "\n")
end

local UNIT_LABELS = { d = "%1 days", w = "%1 weeks", m = "%1 months", y = "%1 years" }

function C.add(a, n, unit, ctx)
    local tr = ctx.tr
    local y, m, d = D.addOffset(a[1], a[2], a[3], n, unit)
    local amount = tpl(tr(UNIT_LABELS[unit]), math.abs(n))
    local lines = {
        C.longDate(a[1], a[2], a[3], ctx, true),
        (n < 0 and "− " or "+ ") .. amount,
        "",
        "= " .. C.longDate(y, m, d, ctx),
    }
    local wy, wk = D.isoWeek(y, m, d)
    lines[#lines + 1] = tpl(tr("Day %1 of %2 · week %3"), D.dayOfYear(y, m, d), D.daysInYear(y),
        wy == y and wk or (wk .. " (" .. wy .. ")"))
    local hs = C.holidayNames(y, m, d, ctx)
    if #hs > 0 then lines[#lines + 1] = table.concat(hs, " · ") end
    return table.concat(lines, "\n"), { y, m, d }
end

function C.age(birth, on, ctx)
    local tr = ctx.tr
    local yy, mm, dd = D.age(birth, on)
    if not yy then return tr("The birth date is after the reference date.") end
    local lines = {
        tpl(tr("Born %1"), C.longDate(birth[1], birth[2], birth[3], ctx)),
        tpl(tr("On %1:"), C.longDate(on[1], on[2], on[3], ctx)),
        "",
        tpl(tr("%1 years, %2 months and %3 days"), yy, mm, dd),
        tpl(tr("= %1 days"), C.thousands(D.diff(birth[1], birth[2], birth[3], on[1], on[2], on[3]), ctx.lang)),
    }
    local ny, nm, nd, n, k = D.nextBirthday(birth, on)
    if n == 0 then
        lines[#lines + 1] = tpl(tr("Happy birthday! %1 today."), k)
    else
        lines[#lines + 1] = tpl(tr("Next birthday (%1): %2, in %3 days"), k, C.longDate(ny, nm, nd, ctx),
            C.thousands(n, ctx.lang))
    end
    return table.concat(lines, "\n")
end

return C
