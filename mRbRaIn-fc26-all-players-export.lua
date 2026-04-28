-- mRbRaIn-fc26-all-players-export.lua
-- Exports ALL FC26 players as a JSON array that exactly matches the
-- sofifaDataScraper PlayerRecord.to_export_dict() format.
--
-- Output: %USERPROFILE%\Downloads\FC26_all_players.json
--
-- Usage: load in FC26 Live Editor → run script
-- Requires: FC26 Live Editor with career save loaded

require 'imports/career_mode/enums'
require 'imports/career_mode/helpers'
require 'imports/other/helpers'

local VERSION = "FC26"
local IMAGE_VERSION_PREFIX = "26"

-- ============================================================
-- Bitwise AND  (LuaJIT bit.band → bit32.band → pure-Lua)
-- ============================================================
local _band
if bit and bit.band then
    _band = bit.band
elseif bit32 and bit32.band then
    _band = bit32.band
else
    _band = function(a, b)
        local result, bv = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then result = result + bv end
            bv = bv * 2
            a  = math.floor(a / 2)
            b  = math.floor(b / 2)
        end
        return result
    end
end

-- ============================================================
-- PlayStyle bitmask tables
-- trait1 / icontrait1  →  PLAYSTYLE1_BITS
-- trait2 / icontrait2  →  PLAYSTYLE2_BITS  (GK + Low Driven only)
-- ============================================================
local PLAYSTYLE1_BITS = {
    { bit = 1,         name = "Finesse Shot"   },
    { bit = 2,         name = "Chip Shot"      },
    { bit = 4,         name = "Power Shot"     },
    { bit = 8,         name = "Dead Ball"      },
    { bit = 16,        name = "Power Header"   },
    { bit = 32,        name = "Incisive Pass"  },
    { bit = 64,        name = "Pinged Pass"    },
    { bit = 128,       name = "Long Ball Pass" },
    { bit = 256,       name = "Tiki Taka"      },
    { bit = 512,       name = "Whipped Pass"   },
    { bit = 1024,      name = "Jockey"         },
    { bit = 2048,      name = "Block"          },
    { bit = 4096,      name = "Intercept"      },
    { bit = 8192,      name = "Anticipate"     },
    { bit = 16384,     name = "Slide Tackle"   },
    { bit = 32768,     name = "Bruiser"        },
    { bit = 65536,     name = "Technical"      },
    { bit = 131072,    name = "Rapid"          },
    { bit = 262144,    name = "Flair"          },
    { bit = 524288,    name = "First Touch"    },
    { bit = 1048576,   name = "Trickster"      },
    { bit = 2097152,   name = "Press Proven"   },
    { bit = 4194304,   name = "Quick Step"     },
    { bit = 8388608,   name = "Relentless"     },
    { bit = 16777216,  name = "Trivela"        },
    { bit = 33554432,  name = "Acrobatic"      },
    { bit = 67108864,  name = "Long Throw"     },
    { bit = 134217728, name = "Aerial"         },
    { bit = 268435456, name = "GK Far Throw"   },
    { bit = 536870912, name = "GK Footwork"    },
}

-- trait2 / icontrait2: only playstyle bits, not career-mode traits (64/128/256/512/1024)
local PLAYSTYLE2_BITS = {
    { bit = 1,  name = "GK Cross Claimer" },
    { bit = 2,  name = "GK Rush Out"      },
    { bit = 4,  name = "GK Far Reach"     },
    { bit = 8,  name = "GK Quick Reflexes"},
    { bit = 48, name = "Low Driven Shot"  },  -- bits 16+32 combined
}

-- ============================================================
-- DB / helper utilities  (self-contained, no careerhub dep)
-- ============================================================
local function safe_call(fn_name, ...)
    local fn = _G[fn_name]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    return ok and result or nil
end

local function get_table(name)
    if LE and LE.db and LE.db.GetTable then
        local ok, tbl = pcall(function() return LE.db:GetTable(name) end)
        if ok and tbl then return tbl end
    end
    return nil
end

local function has_field(tbl, field_name)
    return tbl ~= nil and tbl.fields ~= nil and tbl.fields[field_name] ~= nil
end

local function read_field(tbl, record, field_name, default_value)
    if not tbl or not record or record <= 0 or not has_field(tbl, field_name) then
        return default_value
    end
    local ok, value = pcall(function()
        return tbl:GetRecordFieldValue(record, field_name)
    end)
    if ok and value ~= nil then return value end
    return default_value
end

local function read_first_of(tbl, record, field_names, default_value)
    if not tbl or not record then return default_value end
    for _, fname in ipairs(field_names) do
        if has_field(tbl, fname) then
            local v = read_field(tbl, record, fname, nil)
            if v ~= nil then return v end
        end
    end
    return default_value
end

local function iterate_records(tbl, fn)
    if not tbl or type(fn) ~= "function" then return end
    local record = tbl:GetFirstRecord()
    while record and record > 0 do
        fn(record)
        record = tbl:GetNextValidRecord()
    end
end

-- ============================================================
-- Date helpers
-- ============================================================
local _current_date = GetCurrentDate()
local _birth_date_obj = DATE:new()

local function days_to_date_str(days)
    if not days or days <= 0 then return "" end
    local d = DATE:new()
    d:FromGregorianDays(days)
    return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
end

local function calc_age(birth_days)
    if not birth_days or birth_days <= 0 then return nil end
    _birth_date_obj:FromGregorianDays(birth_days)
    local age = _current_date.year - _birth_date_obj.year
    if _current_date.month < _birth_date_obj.month or
       (_current_date.month == _birth_date_obj.month and
        _current_date.day  < _birth_date_obj.day) then
        age = age - 1
    end
    return age
end

-- ============================================================
-- Lookup tables
-- ============================================================
local FOOT      = { [0] = "Left",   [1] = "Right" }
local WORK_RATE = { [0] = "Low", [1] = "Medium", [2] = "High" }

-- ============================================================
-- Nation name cache
-- ============================================================
local _nation_cache = nil

local function load_nation_cache()
    if _nation_cache then return _nation_cache end
    _nation_cache = {}
    local tbl = get_table("nations")
    iterate_records(tbl, function(rec)
        local nid = read_first_of(tbl, rec, {"nationid","countryid","id"}, -1)
        if nid and nid > 0 then
            local nm = read_first_of(tbl, rec, {"nationname","countryname","name","shortname"}, "")
            if nm and nm ~= "" then _nation_cache[nid] = nm end
        end
    end)
    return _nation_cache
end

local function nation_name(nation_id)
    if not nation_id or nation_id <= 0 then return "" end
    local name = safe_call("GetNationName", nation_id)
             or safe_call("GetCountryName", nation_id)
             or safe_call("GetNationalityName", nation_id)
    if name and name ~= "" then return name end
    return load_nation_cache()[nation_id] or ""
end

-- ============================================================
-- League / team name helpers
-- ============================================================
local function load_league_names()
    local names = {}
    local tbl = get_table("leagues")
    iterate_records(tbl, function(rec)
        local lid = read_field(tbl, rec, "leagueid", -1)
        if lid and lid > 0 then
            names[lid] = read_field(tbl, rec, "leaguename", "") or ""
        end
    end)
    return names
end

local function build_team_league_map(league_names)
    local map = {}
    local tbl = get_table("leagueteamlinks")
    iterate_records(tbl, function(rec)
        local tid = read_field(tbl, rec, "teamid",   -1)
        local lid = read_field(tbl, rec, "leagueid", -1)
        if tid and tid > 0 and lid and lid > 0 then
            map[tid] = league_names[lid] or ""
        end
    end)
    return map
end

local function team_name(team_id)
    if not team_id or team_id <= 0 then return "" end
    return safe_call("GetTeamName", team_id) or ""
end

-- ============================================================
-- Display format helpers
-- ============================================================
local function height_display(h)
    if not h or h <= 0 then return "" end
    local total_inches = math.floor(h / 2.54 + 0.5)
    local feet   = math.floor(total_inches / 12)
    local inches = total_inches % 12
    return string.format('%dcm / %d\'%d"', h, feet, inches)
end

local function weight_display(w)
    if not w or w <= 0 then return "" end
    local lbs = math.floor(w * 2.20462 + 0.5)
    return string.format("%dkg / %dlbs", w, lbs)
end

local function format_value(v)
    if not v or v <= 0 then return "" end
    if v >= 1000000 then
        local m = v / 1000000
        if m == math.floor(m) then
            return string.format("\xE2\x82\xAC%dM", math.floor(m))
        else
            return string.format("\xE2\x82\xAC%.1fM", m)
        end
    elseif v >= 1000 then
        local k = v / 1000
        if k == math.floor(k) then
            return string.format("\xE2\x82\xAC%dK", math.floor(k))
        else
            return string.format("\xE2\x82\xAC%.1fK", k)
        end
    else
        return string.format("\xE2\x82\xAC%d", math.floor(v))
    end
end

-- ============================================================
-- Position helper
-- ============================================================
local function pos_name(pos_id)
    if pos_id == nil or pos_id < 0 then return "" end
    return safe_call("GetPlayerPrimaryPositionName", pos_id) or ""
end

local function collect_alt_positions(pt, rec, primary_name)
    local alt  = {}
    local seen = { [primary_name] = true }
    for _, fname in ipairs({"preferredposition2","preferredposition3","preferredposition4"}) do
        if has_field(pt, fname) then
            local pid = read_field(pt, rec, fname, -1)
            if pid and pid >= 0 then
                local nm = pos_name(pid)
                if nm ~= "" and not seen[nm] then
                    seen[nm] = true
                    alt[#alt + 1] = nm
                end
            end
        end
    end
    return alt
end

-- ============================================================
-- PlayStyle decoder
-- Returns: base_list, plus_list
--   icontrait bits  → PlayStyle+ (name with "+")
--   trait bits only → regular PlayStyle
-- ============================================================
local function decode_playstyles(trait, icontrait, bit_table)
    local base = {}
    local plus = {}
    local t  = trait    or 0
    local ti = icontrait or 0
    for _, entry in ipairs(bit_table) do
        local b      = entry.bit
        local in_ti  = _band(ti, b) == b
        local in_t   = _band(t,  b) == b
        if in_ti then
            plus[#plus + 1] = entry.name .. "+"
        elseif in_t then
            base[#base + 1] = entry.name
        end
    end
    return base, plus
end

local function merge_playstyles(b1, p1, b2, p2)
    local base, plus = {}, {}
    for _, v in ipairs(b1) do base[#base + 1] = v end
    for _, v in ipairs(b2) do base[#base + 1] = v end
    for _, v in ipairs(p1) do plus[#plus + 1] = v end
    for _, v in ipairs(p2) do plus[#plus + 1] = v end
    return base, plus
end

-- ============================================================
-- Attribute fields to read from players table
-- ============================================================
local ATTRIBUTE_FIELDS = {
    -- Main stats (separate DB fields in some FC versions)
    "pac", "sho", "pas", "dri", "def", "phy",
    -- Individual attributes
    "acceleration",   "aggression",       "agility",
    "balance",        "ballcontrol",      "composure",
    "crossing",       "curve",            "defensiveawareness",
    "dribbling",      "finishing",        "freekickaccuracy",
    "gkdiving",       "gkhandling",       "gkkicking",
    "gkpositioning",  "gkreflexes",       "headingaccuracy",
    "interceptions",  "jumping",          "longpassing",
    "longshots",      "penalties",        "reactions",
    "shortpassing",   "shotpower",        "skillmoves",
    "slidingtackle",  "sprintspeed",      "stamina",
    "standingtackle", "strength",         "vision",
    "volleys",        "weakfootabilitytypecode",
}

local function read_attributes(pt, rec)
    local attrs = {}
    for _, fname in ipairs(ATTRIBUTE_FIELDS) do
        if has_field(pt, fname) then
            local v = read_field(pt, rec, fname, nil)
            if v ~= nil then attrs[fname] = v end
        end
    end
    return attrs
end

-- ============================================================
-- JSON serializer  (pretty-print, handles array/object/scalar)
-- ============================================================
local function to_json(value, indent)
    indent = indent or 0
    local kind = type(value)
    local pad  = string.rep("  ", indent)

    if kind == "table" then
        local is_array  = true
        local max_index = 0
        local count     = 0
        for key, _ in pairs(value) do
            count = count + 1
            if type(key) ~= "number" or key <= 0 or key ~= math.floor(key) then
                is_array = false; break
            end
            if key > max_index then max_index = key end
        end
        if is_array and max_index ~= count then is_array = false end

        if is_array then
            if count == 0 then return "[]" end
            local parts = {}
            for i = 1, #value do
                parts[#parts + 1] = pad .. "  " .. to_json(value[i], indent + 1)
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
        end

        if count == 0 then return "{}" end
        local keys = {}
        for key, _ in pairs(value) do keys[#keys + 1] = tostring(key) end
        table.sort(keys)
        local parts = {}
        for _, key in ipairs(keys) do
            parts[#parts + 1] = string.format(
                '%s  "%s": %s',
                pad,
                key:gsub("\\","\\\\"):gsub('"','\\"'),
                to_json(value[key], indent + 1)
            )
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
    end

    if kind == "string" then
        local esc = value
            :gsub("\\","\\\\"):gsub('"','\\"')
            :gsub("\b","\\b"):gsub("\f","\\f")
            :gsub("\n","\\n"):gsub("\r","\\r")
            :gsub("\t","\\t")
        return '"' .. esc .. '"'
    end

    if kind == "number" or kind == "boolean" then
        return tostring(value)
    end

    return "null"
end

-- ============================================================
-- Downloads directory
-- ============================================================
local function downloads_dir()
    local profile = os.getenv("USERPROFILE") or ""
    return profile ~= "" and (profile .. "\\Downloads") or "."
end

-- ============================================================
-- MAIN EXPORT
-- ============================================================
local function export_all_players()
    local pt = get_table("players")
    if not pt then
        error("Could not open 'players' table – make sure a career save is loaded.")
    end

    -- Pre-load lookup tables
    print("Loading league names…")
    local league_names   = load_league_names()
    local team_league    = build_team_league_map(league_names)

    print("Iterating players table…")
    local players = {}
    local skipped = 0

    iterate_records(pt, function(rec)
        local player_id = read_field(pt, rec, "playerid", -1)
        if not player_id or player_id <= 0 then return end

        local ovr = read_field(pt, rec, "overallrating", nil)
        -- Skip placeholder / invalid rows (OVR = 0 or nil usually means dummy entry)
        if not ovr or ovr <= 0 then
            skipped = skipped + 1
            return
        end

        -- ── Identity ──────────────────────────────────────────────────────────
        local display_name = safe_call("GetPlayerName", player_id)
                          or ("PLAYER_" .. player_id)

        local fname  = read_first_of(pt, rec, {"firstname","firstName","first_name"}, "")
        local lname  = read_first_of(pt, rec, {"lastname","lastName","last_name","surname"}, "")
        local common = read_first_of(pt, rec, {"commonname","commonName","aliasname","alias"}, "")

        -- Prefer common name (known-as name) as the display name when available
        if common and common ~= "" then
            display_name = common
        end

        local full_name
        if fname ~= "" and lname ~= "" then
            full_name = fname .. " " .. lname
        else
            full_name = display_name
        end

        -- Derive first/last from display_name if DB didn't provide them
        local fn, ln
        if fname ~= "" then
            fn, ln = fname, lname
        else
            local parts = {}
            for part in display_name:gmatch("%S+") do parts[#parts + 1] = part end
            if #parts >= 2 then
                fn = parts[1]
                ln = table.concat(parts, " ", 2)
            else
                fn = display_name
                ln = ""
            end
        end

        -- ── Physical ──────────────────────────────────────────────────────────
        local h          = read_field(pt, rec, "height", nil)
        local w          = read_field(pt, rec, "weight", nil)
        local birth_days = read_field(pt, rec, "birthdate", nil)
        local birthdate  = days_to_date_str(birth_days)
        local age        = calc_age(birth_days)

        -- ── Nationality ───────────────────────────────────────────────────────
        local nat_id = read_field(pt, rec, "nationality", nil)
        local nat    = nation_name(nat_id)

        -- ── Position ──────────────────────────────────────────────────────────
        local pos1_id     = read_first_of(pt, rec, {"preferredposition1"}, -1)
        local primary_pos = pos_name(pos1_id)
        local alt_pos     = collect_alt_positions(pt, rec, primary_pos)

        -- ── Club / league ─────────────────────────────────────────────────────
        local team_id = safe_call("GetTeamIdFromPlayerId", player_id)
        local club    = team_name(team_id)
        local league  = (team_id and team_league[team_id]) or ""

        -- ── Player characteristics ────────────────────────────────────────────
        local foot_code = read_field(pt, rec, "preferredfoot", nil)
        local foot      = FOOT[foot_code] or ""
        local wf        = read_field(pt, rec, "weakfootabilitytypecode", nil)
        local sm        = read_first_of(pt, rec, {"skillmoves","skillmovesrating"}, nil)
        local awr_code  = read_first_of(pt, rec, {"attackingworkrate","attackworkrate"}, nil)
        local dwr_code  = read_first_of(pt, rec, {"defensiveworkrate","defenseworkrate"}, nil)
        local awr       = WORK_RATE[awr_code] or ""
        local dwr       = WORK_RATE[dwr_code] or ""
        local intrep    = read_first_of(pt, rec, {"internationalrep","internationalreputation","reputation"}, nil)
        local pot       = read_field(pt, rec, "potential", nil)

        -- Real face flag
        local rf_raw  = read_first_of(pt, rec, {"realface","hasrealface","realfacecode"}, nil)
        local rf
        if rf_raw ~= nil then
            rf = (rf_raw == 1 or rf_raw == true)
        else
            rf = false
        end

        -- ── Value / salary ────────────────────────────────────────────────────
        local val_raw  = read_first_of(pt, rec, {"value","playervalue"}, nil)
        local wage_raw = read_first_of(pt, rec, {"weeklywage","wage"}, nil)

        -- ── PlayStyles ────────────────────────────────────────────────────────
        local t1  = read_field(pt, rec, "trait1",    0) or 0
        local ti1 = read_field(pt, rec, "icontrait1",0) or 0
        local t2  = read_field(pt, rec, "trait2",    0) or 0
        local ti2 = read_field(pt, rec, "icontrait2",0) or 0
        local b1, p1 = decode_playstyles(t1,  ti1, PLAYSTYLE1_BITS)
        local b2, p2 = decode_playstyles(t2,  ti2, PLAYSTYLE2_BITS)
        local all_ps, all_pp = merge_playstyles(b1, p1, b2, p2)

        -- ── Attributes ────────────────────────────────────────────────────────
        local attrs = read_attributes(pt, rec)

        -- ── Build export record ───────────────────────────────────────────────
        players[#players + 1] = {
            playerid                 = player_id,
            playername               = display_name,
            age                      = age,
            position                 = primary_pos,
            overallrating            = ovr,
            potential                = pot,
            nationality              = nat,
            club                     = club,
            marketvalue              = format_value(val_raw),
            salary                   = format_value(wage_raw),
            full_name                = full_name,
            first_name               = fn,
            last_name                = ln,
            birthdate                = birthdate,
            league                   = league,
            preferred_foot           = foot,
            weak_foot                = wf,
            skill_moves              = sm,
            height_cm                = h,
            height_display           = height_display(h),
            weight_kg                = w,
            weight_display           = weight_display(w),
            attacking_work_rate      = awr,
            defensive_work_rate      = dwr,
            alternative_positions    = alt_pos,
            release_clause           = "",
            international_reputation = intrep,
            real_face                = rf,
            playstyles               = all_ps,
            playstyles_plus          = all_pp,
            attributes               = attrs,
            source_url               = string.format("https://sofifa.com/player/%d", player_id),
            source_release_id        = "",
            source_version           = VERSION,
            image                    = {
                file    = string.format("%s_%d.png", IMAGE_VERSION_PREFIX, player_id),
                url     = "",
                type    = "playerface",
                version = VERSION,
            },
            raw_data                 = {},
        }
    end)

    print(string.format("Collected %d players (%d skipped). Sorting…", #players, skipped))

    -- Sort: OVR desc → potential desc → name asc
    table.sort(players, function(a, b)
        local ao, bo = a.overallrating or 0, b.overallrating or 0
        if ao ~= bo then return ao > bo end
        local ap, bp = a.potential or 0, b.potential or 0
        if ap ~= bp then return ap > bp end
        return (a.playername or "") < (b.playername or "")
    end)

    -- Write JSON
    print("Serialising JSON…")
    local json_str = to_json(players, 0)

    local out_path = downloads_dir() .. "\\FC26_all_players.json"
    local f, err = io.open(out_path, "w")
    if not f then
        error("Could not write to " .. out_path .. ": " .. tostring(err))
    end
    f:write(json_str)
    f:close()

    print(string.format(
        "Done! Exported %d players → %s  (%.1f KB)",
        #players, out_path, #json_str / 1024
    ))
end

-- ============================================================
-- Run
-- ============================================================
local ok, err = pcall(export_all_players)
if not ok then
    print("EXPORT FAILED: " .. tostring(err))
end
