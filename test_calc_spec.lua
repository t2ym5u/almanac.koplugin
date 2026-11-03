-- Specs for calc.lua (texts of the day panel and of the date calculator).
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path
local C = dofile(DIR .. "calc.lua")

local function ctx(lang, country, extra)
    local c = { lang = lang, country = country or "fr", hol_opts = {},
                tr = function(s) return s end, offset = function() return 3600 end }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

describe("calc", function()
    it("describes a day", function()
        local lines = C.dayInfo(2026, 7, 14, ctx("fr"), { 2026, 7, 14 })
        assert.are.equal("Mardi 14 juillet 2026", lines[1])
        assert.are.equal("Day 195 of 365 · week 29", lines[2])
        assert.are.equal("Today", lines[3])
        assert.are.equal("Fête nationale", lines[4])
        assert.truthy(lines[5]:match("^Moon: "))
        lines = C.dayInfo(2027, 1, 1, ctx("en", "uk"), { 2026, 12, 30 })
        assert.are.equal("Friday, 1 January 2027", lines[1])
        assert.are.equal("Day 1 of 365 · week 53 (2026)", lines[2])
        assert.are.equal("In 2 days", lines[3])
    end)

    it("shows a principal moon phase with its local time", function()
        -- full moon 2024-09-18 02:34 UTC = 03:34 at UTC+1
        assert.truthy(C.moonLine(2024, 9, 18, ctx("en")):match("^Moon: Full moon at 03:3%d$"))
        assert.truthy(C.moonLine(2024, 9, 22, ctx("en")):match("Waning gibbous"))
    end)

    it("formats thousands", function()
        assert.are.equal("13,291", C.thousands(13291, "en"))
        assert.are.equal("13\u{202F}291", C.thousands(13291, "fr"))
        assert.are.equal("291", C.thousands(291, "fr"))
        assert.are.equal("-1,000", C.thousands(-1000, "en"))
    end)

    it("computes the calculator texts", function()
        local t = C.between({ 2026, 11, 2 }, { 2026, 11, 16 }, ctx("en"))
        assert.truthy(t:find("14 days (end day not counted)", 1, true))
        assert.truthy(t:find("15 days counting both ends", 1, true))
        assert.truthy(t:find("= 2 weeks and 0 days", 1, true))
        -- 2..13 Nov minus Armistice: 9 working days; 10 with Mon 16
        assert.truthy(t:find("Working days: 9 (10 counting the end day)", 1, true))
        local txt, r = C.add({ 2026, 1, 31 }, 1, "m", ctx("en"))
        assert.are.same({ 2026, 2, 28 }, r)
        assert.truthy(txt:find("+ 1 months", 1, true))
        local a = C.age({ 1990, 6, 14 }, { 2026, 11, 3 }, ctx("en"))
        assert.truthy(a:find("36 years, 4 months and 20 days", 1, true))
        assert.truthy(a:find("in 223 days", 1, true))
        assert.are.equal("The birth date is after the reference date.", C.age({ 2030, 1, 1 }, { 2026, 1, 1 }, ctx("en")))
    end)
end)
