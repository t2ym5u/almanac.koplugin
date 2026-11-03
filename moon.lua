-- moon.lua -- moon phases. Pure Lua.
--
-- The instants of new moon, first quarter, full moon and last quarter come
-- from Jean Meeus, "Astronomical Algorithms", chapter 49: the mean phase
-- plus the main periodic terms (the planetary terms, worth well under a
-- minute, are left out). Good to a few minutes over centuries -- far more
-- than a calendar needs. Times are Unix seconds, UTC.

local M = {}

M.SYNODIC = 29.530588861

local rad = math.pi / 180
local sin, cos, floor = math.sin, math.cos, math.floor

-- Phase kinds by quarter offset.
M.KINDS = { [0] = "new", [1] = "first", [2] = "full", [3] = "last" }

-- Instant (Unix UTC) of the phase k: integer k = new moon, +0.25 first
-- quarter, +0.5 full, +0.75 last quarter. k = 0 is the new moon of
-- 6 January 2000.
function M.phaseTime(k)
    local T = k / 1236.85
    local T2, T3, T4 = T * T, T * T * T, T * T * T * T
    local jde = 2451550.09766 + M.SYNODIC * k + 0.00015437 * T2 - 0.000000150 * T3 + 0.00000000073 * T4
    local E  = 1 - 0.002516 * T - 0.0000074 * T2
    local Ms = (2.5534 + 29.10535670 * k - 0.0000014 * T2 - 0.00000011 * T3) * rad
    local Mm = (201.5643 + 385.81693528 * k + 0.0107582 * T2 + 0.00001238 * T3 - 0.000000058 * T4) * rad
    local F  = (160.7108 + 390.67050284 * k - 0.0016118 * T2 - 0.00000227 * T3 + 0.000000011 * T4) * rad
    local Om = (124.7746 - 1.56375588 * k + 0.0020672 * T2 + 0.00000215 * T3) * rad
    local q = floor(k * 4 + 0.5) % 4
    local c
    if q == 0 or q == 2 then
        local a = q == 0 and { -0.40720, 0.17241, 0.01608, 0.01039, 0.00739, -0.00514, 0.00208 }
                          or { -0.40614, 0.17302, 0.01614, 0.01043, 0.00734, -0.00515, 0.00209 }
        c = a[1] * sin(Mm) + a[2] * E * sin(Ms) + a[3] * sin(2 * Mm) + a[4] * sin(2 * F)
          + a[5] * E * sin(Mm - Ms) + a[6] * E * sin(Mm + Ms) + a[7] * E * E * sin(2 * Ms)
          - 0.00111 * sin(Mm - 2 * F) - 0.00057 * sin(Mm + 2 * F)
          + 0.00056 * E * sin(2 * Mm + Ms) - 0.00042 * sin(3 * Mm)
          + 0.00042 * E * sin(Ms + 2 * F) + 0.00038 * E * sin(Ms - 2 * F)
          - 0.00024 * E * sin(2 * Mm - Ms) - 0.00017 * sin(Om)
    else
        c = -0.62801 * sin(Mm) + 0.17172 * E * sin(Ms) - 0.01183 * E * sin(Mm + Ms)
          + 0.00862 * sin(2 * Mm) + 0.00804 * sin(2 * F) + 0.00454 * E * sin(Mm - Ms)
          + 0.00204 * E * E * sin(2 * Ms) - 0.00180 * sin(Mm - 2 * F) - 0.00070 * sin(Mm + 2 * F)
          - 0.00040 * sin(3 * Mm) - 0.00034 * E * sin(2 * Mm - Ms)
          + 0.00032 * E * sin(Ms + 2 * F) + 0.00032 * E * sin(Ms - 2 * F)
          - 0.00028 * E * E * sin(Mm + 2 * Ms) + 0.00027 * E * sin(2 * Ms) - 0.00017 * sin(Om)
        local W = 0.00306 - 0.00038 * E * cos(Ms) + 0.00026 * cos(Mm)
                - 0.00002 * cos(Mm - Ms) + 0.00002 * cos(Mm + Ms) + 0.00002 * cos(2 * F)
        c = c + (q == 1 and W or -W)
    end
    jde = jde + c
    -- TT to UTC: about 69 s these decades; close enough at any date shown.
    return (jde - 2440587.5) * 86400 - 69
end

-- k (in quarters) of the phase nearest to Unix time t.
local function nearestQuarter(t)
    local jd = t / 86400 + 2440587.5
    return floor((jd - 2451550.09766) / M.SYNODIC * 4 + 0.5)
end

-- Every principal phase with t0 <= time < t1: { kind, t }, in order.
function M.eventsBetween(t0, t1)
    local out = {}
    local q = nearestQuarter(t0) - 1
    while true do
        local t = M.phaseTime(q / 4)
        if t >= t1 then break end
        if t >= t0 then out[#out + 1] = { kind = M.KINDS[q % 4], t = t } end
        q = q + 1
    end
    return out
end

-- Last new moon at or before t (Unix time).
function M.previousNew(t)
    local k = floor(nearestQuarter(t) / 4) + 1
    while M.phaseTime(k) > t do k = k - 1 end
    return M.phaseTime(k), k
end

-- Age in days since the last new moon, and illuminated fraction (0..1).
function M.ageAt(t)
    local nt, k = M.previousNew(t)
    local next_new = M.phaseTime(k + 1)
    local age = (t - nt) / 86400
    local frac = (t - nt) / (next_new - nt)
    local illum = (1 - cos(2 * math.pi * frac)) / 2
    return age, illum, frac
end

-- One of eight phase names for the moon at t: the four principal phases
-- when one falls within `window` seconds (default: 12 h either side, so a
-- calendar day shows its phase), otherwise the crescent/gibbous in between.
function M.phaseName(t, window)
    window = window or 43200
    for _i, ev in ipairs(M.eventsBetween(t - window, t + window)) do
        return ev.kind
    end
    local _age, _illum, frac = M.ageAt(t)
    if frac < 0.25 then return "waxing_crescent"
    elseif frac < 0.5 then return "waxing_gibbous"
    elseif frac < 0.75 then return "waning_gibbous"
    end
    return "waning_crescent"
end

return M
