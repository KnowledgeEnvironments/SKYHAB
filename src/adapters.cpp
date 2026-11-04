// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/adapters.hpp"
#include "skylab/dyson.hpp"
#include "skylab/ephemeris.hpp"
#include "skylab/meshtastic.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <sstream>
#include <unordered_map>
#include <cctype>
#include <sys/wait.h>
#include <iomanip>
#include <mutex>
#include <poll.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

namespace skylab {
namespace {
std::int64_t now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

std::string host(const nlohmann::json& d) {
  if (d.contains("endpoints") && !d["endpoints"].empty()) return d["endpoints"][0].value("host", "");
  return {};
}

std::pair<int, std::string> capture(const std::string& command) {
  // Adapter commands are assembled only from validated inventory host/ID fields.
  // The transport abstraction will replace this portable bootstrap implementation.
  std::array<char, 4096> buffer{};
  std::string output;
  FILE* pipe = popen(command.c_str(), "r");
  if (!pipe) return {-1, ""};
  while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe)) output += buffer.data();
  const int status = pclose(pipe);
  return {WIFEXITED(status) ? WEXITSTATUS(status) : -1, output};
}

std::string url_component(std::string_view value) {
  std::ostringstream out;
  out << std::uppercase << std::hex;
  for (const unsigned char c : value) {
    if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') out << c;
    else out << '%' << std::setw(2) << std::setfill('0') << static_cast<int>(c);
  }
  return out.str();
}

bool safe_host(const std::string& value) {
  return !value.empty() && value.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:") == std::string::npos;
}

bool safe_ssh_user(const std::string& value) {
  return !value.empty() && value.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-") == std::string::npos;
}

bool safe_nut_name(const std::string& value) {
  return !value.empty() && value.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._@:-") == std::string::npos;
}

bool safe_routeros_fragment(const std::string& value) {
  return !value.empty() && value.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-") == std::string::npos;
}

std::string secret(const nlohmann::json& d, const char* reference_field, const SecretStore& store) {
  const auto reference = d.value("credential_refs", nlohmann::json::object()).value(reference_field, "");
  std::string name = "SKYHAB_SECRET_";
  for (unsigned char c : reference) name += std::isalnum(c) ? static_cast<char>(std::toupper(c)) : '_';
  if (const char* value = std::getenv(name.c_str())) return value;
  return store.get(reference);
}

bool safe_secret(const std::string& value) {
  return !value.empty() && value.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+/=") == std::string::npos;
}

Observation obs(const std::string& id, std::string metric, nlohmann::json value,
                std::string unit = "") {
  return {id, std::move(metric), std::move(value), std::move(unit), "good", now_ms()};
}

int integer_parameter(const nlohmann::json& parameters, const char* key, int fallback) {
  if (!parameters.contains(key)) return fallback;
  try {
    if (parameters[key].is_number_integer()) return parameters[key].get<int>();
    if (parameters[key].is_number()) return static_cast<int>(parameters[key].get<double>());
    if (parameters[key].is_string()) return std::stoi(parameters[key].get<std::string>());
  } catch (...) {}
  return fallback;
}

PollResult ping(const nlohmann::json& d) {
  const auto address = host(d);
  if (!safe_host(address)) return {"unknown", "invalid or missing endpoint", {}};
  const auto [code, text] = capture("/sbin/ping -c 1 -W 1000 " + address + " 2>/dev/null");
  (void)text;
  const auto health = code == 0 ? "responding" : "unreachable";
  return {health, code == 0 ? "" : "ping failed", {obs(d["id"], "health", health)}};
}

PollResult demo_static(const nlohmann::json& d) {
  std::vector<Observation> observations;
  const auto configured = d.value("config", nlohmann::json::object()).value("observations", nlohmann::json::array());
  for (const auto& value : configured) {
    if (!value.is_object() || !value.contains("metric") || !value.contains("value")) continue;
    observations.push_back(obs(value.value("resource", d.value("id", "")), value.value("metric", ""),
                               value["value"], value.value("unit", "")));
  }
  const auto health = d.value("config", nlohmann::json::object()).value("health", "responding");
  const bool has_health = std::any_of(observations.begin(), observations.end(), [&](const Observation& value) {
    return value.resource == d.value("id", "") && value.metric == "health";
  });
  if (!has_health) observations.insert(observations.begin(), obs(d.value("id", ""), "health", health));
  return {health, "", std::move(observations)};
}

struct AdemcoSession {
  std::mutex mutex;
  int socket{-1};
  std::string address;
  std::string buffer;
  nlohmann::json state{{"partition_mode", "unknown"}, {"armed", false}, {"ready", false},
                       {"alarm", false}, {"fire", false}, {"bypass", false},
                       {"trouble", false}, {"ac_power", false}, {"open_zones", ""},
                       {"open_zone_count", 0}, {"keypad_line1", ""}, {"keypad_line2", ""},
                       {"keypad_beep", 0}, {"last_event", ""}};

  ~AdemcoSession() { close_socket(); }
  void close_socket() { if (socket >= 0) ::close(socket); socket = -1; buffer.clear(); }

  static std::vector<std::string> fields(const std::string& value) {
    std::vector<std::string> out; std::size_t start = 0;
    while (true) { const auto comma = value.find(',', start); out.push_back(value.substr(start, comma - start));
      if (comma == std::string::npos) return out; start = comma + 1; }
  }

  void parse(const std::string& raw) {
    if (raw.size() < 4 || raw.front() != '%' || raw.back() != '$') return;
    auto parts = fields(raw.substr(1, raw.size() - 2)); if (parts.empty()) return;
    if (parts[0] == "00" && parts.size() >= 6) {
      unsigned icons = 0; try { icons = static_cast<unsigned>(std::stoul(parts[2], nullptr, 16)); } catch (...) {}
      state["armed_stay"] = (icons & (1u << 15)) != 0; state["low_battery"] = (icons & (1u << 14)) != 0;
      state["fire"] = (icons & (1u << 13)) != 0; state["ready"] = (icons & (1u << 12)) != 0;
      state["trouble"] = (icons & (1u << 9)) != 0; state["fire"] = state["fire"].get<bool>() || (icons & (1u << 8)) != 0;
      state["zero_entry"] = (icons & (1u << 7)) != 0; state["chime"] = (icons & (1u << 5)) != 0;
      state["bypass"] = (icons & (1u << 4)) != 0; state["ac_power"] = (icons & (1u << 3)) != 0;
      state["armed_away"] = (icons & (1u << 2)) != 0; state["alarm_memory"] = (icons & (1u << 1)) != 0;
      state["alarm"] = (icons & 1u) != 0;
      if (state["alarm"].get<bool>()) state["partition_mode"] = "alarm";
      else if (state["armed_stay"].get<bool>()) state["partition_mode"] = state["zero_entry"].get<bool>() ? "zero-entry-stay" : "armed-stay";
      else if (state["armed_away"].get<bool>()) state["partition_mode"] = state["zero_entry"].get<bool>() ? "zero-entry-away" : "armed-away";
      else state["partition_mode"] = state["ready"].get<bool>() ? "ready" : "not-ready";
      state["armed"] = state["armed_stay"].get<bool>() || state["armed_away"].get<bool>();
      try { state["keypad_beep"] = std::stoi(parts[4]); } catch (...) { state["keypad_beep"] = 0; }
      std::string text = parts[5]; for (std::size_t i = 6; i < parts.size(); ++i) text += "," + parts[i];
      if (text.size() < 32) text.resize(32, ' ');
      state["keypad_line1"] = text.substr(0, 16); state["keypad_line2"] = text.substr(16, 16);
    } else if (parts[0] == "01" && parts.size() >= 2) {
      std::vector<int> zones;
      for (std::size_t byte_index = 0; byte_index + 1 < parts[1].size(); byte_index += 2) {
        unsigned byte = 0; try { byte = static_cast<unsigned>(std::stoul(parts[1].substr(byte_index, 2), nullptr, 16)); } catch (...) {}
        for (unsigned bit = 0; bit < 8; ++bit) if (byte & (1u << bit)) zones.push_back(static_cast<int>(byte_index * 4 + bit + 1));
      }
      std::ostringstream names; for (std::size_t i = 0; i < zones.size(); ++i) names << (i ? ", " : "") << zones[i];
      state["open_zones"] = names.str(); state["open_zone_count"] = zones.size();
    } else if (parts[0] == "02" && parts.size() >= 2 && parts[1].size() >= 2) {
      int mode = -1; try { mode = std::stoi(parts[1].substr(0, 2)); } catch (...) {}
      static const std::array<const char*, 11> modes{"away", "ready", "ready-to-arm", "not-ready", "armed-stay", "armed-away", "zero-entry-stay", "exit-delay", "alarm", "alarm-memory", "zero-entry-away"};
      state["partition_mode"] = mode >= 0 && mode < static_cast<int>(modes.size()) ? modes[mode] : "unknown";
      state["armed"] = mode == 4 || mode == 5 || mode == 6 || mode == 7 || mode == 10;
      state["ready"] = mode == 1 || mode == 2;
      if (mode == 8) state["alarm"] = true;
    } else if (parts[0] == "03" && parts.size() >= 2) state["last_event"] = parts[1];
  }

  bool write_line(const std::string& line) {
    const std::string bytes = line + "\r\n"; std::size_t offset = 0;
    while (offset < bytes.size()) { const auto n = ::send(socket, bytes.data() + offset, bytes.size() - offset, 0); if (n <= 0) return false; offset += static_cast<std::size_t>(n); }
    return true;
  }

  bool drain(int wait_ms) {
    bool received = false; const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(wait_ms);
    auto consume = [&] {
      while (true) { const auto end = buffer.find("\r\n"); if (end == std::string::npos) break;
        const auto line = buffer.substr(0, end); buffer.erase(0, end + 2);
        if (!line.empty() && line != "OK" && line.rfind("Login", 0) != 0) parse(line); }
    };
    consume();
    while (std::chrono::steady_clock::now() < deadline) {
      const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now()).count();
      pollfd pfd{socket, POLLIN, 0}; const int ready = ::poll(&pfd, 1, static_cast<int>(std::max<std::int64_t>(1, remaining)));
      if (ready < 0) { close_socket(); return false; } if (ready == 0) break;
      char data[4096]; const auto count = ::recv(socket, data, sizeof(data), 0); if (count <= 0) { close_socket(); return false; }
      received = true; buffer.append(data, static_cast<std::size_t>(count));
      consume();
    }
    return received;
  }

  bool connect_to(const std::string& host, const std::string& password, std::string& error) {
    if (socket >= 0 && address == host) return true; close_socket(); address = host;
    socket = ::socket(AF_INET, SOCK_STREAM, 0); if (socket < 0) { error = "cannot create TPI socket"; return false; }
    sockaddr_in endpoint{}; endpoint.sin_family = AF_INET; endpoint.sin_port = htons(4025);
    if (::inet_pton(AF_INET, host.c_str(), &endpoint.sin_addr) != 1 || ::connect(socket, reinterpret_cast<sockaddr*>(&endpoint), sizeof(endpoint)) != 0) {
      error = "cannot connect to Envisalink TPI"; close_socket(); return false;
    }
    drain(1500); if (!write_line(password)) { error = "cannot send Envisalink login"; close_socket(); return false; }
    std::string login; const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (std::chrono::steady_clock::now() < deadline) {
      pollfd pfd{socket, POLLIN, 0}; if (::poll(&pfd, 1, 300) <= 0) continue;
      char data[4096]; const auto count = ::recv(socket, data, sizeof(data), 0); if (count <= 0) break; login.append(data, static_cast<std::size_t>(count));
      if (login.find("OK") != std::string::npos) { buffer += login; drain(300); write_line("500001"); drain(1000); return true; }
      if (login.find("FAILED") != std::string::npos) break;
    }
    error = "Envisalink login failed"; close_socket(); return false;
  }
};

AdemcoSession& alarm_session() { static AdemcoSession session; return session; }

PollResult envisalink(const nlohmann::json& d, const SecretStore& secrets) {
  auto& session = alarm_session(); std::lock_guard lock(session.mutex); std::string error;
  const auto password = secret(d, "password", secrets);
  if (password.empty()) return {"degraded", "Envisalink password unavailable", {obs(d["id"], "health", "degraded")}};
  if (!session.connect_to(host(d), password, error)) return {"unreachable", error, {obs(d["id"], "health", "unreachable")}};
  if (!session.write_line("500000")) { session.close_socket(); return {"unreachable", "TPI write failed", {obs(d["id"], "health", "unreachable")}}; }
  session.drain(500); std::vector<Observation> out{obs(d["id"], "health", "responding")};
  for (const auto& metric : {"partition_mode","armed","ready","alarm","fire","bypass","trouble","ac_power","low_battery","alarm_memory","chime","open_zones","open_zone_count","keypad_line1","keypad_line2","keypad_beep","last_event"})
    if (session.state.contains(metric)) out.push_back(obs(d["id"], metric, session.state[metric]));
  const auto config = d.value("config", nlohmann::json::object());
  if (config.contains("mandatory_bypass_zone")) {
    out.push_back(obs(d["id"], "mandatory_bypass_zone", config["mandatory_bypass_zone"]));
    out.push_back(obs(d["id"], "bypass_policy", config.value("mandatory_bypass_reason", "configured bypass")));
  }
  return {"responding", "", std::move(out)};
}

PollResult shelly(const nlohmann::json& d) {
  const auto address = host(d), adapter = d.value("adapter", "");
  if (!safe_host(address)) return {"unknown", "invalid endpoint", {}};
  std::string url;
  if (adapter == "shelly.plus-wd") url = "http://" + address + "/light/0";
  else if (adapter == "shelly.dimmer2") url = "http://" + address + "/status";
  else if (adapter == "shelly.plug-us-g4") url = "http://" + address + "/rpc/Switch.GetStatus?id=0";
  else url = "http://" + address + "/rpc/Switch.GetStatus?id=0";
  const auto [code, text] = capture("/usr/bin/curl -fsS --max-time 3 '" + url + "' 2>/dev/null");
  if (code != 0) return {"unreachable", "Shelly request failed", {obs(d["id"], "health", "unreachable")}};
  try {
    const auto data = nlohmann::json::parse(text);
    const auto light = adapter == "shelly.dimmer2" && data.contains("lights") && !data["lights"].empty() ? data["lights"][0] : data;
    const bool on = light.value((adapter == "shelly.plus-wd" || adapter == "shelly.dimmer2") ? "ison" : "output", false);
    const bool dimmable = adapter == "shelly.plus-wd" || adapter == "shelly.dimmer2";
    const double brightness = dimmable ? light.value("brightness", 0.0) : (on ? 100.0 : 0.0);
    return {"responding", "", {obs(d["id"], "health", "responding"), obs(d["id"], "power", on), obs(d["id"], "brightness", brightness, "%")}};
  } catch (...) { return {"degraded", "invalid Shelly response", {obs(d["id"], "health", "degraded")}}; }
}

PollResult venstar(const nlohmann::json& d) {
  if (!safe_host(host(d))) return {"unknown", "invalid endpoint", {}};
  const auto [code, text] = capture("/usr/bin/curl -fsS --max-time 3 'http://" + host(d) + "/query/info' 2>/dev/null");
  if (code != 0) return {"unreachable", "thermostat request failed", {obs(d["id"], "health", "unreachable")}};
  try {
    auto j = nlohmann::json::parse(text);
    static const std::array<const char*, 4> modes{"off", "heat", "cool", "auto"};
    static const std::array<const char*, 3> states{"idle", "heating", "cooling"};
    static const std::array<const char*, 2> fan_modes{"auto", "on"};
    static const std::array<const char*, 2> fan_states{"idle", "running"};
    const int mode = j.value("mode", 0), state = j.value("state", 0);
    const int fan = j.value("fan", 0), fan_state = j.value("fanstate", 0);
    return {"responding", "", {obs(d["id"], "health", "responding"), obs(d["id"], "temperature", j.value("spacetemp", 0.0), "degF"),
      obs(d["id"], "mode", mode >= 0 && mode < static_cast<int>(modes.size()) ? modes[mode] : "unknown"),
      obs(d["id"], "state", state >= 0 && state < static_cast<int>(states.size()) ? states[state] : "unknown"),
      obs(d["id"], "fan_mode", fan >= 0 && fan < static_cast<int>(fan_modes.size()) ? fan_modes[fan] : "unknown"),
      obs(d["id"], "fan_state", fan_state >= 0 && fan_state < static_cast<int>(fan_states.size()) ? fan_states[fan_state] : "unknown"),
      obs(d["id"], "cool_setpoint", j.value("cooltemp", 0.0), "degF"), obs(d["id"], "heat_setpoint", j.value("heattemp", 0.0), "degF")}};
  } catch (...) { return {"degraded", "invalid thermostat response", {obs(d["id"], "health", "degraded")}}; }
}

std::unordered_map<std::string, std::string> colon_values(const std::string& text) {
  std::unordered_map<std::string, std::string> values;
  std::istringstream lines(text); std::string line;
  while (std::getline(lines, line)) {
    const auto colon = line.find(':'); if (colon == std::string::npos) continue;
    auto key = line.substr(0, colon), value = line.substr(colon + 1);
    while (!key.empty() && key.front() == ' ') key.erase(key.begin());
    while (!key.empty() && key.back() == ' ') key.pop_back();
    while (!value.empty() && value.front() == ' ') value.erase(value.begin());
    while (!value.empty() && (value.back() == ' ' || value.back() == '\r')) value.pop_back();
    values[key] = value;
  }
  return values;
}

PollResult nut(const nlohmann::json& d) {
  const auto address = host(d), user = d["config"].value("ssh_user", "");
  const auto name = d["config"].value("nut_name", "ups@localhost");
  if (!safe_host(address) || !safe_ssh_user(user) || !safe_nut_name(name))
    return {"unknown", "invalid NUT endpoint or SSH configuration", {}};
  const auto [code, text] = capture("/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 " + user + "@" + address + " 'upsc " + name + " 2>/dev/null' 2>/dev/null");
  if (code != 0) return {"unreachable", "NUT SSH request failed", {obs(d["id"], "health", "unreachable")}};
  const auto v = colon_values(text); std::vector<Observation> out{obs(d["id"], "health", "responding")};
  auto number = [&](const char* key, const char* metric, const char* unit, double scale = 1.0) {
    if (auto it = v.find(key); it != v.end()) try { out.push_back(obs(d["id"], metric, std::stod(it->second) * scale, unit)); } catch (...) {}
  };
  number("battery.charge", "battery_charge", "%"); number("battery.runtime", "battery_runtime", "min", 1.0/60.0);
  number("input.voltage", "input_voltage", "V"); number("output.voltage", "output_voltage", "V");
  number("ups.load", "load", "%"); number("ups.power", "apparent_power", "VA");
  number("ups.realpower", "real_power", "W"); number("ups.temperature", "temperature", "degC");
  if (auto it = v.find("ups.status"); it != v.end()) out.push_back(obs(d["id"], "status", it->second));
  return {"responding", "", std::move(out)};
}

std::string field(const std::string& line, const std::string& key) {
  const auto marker = key + "=";
  const auto start = line.find(marker); if (start == std::string::npos) return {};
  const auto value = start + marker.size(), end = line.find(' ', value);
  auto result = line.substr(value, end == std::string::npos ? end : end - value);
  while (!result.empty() && (result.back() == '\r' || result.back() == '\n')) result.pop_back();
  return result;
}

struct NetworkIdentityCache {
  std::mutex mutex;
  std::unordered_map<std::string, std::string> ip;
  std::unordered_map<std::string, std::string> name;
};
NetworkIdentityCache& network_identities() { static NetworkIdentityCache cache; return cache; }

double routeros_duration_seconds(std::string text) {
  double total = 0; std::size_t used = 0;
  auto take = [&](char suffix, double scale) {
    const auto at = text.find(suffix, used); if (at == std::string::npos) return;
    try { total += std::stod(text.substr(used, at - used)) * scale; used = at + 1; } catch (...) {}
  };
  take('w', 604800); take('d', 86400);
  const auto clock = text.substr(used); int h = 0, m = 0; double s = 0;
  if (std::sscanf(clock.c_str(), "%d:%d:%lf", &h, &m, &s) == 3) total += h * 3600 + m * 60 + s;
  else { take('h', 3600); take('m', 60); take('s', 1); }
  return total;
}

double routeros_size_bytes(std::string text) {
  double scale = 1;
  for (const auto& [suffix, multiplier] : std::array<std::pair<std::string_view, double>, 4>{{{"KiB", 1024.0}, {"MiB", 1024.0 * 1024}, {"GiB", 1024.0 * 1024 * 1024}, {"TiB", 1024.0 * 1024 * 1024 * 1024}}})
    if (text.ends_with(suffix)) { scale = multiplier; text.resize(text.size() - suffix.size()); break; }
  return std::stod(text) * scale;
}

std::int64_t routeros_local_time_ms(const std::string& text) {
  std::tm time{}; std::istringstream input(text); input >> std::get_time(&time, "%Y-%m-%d %H:%M:%S");
  if (input.fail()) return 0; time.tm_isdst = -1; return static_cast<std::int64_t>(std::mktime(&time)) * 1000;
}

std::string display_bytes(double bytes) {
  static const std::array<const char*, 5> units{"B", "KiB", "MiB", "GiB", "TiB"}; std::size_t unit = 0;
  while (bytes >= 1024 && unit + 1 < units.size()) { bytes /= 1024; ++unit; }
  std::ostringstream out; out << std::fixed << std::setprecision(unit == 0 || bytes >= 10 ? 0 : 1) << bytes << ' ' << units[unit]; return out.str();
}

std::string display_age(std::int64_t timestamp_ms) {
  if (timestamp_ms <= 0) return "unknown"; const auto seconds = std::max<std::int64_t>(0, (now_ms() - timestamp_ms) / 1000);
  if (seconds < 120) return "just now"; if (seconds < 7200) return std::to_string(seconds / 60) + " min ago";
  if (seconds < 172800) return std::to_string(seconds / 3600) + " h ago";
  if (seconds < 1209600) return std::to_string(seconds / 86400) + " d ago";
  if (seconds < 7776000) return std::to_string(seconds / 604800) + " wk ago";
  return std::to_string(seconds / 2592000) + " mo ago";
}

PollResult mikrotik(const nlohmann::json& d) {
  const auto address = host(d), user = d["config"].value("ssh_user", "");
  const bool uses_ssh_alias = d.value("class", "") == "router";
  const auto target = uses_ssh_alias ? d.value("id", address) : user + "@" + address;
  if (!safe_host(address) || !safe_host(target) || (!uses_ssh_alias && !safe_ssh_user(user)))
    return {"unknown", "invalid MikroTik endpoint or SSH configuration", {}};
  const auto config = d.value("config", nlohmann::json::object());
  const auto backup_resource = config.value("backup_share_resource", "");
  const auto backup_label = config.value("backup_disk_label", "backup");
  const auto backup_path = config.value("backup_path", "usb1/dump/");
  const bool backup_enabled = !backup_resource.empty() && safe_routeros_fragment(backup_label) && safe_routeros_fragment(backup_path);
  const bool wifi_discovery = config.value("discover_wifi_clients", false);
  auto remote = std::string("/system resource print; /interface print terse without-paging; /interface monitor-traffic [find type=ether] once do={:put (\"RATE name=\" . $name . \" rx=\" . $\"rx-bits-per-second\" . \" tx=\" . $\"tx-bits-per-second\")}; /interface ethernet monitor [find] once do={:put (\"PHY name=\" . $name . \" rate=\" . $rate . \" status=\" . $status)}");
  if (backup_enabled)
    remote += "; :local b [/disk find where fs-label=\"" + backup_label + "\"]; :if ([:len $b] > 0) do={:put (\"BACKUP size=\" . [/disk get $b size] . \" free=\" . [/disk get $b free] . \" use=\" . [/disk get $b use] . \" model=\" . [/disk get $b model])}; /file print terse without-paging where name~\"" + backup_path + "\"";
  if (wifi_discovery)
    remote += "; :put \"SKYLAB_DHCP\"; /ip dhcp-server lease print terse without-paging; :put \"SKYLAB_WIFI\"; /interface wifi registration-table print terse without-paging";
  if (d.value("class", "") == "network-switch")
    remote += "; :put \"SKYLAB_BRIDGE_HOSTS\"; /interface bridge host print terse without-paging";
  const auto [code, text] = capture("/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=15 " + target + " '" + remote + "' 2>/dev/null");
  if (code != 0) {
    auto reachable = ping(d);
    if (reachable.health == "responding") {
      reachable.error.clear(); reachable.observations.push_back(obs(d["id"], "management_access", false));
      return reachable;
    }
    return {"unreachable", "RouterOS SSH and reachability failed", {obs(d["id"], "health", "unreachable")}};
  }
  std::vector<Observation> out{obs(d["id"], "health", "responding"), obs(d["id"], "management_access", true)};
  if (backup_enabled || wifi_discovery) {
    const auto marker = text.find("BACKUP ");
    if (marker != std::string::npos) {
      const auto line_end = text.find('\n', marker);
      const auto line = text.substr(marker, line_end - marker);
      const auto resource = backup_resource;
      try {
        const double size = std::stod(field(line, "size")), free = std::stod(field(line, "free"));
        out.push_back(obs(resource, "health", "responding")); out.push_back(obs(resource, "size", size, "B"));
        out.push_back(obs(resource, "free", free, "B")); out.push_back(obs(resource, "allocated", size - free, "B"));
        out.push_back(obs(resource, "used_percent", std::stod(field(line, "use")), "%"));
      } catch (...) {}
      out.push_back(obs(resource, "model", field(line, "model")));
      std::istringstream file_lines(text); std::string file_line, latest_name, latest_date;
      while (std::getline(file_lines, file_line)) {
        const auto name = field(file_line, "name"), modified = field(file_line, "last-modified");
        if (!name.empty() && !modified.empty() && modified > latest_date) { latest_date = modified; latest_name = name; }
      }
      if (!latest_name.empty()) { out.push_back(obs(resource, "latest_file", latest_name)); out.push_back(obs(resource, "latest_modified", latest_date)); }
    }
    std::unordered_map<std::string, std::string> client_ip, client_name;
    const auto dhcp_marker = text.find("SKYLAB_DHCP"), wifi_marker = text.find("SKYLAB_WIFI");
    if (dhcp_marker != std::string::npos && wifi_marker != std::string::npos) {
      std::istringstream rows(text.substr(dhcp_marker, wifi_marker - dhcp_marker)); std::string row;
      while (std::getline(rows, row)) { const auto mac = field(row, "mac-address"); if (mac.empty()) continue;
        client_ip[mac] = field(row, "active-address"); if (client_ip[mac].empty()) client_ip[mac] = field(row, "address"); client_name[mac] = field(row, "host-name"); }
      { auto& cache = network_identities(); std::lock_guard lock(cache.mutex); cache.ip = client_ip; cache.name = client_name; }
      rows.clear(); rows.str(text.substr(wifi_marker));
      const auto wifi_parent_map = config.value("wifi_parent_map", nlohmann::json::object());
      while (std::getline(rows, row)) {
        const auto mac = field(row, "mac-address"), radio = field(row, "interface"); if (mac.empty() || radio.empty()) continue;
        std::string parent = d.value("id", "");
        for (const auto& [needle, configured_parent] : wifi_parent_map.items())
          if (configured_parent.is_string() && radio.find(needle) != std::string::npos) { parent = configured_parent.get<std::string>(); break; }
        auto suffix = mac; for (auto& c : suffix) if (c == ':') c = '-'; const auto resource = parent + "/client/" + suffix;
        out.push_back(obs(resource, "health", "associated")); out.push_back(obs(resource, "name", client_name[mac].empty() ? mac : client_name[mac]));
        out.push_back(obs(resource, "mac_address", mac)); out.push_back(obs(resource, "address", client_ip[mac])); out.push_back(obs(resource, "radio", radio));
        out.push_back(obs(resource, "ssid", field(row, "ssid"))); out.push_back(obs(resource, "band", field(row, "band"))); out.push_back(obs(resource, "last_activity", field(row, "last-activity")));
        try { out.push_back(obs(resource, "signal", std::stod(field(row, "signal")), "dBm")); } catch (...) {}
      }
    }
  }
  if (d.value("class", "") == "network-switch") {
    const auto marker = text.find("SKYLAB_BRIDGE_HOSTS");
    if (marker != std::string::npos) {
      std::unordered_map<std::string, std::vector<std::string>> learned;
      std::istringstream rows(text.substr(marker)); std::string row;
      while (std::getline(rows, row)) {
        const auto mac = field(row, "mac-address"), port = field(row, "on-interface");
        const auto prefix = row.substr(0, row.find("mac-address="));
        if (!mac.empty() && !port.empty() && prefix.find('L') == std::string::npos) learned[port].push_back(mac);
      }
      auto& cache = network_identities(); std::lock_guard lock(cache.mutex);
      for (const auto& [port, macs] : learned) {
        const bool infrastructure = port.find("trunk") != std::string::npos || port.find("sfp") != std::string::npos ||
          port.find("vlan") != std::string::npos || port.find("bridge") != std::string::npos || port.find("tap") != std::string::npos;
        if (infrastructure || macs.size() != 1) continue;
        auto suffix = macs[0]; for (auto& c : suffix) if (c == ':') c = '-'; const auto resource = d["id"].get<std::string>() + "/client/" + suffix;
        out.push_back(obs(resource, "health", "learned")); out.push_back(obs(resource, "name", cache.name[macs[0]].empty() ? macs[0] : cache.name[macs[0]]));
        out.push_back(obs(resource, "mac_address", macs[0])); out.push_back(obs(resource, "address", cache.ip[macs[0]])); out.push_back(obs(resource, "physical_port", port));
      }
    }
  }
  const auto values = colon_values(text);
  if (auto it = values.find("uptime"); it != values.end()) {
    out.push_back(obs(d["id"], "uptime", routeros_duration_seconds(it->second), "s"));
    out.push_back(obs(d["id"], "uptime_source", it->second));
  }
  if (auto it = values.find("version"); it != values.end()) out.push_back(obs(d["id"], "routeros_version", it->second));
  if (auto it = values.find("board-name"); it != values.end()) out.push_back(obs(d["id"], "board", it->second));
  if (auto it = values.find("cpu-load"); it != values.end()) {
    auto value = it->second; if (!value.empty() && value.back() == '%') value.pop_back();
    try { out.push_back(obs(d["id"], "cpu_load", std::stod(value), "%")); } catch (...) {}
  }
  if (auto it = values.find("free-memory"); it != values.end()) out.push_back(obs(d["id"], "free_memory", it->second));
  std::istringstream lines(text); std::string line;
  while (std::getline(lines, line)) {
    const auto name = field(line, "name"), type = field(line, "type");
    if (line.rfind("RATE ", 0) == 0 && !name.empty()) {
      const auto resource = d["id"].get<std::string>() + "/port/" + name;
      try { out.push_back(obs(resource, "rx_rate", std::stod(field(line, "rx")), "bit/s")); } catch (...) {}
      try { out.push_back(obs(resource, "tx_rate", std::stod(field(line, "tx")), "bit/s")); } catch (...) {}
      continue;
    }
    if (line.rfind("PHY ", 0) == 0 && !name.empty()) {
      const auto resource = d["id"].get<std::string>() + "/port/" + name;
      const auto rate = field(line, "rate"); if (!rate.empty()) out.push_back(obs(resource, "line_rate", rate));
      const auto status = field(line, "status"); if (!status.empty()) out.push_back(obs(resource, "physical_status", status));
      continue;
    }
    if (name.empty() || type != "ether") continue;
    const auto prefix = line.substr(0, line.find("name="));
    const bool running_port = prefix.find('R') != std::string::npos;
    const auto resource = d["id"].get<std::string>() + "/port/" + name;
    out.push_back(obs(resource, "link", running_port));
    const auto downs = field(line, "link-downs");
    if (!downs.empty()) try { out.push_back(obs(resource, "link_downs", std::stoll(downs), "count")); } catch (...) {}
    const auto default_name = field(line, "default-name");
    if (!default_name.empty()) out.push_back(obs(resource, "physical_port", default_name));
  }
  return {"responding", "", std::move(out)};
}

PollResult posix_host(const nlohmann::json& d) {
  const auto address = host(d);
  if (!safe_host(address)) return ping(d);
  const auto alias = d.value("id", address);
  if (!safe_host(alias)) return ping(d);
  const auto config = d.value("config", nlohmann::json::object());
  const bool discover_zfs = config.value("discover_zfs", false);
  const bool discover_proxmox = config.value("discover_proxmox", false);
  const auto filesystem = config.value("filesystem_probe", nlohmann::json::object());
  const auto filesystem_path = filesystem.value("path", "");
  const bool probe_filesystem = !filesystem_path.empty() && safe_routeros_fragment(filesystem_path);
  std::string remote = "uptime; (cat /proc/uptime 2>/dev/null || true)";
  if (discover_zfs) remote += "; zpool list -Hp -o name,health,size,alloc,free; zpool status -P";
  if (probe_filesystem) remote += "; printf \"SKYLAB_FILESYSTEM \"; df -Pk " + filesystem_path + " 2>/dev/null | tail -1";
  const auto [code, text] = config.value("local", false)
    ? capture(remote + " 2>/dev/null")
    : capture("/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 " + alias + " '" + remote + "' 2>/dev/null");
  if (code != 0) {
    auto reachable = ping(d);
    if (reachable.health == "responding") {
      reachable.error = "SSH management unavailable";
      reachable.observations.push_back(obs(d["id"], "management_access", false));
      return reachable;
    }
    return {"unreachable", "host SSH and reachability failed", {obs(d["id"], "health", "unreachable")}};
  }
  const auto first_newline = text.find('\n'), second_newline = text.find('\n', first_newline == std::string::npos ? 0 : first_newline + 1);
  const auto uptime_text = text.substr(0, first_newline);
  std::vector<Observation> out{obs(d["id"], "health", "responding"), obs(d["id"], "management_access", true), obs(d["id"], "uptime_source", uptime_text)};
  if (first_newline != std::string::npos) try {
    out.push_back(obs(d["id"], "uptime", std::stod(text.substr(first_newline + 1, second_newline - first_newline - 1)), "s"));
  } catch (...) {}
  if (discover_zfs || probe_filesystem || discover_proxmox) {
    std::istringstream lines(text); std::string line;
    std::string current_pool, current_vdev;
    bool in_config = false;
    auto slug = [](std::string value) {
      const auto slash = value.find_last_of('/'); if (slash != std::string::npos) value = value.substr(slash + 1);
      std::string out; for (unsigned char c : value) {
        if (std::isalnum(c)) out += static_cast<char>(std::tolower(c));
        else if (out.empty() || out.back() != '-') out += '-';
      }
      while (!out.empty() && out.back() == '-') out.pop_back(); return out;
    };
    while (std::getline(lines, line)) {
      if (line.rfind("SKYLAB_FILESYSTEM ", 0) == 0) {
        std::istringstream row(line.substr(18)); std::string filesystem_name, percent_text, mounted; double blocks = 0, used = 0, available = 0;
        if (row >> filesystem_name >> blocks >> used >> available >> percent_text >> mounted) {
          double percent = 0; try { percent = std::stod(percent_text); } catch (...) {}
          const auto resource = d["id"].get<std::string>() + filesystem.value("resource_suffix", "/share/filesystem");
          out.push_back(obs(resource, "health", "responding")); out.push_back(obs(resource, "size", blocks * 1024.0, "B"));
          out.push_back(obs(resource, "allocated", used * 1024.0, "B")); out.push_back(obs(resource, "free", available * 1024.0, "B"));
          out.push_back(obs(resource, "used_percent", percent, "%")); out.push_back(obs(resource, "filesystem", filesystem.value("type", "unknown")));
        }
        continue;
      }
      std::istringstream columns(line); std::string pool, health, size, allocated, free;
      if (!line.empty() && !std::isspace(static_cast<unsigned char>(line.front())) &&
          columns >> pool >> health >> size >> allocated >> free &&
          (health == "ONLINE" || health == "DEGRADED" || health == "FAULTED")) {
        const auto resource = d["id"].get<std::string>() + "/pool/" + pool;
        try {
          const double capacity = std::stod(size), used = std::stod(allocated);
          out.push_back(obs(resource, "health", health)); out.push_back(obs(resource, "size", capacity, "B"));
          out.push_back(obs(resource, "allocated", used, "B")); out.push_back(obs(resource, "free", std::stod(free), "B"));
          out.push_back(obs(resource, "used_percent", capacity > 0 ? used / capacity * 100.0 : 0.0, "%"));
        } catch (...) {}
        continue;
      }
      auto trimmed = line; while (!trimmed.empty() && std::isspace(static_cast<unsigned char>(trimmed.front()))) trimmed.erase(trimmed.begin());
      if (trimmed.rfind("pool:", 0) == 0) { current_pool = trimmed.substr(5); while (!current_pool.empty() && current_pool.front() == ' ') current_pool.erase(current_pool.begin()); in_config = false; continue; }
      if (trimmed == "config:") { in_config = true; current_vdev.clear(); continue; }
      if (!in_config || current_pool.empty() || trimmed.empty() || trimmed.rfind("NAME", 0) == 0 || trimmed.rfind("errors:", 0) == 0) continue;
      std::istringstream status(trimmed); std::string name, state; long long read = 0, write = 0, checksum = 0;
      if (!(status >> name >> state >> read >> write >> checksum)) continue;
      if (name == current_pool) continue;
      const bool disk = name.rfind("/dev/", 0) == 0;
      if (!disk) current_vdev = slug(name);
      const auto pool_resource = d["id"].get<std::string>() + "/pool/" + current_pool;
      const auto resource = disk ? pool_resource + "/disk/" + slug(name) : pool_resource + "/vdev/" + current_vdev;
      out.push_back(obs(resource, "health", state)); out.push_back(obs(resource, "name", name));
      out.push_back(obs(resource, "read_errors", read, "count")); out.push_back(obs(resource, "write_errors", write, "count"));
      out.push_back(obs(resource, "checksum_errors", checksum, "count"));
      if (disk && !current_vdev.empty()) out.push_back(obs(resource, "vdev", current_vdev));
    }
    const std::string vm_command = "sudo -n /usr/local/sbin/skylab-proxmox-status";
    const auto [vm_code, vm_text] = discover_proxmox
      ? (config.value("local", false) ? capture(vm_command + " 2>/dev/null")
                                      : capture("/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 " + alias + " '" + vm_command + "' 2>/dev/null"))
      : std::pair<int, std::string>{-1, ""};
    if (vm_code == 0) try {
      const auto resources = nlohmann::json::parse(vm_text);
      for (const auto& vm : resources) {
        const auto vmid = vm.value("vmid", 0);
        if (vmid <= 0) continue;
        const auto resource = d["id"].get<std::string>() + "/vm/" + std::to_string(vmid);
        out.push_back(obs(resource, "name", vm.value("name", "vm-" + std::to_string(vmid))));
        out.push_back(obs(resource, "type", vm.value("type", "unknown")));
        out.push_back(obs(resource, "node", vm.value("node", "")));
        out.push_back(obs(resource, "status", vm.value("status", "unknown")));
        out.push_back(obs(resource, "uptime", vm.value("uptime", 0.0), "s"));
        out.push_back(obs(resource, "cpu_fraction", vm.value("cpu", 0.0), "ratio"));
        out.push_back(obs(resource, "memory_used", vm.value("mem", 0.0), "B"));
        out.push_back(obs(resource, "memory_capacity", vm.value("maxmem", 0.0), "B"));
        out.push_back(obs(resource, "disk_used", vm.value("disk", 0.0), "B"));
        out.push_back(obs(resource, "disk_capacity", vm.value("maxdisk", 0.0), "B"));
      }
    } catch (...) {
      auto invalid = obs(d["id"], "proxmox_status", "invalid-response");
      invalid.quality = "invalid"; out.push_back(std::move(invalid));
    }
  }
  return {"responding", "", std::move(out)};
}

PollResult envoy(const nlohmann::json& d, const SecretStore& secrets) {
  const auto address = host(d), token = secret(d, "cred", secrets);
  if (!safe_host(address)) return {"unknown", "invalid Envoy endpoint", {}};
  if (!safe_secret(token)) return {"degraded", "Envoy token is not configured or contains unsupported bootstrap characters", {obs(d["id"], "health", "degraded")}};
  const auto [code, text] = capture("/usr/bin/curl -kfsS --max-time 8 -H 'Authorization: Bearer " + token + "' 'https://" + address + "/production.json' 2>/dev/null");
  if (code != 0) return {"unreachable", "Envoy request failed", {obs(d["id"], "health", "unreachable")}};
  try {
    const auto data = nlohmann::json::parse(text);
    const auto production = data.value("production", nlohmann::json::array());
    const auto consumption = data.value("consumption", nlohmann::json::array());
    if (production.empty()) throw std::runtime_error("missing production");
    std::vector<Observation> out{obs(d["id"], "health", "responding")};
    out.push_back(obs(d["id"], "production_power", production[0].value("wNow", 0.0), "W"));
    out.push_back(obs(d["id"], "lifetime_energy", production[0].value("whLifetime", 0.0), "Wh"));
    out.push_back(obs(d["id"], "active_inverters", production[0].value("activeCount", 0), "count"));
    if (!consumption.empty()) out.push_back(obs(d["id"], "consumption_power", consumption[0].value("wNow", 0.0), "W"));
    return {"responding", "", std::move(out)};
  } catch (...) { return {"degraded", "invalid Envoy response", {obs(d["id"], "health", "degraded")}}; }
}

PollResult powerwall(const nlohmann::json& d, const SecretStore& secrets) {
  const auto address = host(d), password = secret(d, "password_cred", secrets);
  if (!safe_host(address)) return {"unknown", "invalid Powerwall endpoint", {}};
  if (!safe_secret(password)) return {"degraded", "Powerwall password is not configured or contains unsupported bootstrap characters", {obs(d["id"], "health", "degraded")}};
  const std::string login_body = "{\"username\":\"customer\",\"password\":\"" + password + "\",\"email\":\"\",\"force_sm_off\":false}";
  const auto [login_code, login_text] = capture("/usr/bin/curl -kfsS --max-time 10 -H 'Content-Type: application/json' --data '" + login_body + "' 'https://" + address + "/api/login/Basic' 2>/dev/null");
  if (login_code != 0) return {"unreachable", "Powerwall login failed", {obs(d["id"], "health", "unreachable")}};
  try {
    const auto token = nlohmann::json::parse(login_text).value("token", "");
    if (!safe_secret(token)) throw std::runtime_error("invalid token");
    auto get = [&](const char* endpoint) {
      const auto [code, text] = capture("/usr/bin/curl -kfsS --max-time 8 -H 'Authorization: Bearer " + token + "' 'https://" + address + endpoint + "' 2>/dev/null");
      if (code != 0) throw std::runtime_error("Powerwall endpoint failed");
      return nlohmann::json::parse(text);
    };
    const auto meters = get("/api/meters/aggregates"), status = get("/api/system_status"), operation = get("/api/operation");
    const double remaining = status.value("nominal_energy_remaining", 0.0), full = status.value("nominal_full_pack_energy", 0.0);
    std::vector<Observation> out{obs(d["id"], "health", "responding")};
    out.push_back(obs(d["id"], "state_of_charge", full > 0 ? remaining / full * 100.0 : 0.0, "%"));
    out.push_back(obs(d["id"], "energy_remaining", remaining, "Wh"));
    out.push_back(obs(d["id"], "solar_power", meters.value("solar", nlohmann::json::object()).value("instant_power", 0.0), "W"));
    out.push_back(obs(d["id"], "load_power", meters.value("load", nlohmann::json::object()).value("instant_power", 0.0), "W"));
    out.push_back(obs(d["id"], "battery_power", meters.value("battery", nlohmann::json::object()).value("instant_power", 0.0), "W"));
    out.push_back(obs(d["id"], "grid_power", meters.value("site", nlohmann::json::object()).value("instant_power", 0.0), "W"));
    out.push_back(obs(d["id"], "grid_connected", status.value("system_island_state", "") == "SystemGridConnected"));
    out.push_back(obs(d["id"], "mode", operation.value("real_mode", "unknown")));
    out.push_back(obs(d["id"], "backup_reserve", operation.value("backup_reserve_percent", 0.0), "%"));
    return {"responding", "", std::move(out)};
  } catch (const std::exception& e) { return {"degraded", e.what(), {obs(d["id"], "health", "degraded")}}; }
}
}

AdapterRegistry::AdapterRegistry(const std::string& secrets_file) {
  if (!secrets_file.empty()) secrets_.load(secrets_file);
}

PollResult AdapterRegistry::poll(const nlohmann::json& device) const {
  if (!device.value("enabled", true)) return {"disabled", "", {obs(device["id"], "health", "disabled")}};
  const auto adapter = device.value("adapter", "");
  if (adapter == "demo.static") return demo_static(device);
  if (adapter.rfind("shelly.", 0) == 0) return shelly(device);
  if (adapter == "venstar.local") return venstar(device);
  if (adapter == "nut.ssh") return nut(device);
  if (adapter == "mikrotik.routeros") return mikrotik(device);
  if (adapter == "posix.ssh") return posix_host(device);
  if (adapter == "enphase.envoy") return envoy(device, secrets_);
  if (adapter == "tesla.powerwall") return powerwall(device, secrets_);
  if (adapter == "envisalink.tpi") return envisalink(device, secrets_);
  if (adapter == "dyson.mqtt") return poll_dyson(device, secrets_);
  if (adapter == "site.ephemeris") return poll_ephemeris(device);
  if (adapter == "meshtastic.tcp") return poll_meshtastic(device);
  return ping(device);
}

nlohmann::json AdapterRegistry::describe(const nlohmann::json& device) const {
  nlohmann::json actions = nlohmann::json::array();
  const auto adapter = device.value("adapter", "");
  if (adapter.rfind("shelly.", 0) == 0) {
    actions.push_back({{"id", "power.on"}, {"role", "operator"}, {"widget", "button"}});
    actions.push_back({{"id", "power.off"}, {"role", "operator"}, {"widget", "button"}});
    if (adapter == "shelly.plus-wd" || adapter == "shelly.dimmer2")
      actions.push_back({{"id", "brightness.set"}, {"role", "operator"}, {"widget", "slider"}, {"minimum", 0}, {"maximum", 100}});
  } else if (adapter == "venstar.local") {
    actions.push_back({{"id", "thermostat.setpoints.set"}, {"role", "operator"}, {"widget", "temperature"}});
    actions.push_back({{"id", "thermostat.mode.set"}, {"role", "operator"}, {"widget", "mode"}});
    actions.push_back({{"id", "thermostat.fan.set"}, {"role", "operator"}, {"widget", "mode"}});
  } else if (adapter == "tapo.rtsp") {
    actions.push_back({{"id", "camera.view"}, {"role", "viewer"}, {"widget", "embedded-rtsp"}});
  } else if (adapter == "envisalink.tpi") {
    actions.push_back({{"id", "alarm.arm_stay"}, {"role", "operator"}, {"widget", "confirm-button"}});
    actions.push_back({{"id", "alarm.arm_away"}, {"role", "operator"}, {"widget", "confirm-button"}});
    actions.push_back({{"id", "alarm.disarm"}, {"role", "operator"}, {"widget", "confirm-button"}});
  } else if (adapter == "dyson.mqtt" && device.value("class", "") == "air-purifier") {
    actions.push_back({{"id", "power.on"}, {"role", "operator"}, {"widget", "button"}});
    actions.push_back({{"id", "power.off"}, {"role", "operator"}, {"widget", "button"}});
    actions.push_back({{"id", "dyson.fan_speed.set"}, {"role", "operator"}, {"widget", "slider"}, {"minimum", 1}, {"maximum", 10}});
    actions.push_back({{"id", "dyson.auto.set"}, {"role", "operator"}, {"widget", "toggle"}});
    actions.push_back({{"id", "dyson.night.set"}, {"role", "operator"}, {"widget", "toggle"}});
    actions.push_back({{"id", "dyson.oscillation.set"}, {"role", "operator"}, {"widget", "toggle"}});
  } else if (adapter == "dyson.mqtt" && device.value("class", "") == "robot-vacuum") {
    actions.push_back({{"id", "vacuum.start"}, {"role", "operator"}, {"widget", "confirm-button"}});
    actions.push_back({{"id", "vacuum.pause"}, {"role", "operator"}, {"widget", "button"}});
    actions.push_back({{"id", "vacuum.resume"}, {"role", "operator"}, {"widget", "button"}});
    actions.push_back({{"id", "vacuum.return_to_dock"}, {"role", "operator"}, {"widget", "confirm-button"}});
  }
  return {{"id", device["id"]}, {"class", device["class"]}, {"adapter", adapter},
          {"pretty_name", device["pretty_name"]}, {"comment", device["comment"]},
          {"asset_tag", device.value("asset_tag", "")}, {"notes", device.value("notes", "")},
          {"photo_available", device.value("photo", nlohmann::json::object()).contains("filename")},
          {"room", device.value("room", "")},
          {"groups", device.value("groups", nlohmann::json::array())},
          {"roles", device.value("roles", nlohmann::json::array())},
          {"lifecycle", device.value("lifecycle", "active")},
          {"importance", device.value("importance", "normal")},
          {"presentation_home", device.value("presentation_home", "inventory")},
          {"parent", device.value("parent", "")},
          {"address", host(device)},
          {"actions", actions}, {"presentation", {{"group", device["class"]}, {"widget", device["class"]}}}};
}

nlohmann::json AdapterRegistry::camera_stream(const nlohmann::json& device) const {
  if (device.value("adapter", "") != "tapo.rtsp" || device.value("class", "") != "camera")
    throw std::runtime_error("resource does not provide an RTSP stream");
  const auto address = host(device);
  if (!safe_host(address)) throw std::runtime_error("invalid camera endpoint");
  const auto username = secret(device, "username", secrets_);
  const auto password = secret(device, "password", secrets_);
  if (username.empty() || password.empty()) throw std::runtime_error("camera credentials unavailable");
  const auto port = device["endpoints"][0].value("port", 554);
  const auto path = device.value("config", nlohmann::json::object()).value("rtsp_path", "/stream1");
  if (path.empty() || path.front() != '/' || path.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~/-") != std::string::npos)
    throw std::runtime_error("invalid camera stream path");
  const auto url = "rtsp://" + url_component(username) + ":" + url_component(password) + "@" + address + ":" + std::to_string(port) + path;
  return {{"resource", device.value("id", "")}, {"scheme", "rtsp"}, {"url", url}};
}

nlohmann::json AdapterRegistry::storage_files(const nlohmann::json& device, std::string_view resource,
                                               std::size_t limit) const {
  const auto config = device.value("config", nlohmann::json::object());
  const auto configured_resource = config.value("backup_share_resource", "");
  const auto slot = config.value("backup_disk_slot", "usb1");
  const auto path = config.value("backup_file_root", slot + "/");
  if (configured_resource.empty() || resource != configured_resource || !safe_routeros_fragment(slot) || !safe_routeros_fragment(path))
    throw std::runtime_error("resource does not provide a file listing");
  const auto address = host(device), user = device["config"].value("ssh_user", "");
  const bool uses_ssh_alias = device.value("class", "") == "router";
  const auto target = uses_ssh_alias ? device.value("id", address) : user + "@" + address;
  if (!safe_host(address) || !safe_host(target) || (!uses_ssh_alias && !safe_ssh_user(user)))
    throw std::runtime_error("invalid RouterOS endpoint or SSH configuration");
  const auto remote = std::string("/disk print terse without-paging where slot=\"") + slot + "\"; :put \"SKYLAB_FILES\"; /file print terse without-paging where name~\"" + path + "\"";
  const auto [code, text] = capture("/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=15 " + target + " '" + remote + "' 2>/dev/null");
  if (code != 0) throw std::runtime_error("RouterOS file listing unavailable");
  const auto marker = text.find("SKYLAB_FILES");
  if (marker == std::string::npos) throw std::runtime_error("RouterOS file listing was malformed");
  const auto disk = text.substr(0, marker);
  if (field(disk, "mount-point").empty())
    return {{"resource", resource}, {"available", false}, {"message", "Backup disk is not mounted"}, {"files", nlohmann::json::array()}};
  nlohmann::json files = nlohmann::json::array(); std::istringstream rows(text.substr(marker)); std::string row;
  while (std::getline(rows, row)) {
    const auto name_at = row.find("name="), type_at = row.find(" type=", name_at), modified_at = row.find(" last-modified=", type_at);
    if (name_at == std::string::npos || type_at == std::string::npos || modified_at == std::string::npos) continue;
    const auto path = row.substr(name_at + 5, type_at - name_at - 5);
    const auto type = row.substr(type_at + 6, row.find(' ', type_at + 6) - type_at - 6);
    if (path == slot || type == "directory" || type == "disk") continue;
    const auto size_at = row.find(" size=", type_at); auto modified = row.substr(modified_at + 15);
    while (!modified.empty() && (modified.back() == '\r' || modified.back() == ' ')) modified.pop_back();
    const auto modified_ms = routeros_local_time_ms(modified);
    nlohmann::json file{{"path", path}, {"name", path.rfind('/') == std::string::npos ? path : path.substr(path.rfind('/') + 1)},
                        {"modified", modified}, {"modified_at_ms", modified_ms}, {"age", display_age(modified_ms)}};
    if (size_at != std::string::npos && size_at < modified_at) {
      const auto size = row.substr(size_at + 6, modified_at - size_at - 6);
      try { const auto bytes = routeros_size_bytes(size); file["size_bytes"] = bytes; file["display_size"] = display_bytes(bytes); }
      catch (...) { file["display_size"] = size; }
    }
    files.push_back(std::move(file));
  }
  std::stable_sort(files.begin(), files.end(), [](const auto& a, const auto& b) { return a.value("modified_at_ms", 0LL) > b.value("modified_at_ms", 0LL); });
  if (files.size() > limit) files.erase(files.begin() + static_cast<nlohmann::json::difference_type>(limit), files.end());
  return {{"resource", resource}, {"available", true}, {"message", ""}, {"files", std::move(files)}};
}

nlohmann::json AdapterRegistry::invoke(const nlohmann::json& device, std::string_view action,
                                       const nlohmann::json& parameters) const {
  const auto adapter = device.value("adapter", ""), address = host(device);
  if (!safe_host(address)) return {{"ok", false}, {"error", "invalid endpoint"}};
  const auto before = poll(device);
  if (adapter == "dyson.mqtt") return invoke_dyson(device, secrets_, action, parameters);
  if (adapter.rfind("shelly.", 0) == 0) {
    bool on = action == "power.on";
    if (action == "brightness.set") {
      const int brightness = integer_parameter(parameters, "brightness", -1);
      if (brightness < 0 || brightness > 100) return {{"ok", false}, {"error", "brightness must be 0..100"}};
    } else if (action != "power.on" && action != "power.off") return {{"ok", false}, {"error", "unsupported action"}};
    std::string url, body;
    if (adapter == "shelly.plus-wd") {
      url = "http://" + address + "/rpc";
      body = "{\"id\":0,\"method\":\"Light.Set\",\"params\":{\"id\":0";
    } else if (adapter == "shelly.dimmer2") {
      url = "http://" + address + "/light/0?turn=" + std::string(action == "brightness.set" || on ? "on" : "off");
      if (action == "brightness.set") url += "&brightness=" + std::to_string(integer_parameter(parameters, "brightness", 0));
    } else if (adapter == "shelly.plug-us-g4") {
      url = "http://" + address + "/rpc/Switch.Set";
      body = "{\"id\":0";
    } else {
      url = "http://" + address + "/rpc";
      body = "{\"id\":0,\"method\":\"Switch.Set\",\"params\":{\"id\":0";
    }
    if (adapter != "shelly.dimmer2" && (action == "power.on" || action == "power.off")) body += ",\"on\":" + std::string(on ? "true" : "false");
    else if (action == "brightness.set") {
      const int brightness = integer_parameter(parameters, "brightness", -1);
      if (adapter != "shelly.dimmer2") body += ",\"brightness\":" + std::to_string(brightness);
    }
    if (adapter != "shelly.dimmer2") body += adapter == "shelly.plug-us-g4" ? "}" : "}}";
    const auto command = adapter == "shelly.dimmer2"
      ? "/usr/bin/curl -fsS --max-time 5 '" + url + "' 2>/dev/null"
      : "/usr/bin/curl -fsS --max-time 5 -H 'Content-Type: application/json' -X POST --data '" + body + "' '" + url + "' 2>/dev/null";
    const auto [code, output] = capture(command);
    (void)output;
    if (code != 0) return {{"ok", false}, {"error", "Shelly control request failed"}};
    const auto after = poll(device);
    bool verified = after.health == "responding";
    if (action == "power.on" || action == "power.off") {
      for (const auto& o : after.observations) if (o.metric == "power") verified = verified && o.value == on;
    }
    return {{"ok", verified}, {"verified", verified}, {"before_health", before.health}, {"after_health", after.health}};
  }
  if (adapter == "venstar.local" && (action == "thermostat.setpoints.set" || action == "thermostat.mode.set" || action == "thermostat.fan.set")) {
    std::ostringstream form;
    bool first = true;
    for (const auto& [key, field] : std::vector<std::pair<std::string,std::string>>{{"mode","mode"},{"fan","fan"},{"heat","heattemp"},{"cool","cooltemp"}}) {
      if (!parameters.contains(key)) continue;
      if (key == "mode" && parameters[key].is_string()) {
        const auto name = parameters[key].get<std::string>();
        const std::unordered_map<std::string, int> modes{{"off",0},{"heat",1},{"cool",2},{"auto",3}};
        if (!modes.contains(name)) return {{"ok", false}, {"error", "mode must be off, heat, cool, or auto"}};
        form << (first ? "" : "&") << field << '=' << modes.at(name);
      } else if (key == "fan" && parameters[key].is_string()) {
        const auto name = parameters[key].get<std::string>();
        const std::unordered_map<std::string, int> fan_modes{{"auto",0},{"on",1}};
        if (!fan_modes.contains(name)) return {{"ok", false}, {"error", "fan must be auto or on"}};
        form << (first ? "" : "&") << field << '=' << fan_modes.at(name);
      } else {
        const int value = integer_parameter(parameters, key.c_str(), -1000);
        if (value == -1000) return {{"ok", false}, {"error", key + " must be numeric"}};
        form << (first ? "" : "&") << field << '=' << value;
      }
      first = false;
    }
    if (first) return {{"ok", false}, {"error", "mode, fan, heat, or cool is required"}};
    const auto [code, output] = capture("/usr/bin/curl -fsS --max-time 5 -X POST --data '" + form.str() + "' 'http://" + address + "/control' 2>/dev/null");
    (void)output;
    const auto after = poll(device);
    bool verified = code == 0 && after.health == "responding";
    if (action == "thermostat.mode.set" && parameters.contains("mode") && parameters["mode"].is_string()) {
      const auto requested = parameters["mode"].get<std::string>();
      bool observed = false;
      for (const auto& observation : after.observations) {
        if (observation.metric == "mode" && observation.value.is_string()) {
          observed = true;
          verified = verified && observation.value.get<std::string>() == requested;
        }
      }
      verified = verified && observed;
    }
    if (action == "thermostat.fan.set" && parameters.contains("fan") && parameters["fan"].is_string()) {
      const auto requested = parameters["fan"].get<std::string>();
      bool observed = false;
      for (const auto& observation : after.observations) {
        if (observation.metric == "fan_mode" && observation.value.is_string()) {
          observed = true;
          verified = verified && observation.value.get<std::string>() == requested;
        }
      }
      verified = verified && observed;
    }
    if (action == "thermostat.setpoints.set") {
      for (const auto& [parameter, metric] : std::vector<std::pair<std::string, std::string>>{{"heat", "heat_setpoint"}, {"cool", "cool_setpoint"}}) {
        if (!parameters.contains(parameter)) continue;
        const int requested = integer_parameter(parameters, parameter.c_str(), -1000);
        bool observed = false;
        for (const auto& observation : after.observations) {
          if (observation.metric == metric && observation.value.is_number()) {
            observed = true;
            verified = verified && std::abs(observation.value.get<double>() - requested) < 0.1;
          }
        }
        verified = verified && observed;
      }
    }
    return {{"ok", verified}, {"verified", verified}, {"before_health", before.health}, {"after_health", after.health}};
  }
  if (adapter == "envisalink.tpi") {
    if (action != "alarm.arm_stay" && action != "alarm.arm_away" && action != "alarm.disarm")
      return {{"ok", false}, {"error", "unsupported alarm action"}};
    const auto password = secret(device, "password", secrets_), code = secret(device, "user_code", secrets_);
    if (password.empty() || code.empty()) return {{"ok", false}, {"error", "alarm credentials unavailable"}};
    auto& session = alarm_session(); std::lock_guard lock(session.mutex); std::string error;
    if (!session.connect_to(address, password, error)) return {{"ok", false}, {"error", error}};
    auto wait_for = [&](auto predicate, int milliseconds) {
      const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(milliseconds);
      while (std::chrono::steady_clock::now() < deadline) { session.drain(400); if (predicate(session.state)) return true; }
      return predicate(session.state);
    };
    const bool hazardous = session.state.value("fire", false) || session.state.value("alarm", false) || session.state.value("trouble", false);
    if (action != "alarm.disarm" && hazardous) return {{"ok", false}, {"error", "panel has an active alarm or trouble; arming refused"}};
    const int bypass_zone = device.value("config", nlohmann::json::object()).value("mandatory_bypass_zone", 0);
    std::ostringstream zone; zone << std::setw(2) << std::setfill('0') << bypass_zone;
    auto ensure_bypass = [&]() {
      if (bypass_zone <= 0) return true;
      if (session.state.value("bypass", false)) return true;
      if (!session.write_line(code + "6" + zone.str())) return false;
      return wait_for([](const auto& state) { return state.value("bypass", false); }, 6000);
    };
    if (action == "alarm.disarm") {
      if (!session.write_line(code + "1")) return {{"ok", false}, {"error", "TPI write failed"}};
      session.drain(1000);
      const bool disarmed = wait_for([](const auto& state) { return !state.value("armed", true) && state.value("partition_mode", "") != "alarm"; }, 8000);
      if (!disarmed) return {{"ok", false}, {"verified", false}, {"error", "panel did not confirm disarmed"}};
      // A Vista panel may clear bypasses as disarm completes. Let the final keypad
      // update settle, then restore the configured bypass only when it is absent.
      session.drain(1500);
      const bool bypassed = ensure_bypass();
      return {{"ok", bypassed}, {"verified", bypassed}, {"transition", "disarmed-ready"},
              {"bypass_zone", bypass_zone}, {"bypass_confirmed", bypassed},
              {"error", bypassed ? "" : "disarmed, but zone bypass was not confirmed"}};
    }
    if (!ensure_bypass()) return {{"ok", false}, {"verified", false}, {"error", "zone bypass was not confirmed; arming cancelled"}};
    const bool stay = action == "alarm.arm_stay";
    if (!session.write_line(code + (stay ? "3" : "2"))) return {{"ok", false}, {"error", "TPI arm write failed"}};
    const bool verified = wait_for([stay](const auto& state) {
      const auto mode = state.value("partition_mode", "");
      return stay ? mode == "armed-stay" || mode == "zero-entry-stay" : mode == "armed-away" || mode == "zero-entry-away";
    }, 70000);
    return {{"ok", verified}, {"verified", verified}, {"bypass_zone", bypass_zone},
            {"transition", stay ? "armed-stay" : "armed-away"}, {"error", verified ? "" : "panel did not confirm armed state"}};
  }
  return {{"ok", false}, {"error", "resource is read-only in V1"}};
}

}  // namespace skylab
