-- Specs for dates.lua, holidays.lua and moon.lua (pure logic).
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

local D = require("dates")
local H = require("holidays")
local Moon = require("moon")

local function utc(y, m, d, hh, mm)
    return D.toDays(y, m, d) * 86400 + (hh or 0) * 3600 + (mm or 0) * 60
end

describe("dates", function()
    it("round-trips day numbers", function()
        assert.are.equal(0, D.toDays(1970, 1, 1))
        assert.are.equal(-1, D.toDays(1969, 12, 31))
        for _i, z in ipairs({ -719468, -1, 0, 11016, 20000, 2932896 }) do
            assert.are.equal(z, D.toDays(D.fromDays(z)))
        end
    end)

    it("knows leap years and weekdays", function()
        assert.is_true(D.isLeap(2000)); assert.is_false(D.isLeap(1900)); assert.is_true(D.isLeap(2024))
        assert.are.equal(29, D.daysInMonth(2024, 2)); assert.are.equal(28, D.daysInMonth(2100, 2))
        assert.are.equal(2, D.weekday(2026, 11, 3))   -- Tuesday
        assert.are.equal(4, D.weekday(1970, 1, 1))    -- Thursday
        assert.are.equal(2, D.weekday(1789, 7, 14))   -- Tuesday
        assert.are.equal(7, D.weekday(2000, 1, 2))    -- Sunday
    end)

    it("computes day of year and ISO weeks", function()
        assert.are.equal(307, D.dayOfYear(2026, 11, 3))
        assert.are.equal(366, D.dayOfYear(2024, 12, 31))
        local function wk(y, m, d) local a, b = D.isoWeek(y, m, d); return a .. "-W" .. b end
        assert.are.equal("2026-W45", wk(2026, 11, 3))
        assert.are.equal("2020-W53", wk(2020, 12, 31))
        assert.are.equal("2020-W53", wk(2021, 1, 3))
        assert.are.equal("2021-W1", wk(2021, 1, 4))
        assert.are.equal("2026-W1", wk(2026, 1, 1))
        assert.are.equal("2026-W53", wk(2027, 1, 1))
        assert.are.equal("2025-W1", wk(2024, 12, 30))
        assert.are.equal("2009-W53", wk(2010, 1, 3))
    end)

    it("adds days, weeks, months with clamping", function()
        assert.are.same({ 2027, 1, 2 }, { D.addDays(2026, 12, 31, 2) })
        assert.are.same({ 2024, 2, 29 }, { D.addMonths(2024, 1, 31, 1) })
        assert.are.same({ 2023, 2, 28 }, { D.addMonths(2024, 2, 29, -12) })
        assert.are.same({ 2025, 11, 30 }, { D.addMonths(2026, 1, 30, -2) })
        assert.are.same({ 2026, 11, 24 }, { D.addOffset(2026, 11, 3, 3, "w") })
    end)

    it("counts days and working days between dates", function()
        assert.are.equal(365, D.diff(2025, 1, 1, 2026, 1, 1))
        assert.are.equal(-1, D.diff(2026, 1, 2, 2026, 1, 1))
        -- Mon 2 Nov 2026 .. Mon 9 Nov 2026: 5 working days end excluded, 6 included
        assert.are.equal(5, D.workingDays({ 2026, 11, 2 }, { 2026, 11, 9 }, nil, false))
        assert.are.equal(6, D.workingDays({ 2026, 11, 2 }, { 2026, 11, 9 }, nil, true))
        -- November 2026 in France: 21 weekdays minus Armistice (Wed 11) = 20;
        -- All Saints' Day falls on a Sunday.
        local fr = function(y, m, d) return H.isDayOff("fr", y, m, d) end
        assert.are.equal(20, D.workingDays({ 2026, 11, 1 }, { 2026, 11, 30 }, fr, true))
        assert.are.equal(-5, D.workingDays({ 2026, 11, 9 }, { 2026, 11, 2 }, nil, false))
    end)

    it("computes ages", function()
        assert.are.same({ 36, 4, 20 }, { D.age({ 1990, 6, 14 }, { 2026, 11, 3 }) })
        assert.are.same({ 1, 0, 0 }, { D.age({ 2025, 11, 3 }, { 2026, 11, 3 }) })
        assert.are.same({ 0, 11, 30 }, { D.age({ 2025, 11, 3 }, { 2026, 11, 2 }) })
        -- born 29 Feb: one year old on 28 Feb of the next year
        assert.are.same({ 1, 0, 0 }, { D.age({ 2024, 2, 29 }, { 2025, 2, 28 }) })
        assert.is_nil(D.age({ 2027, 1, 1 }, { 2026, 1, 1 }))
        local y, m, d, n, k = D.nextBirthday({ 1990, 6, 14 }, { 2026, 11, 3 })
        assert.are.same({ 2027, 6, 14, 223, 37 }, { y, m, d, n, k })
    end)

    it("parses typed dates and offsets", function()
        assert.are.same({ 2026, 11, 3 }, { D.parse("2026-11-03") })
        assert.are.same({ 2026, 11, 3 }, { D.parse("3/11/2026") })
        assert.are.same({ 2026, 11, 3 }, { D.parse("03.11.2026") })
        assert.are.same({ 2026, 11, 3 }, { D.parse("11/3/2026", true) })
        assert.are.same({ 1985, 4, 7 }, { D.parse("7/4/85") })
        assert.is_nil(D.parse("31/02/2026"))
        assert.is_nil(D.parse("hello"))
        assert.are.same({ 10, "d" }, { D.parseOffset("+10") })
        assert.are.same({ -3, "w" }, { D.parseOffset("-3 semaines") })
        assert.are.same({ 2, "m" }, { D.parseOffset("2m") })
        assert.are.same({ 1, "y" }, { D.parseOffset("1 an") })
        assert.is_nil(D.parseOffset("x"))
    end)

    it("lays out a month grid on the right first weekday", function()
        local g = D.monthGrid(2026, 11, 1)   -- Monday first
        assert.are.same({ 2026, 10, 26 }, g[1][1])
        assert.are.same({ 2026, 11, 1 }, g[1][7])
        g = D.monthGrid(2026, 11, 7)         -- Sunday first
        assert.are.same({ 2026, 11, 1 }, g[1][1])
    end)
end)

describe("Easter", function()
    local known = {
        [1818] = { 3, 22 }, [1943] = { 4, 25 }, [2000] = { 4, 23 }, [2008] = { 3, 23 },
        [2011] = { 4, 24 }, [2019] = { 4, 21 }, [2024] = { 3, 31 }, [2025] = { 4, 20 },
        [2026] = { 4, 5 }, [2027] = { 3, 28 }, [2038] = { 4, 25 }, [2285] = { 3, 22 },
    }
    for y, md in pairs(known) do
        it("falls on the right day in " .. y, function()
            local _y, m, d = H.easter(y)
            assert.are.same(md, { m, d })
        end)
    end
end)

describe("holidays", function()
    local function names(country, y, opts)
        local out = {}
        for _i, h in ipairs(H.list(country, y, opts)) do
            out[#out + 1] = string.format("%02d-%02d", h[2], h[3])
        end
        return table.concat(out, " ")
    end

    it("France 2026, with and without Alsace-Moselle", function()
        assert.are.equal("01-01 04-05 04-06 05-01 05-08 05-14 05-24 05-25 07-14 08-15 11-01 11-11 12-25",
            names("fr", 2026))
        assert.are.equal("01-01 04-03 04-05 04-06 05-01 05-08 05-14 05-24 05-25 07-14 08-15 11-01 11-11 12-25 12-26",
            names("fr", 2026, { alsace = true }))
        assert.are.equal("Ascension", H.on("fr", 2026, 5, 14)[1].fr)
        assert.are.equal("Lundi de Pentecôte", H.on("fr", 2026, 5, 25)[1].fr)
        assert.are.equal(0, #H.on("fr", 1970, 5, 8))
    end)

    it("England & Wales with substitute days and moved holidays", function()
        assert.are.equal("01-01 04-03 04-06 05-04 05-25 08-31 12-25 12-26 12-28", names("uk", 2026))
        -- 2022: Spring holiday moved to 2 June, Platinum Jubilee 3 June,
        -- State Funeral 19 Sept, Christmas on Sunday -> substitute on the 27th
        assert.are.equal("01-01 01-03 04-15 04-18 05-02 06-02 06-03 08-29 09-19 12-25 12-26 12-27",
            names("uk", 2022))
        -- 2020: early May moved to Friday 8 May (VE Day)
        assert.are.equal(1, #H.on("uk", 2020, 5, 8))
        -- 2021: Christmas Sat, Boxing Day Sun -> 27 and 28 December
        assert.is_true(H.isDayOff("uk", 2021, 12, 27))
        assert.is_true(H.isDayOff("uk", 2021, 12, 28))
    end)

    it("US federal holidays with observed days", function()
        assert.are.equal("01-01 01-19 02-16 05-25 06-19 07-03 07-04 09-07 10-12 11-11 11-26 12-25",
            names("us", 2026))
        -- 1 Jan 2022 is a Saturday: observed on Friday 31 Dec 2021
        assert.is_true(H.isDayOff("us", 2021, 12, 31))
        assert.are.equal(0, #H.on("us", 1980, 1, 21))   -- no MLK Day before 1986
    end)

    it("Germany, Spain, Belgium, Switzerland, Canada 2026", function()
        assert.are.equal("01-01 04-03 04-05 04-06 05-01 05-14 05-24 05-25 10-03 12-25 12-26", names("de", 2026))
        assert.are.equal("01-01 01-06 04-03 05-01 08-15 10-12 11-01 12-06 12-08 12-25", names("es", 2026))
        assert.are.equal("01-01 04-05 04-06 05-01 05-14 05-24 05-25 07-21 08-15 11-01 11-11 12-25", names("be", 2026))
        assert.are.equal("01-01 01-02 04-03 04-05 04-06 05-14 05-24 05-25 08-01 12-25 12-26", names("ch", 2026))
        assert.are.equal("01-01 04-03 05-18 07-01 09-07 09-30 10-12 11-11 12-25 12-26", names("ca", 2026))
        assert.is_true(H.isDayOff("de", 2017, 10, 31))
        assert.are.equal(2, select(3, H.list("ca", 2018)[4][1], H.list("ca", 2018)[4][2], H.list("ca", 2018)[4][3]))
    end)

    it("picks the country from the UI language", function()
        assert.are.equal("fr", H.defaultCountry("fr"))
        assert.are.equal("ca", H.defaultCountry("fr_CA"))
        assert.are.equal("us", H.defaultCountry("en"))
        assert.are.equal("uk", H.defaultCountry("en_GB"))
        assert.are.equal("us", H.defaultCountry("en_US"))
        assert.are.equal("de", H.defaultCountry("de"))
        assert.are.equal("es", H.defaultCountry("es"))
        assert.are.equal("fr", H.defaultCountry("ja"))
    end)
end)

describe("moon", function()
    local function within(t, expected, tol)
        assert.is_true(math.abs(t - expected) <= tol,
            string.format("off by %.1f h", (t - expected) / 3600))
    end
    local function nearest(kind, around)
        for _i, ev in ipairs(Moon.eventsBetween(around - 5 * 86400, around + 5 * 86400)) do
            if ev.kind == kind then return ev.t end
        end
    end

    it("finds known full moons within an hour", function()
        for _i, fm in ipairs({
            { 2000, 1, 21, 4, 40 }, { 2019, 1, 21, 5, 16 }, { 2022, 11, 8, 11, 2 },
            { 2024, 9, 18, 2, 34 }, { 2025, 3, 14, 6, 55 }, { 2025, 9, 7, 18, 9 },
        }) do
            local exp = utc(fm[1], fm[2], fm[3], fm[4], fm[5])
            within(nearest("full", exp), exp, 3600)
        end
    end)

    it("finds known new moons (solar eclipses) within an hour", function()
        for _i, nm in ipairs({ { 2017, 8, 21, 18, 30 }, { 2024, 4, 8, 18, 21 }, { 2000, 1, 6, 18, 14 } }) do
            local exp = utc(nm[1], nm[2], nm[3], nm[4], nm[5])
            within(nearest("new", exp), exp, 3600)
        end
    end)

    it("names phases and ages in between", function()
        local fm = utc(2024, 9, 18, 2, 34)
        assert.are.equal("full", Moon.phaseName(fm))
        assert.are.equal("waning_gibbous", Moon.phaseName(fm + 4 * 86400))
        local age, illum = Moon.ageAt(fm)
        assert.is_true(age > 14 and age < 16)
        assert.is_true(illum > 0.99)
        local list = Moon.eventsBetween(utc(2026, 1, 1), utc(2027, 1, 1))
        assert.is_true(#list >= 48 and #list <= 50)
        for i = 2, #list do assert.is_true(list[i].t > list[i - 1].t) end
    end)
end)
