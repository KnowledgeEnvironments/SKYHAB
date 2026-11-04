// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/telemetry.hpp"

#include <stdexcept>
#include <cmath>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

namespace skylab {
namespace {
void check(int rc, sqlite3* db, const char* operation) {
  if (rc != SQLITE_OK && rc != SQLITE_DONE && rc != SQLITE_ROW)
    throw std::runtime_error(std::string(operation) + ": " + sqlite3_errmsg(db));
}

void add_presentation(nlohmann::json& row) {
  const std::string metric = row.value("metric", "");
  static const std::unordered_map<std::string, std::string> labels{
    {"health","Status"},{"power","Power"},{"brightness","Brightness"},{"temperature","Temperature"},
    {"mode","Mode"},{"state","Activity"},{"fan_mode","Fan"},{"fan_state","Blower"},
    {"heat_setpoint","Heat to"},{"cool_setpoint","Cool to"},
    {"state_of_charge","Charge"},{"battery_power","Battery"},{"load_power","Home load"},{"grid_power","Grid"},
    {"solar_power","Solar"},{"production_power","Solar production"},{"consumption_power","Consumption"},
    {"energy_remaining","Energy remaining"},{"backup_reserve","Backup reserve"},{"grid_connected","Grid connection"},
    {"battery_charge","Battery"},{"battery_runtime","Runtime"},{"load","Load"},{"real_power","Real power"},
    {"apparent_power","Apparent power"},{"input_voltage","Input voltage"},{"output_voltage","Output voltage"},
    {"uptime","Uptime"},{"routeros_version","RouterOS"},{"board","Hardware"},{"cpu_load","CPU"},
    {"free_memory","Free memory"},{"link","Link"},{"link_downs","Link changes"},{"size","Capacity"},
    {"line_rate","Line rate"},{"rx_rate","Receive"},{"tx_rate","Transmit"},{"physical_status","Physical status"},
    {"allocated","Used space"},{"free","Available"},{"used_percent","Utilization"},{"read_errors","Read errors"},
    {"write_errors","Write errors"},{"checksum_errors","Checksum errors"},{"status","Status"},
    {"cpu_fraction","CPU"},{"memory_used","Memory used"},{"memory_capacity","Memory"},
    {"disk_used","Disk used"},{"disk_capacity","Disk"},{"active_inverters","Active inverters"},
    {"lifetime_energy","Lifetime production"},{"name","Name"},{"node","Node"},{"type","Type"},
    {"management_access","SSH management"},{"partition_mode","Partition"},{"armed","Armed"},
    {"ready","Ready"},{"alarm","Burglar alarm"},{"fire","Fire alarm"},{"bypass","Bypass"},
    {"trouble","Trouble"},{"ac_power","Panel AC"},{"low_battery","Low battery"},
    {"alarm_memory","Alarm memory"},{"chime","Chime"},{"open_zones","Open zones"},
    {"open_zone_count","Open zone count"},{"keypad_line1","Keypad line 1"},
    {"keypad_line2","Keypad line 2"},{"keypad_beep","Keypad beep"},{"last_event","Latest event"},
    {"mandatory_bypass_zone","Permanent bypass zone"},{"bypass_policy","Bypass policy"},
    {"mac_address","MAC"},{"address","IP address"},{"radio","Radio/BSSID"},{"ssid","SSID"},
    {"band","Band"},{"signal","Signal"},{"last_activity","Last activity"},
    {"operating_state","Activity"},{"battery_level","Battery"},{"docked","Docked"},
    {"power_mode","Power mode"},{"clean_duration","Clean time"},{"active_faults","Faults"},
    {"fan_speed","Fan level"},{"auto_mode","Auto"},{"night_mode","Night mode"},
    {"oscillation","Oscillation"},{"airflow_direction","Airflow"},
    {"carbon_filter_life","Carbon filter"},{"hepa_filter_life","HEPA filter"},
    {"error_code","Error"},{"wifi_signal","Wi-Fi"},{"humidity","Humidity"},
    {"pm2_5","PM2.5"},{"pm10","PM10"},{"voc_index","VOC index"},
    {"no2_index","NO₂ index"},{"formaldehyde","Formaldehyde"},{"software_version","Software"},
    {"mesh_role","Mesh role"},{"node_count","Known nodes"},{"recent_node_count","Active in 24 h"},
    {"direct_node_count","Direct nodes"},{"mqtt_node_count","Via MQTT"},{"firmware_version","Firmware"},
    {"hardware_model","Radio hardware"},{"reboot_count","Reboots"},{"minimum_app_version","Minimum app"},
    {"platform_environment","Firmware target"},{"expected_node_count","Node database"},
    {"last_mesh_activity_age","Latest mesh activity"},{"local_node_name","Radio name"},
    {"local_node_short_name","Short name"},{"local_node_id","Node ID"},{"radio_snr","Local SNR"},
    {"voltage","Voltage"},{"channel_utilization","Channel utilization"},{"air_utilization","Transmit airtime"},
    {"radio_uptime","Radio uptime"}
  };
  row["label"] = labels.contains(metric) ? labels.at(metric) : metric;
  static const std::unordered_map<std::string, int> priorities{
    {"health",0},{"status",1},{"state",2},{"temperature",3},{"power",3},{"state_of_charge",3},
    {"production_power",4},{"load_power",4},{"battery_power",5},{"grid_power",6},{"battery_charge",3},
    {"battery_runtime",4},{"used_percent",3},{"free",4},{"uptime",7},{"routeros_version",8},
    {"heat_setpoint",4},{"cool_setpoint",5},{"mode",6},{"fan_mode",7},{"fan_state",8},{"brightness",4},{"cpu_load",9},
    {"partition_mode",1},{"fire",2},{"alarm",3},{"low_battery",4},{"trouble",5},{"bypass",6},{"open_zone_count",7},
    {"operating_state",2},{"battery_level",3},{"docked",4},{"power_mode",5},
    {"power",2},{"fan_state",3},{"fan_speed",4},{"auto_mode",5},{"temperature",6},
    {"humidity",7},{"pm2_5",8},{"pm10",9},{"voc_index",10},{"no2_index",11},
    {"formaldehyde",12},{"hepa_filter_life",13},{"carbon_filter_life",14},
    {"mesh_role",1},{"node_count",2},{"recent_node_count",3},{"last_mesh_activity_age",4},
    {"channel_utilization",5},{"air_utilization",6},{"radio_uptime",7}
  };
  row["display_priority"] = priorities.contains(metric) ? priorities.at(metric) : 50;
  const bool internal = metric == "uptime_source" || metric == "uptime_text" || metric == "physical_port" || metric == "vdev" || metric == "keypad_beep";
  const bool detail = metric == "name" || metric == "node" || metric == "type" || metric == "board" || metric == "free_memory" || metric == "management_access" || metric == "armed" || metric == "ready" || metric == "ac_power" || metric == "alarm_memory" || metric == "chime" || metric == "open_zones" || metric == "keypad_line1" || metric == "keypad_line2" || metric == "last_event" || metric == "mandatory_bypass_zone" || metric == "bypass_policy" || metric == "wifi_signal" || metric == "software_version" || metric == "active_faults" || metric == "error_code" || metric == "clean_duration" || metric == "airflow_direction" || metric == "firmware_version" || metric == "hardware_model" || metric == "reboot_count" || metric == "minimum_app_version" || metric == "platform_environment" || metric == "expected_node_count" || metric == "local_node_name" || metric == "local_node_short_name" || metric == "local_node_id" || metric == "radio_snr" || metric == "voltage" || metric == "direct_node_count" || metric == "mqtt_node_count";
  row["visibility"] = internal ? "internal" : detail ? "detail" : "summary";
  row["kind"] = (metric == "health" || metric == "status" || metric == "state" || metric == "mode" || metric == "link") ? "status" :
                (metric.find("errors") != std::string::npos || metric == "link_downs") ? "counter" :
                row["value"].is_number() ? "gauge" : "identity";
  row["severity"] = "info";
  if (metric == "health" || metric == "status") {
    const auto value = row["value"].is_string() ? row["value"].get<std::string>() : "";
    if (value == "responding" || value == "ONLINE" || value == "running" || value == "OL") row["severity"] = "ok";
    else if (value == "degraded" || value == "DEGRADED") row["severity"] = "warning";
    else if (value == "unreachable" || value == "FAULTED" || value == "stopped") row["severity"] = "critical";
  } else if ((metric.find("errors") != std::string::npos) && row["value"].is_number() && row["value"].get<double>() > 0) row["severity"] = "critical";
  else if (metric == "link" && row["value"].is_boolean()) row["severity"] = row["value"].get<bool>() ? "ok" : "info";
  else if ((metric == "alarm" || metric == "fire") && row["value"].is_boolean() && row["value"].get<bool>()) row["severity"] = "critical";
  else if ((metric == "trouble" || metric == "low_battery") && row["value"].is_boolean() && row["value"].get<bool>()) row["severity"] = "warning";
  if ((metric == "alarm" || metric == "fire" || metric == "trouble" || metric == "low_battery") &&
      row["value"].is_boolean())
    row["visibility"] = row["value"].get<bool>() ? "summary" : "detail";
  if (metric == "bypass" && row["value"].is_boolean()) {
    row["visibility"] = row["value"].get<bool>() ? "detail" : "summary";
    if (!row["value"].get<bool>()) row["severity"] = "warning";
  }
  if (metric == "open_zone_count" && row["value"].is_number())
    row["visibility"] = row["value"].get<double>() > 0 ? "summary" : "detail";
  if (row["value"].is_number()) {
    const double value = row["value"].get<double>();
    if (metric == "battery_charge" && value < 20) row["severity"] = "critical";
    else if (metric == "battery_charge" && value < 40) row["severity"] = "warning";
    else if (metric == "state_of_charge" && value < 10) row["severity"] = "critical";
    else if (metric == "state_of_charge" && value < 20) row["severity"] = "warning";
    else if (metric == "used_percent" && value >= 90) row["severity"] = "critical";
    else if (metric == "used_percent" && value >= 80) row["severity"] = "warning";
    else if (metric == "battery_level" && value < 10) row["severity"] = "critical";
    else if (metric == "battery_level" && value < 20) row["severity"] = "warning";
  }
  const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
  const auto age = std::max<std::int64_t>(0, now - row.value("observed_at_ms", now));
  row["age_ms"] = age; row["freshness"] = age > 180000 ? "stale" : "fresh";
  if (age > 180000 && row.value("severity", "info") == "ok") row["severity"] = "warning";

  if (!row["value"].is_number()) {
    if (row["value"].is_boolean()) {
      const bool value = row["value"].get<bool>();
      if (metric == "link") row["display_text"] = value ? "Up" : "Down";
      else if (metric == "grid_connected") row["display_text"] = value ? "Connected" : "Islanded";
      else if (metric == "management_access") row["display_text"] = value ? "Available" : "Unavailable";
      else if (metric == "alarm" || metric == "fire") row["display_text"] = value ? "ACTIVE" : "Clear";
      else if (metric == "trouble") row["display_text"] = value ? "Present" : "Clear";
      else if (metric == "low_battery") row["display_text"] = value ? "Low battery" : "Normal";
      else if (metric == "bypass") row["display_text"] = value ? "Required zone bypassed" : "Required bypass missing";
      else if (metric == "docked") row["display_text"] = value ? "Docked" : "Away";
      else row["display_text"] = value ? "On" : "Off";
    }
    else if (row["value"].is_string()) {
      const auto value = row["value"].get<std::string>();
      if (metric == "operating_state") {
        static const std::unordered_map<std::string, std::string> states{{"INACTIVE_CHARGED","Charged"},{"INACTIVE_CHARGING","Charging"},{"INACTIVE_DISCHARGING","Idle"},{"FULL_CLEAN_INITIATED","Starting"},{"FULL_CLEAN_DISCOVERING","Cleaning"},{"FULL_CLEAN_RUNNING","Cleaning"},{"FULL_CLEAN_TRAVERSING","Cleaning"},{"FULL_CLEAN_PAUSED","Paused"},{"FULL_CLEAN_NEEDS_CHARGE","Returning"},{"FULL_CLEAN_CHARGING","Charging"},{"FULL_CLEAN_FINISHED","Returning"},{"FULL_CLEAN_ABORTED","Returning"}};
        row["display_text"] = states.contains(value) ? states.at(value) : value;
      } else if (metric == "power_mode") row["display_text"] = value == "fullPower" ? "Max" : value == "halfPower" ? "Quiet" : value;
      else row["display_text"] = value;
    }
    else row["display_text"] = "—";
    return;
  }
  const double raw = row["value"].get<double>();
  const std::string unit = row.value("unit", "");
  double shown = raw; std::string shown_unit = unit; int decimals = 1;
  if (unit == "B") {
    static constexpr const char* units[] = {"B", "KiB", "MiB", "GiB", "TiB", "PiB"};
    std::size_t index = 0; while (std::abs(shown) >= 1024.0 && index < 5) { shown /= 1024.0; ++index; }
    shown_unit = units[index]; decimals = index == 0 ? 0 : 1;
  } else if (unit == "W" && std::abs(raw) >= 1000.0) { shown = raw / 1000.0; shown_unit = "kW"; }
  else if (unit == "bit/s") {
    if (std::abs(raw) >= 1000000000.0) { shown = raw / 1000000000.0; shown_unit = "Gbps"; }
    else if (std::abs(raw) >= 1000000.0) { shown = raw / 1000000.0; shown_unit = "Mbps"; }
    else if (std::abs(raw) >= 1000.0) { shown = raw / 1000.0; shown_unit = "kbps"; }
    else { shown_unit = "bps"; decimals = 0; }
  }
  else if (unit == "Wh" && std::abs(raw) >= 1000000.0) { shown = raw / 1000000.0; shown_unit = "MWh"; }
  else if (unit == "Wh" && std::abs(raw) >= 1000.0) { shown = raw / 1000.0; shown_unit = "kWh"; }
  else if (unit == "s") {
    if (std::abs(raw) >= 86400.0) { shown = raw / 86400.0; shown_unit = "d"; }
    else if (std::abs(raw) >= 3600.0) { shown = raw / 3600.0; shown_unit = "h"; }
    else if (std::abs(raw) >= 60.0) { shown = raw / 60.0; shown_unit = "min"; }
    decimals = shown_unit == "s" ? 0 : (shown_unit == "d" && std::abs(shown) >= 10 ? 0 : 1);
  } else if (unit == "min") { decimals = 0; }
  else if (unit == "ratio") { shown = raw * 100.0; shown_unit = "%"; }
  else if (unit == "%" || unit == "V" || unit == "VA" || unit == "W" || unit == "dBm" || unit == "index" || unit == "µg/m³") decimals = 0;
  else if (unit == "dB") decimals = 1;
  else if (unit == "count") { decimals = 0; shown_unit.clear(); }
  else if (unit == "degF") { shown_unit = "°F"; decimals = 1; }
  else if (unit == "degC") { shown_unit = "°C"; decimals = 1; }
  if (metric == "channel_utilization" || metric == "air_utilization" || metric == "voltage") decimals = 1;
  const double factor = std::pow(10.0, decimals);
  row["display_value"] = std::round(shown * factor) / factor;
  row["display_unit"] = shown_unit;
  row["display_decimals"] = decimals;
  std::ostringstream text; text << std::fixed << std::setprecision(decimals)
                                << (unit == "dBm" ? row["display_value"].get<double>() : std::abs(row["display_value"].get<double>()));
  if (!shown_unit.empty()) text << ' ' << shown_unit;
  row["display_text"] = text.str();
  if (metric == "battery_power") row["meaning"] = raw < 0 ? "discharging" : raw > 0 ? "charging" : "idle";
  else if (metric == "grid_power") row["meaning"] = raw > 0 ? "importing" : raw < 0 ? "exporting" : "idle";
  else if (metric == "solar_power" || metric == "production_power") row["meaning"] = "producing";
  else if (metric == "load_power" || metric == "consumption_power") row["meaning"] = "consuming";
}

void add_contextual_severity(nlohmann::json& rows) {
  std::unordered_set<std::string> on_battery;
  for (const auto& row : rows) {
    if (row.value("metric", "") != "status" || !row["value"].is_string()) continue;
    const auto status = row["value"].get<std::string>();
    if (status.find("OB") != std::string::npos) on_battery.insert(row.value("resource", ""));
  }
  for (auto& row : rows) {
    if (row.value("metric", "") != "battery_runtime" || !row["value"].is_number()) continue;
    if (!on_battery.contains(row.value("resource", ""))) { row["severity"] = "info"; continue; }
    const auto minutes = row["value"].get<double>();
    row["severity"] = minutes < 10 ? "critical" : minutes < 15 ? "warning" : "info";
  }
}
}

TelemetryStore::TelemetryStore(const std::filesystem::path& path) {
  std::filesystem::create_directories(path.parent_path());
  check(sqlite3_open(path.c_str(), &db_), db_, "open telemetry database");
  exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA busy_timeout=5000;");
  exec("CREATE TABLE IF NOT EXISTS samples("
       "observed_at_ms INTEGER NOT NULL, resource TEXT NOT NULL, metric TEXT NOT NULL,"
       "value_json TEXT NOT NULL, numeric_value REAL, unit TEXT NOT NULL, quality TEXT NOT NULL);"
       "CREATE INDEX IF NOT EXISTS samples_lookup ON samples(resource,metric,observed_at_ms);"
       "CREATE TABLE IF NOT EXISTS current_state("
       "resource TEXT NOT NULL, metric TEXT NOT NULL, observed_at_ms INTEGER NOT NULL,"
       "value_json TEXT NOT NULL, unit TEXT NOT NULL, quality TEXT NOT NULL,"
       "PRIMARY KEY(resource,metric));"
       "CREATE TABLE IF NOT EXISTS audit("
       "id INTEGER PRIMARY KEY AUTOINCREMENT, at_ms INTEGER NOT NULL, actor TEXT NOT NULL,"
       "resource TEXT NOT NULL, action TEXT NOT NULL, request_json TEXT NOT NULL,"
       "result_json TEXT NOT NULL);");
  exec("CREATE TABLE IF NOT EXISTS state_events("
       "sequence INTEGER PRIMARY KEY AUTOINCREMENT, observed_at_ms INTEGER NOT NULL,"
       "resource TEXT NOT NULL, metric TEXT NOT NULL, old_value_json TEXT, new_value_json TEXT NOT NULL);"
       "CREATE INDEX IF NOT EXISTS state_events_time ON state_events(observed_at_ms);");
  check(sqlite3_prepare_v2(db_, "SELECT value_json FROM current_state WHERE resource=? AND metric=?", -1, &previous_stmt_, nullptr), db_, "prepare previous state");
  check(sqlite3_prepare_v2(db_, "INSERT INTO samples VALUES(?,?,?,?,?,?,?)", -1, &sample_stmt_, nullptr), db_, "prepare sample");
  check(sqlite3_prepare_v2(db_, "INSERT INTO state_events(observed_at_ms,resource,metric,old_value_json,new_value_json) VALUES(?,?,?,?,?)", -1, &event_stmt_, nullptr), db_, "prepare state event");
  check(sqlite3_prepare_v2(db_, "INSERT INTO current_state VALUES(?,?,?,?,?,?) ON CONFLICT(resource,metric) DO UPDATE SET observed_at_ms=excluded.observed_at_ms,value_json=excluded.value_json,unit=excluded.unit,quality=excluded.quality", -1, &upsert_stmt_, nullptr), db_, "prepare current state");
}

TelemetryStore::~TelemetryStore() {
  sqlite3_finalize(previous_stmt_);
  sqlite3_finalize(sample_stmt_);
  sqlite3_finalize(event_stmt_);
  sqlite3_finalize(upsert_stmt_);
  if (db_) sqlite3_close(db_);
}

void TelemetryStore::exec(const char* sql) {
  char* error = nullptr;
  const auto rc = sqlite3_exec(db_, sql, nullptr, nullptr, &error);
  if (rc != SQLITE_OK) {
    const std::string message = error ? error : "sqlite error";
    sqlite3_free(error);
    throw std::runtime_error(message);
  }
}

void TelemetryStore::record(const Observation& o) {
  std::lock_guard lock(mutex_);
  current_cache_at_ = {};
  std::string previous;
  sqlite3_reset(previous_stmt_);
  sqlite3_bind_text(previous_stmt_, 1, o.resource.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(previous_stmt_, 2, o.metric.c_str(), -1, SQLITE_TRANSIENT);
  if (sqlite3_step(previous_stmt_) == SQLITE_ROW) previous = reinterpret_cast<const char*>(sqlite3_column_text(previous_stmt_, 0));
  const auto value = o.value.dump();
  if (!previous.empty() && previous != value) {
    sqlite3_reset(event_stmt_);
    sqlite3_bind_int64(event_stmt_, 1, o.observed_at_ms); sqlite3_bind_text(event_stmt_, 2, o.resource.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(event_stmt_, 3, o.metric.c_str(), -1, SQLITE_TRANSIENT); sqlite3_bind_text(event_stmt_, 4, previous.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(event_stmt_, 5, value.c_str(), -1, SQLITE_TRANSIENT); check(sqlite3_step(event_stmt_), db_, "insert state event");
  }
  sqlite3_reset(sample_stmt_);
  sqlite3_bind_int64(sample_stmt_, 1, o.observed_at_ms);
  sqlite3_bind_text(sample_stmt_, 2, o.resource.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(sample_stmt_, 3, o.metric.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(sample_stmt_, 4, value.c_str(), -1, SQLITE_TRANSIENT);
  if (o.value.is_number()) sqlite3_bind_double(sample_stmt_, 5, o.value.get<double>());
  else sqlite3_bind_null(sample_stmt_, 5);
  sqlite3_bind_text(sample_stmt_, 6, o.unit.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(sample_stmt_, 7, o.quality.c_str(), -1, SQLITE_TRANSIENT);
  check(sqlite3_step(sample_stmt_), db_, "insert sample");

  sqlite3_reset(upsert_stmt_);
  sqlite3_bind_text(upsert_stmt_, 1, o.resource.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(upsert_stmt_, 2, o.metric.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_int64(upsert_stmt_, 3, o.observed_at_ms);
  sqlite3_bind_text(upsert_stmt_, 4, value.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(upsert_stmt_, 5, o.unit.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(upsert_stmt_, 6, o.quality.c_str(), -1, SQLITE_TRANSIENT);
  check(sqlite3_step(upsert_stmt_), db_, "upsert current state");
}

nlohmann::json TelemetryStore::current() const { return current(""); }
nlohmann::json TelemetryStore::current(std::string_view resource) const {
  std::lock_guard lock(mutex_);
  if (resource.empty()) {
    const auto now = std::chrono::steady_clock::now();
    if (current_cache_at_ != std::chrono::steady_clock::time_point{} &&
        now - current_cache_at_ < kCurrentCacheTTL) {
      return current_cache_;
    }
  }
  std::string sql = "SELECT resource,metric,observed_at_ms,value_json,unit,quality FROM current_state";
  if (!resource.empty()) sql += " WHERE resource=?";
  sql += " ORDER BY resource,metric";
  sqlite3_stmt* statement{};
  check(sqlite3_prepare_v2(db_, sql.c_str(), -1, &statement, nullptr), db_, "query current");
  if (!resource.empty()) sqlite3_bind_text(statement, 1, resource.data(), static_cast<int>(resource.size()), SQLITE_TRANSIENT);
  nlohmann::json rows = nlohmann::json::array();
  while (sqlite3_step(statement) == SQLITE_ROW) {
    nlohmann::json row = {{"resource", reinterpret_cast<const char*>(sqlite3_column_text(statement, 0))},
                    {"metric", reinterpret_cast<const char*>(sqlite3_column_text(statement, 1))},
                    {"observed_at_ms", sqlite3_column_int64(statement, 2)},
                    {"value", nlohmann::json::parse(reinterpret_cast<const char*>(sqlite3_column_text(statement, 3)))},
                    {"unit", reinterpret_cast<const char*>(sqlite3_column_text(statement, 4))},
                    {"quality", reinterpret_cast<const char*>(sqlite3_column_text(statement, 5))}};
    add_presentation(row); rows.push_back(std::move(row));
  }
  sqlite3_finalize(statement);
  add_contextual_severity(rows);
  if (resource.empty()) {
    current_cache_ = rows;
    current_cache_at_ = std::chrono::steady_clock::now();
  }
  return rows;
}

nlohmann::json TelemetryStore::query(std::string_view resource, std::string_view metric,
                                     std::int64_t start, std::int64_t end, std::size_t limit) const {
  std::lock_guard lock(mutex_);
  const char* sql = "SELECT observed_at_ms,value_json,unit,quality FROM samples WHERE resource=? AND metric=? AND observed_at_ms BETWEEN ? AND ? ORDER BY observed_at_ms LIMIT ?";
  sqlite3_stmt* statement{};
  check(sqlite3_prepare_v2(db_, sql, -1, &statement, nullptr), db_, "query samples");
  sqlite3_bind_text(statement, 1, resource.data(), static_cast<int>(resource.size()), SQLITE_TRANSIENT);
  sqlite3_bind_text(statement, 2, metric.data(), static_cast<int>(metric.size()), SQLITE_TRANSIENT);
  sqlite3_bind_int64(statement, 3, start); sqlite3_bind_int64(statement, 4, end);
  sqlite3_bind_int64(statement, 5, static_cast<sqlite3_int64>(limit));
  nlohmann::json rows = nlohmann::json::array();
  while (sqlite3_step(statement) == SQLITE_ROW) {
    nlohmann::json row = {{"observed_at_ms", sqlite3_column_int64(statement, 0)},
                    {"value", nlohmann::json::parse(reinterpret_cast<const char*>(sqlite3_column_text(statement, 1)))},
                    {"unit", reinterpret_cast<const char*>(sqlite3_column_text(statement, 2))},
                    {"quality", reinterpret_cast<const char*>(sqlite3_column_text(statement, 3))}};
    add_presentation(row); rows.push_back(std::move(row));
  }
  sqlite3_finalize(statement);
  return rows;
}

void TelemetryStore::record_audit(std::string_view actor, std::string_view resource,
                                  std::string_view action, const nlohmann::json& request,
                                  const nlohmann::json& result, std::int64_t at_ms) {
  std::lock_guard lock(mutex_);
  const char* sql = "INSERT INTO audit(at_ms,actor,resource,action,request_json,result_json) VALUES(?,?,?,?,?,?)";
  sqlite3_stmt* statement{}; check(sqlite3_prepare_v2(db_, sql, -1, &statement, nullptr), db_, "prepare audit");
  const auto request_text = request.dump(), result_text = result.dump();
  sqlite3_bind_int64(statement, 1, at_ms);
  sqlite3_bind_text(statement, 2, actor.data(), static_cast<int>(actor.size()), SQLITE_TRANSIENT);
  sqlite3_bind_text(statement, 3, resource.data(), static_cast<int>(resource.size()), SQLITE_TRANSIENT);
  sqlite3_bind_text(statement, 4, action.data(), static_cast<int>(action.size()), SQLITE_TRANSIENT);
  sqlite3_bind_text(statement, 5, request_text.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(statement, 6, result_text.c_str(), -1, SQLITE_TRANSIENT);
  check(sqlite3_step(statement), db_, "insert audit"); sqlite3_finalize(statement);
}

nlohmann::json TelemetryStore::audit(std::size_t limit) const {
  std::lock_guard lock(mutex_);
  const char* sql = "SELECT id,at_ms,actor,resource,action,request_json,result_json FROM audit ORDER BY id DESC LIMIT ?";
  sqlite3_stmt* statement{}; check(sqlite3_prepare_v2(db_, sql, -1, &statement, nullptr), db_, "query audit");
  sqlite3_bind_int64(statement, 1, static_cast<sqlite3_int64>(limit)); nlohmann::json rows = nlohmann::json::array();
  while (sqlite3_step(statement) == SQLITE_ROW)
    rows.push_back({{"id", sqlite3_column_int64(statement, 0)}, {"at_ms", sqlite3_column_int64(statement, 1)},
                    {"actor", reinterpret_cast<const char*>(sqlite3_column_text(statement, 2))},
                    {"resource", reinterpret_cast<const char*>(sqlite3_column_text(statement, 3))},
                    {"action", reinterpret_cast<const char*>(sqlite3_column_text(statement, 4))},
                    {"request", nlohmann::json::parse(reinterpret_cast<const char*>(sqlite3_column_text(statement, 5)))},
                    {"result", nlohmann::json::parse(reinterpret_cast<const char*>(sqlite3_column_text(statement, 6)))}});
  sqlite3_finalize(statement); return rows;
}

nlohmann::json TelemetryStore::events(std::size_t limit) const {
  std::lock_guard lock(mutex_);
  sqlite3_stmt* statement{};
  check(sqlite3_prepare_v2(db_, "SELECT sequence,observed_at_ms,resource,metric,old_value_json,new_value_json FROM state_events ORDER BY sequence DESC LIMIT ?", -1, &statement, nullptr), db_, "query events");
  sqlite3_bind_int64(statement, 1, static_cast<sqlite3_int64>(limit)); nlohmann::json rows = nlohmann::json::array();
  while (sqlite3_step(statement) == SQLITE_ROW)
    rows.push_back({{"sequence", sqlite3_column_int64(statement, 0)}, {"observed_at_ms", sqlite3_column_int64(statement, 1)},
                    {"resource", reinterpret_cast<const char*>(sqlite3_column_text(statement, 2))},
                    {"metric", reinterpret_cast<const char*>(sqlite3_column_text(statement, 3))},
                    {"old_value", nlohmann::json::parse(reinterpret_cast<const char*>(sqlite3_column_text(statement, 4)))},
                    {"new_value", nlohmann::json::parse(reinterpret_cast<const char*>(sqlite3_column_text(statement, 5)))}});
  sqlite3_finalize(statement); return rows;
}

}  // namespace skylab
