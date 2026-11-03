-- names.lua -- month and weekday names, and date formatting, by language.
-- Pure data: not routed through the shared i18n table, where single words
-- like "May" or "March" would collide with other plugins' keys.

local N = {}

N.MONTHS = {
    en = { "January", "February", "March", "April", "May", "June", "July",
           "August", "September", "October", "November", "December" },
    fr = { "janvier", "février", "mars", "avril", "mai", "juin", "juillet",
           "août", "septembre", "octobre", "novembre", "décembre" },
    de = { "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
           "August", "September", "Oktober", "November", "Dezember" },
    es = { "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
           "agosto", "septiembre", "octubre", "noviembre", "diciembre" },
}

-- ISO order: Monday first.
N.WEEKDAYS = {
    en = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" },
    fr = { "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche" },
    de = { "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag" },
    es = { "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo" },
}

N.SHORT_WEEKDAYS = {
    en = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" },
    fr = { "lun", "mar", "mer", "jeu", "ven", "sam", "dim" },
    de = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" },
    es = { "lun", "mar", "mié", "jue", "vie", "sáb", "dom" },
}

local function pick(t, lang) return t[lang] or t.en end

local function cap(s)
    -- Upper-cases the first letter, accented ones included (é -> É).
    local first, rest = s:match("^([\xC0-\xDF][\x80-\xBF])(.*)$")
    if first then
        local up = { ["é"] = "É", ["è"] = "È", ["à"] = "À", ["â"] = "Â", ["ô"] = "Ô", ["î"] = "Î" }
        return (up[first] or first) .. rest
    end
    return s:sub(1, 1):upper() .. s:sub(2)
end
N.cap = cap

function N.month(m, lang) return pick(N.MONTHS, lang)[m] end
function N.weekday(wd, lang) return pick(N.WEEKDAYS, lang)[wd] end
function N.shortWeekday(wd, lang) return pick(N.SHORT_WEEKDAYS, lang)[wd] end

-- "November 2026" / "Novembre 2026"
function N.monthTitle(y, m, lang)
    return cap(N.month(m, lang)) .. " " .. y
end

-- Long date with weekday: "Tuesday, 3 November 2026" (en: US order when
-- us is set), "Mardi 3 novembre 2026", "Dienstag, 3. November 2026",
-- "martes, 3 de noviembre de 2026".
-- French and Spanish weekdays are lower case inside a sentence; `capital`
-- capitalises the first letter for a date standing on its own.
function N.longDate(y, m, d, wd, lang, us, capital)
    local s = N._longDate(y, m, d, wd, lang, us)
    return capital and cap(s) or s
end

function N._longDate(y, m, d, wd, lang, us)
    if lang == "fr" then
        return string.format("%s %s %s %d", N.weekday(wd, lang), d == 1 and "1er" or tostring(d), N.month(m, lang), y)
    elseif lang == "de" then
        return string.format("%s, %d. %s %d", N.weekday(wd, lang), d, N.month(m, lang), y)
    elseif lang == "es" then
        return string.format("%s, %d de %s de %d", N.weekday(wd, lang), d, N.month(m, lang), y)
    end
    if us then
        return string.format("%s, %s %d, %d", N.weekday(wd, "en"), N.month(m, "en"), d, y)
    end
    return string.format("%s, %d %s %d", N.weekday(wd, "en"), d, N.month(m, "en"), y)
end

-- Short numeric date as typed back in dialogs: 03/11/2026, or 11/03/2026 (US).
function N.numeric(y, m, d, us)
    if us then return string.format("%02d/%02d/%04d", m, d, y) end
    return string.format("%02d/%02d/%04d", d, m, y)
end

return N
