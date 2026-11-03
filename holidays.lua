-- holidays.lua -- public holidays by country, computed for any year.
-- Pure Lua on top of dates.lua.
--
-- Scope, per country (national/federal holidays only; regional ones vary):
--   fr  France, plus Alsace-Moselle (Good Friday, St Stephen's Day) as an option
--   uk  United Kingdom -- England & Wales bank holidays, with substitute days
--       and the one-off royal/jubilee holidays since 1999
--   us  United States -- federal holidays, with Friday/Monday observed days
--   de  Germany -- the nine nationwide holidays (+ Reformation Day 2017)
--   es  Spain -- national holidays common to every region
--   be  Belgium -- the ten legal holidays
--   ch  Switzerland -- National Day plus the holidays kept by most cantons
--   ca  Canada -- federal statutory holidays
-- Easter and Pentecost Sundays are listed where they are the reason for the
-- Monday after (they fall on Sundays and never change a working-day count).
--
-- Each holiday: { y, m, d, en = "...", fr = "...", observed = bool }.
-- `observed` marks a substitute day off for a holiday falling on a weekend.

local _dir = (debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])")) or "./"
local D = package.loaded[_dir .. "dates"] or dofile(_dir .. "dates.lua")
package.loaded[_dir .. "dates"] = D

local H = {}

H.COUNTRIES = { "fr", "uk", "us", "de", "es", "be", "ch", "ca" }

H.COUNTRY_NAMES = {
    fr = { en = "France", fr = "France" },
    uk = { en = "United Kingdom (England & Wales)", fr = "Royaume-Uni (Angleterre et pays de Galles)" },
    us = { en = "United States (federal)", fr = "États-Unis (fédéral)" },
    de = { en = "Germany (nationwide)", fr = "Allemagne (fériés nationaux)" },
    es = { en = "Spain (nationwide)", fr = "Espagne (fériés nationaux)" },
    be = { en = "Belgium", fr = "Belgique" },
    ch = { en = "Switzerland (most cantons)", fr = "Suisse (la plupart des cantons)" },
    ca = { en = "Canada (federal)", fr = "Canada (fédéral)" },
}

-- Gregorian Easter Sunday (anonymous Gregorian algorithm, Meeus/Jones/Butcher).
function H.easter(y)
    local a = y % 19
    local b, c = math.floor(y / 100), y % 100
    local d, e = math.floor(b / 4), b % 4
    local f = math.floor((b + 8) / 25)
    local g = math.floor((b - f + 1) / 3)
    local h = (19 * a + b - d - g + 15) % 30
    local i, k = math.floor(c / 4), c % 4
    local l = (32 + 2 * e + 2 * i - h - k) % 7
    local m = math.floor((a + 11 * h + 22 * l) / 451)
    local month = math.floor((h + l - 7 * m + 114) / 31)
    local day = (h + l - 7 * m + 114) % 31 + 1
    return y, month, day
end

-- n-th weekday `wd` (1 = Monday) of a month; n = -1 for the last one.
function H.nthWeekday(y, m, wd, n)
    if n > 0 then
        local first = D.weekday(y, m, 1)
        return y, m, 1 + (wd - first) % 7 + 7 * (n - 1)
    end
    local last = D.daysInMonth(y, m)
    local lwd = D.weekday(y, m, last)
    return y, m, last - (lwd - wd) % 7
end

local function hol(list, y, m, d, en, fr, extra)
    local h = { y, m, d, en = en, fr = fr }
    if extra then for k, v in pairs(extra) do h[k] = v end end
    list[#list + 1] = h
    return h
end

local function easterOffset(y, n)
    local ey, em, ed = H.easter(y)
    return D.addDays(ey, em, ed, n)
end

-- ---------------------------------------------------------------------------
-- Countries
-- ---------------------------------------------------------------------------

local C = {}

function C.fr(y, opts)
    local l = {}
    hol(l, y, 1, 1, "New Year's Day", "Jour de l'an")
    if opts and opts.alsace then
        local a, b, c = easterOffset(y, -2)
        hol(l, a, b, c, "Good Friday", "Vendredi saint")
    end
    local a, b, c = H.easter(y)
    hol(l, a, b, c, "Easter Sunday", "Pâques")
    a, b, c = easterOffset(y, 1)
    hol(l, a, b, c, "Easter Monday", "Lundi de Pâques")
    hol(l, y, 5, 1, "Labour Day", "Fête du Travail")
    if y >= 1953 and not (y >= 1959 and y <= 1981) then
        hol(l, y, 5, 8, "Victory in Europe Day", "Victoire 1945")
    end
    a, b, c = easterOffset(y, 39)
    hol(l, a, b, c, "Ascension Day", "Ascension")
    a, b, c = easterOffset(y, 49)
    hol(l, a, b, c, "Whit Sunday", "Pentecôte")
    -- Whit Monday became the "journée de solidarité" in 2005 (worked in many
    -- companies) but is still a public holiday by law.
    a, b, c = easterOffset(y, 50)
    hol(l, a, b, c, "Whit Monday", "Lundi de Pentecôte")
    hol(l, y, 7, 14, "Bastille Day", "Fête nationale")
    hol(l, y, 8, 15, "Assumption Day", "Assomption")
    hol(l, y, 11, 1, "All Saints' Day", "Toussaint")
    hol(l, y, 11, 11, "Armistice Day", "Armistice 1918")
    hol(l, y, 12, 25, "Christmas Day", "Noël")
    if opts and opts.alsace then
        hol(l, y, 12, 26, "St Stephen's Day", "Saint-Étienne")
    end
    return l
end

-- UK: a holiday on a weekend moves to the next weekday not already taken.
local function ukSubstitutes(l, y)
    local taken = {}
    for _i, h in ipairs(l) do taken[D.toDays(h[1], h[2], h[3])] = true end
    for _i, key in ipairs({ { 1, 1, "New Year's Day", "Jour de l'an" },
                            { 12, 25, "Christmas Day", "Noël" },
                            { 12, 26, "Boxing Day", "Lendemain de Noël" } }) do
        local m, d = key[1], key[2]
        local wd = D.weekday(y, m, d)
        if wd >= 6 then
            local z = D.toDays(y, m, d)
            repeat
                z = z + 1
            until ((z + 3) % 7 + 1) <= 5 and not taken[z]
            taken[z] = true
            local yy, mm, dd = D.fromDays(z)
            hol(l, yy, mm, dd, key[3] .. " (substitute day)", key[4] .. " (jour de remplacement)", { observed = true })
        end
    end
end

local UK_ONE_OFF = {
    { 1999, 12, 31, "Millennium Celebrations", "Célébrations du millénaire" },
    { 2002, 6, 3, "Golden Jubilee", "Jubilé d'or" },
    { 2011, 4, 29, "Royal Wedding", "Mariage royal" },
    { 2012, 6, 5, "Diamond Jubilee", "Jubilé de diamant" },
    { 2022, 6, 3, "Platinum Jubilee", "Jubilé de platine" },
    { 2022, 9, 19, "State Funeral of Queen Elizabeth II", "Funérailles d'Élisabeth II" },
    { 2023, 5, 8, "Coronation of King Charles III", "Couronnement de Charles III" },
}
-- Years the late-May / early-May holidays moved.
local UK_SPRING = { [2002] = { 6, 4 }, [2012] = { 6, 4 }, [2022] = { 6, 2 } }
local UK_EARLY_MAY = { [1995] = { 5, 8 }, [2020] = { 5, 8 } }

function C.uk(y)
    local l = {}
    hol(l, y, 1, 1, "New Year's Day", "Jour de l'an")
    local a, b, c = easterOffset(y, -2)
    hol(l, a, b, c, "Good Friday", "Vendredi saint")
    a, b, c = easterOffset(y, 1)
    hol(l, a, b, c, "Easter Monday", "Lundi de Pâques")
    if y >= 1978 then
        local em = UK_EARLY_MAY[y]
        if em then hol(l, y, em[1], em[2], "Early May bank holiday", "Jour férié de début mai")
        else
            local _y, m, d = H.nthWeekday(y, 5, 1, 1)
            hol(l, y, m, d, "Early May bank holiday", "Jour férié de début mai")
        end
    end
    local sp = UK_SPRING[y]
    if sp then hol(l, y, sp[1], sp[2], "Spring bank holiday", "Jour férié de printemps")
    else
        local _y, m, d = H.nthWeekday(y, 5, 1, -1)
        hol(l, y, m, d, "Spring bank holiday", "Jour férié de printemps")
    end
    local _y, m, d = H.nthWeekday(y, 8, 1, -1)
    hol(l, y, m, d, "Summer bank holiday", "Jour férié d'été")
    hol(l, y, 12, 25, "Christmas Day", "Noël")
    hol(l, y, 12, 26, "Boxing Day", "Lendemain de Noël")
    for _i, o in ipairs(UK_ONE_OFF) do
        if o[1] == y then hol(l, y, o[2], o[3], o[4], o[5]) end
    end
    ukSubstitutes(l, y)
    return l
end

-- US: Saturday holidays are observed on the Friday before, Sunday ones on
-- the Monday after.
local function usFixed(l, y, m, d, en, fr)
    hol(l, y, m, d, en, fr)
    local wd = D.weekday(y, m, d)
    if wd == 6 then
        local a, b, c = D.addDays(y, m, d, -1)
        hol(l, a, b, c, en .. " (observed)", fr .. " (jour chômé)", { observed = true })
    elseif wd == 7 then
        local a, b, c = D.addDays(y, m, d, 1)
        hol(l, a, b, c, en .. " (observed)", fr .. " (jour chômé)", { observed = true })
    end
end

function C.us(y)
    local l = {}
    usFixed(l, y, 1, 1, "New Year's Day", "Jour de l'an")
    if y >= 1986 then
        local a, b, c = H.nthWeekday(y, 1, 1, 3)
        hol(l, a, b, c, "Martin Luther King Jr. Day", "Journée Martin Luther King")
    end
    local a, b, c = H.nthWeekday(y, 2, 1, 3)
    hol(l, a, b, c, "Washington's Birthday", "Anniversaire de Washington")
    a, b, c = H.nthWeekday(y, 5, 1, -1)
    hol(l, a, b, c, "Memorial Day", "Memorial Day")
    if y >= 2021 then usFixed(l, y, 6, 19, "Juneteenth", "Juneteenth") end
    usFixed(l, y, 7, 4, "Independence Day", "Fête de l'Indépendance")
    a, b, c = H.nthWeekday(y, 9, 1, 1)
    hol(l, a, b, c, "Labor Day", "Fête du Travail")
    a, b, c = H.nthWeekday(y, 10, 1, 2)
    hol(l, a, b, c, "Columbus Day", "Columbus Day")
    usFixed(l, y, 11, 11, "Veterans Day", "Journée des anciens combattants")
    a, b, c = H.nthWeekday(y, 11, 4, 4)
    hol(l, a, b, c, "Thanksgiving Day", "Thanksgiving")
    usFixed(l, y, 12, 25, "Christmas Day", "Noël")
    -- New Year's Day of next year on a Saturday is observed on 31 December.
    if D.weekday(y + 1, 1, 1) == 6 then
        hol(l, y, 12, 31, "New Year's Day (observed)", "Jour de l'an (jour chômé)", { observed = true })
    end
    -- ... and this year's, observed last year, is not a day off this year.
    for i = #l, 1, -1 do
        if l[i][1] ~= y then table.remove(l, i) end
    end
    return l
end

function C.de(y)
    local l = {}
    hol(l, y, 1, 1, "New Year's Day", "Jour de l'an")
    local a, b, c = easterOffset(y, -2)
    hol(l, a, b, c, "Good Friday", "Vendredi saint")
    a, b, c = H.easter(y)
    hol(l, a, b, c, "Easter Sunday", "Pâques")
    a, b, c = easterOffset(y, 1)
    hol(l, a, b, c, "Easter Monday", "Lundi de Pâques")
    hol(l, y, 5, 1, "Labour Day", "Fête du Travail")
    a, b, c = easterOffset(y, 39)
    hol(l, a, b, c, "Ascension Day", "Ascension")
    a, b, c = easterOffset(y, 49)
    hol(l, a, b, c, "Whit Sunday", "Pentecôte")
    a, b, c = easterOffset(y, 50)
    hol(l, a, b, c, "Whit Monday", "Lundi de Pentecôte")
    if y >= 1990 then hol(l, y, 10, 3, "German Unity Day", "Fête de l'unité allemande") end
    if y == 2017 then hol(l, y, 10, 31, "Reformation Day", "Fête de la Réformation") end
    hol(l, y, 12, 25, "Christmas Day", "Noël")
    hol(l, y, 12, 26, "St Stephen's Day", "Saint-Étienne")
    return l
end

function C.es(y)
    local l = {}
    hol(l, y, 1, 1, "New Year's Day", "Jour de l'an")
    hol(l, y, 1, 6, "Epiphany", "Épiphanie")
    local a, b, c = easterOffset(y, -2)
    hol(l, a, b, c, "Good Friday", "Vendredi saint")
    hol(l, y, 5, 1, "Labour Day", "Fête du Travail")
    hol(l, y, 8, 15, "Assumption Day", "Assomption")
    hol(l, y, 10, 12, "National Day of Spain", "Fête nationale espagnole")
    hol(l, y, 11, 1, "All Saints' Day", "Toussaint")
    hol(l, y, 12, 6, "Constitution Day", "Jour de la Constitution")
    hol(l, y, 12, 8, "Immaculate Conception", "Immaculée Conception")
    hol(l, y, 12, 25, "Christmas Day", "Noël")
    return l
end

function C.be(y)
    local l = {}
    hol(l, y, 1, 1, "New Year's Day", "Jour de l'an")
    local a, b, c = H.easter(y)
    hol(l, a, b, c, "Easter Sunday", "Pâques")
    a, b, c = easterOffset(y, 1)
    hol(l, a, b, c, "Easter Monday", "Lundi de Pâques")
    hol(l, y, 5, 1, "Labour Day", "Fête du Travail")
    a, b, c = easterOffset(y, 39)
    hol(l, a, b, c, "Ascension Day", "Ascension")
    a, b, c = easterOffset(y, 49)
    hol(l, a, b, c, "Whit Sunday", "Pentecôte")
    a, b, c = easterOffset(y, 50)
    hol(l, a, b, c, "Whit Monday", "Lundi de Pentecôte")
    hol(l, y, 7, 21, "Belgian National Day", "Fête nationale")
    hol(l, y, 8, 15, "Assumption Day", "Assomption")
    hol(l, y, 11, 1, "All Saints' Day", "Toussaint")
    hol(l, y, 11, 11, "Armistice Day", "Armistice")
    hol(l, y, 12, 25, "Christmas Day", "Noël")
    return l
end

function C.ch(y)
    local l = {}
    hol(l, y, 1, 1, "New Year's Day", "Nouvel An")
    hol(l, y, 1, 2, "St Berchtold's Day", "Saint-Berchtold")
    local a, b, c = easterOffset(y, -2)
    hol(l, a, b, c, "Good Friday", "Vendredi saint")
    a, b, c = H.easter(y)
    hol(l, a, b, c, "Easter Sunday", "Pâques")
    a, b, c = easterOffset(y, 1)
    hol(l, a, b, c, "Easter Monday", "Lundi de Pâques")
    a, b, c = easterOffset(y, 39)
    hol(l, a, b, c, "Ascension Day", "Ascension")
    a, b, c = easterOffset(y, 49)
    hol(l, a, b, c, "Whit Sunday", "Pentecôte")
    a, b, c = easterOffset(y, 50)
    hol(l, a, b, c, "Whit Monday", "Lundi de Pentecôte")
    hol(l, y, 8, 1, "Swiss National Day", "Fête nationale")
    hol(l, y, 12, 25, "Christmas Day", "Noël")
    hol(l, y, 12, 26, "St Stephen's Day", "Saint-Étienne")
    return l
end

function C.ca(y)
    local l = {}
    hol(l, y, 1, 1, "New Year's Day", "Jour de l'an")
    local a, b, c = easterOffset(y, -2)
    hol(l, a, b, c, "Good Friday", "Vendredi saint")
    -- Victoria Day: the last Monday before 25 May.
    local z = D.toDays(y, 5, 24)
    while (z + 3) % 7 + 1 ~= 1 do z = z - 1 end
    a, b, c = D.fromDays(z)
    hol(l, a, b, c, "Victoria Day", "Fête de la Reine / journée nationale des patriotes")
    if D.weekday(y, 7, 1) == 7 then
        hol(l, y, 7, 2, "Canada Day", "Fête du Canada")
    else
        hol(l, y, 7, 1, "Canada Day", "Fête du Canada")
    end
    a, b, c = H.nthWeekday(y, 9, 1, 1)
    hol(l, a, b, c, "Labour Day", "Fête du Travail")
    if y >= 2021 then
        hol(l, y, 9, 30, "National Day for Truth and Reconciliation", "Journée nationale de la vérité et de la réconciliation")
    end
    a, b, c = H.nthWeekday(y, 10, 1, 2)
    hol(l, a, b, c, "Thanksgiving", "Action de grâce")
    hol(l, y, 11, 11, "Remembrance Day", "Jour du Souvenir")
    hol(l, y, 12, 25, "Christmas Day", "Noël")
    hol(l, y, 12, 26, "Boxing Day", "Lendemain de Noël")
    return l
end

-- ---------------------------------------------------------------------------
-- Lookup
-- ---------------------------------------------------------------------------

function H.list(country, y, opts)
    local f = C[country] or C.fr
    local l = f(y, opts)
    table.sort(l, function(a, b) return D.toDays(a[1], a[2], a[3]) < D.toDays(b[1], b[2], b[3]) end)
    return l
end

-- A memo of { [day number] = { holiday, ... } } per country/year/options.
local cache = {}
function H.byDay(country, y, opts)
    local key = country .. ":" .. y .. ":" .. tostring(opts and opts.alsace or false)
    local t = cache[key]
    if not t then
        t = {}
        for _i, h in ipairs(H.list(country, y, opts)) do
            local z = D.toDays(h[1], h[2], h[3])
            t[z] = t[z] or {}
            table.insert(t[z], h)
        end
        cache[key] = t
    end
    return t
end

-- Holidays on a date (a list, possibly empty).
function H.on(country, y, m, d, opts)
    return H.byDay(country, y, opts)[D.toDays(y, m, d)] or {}
end

-- A day off: a holiday falling on a weekday (Sundays are not counted again).
function H.isDayOff(country, y, m, d, opts)
    return #H.on(country, y, m, d, opts) > 0
end

-- Default country from KOReader's UI language ("fr", "en_GB", "de" ...).
function H.defaultCountry(lang)
    lang = tostring(lang or "en")
    local region = lang:match("^%a%a[_-](%a%a)")
    region = region and region:lower()
    local map = { fr = "fr", gb = "uk", uk = "uk", us = "us", de = "de", at = "de",
                  es = "es", be = "be", ch = "ch", ca = "ca" }
    if region and map[region] then return map[region] end
    local l2 = lang:sub(1, 2):lower()
    return ({ fr = "fr", de = "de", es = "es", nl = "be", en = "us" })[l2] or "fr"
end

return H
