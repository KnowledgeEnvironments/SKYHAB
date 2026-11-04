// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/dyson.hpp"
#include "skylab/mqtt.hpp"

#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <sstream>

namespace skylab {
namespace {
std::int64_t now_ms() { return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count(); }
Observation observation(const nlohmann::json& d, std::string metric, nlohmann::json value, std::string unit = {}) {
  return {d.value("id", ""), std::move(metric), std::move(value), std::move(unit), "good", now_ms()};
}
std::string get_secret(const nlohmann::json& d, const char* field, const SecretStore& store) {
  const auto ref = d.value("credential_refs", nlohmann::json::object()).value(field, "");
  std::string env = "SKYHAB_SECRET_"; for (unsigned char c : ref) env += std::isalnum(c) ? static_cast<char>(std::toupper(c)) : '_';
  if (const char* value = std::getenv(env.c_str())) return value; return store.get(ref);
}
std::string iso_time() {
  const auto time = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now()); std::tm utc{}; gmtime_r(&time, &utc);
  std::ostringstream out; out << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ"); return out.str();
}
std::string envelope(std::string_view message, nlohmann::json fields = nlohmann::json::object()) {
  fields["msg"] = message; fields["time"] = iso_time(); return fields.dump();
}
struct DysonConfig { std::string host, username, password, root, status, command; bool robot{}; };
DysonConfig config(const nlohmann::json& d, const SecretStore& secrets) {
  DysonConfig c; c.host = d.at("endpoints").at(0).value("host", ""); c.username = get_secret(d, "username", secrets); c.password = get_secret(d, "password", secrets);
  const auto cfg = d.value("config", nlohmann::json::object()); c.root = cfg.value("mqtt_root_topic", ""); c.robot = d.value("class", "") == "robot-vacuum";
  if (c.host.empty() || c.username.empty() || c.password.empty() || c.root.empty()) throw std::runtime_error("Dyson MQTT configuration is incomplete");
  c.command = c.root + "/" + c.username + "/command"; c.status = c.root + "/" + c.username + (c.robot ? "/status" : "/status/current"); return c;
}
nlohmann::json current_value(const nlohmann::json& value) {
  if (value.is_array() && value.size() >= 2) return value[1]; return value;
}
void add_air(const nlohmann::json& d, const nlohmann::json& msg, std::vector<Observation>& out) {
  if (msg.value("msg", "") == "CURRENT-STATE" || msg.value("msg", "") == "STATE-CHANGE") {
    // Air-treatment firmware uses kebab-case on the wire; higher-level Dyson
    // libraries normalize it to productState before exposing it.
    const auto state = msg.contains("productState") ? msg["productState"]
                                                     : msg.value("product-state", nlohmann::json::object());
    auto text = [&](const char* key) { return state.contains(key) ? current_value(state[key]).get<std::string>() : std::string{}; };
    if (state.contains("fpwr")) out.push_back(observation(d, "power", text("fpwr") == "ON"));
    if (state.contains("fnst")) out.push_back(observation(d, "fan_state", text("fnst") == "FAN" ? "running" : "idle"));
    if (state.contains("fnsp")) { const auto value = text("fnsp"); if (value != "AUTO") try { out.push_back(observation(d, "fan_speed", std::stoi(value), "count")); } catch (...) {} }
    if (state.contains("auto")) out.push_back(observation(d, "auto_mode", text("auto") == "ON"));
    if (state.contains("nmod")) out.push_back(observation(d, "night_mode", text("nmod") == "ON"));
    if (state.contains("oson")) out.push_back(observation(d, "oscillation", text("oson") == "ON"));
    if (state.contains("fdir")) out.push_back(observation(d, "airflow_direction", text("fdir") == "ON" ? "forward" : "backward"));
    if (state.contains("cflr")) try { out.push_back(observation(d, "carbon_filter_life", std::stoi(text("cflr")), "%")); } catch (...) {}
    if (state.contains("hflr")) try { out.push_back(observation(d, "hepa_filter_life", std::stoi(text("hflr")), "%")); } catch (...) {}
    if (state.contains("ercd")) out.push_back(observation(d, "error_code", text("ercd")));
    if (msg.contains("rssi")) try { out.push_back(observation(d, "wifi_signal", std::stoi(msg["rssi"].get<std::string>()), "dBm")); } catch (...) {}
  }
  if (msg.value("msg", "") == "ENVIRONMENTAL-CURRENT-SENSOR-DATA") {
    const auto data = msg.value("data", nlohmann::json::object());
    auto numeric = [&](const char* metric, const char* key, double scale, double offset, const char* unit) { if (!data.contains(key) || !data[key].is_string()) return; try { out.push_back(observation(d, metric, std::stod(data[key].get<std::string>()) * scale + offset, unit)); } catch (...) {} };
    numeric("temperature", "tact", 0.1, -273.15, "°C"); numeric("humidity", "hact", 1, 0, "%");
    numeric("pm2_5", data.contains("p25r") ? "p25r" : "pm25", 1, 0, "µg/m³"); numeric("pm10", data.contains("p10r") ? "p10r" : "pm10", 1, 0, "µg/m³");
    numeric("voc_index", data.contains("va10") ? "va10" : "vact", 1, 0, "index"); numeric("no2_index", "noxl", 1, 0, "index"); numeric("formaldehyde", data.contains("hchr") ? "hchr" : "hcho", 1, 0, "µg/m³");
  }
}
void add_robot(const nlohmann::json& d, const nlohmann::json& msg, std::vector<Observation>& out) {
  const auto kind = msg.value("msg", ""); if (kind != "CURRENT-STATE" && kind != "STATE-CHANGE" && kind != "HELLO") return;
  if (kind == "HELLO") { if (msg.contains("version")) out.push_back(observation(d, "software_version", msg["version"])); return; }
  const auto state = kind == "STATE-CHANGE" ? msg.value("newstate", "unknown") : msg.value("state", "unknown"); out.push_back(observation(d, "operating_state", state));
  if (msg.contains("batteryChargeLevel")) out.push_back(observation(d, "battery_level", msg["batteryChargeLevel"], "%"));
  if (msg.contains("rssi")) try { out.push_back(observation(d, "wifi_signal", std::stoi(msg["rssi"].get<std::string>()), "dBm")); } catch (...) {}
  if (msg.contains("cleanDuration")) out.push_back(observation(d, "clean_duration", msg["cleanDuration"], "s"));
  if (msg.contains("currentVacuumPowerMode")) out.push_back(observation(d, "power_mode", msg["currentVacuumPowerMode"]));
  if (msg.contains("activeFaults")) out.push_back(observation(d, "active_faults", msg["activeFaults"].dump()));
  const bool docked = state == "CHARGED" || state == "CHARGING" || state == "DOCKED" ||
                      state == "INACTIVE_CHARGED" || state == "INACTIVE_CHARGING";
  out.push_back(observation(d, "docked", docked));
}
std::vector<nlohmann::json> mqtt_exchange(const DysonConfig& c, const std::vector<std::pair<std::string, nlohmann::json>>& requests, int wait = 2800) {
  mqtt::Client client(c.host, 1883, "skyhabd-" + std::to_string(now_ms()), c.username, c.password);
  std::vector<std::string> topics{c.status}; if (!c.robot) { topics.push_back(c.root + "/" + c.username + "/status/faults"); topics.push_back(c.root + "/" + c.username + "/status/connection"); }
  // Subscribe one topic per packet. Besides keeping compatibility with the
  // oldest RB01 broker, this gives each SUBACK a fixed, unambiguous length.
  for (const auto& topic : topics) client.subscribe({topic});
  for (const auto& [message, fields] : requests) client.publish(c.command, envelope(message, fields));
  std::vector<nlohmann::json> out; for (const auto& message : client.receive_for(wait)) try { out.push_back(nlohmann::json::parse(message.payload)); } catch (...) {} return out;
}
}

PollResult poll_dyson(const nlohmann::json& d, const SecretStore& secrets) {
  try { const auto c = config(d, secrets); std::vector<std::pair<std::string, nlohmann::json>> requests{{"REQUEST-CURRENT-STATE", {}}};
    if (!c.robot) { requests.push_back({"REQUEST-CURRENT-FAULTS", {}}); requests.push_back({"REQUEST-PRODUCT-ENVIRONMENT-CURRENT-SENSOR-DATA", {}}); }
    auto messages = mqtt_exchange(c, requests); std::vector<Observation> out{observation(d, "health", messages.empty() ? "degraded" : "responding")};
    for (const auto& message : messages) c.robot ? add_robot(d, message, out) : add_air(d, message, out);
    return {messages.empty() ? "degraded" : "responding", messages.empty() ? "Dyson MQTT returned no state" : "", std::move(out)};
  } catch (const std::exception& e) { return {"unreachable", e.what(), {observation(d, "health", "unreachable")}}; }
}

nlohmann::json invoke_dyson(const nlohmann::json& d, const SecretStore& secrets, std::string_view action, const nlohmann::json& parameters) {
  try { const auto c = config(d, secrets); std::string message; nlohmann::json fields;
    nlohmann::json requested_state = nlohmann::json::object();
    auto integer = [&](const char* key, int fallback) { try { const auto& value = parameters.at(key); return value.is_string() ? std::stoi(value.get<std::string>()) : value.get<int>(); } catch (...) { return fallback; } };
    auto boolean = [&](const char* key, bool fallback) { try { const auto& value = parameters.at(key); if (value.is_boolean()) return value.get<bool>(); if (value.is_string()) return value.get<std::string>() == "true"; } catch (...) {} return fallback; };
    if (c.robot) {
      if (action == "vacuum.start") { message = "START"; fields = {{"mode-reason", "RAPP"}, {"fullCleanType", "immediate"}}; }
      else if (action == "vacuum.pause") { message = "PAUSE"; fields = {{"mode-reason", "RAPP"}}; }
      else if (action == "vacuum.resume") { message = "RESUME"; fields = {{"mode-reason", "RAPP"}}; }
      else if (action == "vacuum.return_to_dock") { message = "ABORT"; fields = {{"mode-reason", "RAPP"}}; }
      else return {{"ok", false}, {"error", "unsupported Dyson vacuum action"}};
    } else {
      nlohmann::json data;
      if (action == "power.on" || action == "power.off") data["fpwr"] = action == "power.on" ? "ON" : "OFF";
      else if (action == "dyson.fan_speed.set") { const auto speed = integer("speed", -1); if (speed < 1 || speed > 10) return {{"ok", false}, {"error", "speed must be 1..10"}}; auto value = std::to_string(speed); data["fnsp"] = std::string(4 - value.size(), '0') + value; }
      else if (action == "dyson.auto.set") data["auto"] = boolean("enabled", false) ? "ON" : "OFF";
      else if (action == "dyson.night.set") data["nmod"] = boolean("enabled", false) ? "ON" : "OFF";
      else if (action == "dyson.oscillation.set") data["oson"] = boolean("enabled", false) ? "ON" : "OFF";
      else return {{"ok", false}, {"error", "unsupported Dyson air action"}};
      requested_state = data;
      message = "STATE-SET"; fields = {{"mode-reason", "RAPP"}, {"data", data}};
    }
    auto messages = mqtt_exchange(c, {{message, fields}, {"REQUEST-CURRENT-STATE", {}}}, 3500);
    bool verified = false; std::string observed_state;
    if (c.robot) {
      for (const auto& reply : messages) {
        if (reply.value("msg", "") == "STATE-CHANGE") observed_state = reply.value("newstate", observed_state);
        else if (reply.value("msg", "") == "CURRENT-STATE") observed_state = reply.value("state", observed_state);
      }
      if (action == "vacuum.start") verified = observed_state.rfind("FULL_CLEAN_", 0) == 0 && observed_state != "FULL_CLEAN_ABORTED" && observed_state != "FULL_CLEAN_FINISHED";
      else if (action == "vacuum.pause") verified = observed_state == "FULL_CLEAN_PAUSED";
      else if (action == "vacuum.resume") verified = observed_state == "FULL_CLEAN_RUNNING" || observed_state == "FULL_CLEAN_TRAVERSING" || observed_state == "FULL_CLEAN_DISCOVERING";
      else verified = observed_state == "FULL_CLEAN_ABORTED" || observed_state == "FULL_CLEAN_ABANDONED" || observed_state == "FULL_CLEAN_NEEDS_CHARGE" || observed_state == "FULL_CLEAN_CHARGING" || observed_state.rfind("INACTIVE_", 0) == 0;
    } else {
      for (const auto& reply : messages) {
        const auto product = reply.contains("productState") ? reply["productState"] : reply.value("product-state", nlohmann::json::object());
        if (!product.is_object()) continue; bool matches = true;
        for (const auto& [key, requested] : requested_state.items()) {
          if (!product.contains(key) || current_value(product[key]) != requested) { matches = false; break; }
        }
        if (matches) verified = true;
      }
    }
    return {{"ok", verified}, {"verified", verified}, {"messages_received", messages.size()},
            {"error", verified ? "" : "Dyson did not confirm the requested state"}};
  } catch (const std::exception& e) { return {{"ok", false}, {"error", e.what()}}; }
}
}  // namespace skylab
