require 'imports/career_mode/enums'
require 'imports/career_mode/helpers'
require 'imports/other/helpers'

local TARGET_TEAM_ID = 36
local TARGET_TEAM_NAME = nil
local SEASON_START_MONTH = 7

local function to_json(value, indent)
  indent = indent or 0
  local kind = type(value)
  local pad = string.rep("  ", indent)

  if kind == "table" then
    local is_array = true
    local max_index = 0
    local count = 0

    for key, _ in pairs(value) do
      count = count + 1
      if type(key) ~= "number" or key <= 0 or key ~= math.floor(key) then
        is_array = false
        break
      end
      if key > max_index then
        max_index = key
      end
    end

    if is_array and max_index ~= count then
      is_array = false
    end

    if is_array then
      local parts = {}
      for i = 1, #value do
        parts[#parts + 1] = pad .. "  " .. to_json(value[i], indent + 1)
      end
      return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
    end

    local keys = {}
    for key, _ in pairs(value) do
      keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
      parts[#parts + 1] = string.format(
        "%s  \"%s\": %s",
        pad,
        key:gsub("\\", "\\\\"):gsub('"', '\\"'),
        to_json(value[key], indent + 1)
      )
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
  end

  if kind == "string" then
    local escaped = value
      :gsub("\\", "\\\\")
      :gsub('"', '\\"')
      :gsub("\b", "\\b")
      :gsub("\f", "\\f")
      :gsub("\n", "\\n")
      :gsub("\r", "\\r")
      :gsub("\t", "\\t")
    return '"' .. escaped .. '"'
  end

  if kind == "number" or kind == "boolean" then
    return tostring(value)
  end

  return "null"
end

local function safe_call(fn_name, ...)
  local fn = _G[fn_name]
  if type(fn) ~= "function" then
    return nil
  end

  local ok, result = pcall(fn, ...)
  if ok then
    return result
  end

  return nil
end

local fallback_db = nil
local fallback_db_loaded = false

local function load_fallback_db()
  if fallback_db_loaded then
    return fallback_db
  end

  fallback_db_loaded = true
  local ok, DB = pcall(require, 'imports/t3db/db')
  if not ok or not DB then
    fallback_db = nil
    return nil
  end

  local db = DB:new()
  local load_ok = pcall(function()
    db:Load()
  end)

  if load_ok then
    fallback_db = db
  else
    fallback_db = nil
  end

  return fallback_db
end

local function get_table(name)
  if LE and LE.db and LE.db.GetTable then
    local ok, tbl = pcall(function()
      return LE.db:GetTable(name)
    end)
    if ok and tbl then
      return tbl
    end
  end

  local db = load_fallback_db()
  if db and db.GetTable then
    local ok, tbl = pcall(function()
      return db:GetTable(name)
    end)
    if ok and tbl then
      return tbl
    end
  end

  return nil
end

local function get_live_table(name)
  if LE and LE.db and LE.db.GetTable then
    local ok, tbl = pcall(function()
      return LE.db:GetTable(name)
    end)
    if ok and tbl then
      return tbl
    end
  end

  return nil
end

local function has_field(tbl, field_name)
  return tbl and tbl.fields and tbl.fields[field_name] ~= nil
end

local function read_field(tbl, record, field_name, default_value)
  if not tbl or not record or record <= 0 or not has_field(tbl, field_name) then
    return default_value
  end

  local ok, value = pcall(function()
    return tbl:GetRecordFieldValue(record, field_name)
  end)

  if ok and value ~= nil then
    return value
  end

  return default_value
end

local function read_first_available_field(tbl, record, field_names, default_value)
  if not tbl or not record or not field_names then
    return default_value
  end

  for _, field_name in ipairs(field_names) do
    if has_field(tbl, field_name) then
      local value = read_field(tbl, record, field_name, default_value)
      if value ~= nil then
        return value
      end
    end
  end

  return default_value
end

local function iterate_records(tbl, fn)
  if not tbl or type(fn) ~= "function" then
    return
  end

  local record = tbl:GetFirstRecord()
  while record and record > 0 do
    fn(record)
    record = tbl:GetNextValidRecord()
  end
end

local function find_team_id_by_name(target_name)
  for team_id = 1, 200000 do
    local name = safe_call("GetTeamName", team_id)
    if name == target_name then
      return team_id
    end
  end

  error("Team not found: " .. tostring(target_name))
end

local current_date = GetCurrentDate()
local current_date_days = current_date:ToGregorianDays()

local function get_season_years(year_value, month_value)
  local start_year = year_value
  if month_value < SEASON_START_MONTH then
    start_year = start_year - 1
  end
  return start_year, start_year + 1
end

local function build_season_labels(year_value, month_value)
  local start_year, end_year = get_season_years(year_value, month_value)
  return {
    start_year = start_year,
    end_year = end_year,
    display = string.format("%04d/%02d", start_year, end_year % 100),
    file = string.format("%04d-%02d", start_year, end_year % 100)
  }
end

local season = build_season_labels(current_date.year, current_date.month or SEASON_START_MONTH)

local function season_label_from_index(index_value, max_index, current_start_year)
  if index_value == nil or max_index == nil then
    return nil
  end

  local delta = max_index - index_value
  local start_year = current_start_year - delta
  local end_year = start_year + 1
  return string.format("%04d/%02d", start_year, end_year % 100)
end

local function team_name(team_id)
  if not team_id or team_id <= 0 then
    return ""
  end

  local name = safe_call("GetTeamName", team_id)
  return name or ("TEAM_" .. tostring(team_id))
end

local function player_name(player_id)
  if not player_id or player_id <= 0 then
    return ""
  end

  local name = safe_call("GetPlayerName", player_id)
  return name or ("PLAYER_" .. tostring(player_id))
end

local function competition_name(comp_id)
  if not comp_id or comp_id <= 0 then
    return ""
  end

  local name = safe_call("GetCompetitionNameByObjID", comp_id)
  if name and name ~= "" then
    return name
  end

  return ""
end

local nation_name_cache = nil

local function load_nation_name_cache()
  if nation_name_cache ~= nil then
    return nation_name_cache
  end

  nation_name_cache = {}
  local nations_table = get_table("nations")

  iterate_records(nations_table, function(record)
    local nation_id = read_first_available_field(nations_table, record, { "nationid", "countryid", "id" }, -1)
    if nation_id and nation_id > 0 then
      local display_name = read_first_available_field(
        nations_table,
        record,
        { "nationname", "countryname", "name", "shortname" },
        ""
      )

      if display_name and display_name ~= "" then
        nation_name_cache[nation_id] = display_name
      end
    end
  end)

  return nation_name_cache
end

local function nation_name(nation_id)
  if not nation_id or nation_id <= 0 then
    return ""
  end

  local helper_name =
    safe_call("GetNationName", nation_id) or
    safe_call("GetCountryName", nation_id) or
    safe_call("GetNationalityName", nation_id) or
    safe_call("GetNationNameById", nation_id) or
    safe_call("GetCountryNameById", nation_id)

  if helper_name and helper_name ~= "" then
    return helper_name
  end

  local names = load_nation_name_cache()
  return names[nation_id] or ""
end

local function format_date_from_days(raw_days)
  if not raw_days or raw_days <= 0 then
    return ""
  end

  local date_obj = DATE:new()
  date_obj:FromGregorianDays(raw_days)
  return string.format("%04d-%02d-%02d", date_obj.year, date_obj.month, date_obj.day)
end

local function format_date_from_yyyymmdd(raw_date)
  if not raw_date or raw_date <= 0 then
    return ""
  end

  local year_value = math.floor(raw_date / 10000)
  local month_value = math.floor(raw_date / 100) % 100
  local day_value = raw_date % 100
  return string.format("%04d-%02d-%02d", year_value, month_value, day_value)
end

local function format_time_from_seconds(raw_seconds)
  if raw_seconds == nil or raw_seconds < 0 then
    return ""
  end

  local hours = math.floor(raw_seconds / 3600)
  local minutes = math.floor((raw_seconds % 3600) / 60)
  return string.format("%02d:%02d", hours, minutes)
end

local function downloads_dir()
  local profile = os.getenv("USERPROFILE") or ""
  if profile ~= "" then
    return profile .. "\\Downloads"
  end
  return "."
end

local function sorted_values(map, sorter)
  local list = {}
  for _, value in pairs(map) do
    list[#list + 1] = value
  end
  if sorter then
    table.sort(list, sorter)
  end
  return list
end

local target_team_id = TARGET_TEAM_ID or find_team_id_by_name(TARGET_TEAM_NAME)

local function load_contract_map(team_id)
  local contracts = {}
  local contract_table = get_table("career_playercontract")

  iterate_records(contract_table, function(record)
    local record_team_id = read_field(contract_table, record, "teamid", -1)
    local player_id = read_field(contract_table, record, "playerid", -1)

    if record_team_id == team_id and player_id > 0 then
      local contract_date = read_field(contract_table, record, "contract_date", 0)
      local existing = contracts[player_id]
      if not existing or contract_date >= (existing.contract_date or 0) then
        contracts[player_id] = {
          playerid = player_id,
          teamid = record_team_id,
          wage = read_field(contract_table, record, "wage", nil),
          contract_date = contract_date,
          contract_status = read_field(contract_table, record, "contract_status", nil),
          duration_months = read_field(contract_table, record, "duration_months", nil),
          player_role = read_field(contract_table, record, "playerrole", nil),
          performance_bonus_value = read_field(contract_table, record, "performancebonusvalue", nil),
          performance_bonus_count = read_field(contract_table, record, "performancebonuscount", nil)
        }
      end
    end
  end)

  return contracts
end

local function load_team_player_links(team_id)
  local rows = {}
  local link_table = get_table("teamplayerlinks")

  iterate_records(link_table, function(record)
    local record_team_id = read_field(link_table, record, "teamid", -1)
    local player_id = read_field(link_table, record, "playerid", -1)

    if record_team_id == team_id and player_id > 0 then
      rows[player_id] = {
        teamid = record_team_id,
        playerid = player_id,
        jersey_number = read_field(link_table, record, "jerseynumber", nil),
        league_appearances = read_field(link_table, record, "leagueappearances", 0),
        league_goals = read_field(link_table, record, "leaguegoals", 0),
        reds = read_field(link_table, record, "reds", 0),
        yellows = read_field(link_table, record, "yellows", 0),
        position = read_field(link_table, record, "position", nil),
        form = read_field(link_table, record, "form", nil)
      }
    end
  end)

  return rows
end

local function build_record_index(tbl, key_field)
  local index = {}

  iterate_records(tbl, function(record)
    local key_value = read_field(tbl, record, key_field, -1)
    if key_value and key_value > 0 and index[key_value] == nil then
      index[key_value] = record
    end
  end)

  return index
end

local function load_owned_loan_map(team_id)
  local loans = {}
  local loan_table = get_table("playerloans")

  iterate_records(loan_table, function(record)
    local player_id = read_field(loan_table, record, "playerid", -1)
    local loaned_from_team_id = read_field(loan_table, record, "teamidloanedfrom", -1)

    if player_id > 0 and loaned_from_team_id == team_id then
      loans[player_id] = {
        playerid = player_id,
        teamidloanedfrom = loaned_from_team_id,
        loandateend = read_field(loan_table, record, "loandateend", nil),
        isloantobuy = read_field(loan_table, record, "isloantobuy", nil)
      }
    end
  end)

  return loans
end

local function load_player_minutes_map()
  local minutes_map = {}
  local rating_table = get_table("career_playermatchratinghistory")
  local last_match_table = get_table("career_playerlastmatchhistory")

  iterate_records(rating_table, function(record)
    local player_id = read_field(rating_table, record, "playerid", -1)
    if player_id <= 0 then
      return
    end

    local entry = minutes_map[player_id]
    if not entry then
      entry = {
        minutes_played = 0,
        matches_played = 0,
        match_history = {},
        rating_total = 0,
        rating_entries = 0
      }
      minutes_map[player_id] = entry
    end

    local mins_played = read_field(rating_table, record, "minsplayed", 0) or 0
    local raw_rating = read_field(rating_table, record, "rating", nil)
    local position_id = read_field(rating_table, record, "position", nil)
    local raw_date = read_field(rating_table, record, "date", nil)

    entry.match_history[#entry.match_history + 1] = {
      date = raw_date,
      date_text = format_date_from_yyyymmdd(raw_date),
      minsplayed = mins_played,
      rating = raw_rating,
      rating_display = (raw_rating and raw_rating >= 0) and string.format("%0.2f", raw_rating / 10) or "",
      position = position_id,
      position_name = position_id and (safe_call("GetPlayerPrimaryPositionName", position_id) or "") or ""
    }

    if mins_played > 0 then
      entry.minutes_played = entry.minutes_played + mins_played
      entry.matches_played = entry.matches_played + 1
    end

    if raw_rating and raw_rating >= 0 then
      entry.rating_total = entry.rating_total + raw_rating
      entry.rating_entries = entry.rating_entries + 1
    end
  end)

  iterate_records(last_match_table, function(record)
    local player_id = read_field(last_match_table, record, "playerid", -1)
    if player_id <= 0 then
      return
    end

    local entry = minutes_map[player_id]
    if not entry then
      entry = {
        minutes_played = 0,
        matches_played = 0,
        match_history = {},
        rating_total = 0,
        rating_entries = 0
      }
      minutes_map[player_id] = entry
    end

    local snapshot_team_id = read_field(last_match_table, record, "teamid", nil)
    local snapshot_position_id = read_field(last_match_table, record, "position", nil)
    entry.last_match_snapshot = {
      teamid = snapshot_team_id,
      teamname = team_name(snapshot_team_id),
      minsplayed = read_field(last_match_table, record, "minsplayed", nil),
      playeroverall = read_field(last_match_table, record, "playeroverall", nil),
      playerfact = read_field(last_match_table, record, "playerfact", nil),
      position = snapshot_position_id,
      position_name = snapshot_position_id and (safe_call("GetPlayerPrimaryPositionName", snapshot_position_id) or "") or ""
    }
  end)

  for _, entry in pairs(minutes_map) do
    table.sort(entry.match_history, function(a, b)
      if (a.date or 0) ~= (b.date or 0) then
        return (a.date or 0) < (b.date or 0)
      end
      return (a.minsplayed or 0) < (b.minsplayed or 0)
    end)

    if entry.matches_played > 0 then
      entry.average_minutes = string.format("%0.2f", entry.minutes_played / entry.matches_played)
    else
      entry.average_minutes = "0.00"
    end

    if entry.rating_entries > 0 then
      entry.average_rating = string.format("%0.2f", (entry.rating_total / entry.rating_entries) / 10)
    else
      entry.average_rating = "0.00"
    end

    entry.last_match = entry.match_history[#entry.match_history] or nil
    entry.rating_total = nil
    entry.rating_entries = nil
  end

  return minutes_map
end

local function read_player_attributes(players_table, record)
  local attributes = {}
  local attribute_fields = {
    "acceleration",
    "aggression",
    "agility",
    "balance",
    "ballcontrol",
    "composure",
    "crossing",
    "curve",
    "defensiveawareness",
    "dribbling",
    "dribspeed",
    "finishing",
    "freekickaccuracy",
    "gkdiving",
    "gkhandling",
    "gkkicking",
    "gkpositioning",
    "gkreflexes",
    "headingaccuracy",
    "interceptions",
    "jumping",
    "longpassing",
    "longshots",
    "penalties",
    "reactions",
    "shortpassing",
    "shotpower",
    "skillmoves",
    "slidingtackle",
    "sprintspeed",
    "stamina",
    "standingtackle",
    "strength",
    "vision",
    "volleys",
    "weakfootabilitytypecode"
  }

  for _, field_name in ipairs(attribute_fields) do
    if has_field(players_table, field_name) then
      attributes[field_name] = read_field(players_table, record, field_name, nil)
    end
  end

  return attributes
end

local function get_player_value(player_id, players_table, record, live_players_table, live_record)
  local helper_value =
    safe_call("GetPlayerValue", player_id) or
    safe_call("GetPlayerMarketValue", player_id)

  if helper_value ~= nil and helper_value ~= 0 then
    return helper_value
  end

  local live_value = read_field(live_players_table, live_record, "value", nil)
  if live_value ~= nil and live_value ~= 0 then
    return live_value
  end

  local db_value = read_field(players_table, record, "value", nil)
  if db_value ~= nil and db_value ~= 0 then
    return db_value
  end

  return nil
end

local function get_player_salary(player_id, contract_entry, players_table, record)
  if contract_entry and contract_entry.wage ~= nil then
    return contract_entry.wage
  end

  local helper_salary =
    safe_call("GetPlayerWeeklyWage", player_id) or
    safe_call("GetPlayerWage", player_id)

  if helper_salary ~= nil then
    return helper_salary
  end

  return read_field(players_table, record, "weeklywage", nil)
end

local function load_players_for_team(team_id)
  local players = {}
  local players_table = get_table("players")
  local live_players_table = get_live_table("players")
  local live_player_records = build_record_index(live_players_table, "playerid")
  local contracts = load_contract_map(team_id)
  local team_links = load_team_player_links(team_id)
  local owned_loans = load_owned_loan_map(team_id)
  local minutes_map = load_player_minutes_map()
  local birth_date = DATE:new()

  iterate_records(players_table, function(record)
    local player_id = read_field(players_table, record, "playerid", -1)
    if player_id <= 0 then
      return
    end

    local current_team_id = safe_call("GetTeamIdFromPlayerId", player_id)
    local owned_loan = owned_loans[player_id]
    if current_team_id ~= team_id and not owned_loan then
      return
    end

    local preferred_position = read_field(players_table, record, "preferredposition1", nil)
    local position_name = preferred_position and safe_call("GetPlayerPrimaryPositionName", preferred_position) or ""
    local birth_days = read_field(players_table, record, "birthdate", nil)
    local age = nil

    if birth_days and birth_days > 0 then
      birth_date:FromGregorianDays(birth_days)
      age = current_date.year - birth_date.year
      if current_date.month < birth_date.month or (current_date.month == birth_date.month and current_date.day < birth_date.day) then
        age = age - 1
      end
    end

    local contract = contracts[player_id]
    local team_link = team_links[player_id]
    local live_record = live_player_records[player_id]
    local source_table = live_record and live_players_table or players_table
    local source_record = live_record or record
    local player_minutes = minutes_map[player_id]
    local current_team_name = team_name(current_team_id)
    local loaned_out = owned_loan ~= nil and current_team_id ~= team_id
    local market_value = get_player_value(player_id, players_table, record, live_players_table, live_record)
    local salary = get_player_salary(player_id, contract, players_table, record)

    players[player_id] = {
      id = player_id,
      playerid = player_id,
      playername = player_name(player_id),
      position = position_name or "",
      age = age and tostring(age) or "",
      overallrating = read_field(players_table, record, "overallrating", 0),
      potential = read_field(players_table, record, "potential", nil),
      contractvaliduntil = read_field(players_table, record, "contractvaliduntil", ""),
      marketValue = market_value ~= nil and tostring(market_value) or "",
      salary = salary ~= nil and tostring(salary) or "",
      preferredfoot = read_field(players_table, record, "preferredfoot", nil),
      height = read_field(players_table, record, "height", nil),
      weight = read_field(players_table, record, "weight", nil),
      nationality = read_field(players_table, record, "nationality", nil),
      nationality_name = nation_name(read_field(players_table, record, "nationality", nil)),
      currentteamid = current_team_id or 0,
      currentteamname = current_team_name,
      squad_status = loaned_out and "loaned_out" or "current_squad",
      attributes = read_player_attributes(source_table, source_record),
      jersey_number = team_link and team_link.jersey_number or nil,
      league_summary = team_link and {
        appearances = team_link.league_appearances,
        goals = team_link.league_goals,
        yellows = team_link.yellows,
        reds = team_link.reds,
        form = team_link.form
      } or nil,
      contract = contract and {
        wage = contract.wage,
        contract_date = contract.contract_date,
        contract_date_text = format_date_from_yyyymmdd(contract.contract_date),
        contract_status = contract.contract_status,
        duration_months = contract.duration_months,
        player_role = contract.player_role,
        performance_bonus_value = contract.performance_bonus_value,
        performance_bonus_count = contract.performance_bonus_count
      } or nil,
      loan = loaned_out and owned_loan and {
        teamidloanedfrom = owned_loan.teamidloanedfrom,
        teamname_loanedfrom = team_name(owned_loan.teamidloanedfrom),
        teamidloanedto = current_team_id or 0,
        teamname_loanedto = current_team_name,
        loandateend = owned_loan.loandateend,
        loandateend_text = format_date_from_days(owned_loan.loandateend),
        isloantobuy = owned_loan.isloantobuy
      } or nil,
      play_time = player_minutes and {
        minutes_played = player_minutes.minutes_played,
        matches_played = player_minutes.matches_played,
        average_minutes = player_minutes.average_minutes,
        average_rating = player_minutes.average_rating,
        last_match = player_minutes.last_match,
        last_match_snapshot = player_minutes.last_match_snapshot,
        match_history = player_minutes.match_history
      } or {
        minutes_played = 0,
        matches_played = 0,
        average_minutes = "0.00",
        average_rating = "0.00",
        match_history = {}
      },
      stats = {},
      totals = {
        app = 0,
        goals = 0,
        assists = 0,
        yellow = 0,
        red = 0,
        clean_sheets = 0,
        saves = 0,
        goals_conceded = 0,
        two_yellow = 0,
        motm = 0,
        minutes_played = player_minutes and player_minutes.minutes_played or 0
      },
      avg_raw = 0
    }
  end)

  return players
end

local function attach_player_stats(players)
  local all_stats = GetPlayersStats()

  for index = 1, #all_stats do
    local stat = all_stats[index]
    local player_id = stat.playerid
    local appearances = stat.app or 0
    local player = players[player_id]

    if player and player_id > 0 and player_id < 4294967295 and appearances > 0 then
      local comp_id = stat.compobjid
      local comp_stat = {
        playerid = player_id,
        position = player.position,
        compobjid = comp_id,
        compname = competition_name(comp_id),
        goals = stat.goals or 0,
        assists = stat.assists or 0,
        yellow = stat.yellow or 0,
        red = stat.red or 0,
        clean_sheets = stat.clean_sheets or 0,
        motm = stat.motm or 0,
        saves = stat.saves or 0,
        goals_conceded = stat.goals_conceded or 0,
        two_yellow = stat.two_yellow or 0,
        app = appearances,
        avg = string.format("%0.2f", ((stat.avg or 0) / appearances) / 10)
      }

      player.stats[comp_id] = comp_stat
      player.totals.app = player.totals.app + comp_stat.app
      player.totals.goals = player.totals.goals + comp_stat.goals
      player.totals.assists = player.totals.assists + comp_stat.assists
      player.totals.yellow = player.totals.yellow + comp_stat.yellow
      player.totals.red = player.totals.red + comp_stat.red
      player.totals.clean_sheets = player.totals.clean_sheets + comp_stat.clean_sheets
      player.totals.motm = player.totals.motm + comp_stat.motm
      player.totals.saves = player.totals.saves + comp_stat.saves
      player.totals.goals_conceded = player.totals.goals_conceded + comp_stat.goals_conceded
      player.totals.two_yellow = player.totals.two_yellow + comp_stat.two_yellow
      player.avg_raw = player.avg_raw + (stat.avg or 0)
    end
  end

  for _, player in pairs(players) do
    if player.totals.app > 0 then
      player.totals.avg = string.format("%0.2f", (player.avg_raw / player.totals.app) / 10)
    else
      player.totals.avg = "0.00"
    end
    player.avg_raw = nil
  end
end

local function build_player_list(players)
  local list = sorted_values(players, function(a, b)
    return (a.playername or "") < (b.playername or "")
  end)

  for _, player in ipairs(list) do
    local stats_list = sorted_values(player.stats, function(a, b)
      if (a.compname or "") ~= (b.compname or "") then
        return (a.compname or "") < (b.compname or "")
      end
      return (a.compobjid or 0) < (b.compobjid or 0)
    end)
    player.stats = stats_list
  end

  return list
end

local function load_league_names()
  local names = {}
  local league_table = get_table("leagues")

  iterate_records(league_table, function(record)
    local league_id = read_field(league_table, record, "leagueid", -1)
    if league_id > 0 then
      names[league_id] = read_field(league_table, record, "leaguename", "") or ""
    end
  end)

  return names
end

local function load_league_table(team_id, league_names)
  local rows = {}
  local links_table = get_table("leagueteamlinks")
  local target_league_id = nil

  iterate_records(links_table, function(record)
    local record_team_id = read_field(links_table, record, "teamid", -1)
    local league_id = read_field(links_table, record, "leagueid", -1)

    if record_team_id == team_id then
      target_league_id = league_id
    end
  end)

  if not target_league_id or target_league_id <= 0 then
    return nil
  end

  iterate_records(links_table, function(record)
    local league_id = read_field(links_table, record, "leagueid", -1)
    if league_id ~= target_league_id then
      return
    end

    local row_team_id = read_field(links_table, record, "teamid", -1)
    if row_team_id <= 0 then
      return
    end

    rows[#rows + 1] = {
      teamid = row_team_id,
      teamname = team_name(row_team_id),
      leagueid = league_id,
      leaguename = league_names[league_id] or "",
      currenttableposition = read_field(links_table, record, "currenttableposition", 0),
      previousyeartableposition = read_field(links_table, record, "previousyeartableposition", nil),
      points = read_field(links_table, record, "points", 0),
      nummatchesplayed = read_field(links_table, record, "nummatchesplayed", 0),
      homewins = read_field(links_table, record, "homewins", 0),
      homedraws = read_field(links_table, record, "homedraws", 0),
      homelosses = read_field(links_table, record, "homelosses", 0),
      awaywins = read_field(links_table, record, "awaywins", 0),
      awaydraws = read_field(links_table, record, "awaydraws", 0),
      awaylosses = read_field(links_table, record, "awaylosses", 0),
      goals_for = (read_field(links_table, record, "homegf", 0) or 0) + (read_field(links_table, record, "awaygf", 0) or 0),
      goals_against = (read_field(links_table, record, "homega", 0) or 0) + (read_field(links_table, record, "awayga", 0) or 0),
      goal_difference = ((read_field(links_table, record, "homegf", 0) or 0) + (read_field(links_table, record, "awaygf", 0) or 0)) -
        ((read_field(links_table, record, "homega", 0) or 0) + (read_field(links_table, record, "awayga", 0) or 0)),
      champion = read_field(links_table, record, "champion", 0),
      objective = read_field(links_table, record, "objective", nil),
      grouping = read_field(links_table, record, "grouping", nil),
      lastgameresult = read_field(links_table, record, "lastgameresult", nil),
      teamform = read_field(links_table, record, "teamform", nil)
    }
  end)

  for _, row in ipairs(rows) do
    row.wins = (row.homewins or 0) + (row.awaywins or 0)
    row.draws = (row.homedraws or 0) + (row.awaydraws or 0)
    row.losses = (row.homelosses or 0) + (row.awaylosses or 0)

    if (row.points == nil or row.points == 0) and ((row.wins or 0) > 0 or (row.draws or 0) > 0) then
      row.points = (row.wins * 3) + row.draws
    end

    if (row.goal_difference == nil or row.goal_difference == 0) and ((row.goals_for or 0) > 0 or (row.goals_against or 0) > 0) then
      row.goal_difference = (row.goals_for or 0) - (row.goals_against or 0)
    end
  end

  local need_standings_fallback = true
  for _, row in ipairs(rows) do
    if (row.points or 0) > 0 or (row.goals_for or 0) > 0 or (row.goals_against or 0) > 0 then
      need_standings_fallback = false
      break
    end
  end

  if need_standings_fallback then
    local standings_table = get_table("standings")
    local standings_map = {}

    iterate_records(standings_table, function(record)
      local standing_team_id = read_first_available_field(standings_table, record, { "teamid" }, -1)
      if standing_team_id and standing_team_id > 0 then
        standings_map[standing_team_id] = {
          points = read_first_available_field(standings_table, record, { "points", "pts" }, nil),
          goal_difference = read_first_available_field(standings_table, record, { "goaldifference", "gd" }, nil),
          goals_for = read_first_available_field(standings_table, record, { "goalsfor", "gf" }, nil),
          goals_against = read_first_available_field(standings_table, record, { "goalsagainst", "ga" }, nil),
          wins = read_first_available_field(standings_table, record, { "wins" }, nil),
          draws = read_first_available_field(standings_table, record, { "draws" }, nil),
          losses = read_first_available_field(standings_table, record, { "losses" }, nil)
        }
      end
    end)

    for _, row in ipairs(rows) do
      local fallback = standings_map[row.teamid]
      if fallback then
        row.points = fallback.points or row.points
        row.goal_difference = fallback.goal_difference or row.goal_difference
        row.goals_for = fallback.goals_for or row.goals_for
        row.goals_against = fallback.goals_against or row.goals_against
        row.wins = fallback.wins or row.wins
        row.draws = fallback.draws or row.draws
        row.losses = fallback.losses or row.losses
      end
    end
  end

  table.sort(rows, function(a, b)
    local pos_a = a.currenttableposition or 999
    local pos_b = b.currenttableposition or 999
    if pos_a ~= pos_b then
      return pos_a < pos_b
    end
    if (a.points or 0) ~= (b.points or 0) then
      return (a.points or 0) > (b.points or 0)
    end
    if (a.goal_difference or 0) ~= (b.goal_difference or 0) then
      return (a.goal_difference or 0) > (b.goal_difference or 0)
    end
    return (a.teamname or "") < (b.teamname or "")
  end)

  return {
    leagueid = target_league_id,
    leaguename = league_names[target_league_id] or "",
    rows = rows
  }
end

local function load_matches(team_id, league_names)
  local matches = {}
  local fixtures_table = get_table("fixtures")

  iterate_records(fixtures_table, function(record)
    local home_team_id = read_field(fixtures_table, record, "hometeamid", -1)
    local away_team_id = read_field(fixtures_table, record, "awayteamid", -1)

    if home_team_id ~= team_id and away_team_id ~= team_id then
      return
    end

    local fixture_days = read_field(fixtures_table, record, "fixturedate", 0)
    local competition_id = read_field(fixtures_table, record, "competitionid", 0)
    local home_league_id = read_field(fixtures_table, record, "homeleagueid", 0)
    local away_league_id = read_field(fixtures_table, record, "awayleagueid", 0)

    local status = "upcoming"
    if fixture_days < current_date_days then
      status = "played"
    elseif fixture_days == current_date_days then
      status = "today"
    end

    matches[#matches + 1] = {
      fixtureid = read_field(fixtures_table, record, "fixtureid", 0),
      competitionid = competition_id,
      competitionname = competition_name(competition_id),
      fixturedate = fixture_days,
      fixturedate_text = format_date_from_days(fixture_days),
      fixturetime = read_field(fixtures_table, record, "fixturetime", nil),
      fixturetime_text = format_time_from_seconds(read_field(fixtures_table, record, "fixturetime", nil) or -1),
      home = {
        teamid = home_team_id,
        teamname = team_name(home_team_id),
        leagueid = home_league_id,
        leaguename = league_names[home_league_id] or "",
        league_position = read_field(fixtures_table, record, "hometeamleaguepos", nil),
        matches_played = read_field(fixtures_table, record, "hometeammatchesplayed", nil),
        form = read_field(fixtures_table, record, "hometeamform", nil)
      },
      away = {
        teamid = away_team_id,
        teamname = team_name(away_team_id),
        leagueid = away_league_id,
        leaguename = league_names[away_league_id] or "",
        league_position = read_field(fixtures_table, record, "awayteamleaguepos", nil),
        matches_played = read_field(fixtures_table, record, "awayteammatchesplayed", nil),
        form = read_field(fixtures_table, record, "awayteamform", nil)
      },
      stadiumid = read_field(fixtures_table, record, "stadiumid", nil),
      status = status,
      is_home = home_team_id == team_id,
      source = "fixtures"
    }
  end)

  table.sort(matches, function(a, b)
    if (a.fixturedate or 0) ~= (b.fixturedate or 0) then
      return (a.fixturedate or 0) < (b.fixturedate or 0)
    end
    return (a.fixturetime or 0) < (b.fixturetime or 0)
  end)

  if #matches > 0 then
    return matches
  end

  local matchup_table = get_table("competitionmatchups")

  iterate_records(matchup_table, function(record)
    local home_team_id = read_field(matchup_table, record, "hometeamid", -1)
    local away_team_id = read_field(matchup_table, record, "awayteamid", -1)

    if home_team_id ~= team_id and away_team_id ~= team_id then
      return
    end

    local competition_id = read_field(matchup_table, record, "competitionid", 0)
    matches[#matches + 1] = {
      matchupid = read_field(matchup_table, record, "matchupid", 0),
      competitionid = competition_id,
      competitionname = competition_name(competition_id),
      fixturedate = nil,
      fixturedate_text = "",
      fixturetime = nil,
      fixturetime_text = "",
      home = {
        teamid = home_team_id,
        teamname = team_name(home_team_id),
        leagueid = nil,
        leaguename = ""
      },
      away = {
        teamid = away_team_id,
        teamname = team_name(away_team_id),
        leagueid = nil,
        leaguename = ""
      },
      stadiumid = nil,
      status = "unknown",
      is_home = home_team_id == team_id,
      source = "competitionmatchups"
    }
  end)

  table.sort(matches, function(a, b)
    if (a.competitionname or "") ~= (b.competitionname or "") then
      return (a.competitionname or "") < (b.competitionname or "")
    end
    if (a.fixturedate or 0) ~= (b.fixturedate or 0) then
      return (a.fixturedate or 0) < (b.fixturedate or 0)
    end
    return ((a.home and a.home.teamname) or "") < ((b.home and b.home.teamname) or "")
  end)

  return matches
end

local function load_competition_progress(team_id)
  local rows = {}
  local progress_table = get_table("career_competitionprogress")
  local max_index = nil

  iterate_records(progress_table, function(record)
    local record_team_id = read_field(progress_table, record, "teamid", -1)
    if record_team_id ~= team_id then
      return
    end

    local season_index = read_field(progress_table, record, "season", nil)
    if season_index ~= nil and (max_index == nil or season_index > max_index) then
      max_index = season_index
    end

    rows[#rows + 1] = {
      compobjid = read_field(progress_table, record, "compobjid", nil),
      competition_name = competition_name(read_field(progress_table, record, "compobjid", nil)),
      compshortname = read_field(progress_table, record, "compshortname", ""),
      stageid = read_field(progress_table, record, "stageid", nil),
      hasteamwon = read_field(progress_table, record, "hasteamwon", nil),
      cup_objective_result = read_field(progress_table, record, "cup_objective_result", nil),
      season_index = season_index
    }
  end)

  table.sort(rows, function(a, b)
    if (a.season_index or 0) ~= (b.season_index or 0) then
      return (a.season_index or 0) < (b.season_index or 0)
    end
    return (a.compobjid or 0) < (b.compobjid or 0)
  end)

  for _, row in ipairs(rows) do
    row.season = season_label_from_index(row.season_index, max_index, season.start_year)
  end

  return rows
end

local function load_manager_history(team_id, league_names)
  local rows = {}
  local history_table = get_table("career_managerhistory")
  local max_index = nil

  iterate_records(history_table, function(record)
    local record_team_id = read_field(history_table, record, "teamid", -1)
    if record_team_id ~= team_id then
      return
    end

    local season_index = read_field(history_table, record, "season", nil)
    if season_index ~= nil and (max_index == nil or season_index > max_index) then
      max_index = season_index
    end

    local league_id = read_field(history_table, record, "leagueid", nil)
    rows[#rows + 1] = {
      teamid = record_team_id,
      teamname = team_name(record_team_id),
      season_index = season_index,
      leagueid = league_id,
      leaguename = league_names[league_id] or "",
      tableposition = read_field(history_table, record, "tableposition", nil),
      points = read_field(history_table, record, "points", nil),
      games_played = read_field(history_table, record, "games_played", nil),
      wins = read_field(history_table, record, "wins", nil),
      draws = read_field(history_table, record, "draws", nil),
      losses = read_field(history_table, record, "losses", nil),
      goals_for = read_field(history_table, record, "goals_for", nil),
      goals_against = read_field(history_table, record, "goals_against", nil),
      leagueobjective = read_field(history_table, record, "leagueobjective", nil),
      leagueobjectiveresult = read_field(history_table, record, "leagueobjectiveresult", nil),
      domestic_cup_objective = read_field(history_table, record, "domestic_cup_objective", nil),
      domestic_cup_result = read_field(history_table, record, "domestic_cup_result", nil),
      europe_cup_objective = read_field(history_table, record, "europe_cup_objective", nil),
      europe_cup_result = read_field(history_table, record, "europe_cup_result", nil),
      leaguetrophies = read_field(history_table, record, "leaguetrophies", nil),
      domesticcuptrophies = read_field(history_table, record, "domesticcuptrophies", nil),
      continentalcuptrophies = read_field(history_table, record, "continentalcuptrophies", nil),
      bigbuyamount = read_field(history_table, record, "bigbuyamount", nil),
      bigsellamount = read_field(history_table, record, "bigsellamount", nil),
      bigbuyplayername = read_field(history_table, record, "bigbuyplayername", ""),
      bigsellplayername = read_field(history_table, record, "bigsellplayername", "")
    }
  end)

  table.sort(rows, function(a, b)
    return (a.season_index or 0) < (b.season_index or 0)
  end)

  for _, row in ipairs(rows) do
    row.season = season_label_from_index(row.season_index, max_index, season.start_year)
  end

  return rows
end

local function load_team_season_metrics(team_id, league_names)
  local rows = {}
  local teamstats_table = get_table("career_playasplayerhistory")
  local max_index = nil

  iterate_records(teamstats_table, function(record)
    local record_team_id = read_field(teamstats_table, record, "teamid", -1)
    if record_team_id ~= team_id then
      return
    end

    local season_index = read_field(teamstats_table, record, "season", nil)
    if season_index ~= nil and (max_index == nil or season_index > max_index) then
      max_index = season_index
    end

    local total_passes = read_field(teamstats_table, record, "totalpasses", 0) or 0
    local passes_on_target = read_field(teamstats_table, record, "passesontarget", 0) or 0
    local total_shots = read_field(teamstats_table, record, "totalshots", 0) or 0
    local shots_on_target = read_field(teamstats_table, record, "shotsontarget", 0) or 0
    local wins = read_field(teamstats_table, record, "wins", 0) or 0
    local draws = read_field(teamstats_table, record, "draws", 0) or 0
    local losses = read_field(teamstats_table, record, "loses", 0) or 0
    local league_id = read_field(teamstats_table, record, "leagueid", nil)

    rows[#rows + 1] = {
      teamid = record_team_id,
      teamname = team_name(record_team_id),
      season_index = season_index,
      leagueid = league_id,
      leaguename = league_names[league_id] or "",
      appearances = read_field(teamstats_table, record, "appearances", nil),
      tableposition = read_field(teamstats_table, record, "tableposition", nil),
      wins = wins,
      draws = draws,
      losses = losses,
      points = (wins * 3) + draws,
      value = read_field(teamstats_table, record, "value", nil),
      wage = read_field(teamstats_table, record, "wage", nil),
      overall = read_field(teamstats_table, record, "overall", nil),
      clublevel = read_field(teamstats_table, record, "clublevel", nil),
      assists = read_field(teamstats_table, record, "assists", nil),
      cleansheets = read_field(teamstats_table, record, "cleansheets", nil),
      goalsconceded = read_field(teamstats_table, record, "goalsconceded", nil),
      saves = read_field(teamstats_table, record, "saves", nil),
      totalshots = total_shots,
      shotsontarget = shots_on_target,
      shot_accuracy = total_shots > 0 and string.format("%0.2f", (shots_on_target / total_shots) * 100) or "",
      totalpasses = total_passes,
      passesontarget = passes_on_target,
      pass_accuracy = total_passes > 0 and string.format("%0.2f", (passes_on_target / total_passes) * 100) or "",
      fouls = read_field(teamstats_table, record, "fouls", nil),
      totalyellows = read_field(teamstats_table, record, "totalyellows", nil),
      totalreds = read_field(teamstats_table, record, "totalreds", nil),
      totaltackles = read_field(teamstats_table, record, "totaltackles", nil),
      tacklesontarget = read_field(teamstats_table, record, "tacklesontarget", nil),
      motm = read_field(teamstats_table, record, "motm", nil),
      leaguetrophies = read_field(teamstats_table, record, "leaguetrophies", nil),
      domesticcuptrophies = read_field(teamstats_table, record, "domesticcuptrophies", nil),
      continentalcuptrophies = read_field(teamstats_table, record, "continentalcuptrophies", nil)
    }
  end)

  table.sort(rows, function(a, b)
    return (a.season_index or 0) < (b.season_index or 0)
  end)

  for _, row in ipairs(rows) do
    row.season = season_label_from_index(row.season_index, max_index, season.start_year)
  end

  return rows
end

local function latest_entry(list)
  if not list or #list == 0 then
    return nil
  end
  return list[#list]
end

local function find_league_row(team_id, league_table)
  if not league_table or not league_table.rows then
    return nil
  end

  for _, row in ipairs(league_table.rows) do
    if row.teamid == team_id then
      return row
    end
  end

  return nil
end

local function build_trophy_summary(competition_progress, manager_history)
  local won = {}
  local seen = {}

  for _, row in ipairs(competition_progress or {}) do
    if row.hasteamwon == 1 then
      local trophy_key = string.format("%s:%s", tostring(row.season or ""), tostring(row.compobjid or 0))
      if not seen[trophy_key] then
        seen[trophy_key] = true
        won[#won + 1] = {
          season = row.season,
          compobjid = row.compobjid,
          competition_name = row.competition_name,
          stageid = row.stageid,
          source = "career_competitionprogress"
        }
      end
    end
  end

  table.sort(won, function(a, b)
    if (a.season or "") ~= (b.season or "") then
      return (a.season or "") < (b.season or "")
    end
    return (a.competition_name or "") < (b.competition_name or "")
  end)

  local latest_history = latest_entry(manager_history)

  return {
    won = won,
    cumulative = latest_history and {
      leaguetrophies = latest_history.leaguetrophies,
      domesticcuptrophies = latest_history.domesticcuptrophies,
      continentalcuptrophies = latest_history.continentalcuptrophies
    } or nil
  }
end

local function build_team_totals(players)
  local totals = {
    app = 0,
    goals = 0,
    assists = 0,
    yellow = 0,
    red = 0,
    clean_sheets = 0,
    saves = 0,
    goals_conceded = 0,
    two_yellow = 0,
    motm = 0,
    minutes_played = 0
  }

  local avg_raw_total = 0

  for _, player in ipairs(players) do
    local player_totals = player.totals or {}
    totals.app = totals.app + (player_totals.app or 0)
    totals.goals = totals.goals + (player_totals.goals or 0)
    totals.assists = totals.assists + (player_totals.assists or 0)
    totals.yellow = totals.yellow + (player_totals.yellow or 0)
    totals.red = totals.red + (player_totals.red or 0)
    totals.clean_sheets = totals.clean_sheets + (player_totals.clean_sheets or 0)
    totals.saves = totals.saves + (player_totals.saves or 0)
    totals.goals_conceded = totals.goals_conceded + (player_totals.goals_conceded or 0)
    totals.two_yellow = totals.two_yellow + (player_totals.two_yellow or 0)
    totals.motm = totals.motm + (player_totals.motm or 0)
    totals.minutes_played = totals.minutes_played + (player_totals.minutes_played or 0)

    if player_totals.avg and player_totals.app and player_totals.app > 0 then
      avg_raw_total = avg_raw_total + (tonumber(player_totals.avg) or 0) * player_totals.app * 10
    end
  end

  if totals.app > 0 then
    totals.avg = string.format("%0.2f", (avg_raw_total / totals.app) / 10)
  else
    totals.avg = "0.00"
  end

  return totals
end

local function build_team_competition_totals(players)
  local totals = {}

  for _, player in ipairs(players) do
    for _, comp_stat in ipairs(player.stats or {}) do
      local comp_id = comp_stat.compobjid or 0
      local entry = totals[comp_id]

      if not entry then
        entry = {
          compobjid = comp_id,
          compname = comp_stat.compname or "",
          players_used = 0,
          player_apps = 0,
          goals = 0,
          assists = 0,
          yellow = 0,
          red = 0,
          clean_sheets = 0,
          saves = 0,
          goals_conceded = 0,
          two_yellow = 0,
          motm = 0
        }
        totals[comp_id] = entry
      end

      entry.players_used = entry.players_used + 1
      entry.player_apps = entry.player_apps + (comp_stat.app or 0)
      entry.goals = entry.goals + (comp_stat.goals or 0)
      entry.assists = entry.assists + (comp_stat.assists or 0)
      entry.yellow = entry.yellow + (comp_stat.yellow or 0)
      entry.red = entry.red + (comp_stat.red or 0)
      entry.clean_sheets = entry.clean_sheets + (comp_stat.clean_sheets or 0)
      entry.saves = entry.saves + (comp_stat.saves or 0)
      entry.goals_conceded = entry.goals_conceded + (comp_stat.goals_conceded or 0)
      entry.two_yellow = entry.two_yellow + (comp_stat.two_yellow or 0)
      entry.motm = entry.motm + (comp_stat.motm or 0)
    end
  end

  return sorted_values(totals, function(a, b)
    if (a.compname or "") ~= (b.compname or "") then
      return (a.compname or "") < (b.compname or "")
    end
    return (a.compobjid or 0) < (b.compobjid or 0)
  end)
end

local function build_squad_summary(players)
  local summary = {
    total_players = #players,
    current_squad = 0,
    loaned_out = 0,
    players_with_stats = 0,
    players_with_minutes = 0,
    players_with_market_value = 0
  }

  for _, player in ipairs(players) do
    if player.squad_status == "loaned_out" then
      summary.loaned_out = summary.loaned_out + 1
    else
      summary.current_squad = summary.current_squad + 1
    end

    if player.totals and (player.totals.app or 0) > 0 then
      summary.players_with_stats = summary.players_with_stats + 1
    end

    if player.play_time and (player.play_time.minutes_played or 0) > 0 then
      summary.players_with_minutes = summary.players_with_minutes + 1
    end

    if player.marketValue and player.marketValue ~= "" then
      summary.players_with_market_value = summary.players_with_market_value + 1
    end
  end

  return summary
end

function get_succeeded_ai_club_transfers(out, storage)
  local obj_size = 0xB8
  local vec = MEMORY:ReadPointer(storage + 0x8)
  local begin_ptr = MEMORY:ReadPointer(vec + 0x0)
  local end_ptr = MEMORY:ReadPointer(vec + 0x8)
  local current = begin_ptr

  while current < end_ptr do
    local player_id = MEMORY:ReadInt(current + 0x0)
    local buying_team = MEMORY:ReadInt(current + 0x4)
    local selling_team = MEMORY:ReadInt(current + 0x8)

    if player_id > 0 and buying_team > 0 and selling_team > 0 then
      local seller_accepted = MEMORY:ReadBool(current + 0x6E)
      local buyer_accepted = MEMORY:ReadBool(current + 0x6F)

      if seller_accepted or buyer_accepted then
        local final_fee = 0
        local exchange_value = 0

        if seller_accepted then
          final_fee = MEMORY:ReadInt(MEMORY:ReadPointer(current + 0x28) - 0xC)
        else
          local request = MEMORY:ReadPointer(current + 0x48)
          final_fee = MEMORY:ReadInt(request - 0x14 + 0x0)
          exchange_value = MEMORY:ReadInt(request - 0x14 + 0x4)
        end

        local key = string.format("T%d-%d-%d", player_id, buying_team, selling_team)
        out[key] = {
          final_fee = final_fee,
          exchange_value = exchange_value
        }
      end
    end

    current = current + obj_size
  end
end

function get_succeeded_user_club_transfers(out, storage)
  local obj_size = 0xA0
  local vec = MEMORY:ReadPointer(storage + 0x28)
  local begin_ptr = MEMORY:ReadPointer(vec + 0x0)
  local end_ptr = MEMORY:ReadPointer(vec + 0x8)
  local current = begin_ptr

  while current < end_ptr do
    local player_id = MEMORY:ReadInt(current + 0x0)
    local buying_team = MEMORY:ReadInt(current + 0x4)
    local selling_team = MEMORY:ReadInt(current + 0x8)

    if player_id > 0 and buying_team > 0 and selling_team > 0 then
      local actions_begin = MEMORY:ReadPointer(current + 0x58)
      local actions_end = MEMORY:ReadPointer(current + 0x60)

      if actions_begin ~= actions_end then
        local last_action = MEMORY:ReadChar(actions_end - 0xC + 0x8)
        local seller_accepted = last_action == 0
        local buyer_accepted = last_action == 4

        if seller_accepted or buyer_accepted then
          local final_fee = 0
          local exchange_value = 0
          local exchange_player = 0

          if seller_accepted then
            local offer = MEMORY:ReadPointer(current + 0x20)
            exchange_player = MEMORY:ReadInt(offer - 0x28 + 0x0)
            exchange_value = MEMORY:ReadInt(offer - 0x28 + 0x4)
            final_fee = MEMORY:ReadInt(offer - 0x28 + 0xC)
          else
            local request = MEMORY:ReadPointer(current + 0x40)
            exchange_player = MEMORY:ReadInt(request - 0x28 + 0x0)
            exchange_value = MEMORY:ReadInt(request - 0x28 + 0x4)
            final_fee = MEMORY:ReadInt(request - 0x28 + 0xC)
          end

          local key = string.format("T%d-%d-%d", player_id, buying_team, selling_team)
          out[key] = {
            final_fee = final_fee,
            exchange_player = exchange_player,
            exchange_value = exchange_value
          }
        end
      end
    end

    current = current + obj_size
  end
end

function get_succeeded_ai_player_transfers(out, storage)
  local obj_size = 0xA8
  local vec = MEMORY:ReadPointer(storage + 0x10)
  local begin_ptr = MEMORY:ReadPointer(vec + 0x0)
  local end_ptr = MEMORY:ReadPointer(vec + 0x8)
  local current = begin_ptr

  while current < end_ptr do
    local player_id = MEMORY:ReadInt(current + 0x0)
    local buying_team = MEMORY:ReadInt(current + 0x4)
    local selling_team = MEMORY:ReadInt(current + 0x8)

    if player_id > 0 and buying_team > 0 and selling_team > 0 then
      local seller_accepted = MEMORY:ReadBool(current + 0x67)
      if seller_accepted then
        local last_index = MEMORY:ReadChar(current + 0x6B)
        local last_date = MEMORY:ReadInt(current + 0x6C + 0xC * last_index)
        local key = string.format("T%d-%d-%d", player_id, buying_team, selling_team)
        out[key] = {
          playerid = player_id,
          buying_team = buying_team,
          selling_team = selling_team,
          date = last_date,
          type = "transfer"
        }
      end
    end

    current = current + obj_size
  end
end

function get_succeeded_ai_player_exchanges(out, storage)
  local obj_size = 0xA8
  local vec = MEMORY:ReadPointer(storage + 0x40)
  local begin_ptr = MEMORY:ReadPointer(vec + 0x0)
  local end_ptr = MEMORY:ReadPointer(vec + 0x8)
  local current = begin_ptr

  while current < end_ptr do
    local player_id = MEMORY:ReadInt(current + 0x0)
    local buying_team = MEMORY:ReadInt(current + 0x4)
    local selling_team = MEMORY:ReadInt(current + 0x8)

    if player_id > 0 and buying_team > 0 and selling_team > 0 then
      local seller_accepted = MEMORY:ReadBool(current + 0x67)
      if seller_accepted then
        local last_index = MEMORY:ReadChar(current + 0x6B) - 1
        local last_date = MEMORY:ReadInt(current + 0x6C + 0xC * last_index)
        local key = string.format("T%d-%d-%d", player_id, buying_team, selling_team)
        out[key] = {
          playerid = player_id,
          buying_team = buying_team,
          selling_team = selling_team,
          date = last_date,
          type = "transfer"
        }
      end
    end

    current = current + obj_size
  end
end

function get_succeeded_user_player_transfers(out, storage)
  local obj_size = 0x98
  local vec = MEMORY:ReadPointer(storage + 0x38)
  local begin_ptr = MEMORY:ReadPointer(vec + 0x0)
  local end_ptr = MEMORY:ReadPointer(vec + 0x8)
  local current = begin_ptr

  while current < end_ptr do
    local player_id = MEMORY:ReadInt(current + 0x0)
    local buying_team = MEMORY:ReadInt(current + 0x4)
    local selling_team = MEMORY:ReadInt(current + 0x8)

    if player_id > 0 and buying_team > 0 and selling_team > 0 then
      local begin_actions = MEMORY:ReadPointer(current + 0x50)
      local end_actions = MEMORY:ReadPointer(current + 0x58)

      if begin_actions ~= end_actions then
        local last_action = MEMORY:ReadChar(end_actions - 0xC + 0x8)
        local seller_accepted = last_action == 0
        local buyer_accepted = last_action == 4

        if seller_accepted or buyer_accepted then
          local last_date = MEMORY:ReadInt(end_actions - 0xC + 0x0)
          local key = string.format("T%d-%d-%d", player_id, buying_team, selling_team)
          out[key] = {
            playerid = player_id,
            buying_team = buying_team,
            selling_team = selling_team,
            date = last_date,
            type = "transfer"
          }
        end
      end
    end

    current = current + obj_size
  end
end

function get_succeeded_user_player_exchanges(out, storage)
  local obj_size = 0x98
  local vec = MEMORY:ReadPointer(storage + 0x48)
  local begin_ptr = MEMORY:ReadPointer(vec + 0x0)
  local end_ptr = MEMORY:ReadPointer(vec + 0x8)
  local current = begin_ptr

  while current < end_ptr do
    local player_id = MEMORY:ReadInt(current + 0x0)
    local buying_team = MEMORY:ReadInt(current + 0x4)
    local selling_team = MEMORY:ReadInt(current + 0x8)

    if player_id > 0 and buying_team > 0 and selling_team > 0 then
      local begin_actions = MEMORY:ReadPointer(current + 0x50)
      local end_actions = MEMORY:ReadPointer(current + 0x58)

      if begin_actions ~= end_actions then
        local last_action = MEMORY:ReadChar(end_actions - 0xC + 0x8)
        local seller_accepted = last_action == 0
        local buyer_accepted = last_action == 4

        if seller_accepted or buyer_accepted then
          local last_date = MEMORY:ReadInt(end_actions - 0xC + 0x0)
          local key = string.format("T%d-%d-%d", player_id, buying_team, selling_team)
          out[key] = {
            playerid = player_id,
            buying_team = buying_team,
            selling_team = selling_team,
            date = last_date,
            type = "transfer"
          }
        end
      end
    end

    current = current + obj_size
  end
end

function get_succeeded_ai_player_loans(out, storage)
  local obj_size = 0x98
  local vec = MEMORY:ReadPointer(storage + 0x20)
  local begin_ptr = MEMORY:ReadPointer(vec + 0x0)
  local end_ptr = MEMORY:ReadPointer(vec + 0x8)
  local current = begin_ptr

  while current < end_ptr do
    local player_id = MEMORY:ReadInt(current + 0x0)
    local buying_team = MEMORY:ReadInt(current + 0x4)
    local selling_team = MEMORY:ReadInt(current + 0x8)
    local accepted = MEMORY:ReadBool(current + 0x52)

    if player_id > 0 and buying_team > 0 and selling_team > 0 and accepted then
      local first_date = MEMORY:ReadInt(current + 0x58)
      local last_index = MEMORY:ReadChar(current + 0x57)
      local last_date = MEMORY:ReadInt(current + 0x58 + 0xC * (last_index - 1))
      local y1 = math.floor(first_date / 10000)
      local m1 = math.floor(first_date / 100) % 100
      local y2 = math.floor(last_date / 10000)
      local m2 = math.floor(last_date / 100) % 100
      local months = (y2 - y1) * 12 + (m2 - m1)
      local key = string.format("L%d-%d-%d", player_id, buying_team, selling_team)
      out[key] = {
        playerid = player_id,
        buying_team = buying_team,
        selling_team = selling_team,
        date = last_date,
        type = "loan",
        duration = months * 30
      }
    end

    current = current + obj_size
  end
end

function get_succeeded_ai_club_loans(out, storage)
  local obj_size = 0xB8
  local vec = MEMORY:ReadPointer(storage + 0x18)
  local begin_ptr = MEMORY:ReadPointer(vec + 0x0)
  local end_ptr = MEMORY:ReadPointer(vec + 0x8)
  local current = begin_ptr

  while current < end_ptr do
    local player_id = MEMORY:ReadInt(current + 0x0)
    local buying_team = MEMORY:ReadInt(current + 0x4)
    local selling_team = MEMORY:ReadInt(current + 0x8)
    local seller_accepted = MEMORY:ReadBool(current + 0x72)
    local buyer_accepted = MEMORY:ReadBool(current + 0x73)

    if player_id > 0 and buying_team > 0 and selling_team > 0 and (seller_accepted or buyer_accepted) then
      local key = string.format("L%d-%d-%d", player_id, buying_team, selling_team)
      out[key] = { final_fee = 0 }
    end

    current = current + obj_size
  end
end

function get_succeeded_user_club_loans(out, storage)
  local obj_size = 0xF8
  local vec = MEMORY:ReadPointer(storage + 0x30)
  local begin_ptr = MEMORY:ReadPointer(vec + 0x0)
  local end_ptr = MEMORY:ReadPointer(vec + 0x8)
  local current = begin_ptr

  while current < end_ptr do
    local player_id = MEMORY:ReadInt(current + 0x0)
    local buying_team = MEMORY:ReadInt(current + 0x4)
    local selling_team = MEMORY:ReadInt(current + 0x8)
    local actions_begin = MEMORY:ReadPointer(current + 0x50)
    local actions_end = MEMORY:ReadPointer(current + 0x58)

    if player_id > 0 and buying_team > 0 and selling_team > 0 and actions_begin ~= actions_end then
      local first_date = MEMORY:ReadInt(actions_begin - 0xC + 0x0)
      local last_date = MEMORY:ReadInt(actions_end - 0xC + 0x0)
      local y1 = math.floor(first_date / 10000)
      local m1 = math.floor(first_date / 100) % 100
      local y2 = math.floor(last_date / 10000)
      local m2 = math.floor(last_date / 100) % 100
      local months = (y2 - y1) * 12 + (m2 - m1)
      local key = string.format("L%d-%d-%d", player_id, buying_team, selling_team)
      out[key] = {
        playerid = player_id,
        buying_team = buying_team,
        selling_team = selling_team,
        date = last_date,
        type = "loan",
        duration = months * 30
      }
    end

    current = current + obj_size
  end
end

local function build_transfer_export(team_id)
  local manager = GetManagerObjByTypeId(ENUM_FCEGameModesFCECareerModeTransferManager)
  assert(manager ~= 0, "TransferManager not found")

  local storage = MEMORY:ReadPointer(MEMORY:ReadPointer(manager + 0x1DB0) + 0x8)
  local player_negotiations = {}
  local club_negotiations = {}

  get_succeeded_ai_player_transfers(player_negotiations, storage)
  get_succeeded_ai_player_exchanges(player_negotiations, storage)
  get_succeeded_user_player_transfers(player_negotiations, storage)
  get_succeeded_user_player_exchanges(player_negotiations, storage)
  get_succeeded_ai_club_transfers(club_negotiations, storage)
  get_succeeded_user_club_transfers(club_negotiations, storage)
  get_succeeded_ai_player_loans(player_negotiations, storage)
  get_succeeded_ai_club_loans(club_negotiations, storage)
  get_succeeded_user_club_loans(club_negotiations, storage)

  local export_data = {
    teamid = team_id,
    season = season.display,
    exported_date = string.format("%04d-%02d-%02d", current_date.year, current_date.month, current_date.day),
    transfers = {},
    loans = {}
  }

  for key, negotiation in pairs(player_negotiations) do
    local team_from_id = negotiation.selling_team
    local team_to_id = negotiation.buying_team

    if team_from_id == team_id or team_to_id == team_id then
      if negotiation.type == "transfer" then
        local club = club_negotiations[key] or {}
        export_data.transfers[#export_data.transfers + 1] = {
          type = "transfer",
          date = negotiation.date,
          date_text = format_date_from_yyyymmdd(negotiation.date),
          playerid = negotiation.playerid,
          playername = player_name(negotiation.playerid),
          exchangeplayerid = club.exchange_player or 0,
          exchangeplayername = (club.exchange_player and club.exchange_player > 0) and player_name(club.exchange_player) or "",
          teamfromid = team_from_id,
          teamfromname = team_name(team_from_id),
          teamtoid = team_to_id,
          teamtoname = team_name(team_to_id),
          fee = club.final_fee or 0,
          exchange_value = club.exchange_value or 0,
          total_deal_value = (club.final_fee or 0) + (club.exchange_value or 0)
        }
      elseif negotiation.type == "loan" then
        export_data.loans[#export_data.loans + 1] = {
          type = "loan",
          date = negotiation.date,
          date_text = format_date_from_yyyymmdd(negotiation.date),
          playerid = negotiation.playerid,
          playername = player_name(negotiation.playerid),
          teamfromid = team_from_id,
          teamfromname = team_name(team_from_id),
          teamtoid = team_to_id,
          teamtoname = team_name(team_to_id),
          duration = negotiation.duration
        }
      end
    end
  end

  table.sort(export_data.transfers, function(a, b)
    if (a.date or 0) ~= (b.date or 0) then
      return (a.date or 0) < (b.date or 0)
    end
    return (a.playername or "") < (b.playername or "")
  end)

  table.sort(export_data.loans, function(a, b)
    if (a.date or 0) ~= (b.date or 0) then
      return (a.date or 0) < (b.date or 0)
    end
    return (a.playername or "") < (b.playername or "")
  end)

  return export_data
end

local function build_playerstats_export(team_id)
  local players = load_players_for_team(team_id)
  attach_player_stats(players)

  local player_list = build_player_list(players)

  return {
    teamid = team_id,
    teamname = team_name(team_id),
    season = season.display,
    season_start_year = season.start_year,
    season_end_year = season.end_year,
    exported_date = string.format("%04d-%02d-%02d", current_date.year, current_date.month, current_date.day),
    squad_summary = build_squad_summary(player_list),
    players = player_list,
    team_totals = build_team_totals(player_list)
  }
end

local function build_game_export(team_id, playerstats_export)
  local league_names = load_league_names()
  local manager_history = load_manager_history(team_id, league_names)
  local competition_progress = load_competition_progress(team_id)
  local league_table = load_league_table(team_id, league_names)
  local matches = load_matches(team_id, league_names)
  local season_metrics = load_team_season_metrics(team_id, league_names)
  local competition_totals = build_team_competition_totals(playerstats_export.players or {})

  return {
    teamid = team_id,
    teamname = team_name(team_id),
    season = season.display,
    season_start_year = season.start_year,
    season_end_year = season.end_year,
    exported_date = string.format("%04d-%02d-%02d", current_date.year, current_date.month, current_date.day),
    tables = {
      league = league_table,
      current_team = find_league_row(team_id, league_table)
    },
    team_stats = {
      squad_summary = playerstats_export.squad_summary,
      squad_totals = build_team_totals(playerstats_export.players or {}),
      squad_competition_totals = competition_totals,
      by_competition = competition_totals,
      season_summary = latest_entry(manager_history),
      season_metrics = season_metrics,
      current_season_metrics = latest_entry(season_metrics)
    },
    matches = {
      source = (#matches > 0 and matches[1].source) or "none",
      items = matches
    },
    trophies = build_trophy_summary(competition_progress, manager_history),
    history = {
      seasons = manager_history,
      competition_progress = competition_progress
    }
  }
end

assert(IsInCM(), "Script must be executed in career mode")

local transfer_export = build_transfer_export(target_team_id)
local playerstats_export = build_playerstats_export(target_team_id)
local game_export = build_game_export(target_team_id, playerstats_export)
local output_dir = downloads_dir()

local transfer_path = string.format("%s\\FC25-Transfers-%s-%d.json", output_dir, season.file, target_team_id)
local playerstats_path = string.format("%s\\FC25-PlayerStats-%s-%d.json", output_dir, season.file, target_team_id)
local game_path = string.format("%s\\FC25-Game-%s-%d.json", output_dir, season.file, target_team_id)

local transfer_file = assert(io.open(transfer_path, "w+"), "Could not write transfer export")
transfer_file:write(to_json(transfer_export, 0))
transfer_file:close()

local playerstats_file = assert(io.open(playerstats_path, "w+"), "Could not write player stats export")
playerstats_file:write(to_json(playerstats_export, 0))
playerstats_file:close()

local game_file = assert(io.open(game_path, "w+"), "Could not write game export")
game_file:write(to_json(game_export, 0))
game_file:close()

LOGGER:LogInfo("CareerHub transfer export written: " .. transfer_path)
LOGGER:LogInfo("CareerHub player stats export written: " .. playerstats_path)
LOGGER:LogInfo("CareerHub game export written: " .. game_path)
