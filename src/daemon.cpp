// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/adapters.hpp"
#include "skylab/auth.hpp"
#include "skylab/inventory.hpp"
#include "skylab/skywire.hpp"
#include "skylab/telemetry.hpp"
#include "skylab/presentation.hpp"

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstring>
#include <iostream>
#include <mutex>
#include <memory>
#include <set>
#include <thread>
#include <unordered_map>
#include <functional>
#include <filesystem>
#include <fstream>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>

using skylab::wire::Message;

namespace {
std::atomic_bool running{true};
std::atomic_int listener_socket{-1};

void stop(int) {
  running = false;
  const int socket = listener_socket.exchange(-1);
  if (socket >= 0) ::close(socket);
}

std::unordered_map<std::string, std::string> arguments(const Message& request) {
  std::unordered_map<std::string, std::string> result;
  for (std::size_t i = 3; i + 1 < request.size(); i += 2) result[request[i]] = request[i + 1];
  return result;
}
std::string raw(const std::string& typed) { return typed.empty() ? "" : typed.substr(1); }

std::string now_utc() {
  const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
  std::tm tm{}; gmtime_r(&now, &tm); char text[32];
  std::strftime(text, sizeof(text), "%Y-%m-%dT%H:%M:%SZ", &tm); return text;
}

std::string asset_filename(std::string_view resource, std::string_view mime, std::uint64_t revision) {
  static constexpr char digits[] = "0123456789abcdef";
  static std::atomic_uint64_t nonce{0};
  std::string result; result.reserve(resource.size() * 2 + 4);
  for (const unsigned char c : resource) { result += digits[c >> 4]; result += digits[c & 15]; }
  return result + "-" + std::to_string(revision) + "-" + std::to_string(nonce.fetch_add(1)) +
         (mime == "image/png" ? ".png" : ".jpg");
}

std::string base64_encode(std::string_view input) {
  static constexpr char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out; out.reserve((input.size() + 2) / 3 * 4);
  for (std::size_t i = 0; i < input.size(); i += 3) {
    const auto a = static_cast<unsigned char>(input[i]);
    const auto b = i + 1 < input.size() ? static_cast<unsigned char>(input[i + 1]) : 0;
    const auto c = i + 2 < input.size() ? static_cast<unsigned char>(input[i + 2]) : 0;
    out += table[a >> 2]; out += table[((a & 3) << 4) | (b >> 4)];
    out += i + 1 < input.size() ? table[((b & 15) << 2) | (c >> 6)] : '=';
    out += i + 2 < input.size() ? table[c & 63] : '=';
  }
  return out;
}

std::string base64_decode(std::string_view input) {
  auto value = [](unsigned char c) -> int {
    if (c >= 'A' && c <= 'Z') return c - 'A'; if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52; if (c == '+') return 62; if (c == '/') return 63; return -1;
  };
  if (input.empty() || input.size() % 4 != 0) throw std::runtime_error("invalid photo encoding");
  std::string out; out.reserve(input.size() / 4 * 3);
  for (std::size_t i = 0; i < input.size(); i += 4) {
    const int a = value(input[i]), b = value(input[i + 1]);
    const int c = input[i + 2] == '=' ? -2 : value(input[i + 2]);
    const int d = input[i + 3] == '=' ? -2 : value(input[i + 3]);
    if (a < 0 || b < 0 || c == -1 || d == -1 || (c == -2 && d != -2)) throw std::runtime_error("invalid photo encoding");
    out += static_cast<char>((a << 2) | (b >> 4));
    if (c >= 0) out += static_cast<char>(((b & 15) << 4) | (c >> 2));
    if (d >= 0) out += static_cast<char>(((c & 3) << 6) | d);
  }
  return out;
}

bool send_all(int socket, std::string_view bytes) {
  while (!bytes.empty()) {
    const auto count = ::send(socket, bytes.data(), bytes.size(), 0);
    if (count <= 0) return false;
    bytes.remove_prefix(static_cast<std::size_t>(count));
  }
  return true;
}

Message ok(std::string id, std::string record, const nlohmann::json& value) {
  return {"R", std::move(id), "OK", std::move(record), "json", skylab::wire::typed_string(value.dump())};
}
Message error(std::string id, std::string code, std::string message) {
  return {"R", std::move(id), "ERR", std::move(code), "b0", std::move(message)};
}

class Service {
 public:
  Service(std::string inventory, std::string database, std::string token, std::string auth_file,
          std::string secrets_file, std::string views_file)
      : inventory_(std::move(inventory)), assets_dir_(std::filesystem::path(database).parent_path() / "assets"),
        telemetry_(std::move(database)), adapters_(secrets_file), presentation_(views_file), token_(std::move(token)) {
    if (!auth_file.empty()) auth_ = std::make_unique<skylab::AuthStore>(std::move(auth_file));
    std::filesystem::create_directories(assets_dir_);
    std::filesystem::permissions(assets_dir_, std::filesystem::perms::owner_all);
  }

  void start_polling() {
    auto lane = [this](std::function<bool(const nlohmann::json&)> includes, int interval, int workers) {
      pollers_.emplace_back([this, includes = std::move(includes), interval, workers] {
      while (running) {
        std::vector<nlohmann::json> selected;
        for (const auto& device : inventory_.devices()) if (includes(device)) selected.push_back(device);
        std::atomic_size_t next{0}; std::vector<std::thread> pool;
        for (int worker = 0; worker < workers; ++worker) pool.emplace_back([&, this] {
          while (running) {
            const auto index = next.fetch_add(1); if (index >= selected.size()) break;
            const auto& device = selected[index];
            try {
              const auto result = adapters_.poll(device);
              if (!result.error.empty()) log_poll_error(device.value("id", "?"), result.error);
              for (const auto& observation : result.observations) telemetry_.record(observation);
            } catch (const std::exception& e) { log_poll_error(device.value("id", "?"), e.what()); }
          }
        });
        for (auto& worker : pool) worker.join();
        for (int i = 0; i < interval && running; ++i) std::this_thread::sleep_for(std::chrono::seconds(1));
      }
      });
    };
    auto adapter = [](const nlohmann::json& d) { return d.value("adapter", ""); };
    lane([adapter](const auto& d) { const auto a = adapter(d); return a.rfind("shelly.", 0) == 0 || a == "venstar.local"; }, 5, 8);
    lane([adapter](const auto& d) { const auto a = adapter(d); return a == "tesla.powerwall" || a == "enphase.envoy" || a == "nut.ssh" || a == "mikrotik.routeros" || a == "posix.ssh"; }, 30, 8);
    lane([adapter](const auto& d) { const auto a = adapter(d); return !(a.rfind("shelly.", 0) == 0 || a == "venstar.local" || a == "tesla.powerwall" || a == "enphase.envoy" || a == "nut.ssh" || a == "mikrotik.routeros" || a == "posix.ssh"); }, 60, 10);
  }
  // A persistently failing device otherwise writes its poll error every lane cycle
  // forever; the error log reached 336 MB of repeats. Report each resource at most
  // once per interval, summarizing how many repeats were suppressed.
  void log_poll_error(const std::string& id, const std::string& message) {
    std::lock_guard lock(error_log_mutex_);
    const auto now = std::chrono::steady_clock::now();
    auto& entry = poll_error_state_[id];
    const auto since = now - entry.last_logged;
    if (since < std::chrono::minutes(10)) { ++entry.suppressed; return; }
    if (entry.suppressed > 0)
      std::cerr << "poll " << id << ": " << message << " (unchanged; " << entry.suppressed << " repeats suppressed)\n";
    else
      std::cerr << "poll " << id << ": " << message << "\n";
    entry.last_logged = now;
    entry.suppressed = 0;
  }
  struct PollErrorState {
    std::chrono::steady_clock::time_point last_logged{};
    std::uint64_t suppressed{0};
  };
  std::mutex error_log_mutex_;
  std::unordered_map<std::string, PollErrorState> poll_error_state_;
  ~Service() { for (auto& poller : pollers_) if (poller.joinable()) poller.join(); }

  Message handle(const Message& q, std::optional<skylab::Identity>& identity) {
    if (q.size() < 3 || q[0] != "Q") return error("0", "bad_request", "expected request tokens");
    const auto id = q[1], command = q[2];
    const auto args = arguments(q);
    if (command == "PING") return ok(id, "pong", {{"version", SKYL_VERSION}});
    if (command == "AUTH") {
      auto token = args.find("token"), client = args.find("client");
      // A malformed auth file is a failed login, never a daemon crash. reload()
      // no longer throws, but guard anyway so a future regression here cannot
      // terminate the process from a client connection thread.
      if (token != args.end() && client != args.end()) {
        try {
          if (auth_) { auth_->reload(); identity = auth_->authenticate(raw(client->second), raw(token->second)); }
          else if (raw(token->second) == token_) identity = skylab::Identity{raw(client->second), "admin"};
        } catch (const std::exception& e) {
          std::cerr << "AUTH: reload failed, treating as unauthenticated: " << e.what() << "\n";
        }
      }
      return identity ? ok(id, "auth", {{"client", identity->client}, {"role", identity->role}})
                      : error(id, "unauthenticated", "invalid credentials");
    }
    if (!identity) return error(id, "unauthenticated", "AUTH required");
    if (command == "SERVICE.DESCRIBE") {
      const auto inventory = inventory_.snapshot();
      const auto configured_site = inventory.value("site", nlohmann::json::object());
      const nlohmann::json site{{"id", configured_site.value("id", "site")},
                                {"pretty_name", configured_site.value("pretty_name", "Habitat")},
                                {"subtitle", configured_site.value("subtitle", "Local-first habitat console")},
                                {"timezone", configured_site.value("timezone", "UTC")}};
      return ok(id, "service", {{"name", "skyhabd"}, {"version", SKYL_VERSION}, {"protocol", "SkyWire/1.0"},
                                 {"inventory_revision", inventory_.revision()}, {"site", site},
                                 {"presentation_schema", "skylab.presentation/1"}, {"view_revision", presentation_.revision()}});
    }
    if (command == "VIEW.LIST") return ok(id, "views", presentation_.list());
    if (command == "VIEW.DESCRIBE") {
      try { return ok(id, "view", presentation_.describe(raw(args.at("id")))); }
      catch (const std::exception& e) { return error(id, "not_found", e.what()); }
    }
    if (command == "RESOURCE.LIST") {
      nlohmann::json values = nlohmann::json::array();
      const auto inventory = inventory_.snapshot();
      const auto current_state = telemetry_.current();
      std::set<std::string> known;
      std::set<std::string> hidden;
      for (const auto& d : inventory["devices"])
        for (const auto& resource : d.value("config", nlohmann::json::object()).value("hidden_resources", nlohmann::json::array()))
          if (resource.is_string()) hidden.insert(resource.get<std::string>());
      for (const auto& d : inventory_.devices()) { values.push_back(adapters_.describe(d)); known.insert(d.value("id", "")); }
      for (const auto& row : current_state) {
        const auto resource = row.value("resource", "");
        if (resource.empty() || hidden.contains(resource) || !known.insert(resource).second) continue;
        const auto port = resource.find("/port/"), client = resource.find("/client/"), pool = resource.find("/pool/"), vm = resource.find("/vm/"), disk = resource.find("/disk/"), vdev = resource.find("/vdev/"), share = resource.find("/share/");
        std::string klass, parent, name = resource;
        if (port != std::string::npos) { klass = "network-port"; parent = resource.substr(0, port); name = resource.substr(port + 6); }
        else if (client != std::string::npos) { klass = "network-client"; parent = resource.substr(0, client); name = resource.substr(client + 8); }
        else if (disk != std::string::npos) { klass = "storage-disk"; parent = resource.substr(0, disk); name = resource.substr(disk + 6); }
        else if (vdev != std::string::npos) { klass = "storage-vdev"; parent = resource.substr(0, vdev); name = resource.substr(vdev + 6); }
        else if (pool != std::string::npos) { klass = "storage-pool"; parent = resource.substr(0, pool); name = resource.substr(pool + 6); }
        else if (share != std::string::npos) { klass = "storage-share"; parent = resource.substr(0, share); name = resource.substr(share + 7); }
        else if (vm != std::string::npos) { klass = "vm"; parent = resource.substr(0, vm); name = "VM " + resource.substr(vm + 4); }
        // Telemetry outlives inventory revisions. Only synthesize resources for
        // recognized child identifiers; otherwise a renamed/removed top-level
        // device would reappear forever as a phantom discovered component.
        if (klass.empty() || parent.empty()) continue;
        for (const auto& candidate : current_state) if (candidate.value("resource", "") == resource && candidate.value("metric", "") == "name" && candidate["value"].is_string()) { name = candidate["value"].get<std::string>(); break; }
        const bool embedded = klass == "network-port" || klass == "network-client" || klass == "storage-disk" || klass == "storage-vdev";
        nlohmann::json roles = nlohmann::json::array();
        for (const auto& owner : inventory["devices"])
          if (owner.value("id", "") == parent &&
              owner.value("config", nlohmann::json::object()).value("backup_share_resource", "") == resource)
            roles.push_back("file-listing");
        values.push_back({{"id", resource}, {"class", klass}, {"adapter", "discovered"},
                          {"pretty_name", name}, {"comment", "Discovered by parent adapter"},
                          {"asset_tag", ""}, {"notes", ""}, {"photo_available", false},
                          {"parent", parent}, {"room", ""}, {"groups", nlohmann::json::array()}, {"roles", roles}, {"address", ""}, {"actions", nlohmann::json::array()},
                          {"presentation", {{"group", klass}, {"widget", klass}, {"visibility", embedded ? "embedded" : "normal"}, {"container", parent}}}});
      }
      for (auto& value : values) for (const auto& device : inventory["devices"]) {
        const auto& overrides = device.value("component_overrides", nlohmann::json::object());
        const auto key = value.value("id", ""); if (!overrides.contains(key)) continue;
        for (const auto& field : {"pretty_name", "comment", "asset_tag", "notes", "room", "groups"})
          if (overrides[key].contains(field)) value[field] = overrides[key][field];
        if (overrides[key].contains("photo")) value["photo_available"] = overrides[key]["photo"].contains("filename");
      }
      for (auto& value : values) {
        const auto parent = value.value("parent", "");
        if (!parent.empty()) for (const auto& candidate : values) if (candidate.value("id", "") == parent) {
          if (value.value("room", "").empty()) value["room"] = candidate.value("room", "");
          if (value.value("groups", nlohmann::json::array()).empty()) value["groups"] = candidate.value("groups", nlohmann::json::array());
          break;
        }
      }
      // Resolve containment once in the middle tier so every client sees the same
      // topology and does not have to infer relationships from IDs or group names.
      for (auto& value : values) {
        if (!value.contains("roles")) value["roles"] = nlohmann::json::array();
        if (!value.contains("lifecycle")) value["lifecycle"] = "active";
        if (!value.contains("importance")) value["importance"] = "normal";
        if (!value.contains("presentation_home")) {
          const auto klass = value.value("class", "");
          value["presentation_home"] = klass.rfind("storage-", 0) == 0 ? "storage" : "inventory";
        }
        value["children"] = nlohmann::json::array(); value["ancestors"] = nlohmann::json::array(); value["depth"] = 0;
      }
      for (auto& parent : values) for (const auto& child : values)
        if (child.value("parent", "") == parent.value("id", "")) parent["children"].push_back(child.value("id", ""));
      for (auto& value : values) {
        std::string parent = value.value("parent", ""); std::set<std::string> visited;
        while (!parent.empty() && visited.insert(parent).second) {
          value["ancestors"].push_back(parent); value["depth"] = value["depth"].get<int>() + 1;
          std::string next; for (const auto& candidate : values) if (candidate.value("id", "") == parent) { next = candidate.value("parent", ""); break; }
          parent = next;
        }
      }
      for (auto& value : values) {
        value["pinned"] = false; value["pin_order"] = nullptr;
        for (const auto& pin : inventory["pins"]) if (pin.value("resource", "") == value.value("id", "")) {
          value["pinned"] = true; value["pin_order"] = pin.value("order", 0); break;
        }
        nlohmann::json summary = nlohmann::json::array(); std::string severity = "info", state_text = "unknown";
        auto severity_rank = [](const std::string& value) { return value == "critical" ? 3 : value == "warning" ? 2 : value == "ok" ? 1 : 0; };
        for (const auto& row : current_state) {
          if (row.value("resource", "") != value.value("id", "")) continue;
          if (row.value("metric", "") == "health" || row.value("metric", "") == "status") {
            state_text = row.value("display_text", "unknown");
          }
          const auto row_severity = row.value("severity", "info"); if (severity_rank(row_severity) > severity_rank(severity)) severity = row_severity;
          if (row.value("visibility", "summary") == "summary" && row.value("metric", "") != "health") summary.push_back(row);
        }
        std::stable_sort(summary.begin(), summary.end(), [](const auto& a, const auto& b) { return a.value("display_priority", 50) < b.value("display_priority", 50); });
        if (summary.size() > 4) summary.erase(summary.begin() + 4, summary.end());
        value["severity"] = severity; value["state_text"] = state_text; value["summary"] = std::move(summary);
        const bool offline = state_text == "unreachable" || state_text == "stopped" || state_text == "disabled" || state_text == "OFFLINE";
        const bool online = state_text == "responding" || state_text == "running" || state_text == "ONLINE" || state_text == "OL";
        value["availability"] = offline ? "offline" : online ? "online" : "unknown";
        const auto groups = value.value("groups", nlohmann::json::array());
        const auto section = !groups.empty() ? groups[0].get<std::string>() : !value.value("room", "").empty() ? value.value("room", "") : value.value("class", "device");
        value["presentation"]["section"] = section;
        const auto availability_order = online ? "0" : offline ? "2" : "1";
        value["presentation"]["sort_key"] = (value.value("pinned", false) ? "0/" : "1/") + section + "/" + availability_order + "/" + value.value("pretty_name", "");
        if (offline && value.value("lifecycle", "active") == "active" && value["presentation"].value("visibility", "normal") != "embedded") value["presentation"]["visibility"] = "offline";
      }
      std::stable_sort(values.begin(), values.end(), [](const auto& a, const auto& b) {
        const auto ap = a.value("pinned", false), bp = b.value("pinned", false);
        if (ap != bp) return ap > bp;
        const auto ar = a.value("room", ""), br = b.value("room", "");
        if (ar != br) return ar < br;
        const auto availability_rank = [](const auto& value) { const auto state = value.value("availability", "unknown"); return state == "offline" ? 2 : state == "unknown" ? 1 : 0; };
        const auto aa = availability_rank(a), ba = availability_rank(b); if (aa != ba) return aa < ba;
        return a.value("pretty_name", "") < b.value("pretty_name", "");
      });
      return ok(id, "resources", values);
    }
    if (command == "CLASS.LIST") {
      nlohmann::json classes = nlohmann::json::array();
      std::set<std::string> seen;
      for (const auto& d : inventory_.devices()) if (seen.insert(d.value("class", "device")).second)
        classes.push_back({{"id", d.value("class", "device")}, {"presentation", {{"widget", d.value("class", "device")}}}});
      return ok(id, "classes", classes);
    }
    if (command == "RELATIONSHIP.LIST")
      return ok(id, "relationships", inventory_.snapshot().value("relationships", nlohmann::json::array()));
    if (command == "RESOURCE.GET" || command == "RESOURCE.DESCRIBE") {
      auto it = args.find("id"); if (it == args.end()) return error(id, "bad_request", "id required");
      auto device = inventory_.device(raw(it->second));
      return device ? ok(id, "resource", adapters_.describe(*device)) : error(id, "not_found", "resource not found");
    }
    if (command == "STATE.GET") {
      auto it = args.find("resource");
      return ok(id, "state", it == args.end() ? telemetry_.current() : telemetry_.current(raw(it->second)));
    }
    if (command == "CAMERA.STREAM") {
      try {
        auto device = inventory_.device(raw(args.at("resource")));
        if (!device) return error(id, "not_found", "resource not found");
        return ok(id, "camera-stream", adapters_.camera_stream(*device));
      } catch (const std::exception& e) { return error(id, "unavailable", e.what()); }
    }
    if (command == "STORAGE.FILES") {
      try {
        const auto resource = raw(args.at("resource")); const auto limit = std::min<std::size_t>(100, args.contains("limit") ? std::stoull(raw(args.at("limit"))) : 50);
        std::optional<nlohmann::json> owner; std::size_t longest = 0;
        for (const auto& device : inventory_.devices()) { const auto candidate = device.value("id", ""); if ((resource == candidate || (resource.size() > candidate.size() && resource.rfind(candidate + "/", 0) == 0)) && candidate.size() > longest) { owner = device; longest = candidate.size(); } }
        if (!owner) return error(id, "not_found", "resource owner not found");
        return ok(id, "storage-files", adapters_.storage_files(*owner, resource, limit));
      } catch (const std::exception& e) { return error(id, "unavailable", e.what()); }
    }
    if (command == "ASSET.PHOTO.GET") {
      try {
        const auto resource = raw(args.at("resource")); const auto record = asset_record(resource);
        if (!record.contains("filename")) return error(id, "not_found", "resource has no photo");
        const auto filename = record.value("filename", "");
        if (filename.empty() || filename.find('/') != std::string::npos) return error(id, "bad_request", "invalid photo reference");
        std::ifstream input(assets_dir_ / filename, std::ios::binary);
        if (!input) return error(id, "not_found", "photo file is unavailable");
        const std::string bytes((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
        return ok(id, "asset-photo", {{"resource", resource}, {"mime", record.value("mime", "image/jpeg")}, {"data", base64_encode(bytes)}});
      } catch (const std::exception& e) { return error(id, "bad_request", e.what()); }
    }
    if (command == "ASSET.PHOTO.SET") {
      if (!skylab::AuthStore::permits(identity->role, "operator")) return error(id, "forbidden", "operator role required");
      try {
        const auto resource = raw(args.at("resource")), mime = raw(args.at("mime"));
        if (mime != "image/jpeg" && mime != "image/png") throw std::runtime_error("photo must be JPEG or PNG");
        const auto bytes = base64_decode(raw(args.at("data")));
        if (bytes.empty() || bytes.size() > 256 * 1024) throw std::runtime_error("photo must be between 1 byte and 256 KiB");
        const auto revision = std::stoull(raw(args.at("revision")));
        const auto filename = asset_filename(resource, mime, revision + 1);
        const auto previous = asset_record(resource).value("filename", "");
        const auto target = assets_dir_ / filename;
        const auto temporary = target.string() + ".tmp";
        { std::ofstream output(temporary, std::ios::binary | std::ios::trunc); output.write(bytes.data(), static_cast<std::streamsize>(bytes.size())); if (!output) throw std::runtime_error("photo write failed"); }
        std::filesystem::rename(temporary, target); std::filesystem::permissions(target, std::filesystem::perms::owner_read | std::filesystem::perms::owner_write);
        const nlohmann::json changes{{"photo", {{"filename", filename}, {"mime", mime}, {"updated_at", now_utc()}}}};
        std::uint64_t next;
        try { next = inventory_.device(resource) ? inventory_.patch(resource, revision, changes) : inventory_.patch_component(resource, revision, changes); }
        catch (...) { std::filesystem::remove(target); throw; }
        if (!previous.empty() && previous != filename && previous.find('/') == std::string::npos) std::filesystem::remove(assets_dir_ / previous);
        return ok(id, "asset-photo", {{"resource", resource}, {"revision", next}, {"mime", mime}});
      } catch (const std::exception& e) { return error(id, "conflict", e.what()); }
    }
    if (command == "ASSET.PHOTO.DELETE") {
      if (!skylab::AuthStore::permits(identity->role, "operator")) return error(id, "forbidden", "operator role required");
      try {
        const auto resource = raw(args.at("resource")); const auto record = asset_record(resource);
        const auto revision = std::stoull(raw(args.at("revision")));
        const nlohmann::json changes{{"photo", nlohmann::json::object()}};
        const auto next = inventory_.device(resource) ? inventory_.patch(resource, revision, changes) : inventory_.patch_component(resource, revision, changes);
        const auto filename = record.value("filename", ""); if (!filename.empty() && filename.find('/') == std::string::npos) std::filesystem::remove(assets_dir_ / filename);
        return ok(id, "asset-photo", {{"resource", resource}, {"revision", next}, {"deleted", true}});
      } catch (const std::exception& e) { return error(id, "conflict", e.what()); }
    }
    if (command == "METRIC.QUERY") {
      try {
        const auto resource = raw(args.at("resource")), metric = raw(args.at("metric"));
        const auto start = std::stoll(raw(args.at("start_ms"))), end = std::stoll(raw(args.at("end_ms")));
        const auto limit = args.contains("limit") ? std::stoull(raw(args.at("limit"))) : 10000;
        return ok(id, "samples", telemetry_.query(resource, metric, start, end, limit));
      } catch (const std::exception& e) { return error(id, "bad_request", e.what()); }
    }
    if (command == "ACTION.INVOKE") {
      if (!skylab::AuthStore::permits(identity->role, "operator")) return error(id, "forbidden", "operator role required");
      try {
        auto device = inventory_.device(raw(args.at("resource")));
        if (!device) return error(id, "not_found", "resource not found");
        const auto action = raw(args.at("action"));
        const auto params = args.contains("parameters") ? nlohmann::json::parse(raw(args.at("parameters"))) : nlohmann::json::object();
        auto result = adapters_.invoke(*device, action, params);
        const auto refreshed = adapters_.poll(*device);
        for (const auto& observation : refreshed.observations) telemetry_.record(observation);
        result["post_health"] = refreshed.health;
        const auto at = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
        telemetry_.record_audit(identity->client, raw(args.at("resource")), action, params, result, at);
        return result.value("ok", false) ? ok(id, "action", result)
                                         : error(id, "verification_failed", result.value("error", "action failed"));
      } catch (const std::exception& e) { return error(id, "bad_request", e.what()); }
    }
    if (command == "AUDIT.LIST") {
      if (!skylab::AuthStore::permits(identity->role, "admin")) return error(id, "forbidden", "admin role required");
      const auto limit = args.contains("limit") ? std::stoull(raw(args.at("limit"))) : 100;
      return ok(id, "audit", telemetry_.audit(limit));
    }
    if (command == "EVENT.LIST") {
      const auto limit = args.contains("limit") ? std::stoull(raw(args.at("limit"))) : 100;
      return ok(id, "events", telemetry_.events(limit));
    }
    if (command == "INVENTORY.GET") return ok(id, "inventory", inventory_.snapshot());
    if (command == "INVENTORY.PATCH") {
      try {
        const auto device = raw(args.at("id"));
        const auto revision = std::stoull(raw(args.at("revision")));
        const auto changes = nlohmann::json::parse(raw(args.at("changes")));
        if (!skylab::AuthStore::permits(identity->role, "admin")) {
          if (!skylab::AuthStore::permits(identity->role, "operator")) return error(id, "forbidden", "operator role required");
          static const std::set<std::string> presentation_fields{"pretty_name", "comment", "asset_tag", "notes", "room", "groups"};
          for (auto it = changes.begin(); it != changes.end(); ++it)
            if (!presentation_fields.contains(it.key())) return error(id, "forbidden", "admin role required for field: " + it.key());
        }
        return ok(id, "inventory", {{"revision", inventory_.patch(device, revision, changes)}});
      } catch (const std::exception& e) { return error(id, "conflict", e.what()); }
    }
    if (command == "METADATA.PATCH") {
      if (!skylab::AuthStore::permits(identity->role, "operator")) return error(id, "forbidden", "operator role required");
      try {
        const auto resource = raw(args.at("resource"));
        const auto revision = std::stoull(raw(args.at("revision")));
        const auto changes = nlohmann::json::parse(raw(args.at("changes")));
        static const std::set<std::string> metadata_fields{"pretty_name", "comment", "asset_tag", "notes", "room", "groups"};
        for (auto it = changes.begin(); it != changes.end(); ++it)
          if (!metadata_fields.contains(it.key())) return error(id, "forbidden", "metadata field not editable: " + it.key());
        const auto next = inventory_.device(resource)
          ? inventory_.patch(resource, revision, changes)
          : inventory_.patch_component(resource, revision, changes);
        return ok(id, "metadata", {{"resource", resource}, {"revision", next}});
      } catch (const std::exception& e) { return error(id, "conflict", e.what()); }
    }
    if (command == "PIN.SET") {
      if (!skylab::AuthStore::permits(identity->role, "operator")) return error(id, "forbidden", "operator role required");
      try {
        const auto resource = raw(args.at("resource"));
        const auto revision = std::stoull(raw(args.at("revision")));
        const bool pinned = raw(args.at("pinned")) == "true" || raw(args.at("pinned")) == "1";
        return ok(id, "pin", {{"resource", resource}, {"pinned", pinned}, {"revision", inventory_.set_pin(resource, pinned, revision)}});
      } catch (const std::exception& e) { return error(id, "conflict", e.what()); }
    }
    if (command == "COMPONENT.PATCH") {
      if (!skylab::AuthStore::permits(identity->role, "operator")) return error(id, "forbidden", "operator role required");
      try {
        const auto resource = raw(args.at("resource"));
        const auto revision = std::stoull(raw(args.at("revision")));
        const auto changes = nlohmann::json::parse(raw(args.at("changes")));
        return ok(id, "component", {{"resource", resource}, {"revision", inventory_.patch_component(resource, revision, changes)}});
      } catch (const std::exception& e) { return error(id, "conflict", e.what()); }
    }
    return error(id, "not_found", "unknown command");
  }

 private:
  nlohmann::json asset_record(const std::string& resource) const {
    if (const auto device = inventory_.device(resource)) return device->value("photo", nlohmann::json::object());
    const auto snapshot = inventory_.snapshot(); std::size_t longest = 0; nlohmann::json result = nlohmann::json::object();
    for (const auto& device : snapshot["devices"]) {
      const auto owner = device.value("id", "");
      if (resource.size() <= owner.size() || resource.compare(0, owner.size(), owner) != 0 || resource[owner.size()] != '/' || owner.size() <= longest) continue;
      const auto overrides = device.value("component_overrides", nlohmann::json::object());
      if (overrides.contains(resource)) { result = overrides[resource].value("photo", nlohmann::json::object()); longest = owner.size(); }
    }
    return result;
  }
  skylab::InventoryStore inventory_;
  std::filesystem::path assets_dir_;
  skylab::TelemetryStore telemetry_;
  skylab::AdapterRegistry adapters_;
  skylab::PresentationCatalog presentation_;
  std::string token_;
  std::unique_ptr<skylab::AuthStore> auth_;
  std::vector<std::thread> pollers_;
};

void client_loop(int socket, Service& service) {
  const std::string max_frame = std::to_string(skylab::wire::Decoder::max_frame);
  send_all(socket, skylab::wire::encode({"H", "1", "0", "skyhabd", max_frame, "discovery", "events"}));
  skylab::wire::Decoder decoder;
  std::optional<skylab::Identity> identity;
  char buffer[8192];
  while (running) {
    const auto count = ::recv(socket, buffer, sizeof(buffer), 0);
    if (count <= 0) break;
    decoder.feed(std::string_view(buffer, static_cast<std::size_t>(count)));
    while (auto request = decoder.next()) {
      if (!send_all(socket, skylab::wire::encode(service.handle(*request, identity)))) break;
    }
    if (decoder.failed()) break;
  }
  ::close(socket);
}
}

int main(int argc, char** argv) {
  std::string inventory = "inventory/inventory.example.json", database = "var/skyhab.sqlite3";
  std::string bind_address = "127.0.0.1", token, auth_file, secrets_file;
  std::string views_file = "presentation/views.json";
  int port = 3636;
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--inventory" && i + 1 < argc) inventory = argv[++i];
    else if (arg == "--database" && i + 1 < argc) database = argv[++i];
    else if (arg == "--bind" && i + 1 < argc) bind_address = argv[++i];
    else if (arg == "--port" && i + 1 < argc) port = std::stoi(argv[++i]);
    else if (arg == "--token" && i + 1 < argc) token = argv[++i];
    else if (arg == "--auth-file" && i + 1 < argc) auth_file = argv[++i];
    else if (arg == "--secrets-file" && i + 1 < argc) secrets_file = argv[++i];
    else if (arg == "--views" && i + 1 < argc) views_file = argv[++i];
  }
  if (token.empty()) { if (const char* env = std::getenv("SKYHAB_TOKEN")) token = env; }
  if (token.empty()) { if (const char* env = std::getenv("SKYLAB_TOKEN")) token = env; }
  if (token.empty() && auth_file.empty()) { std::cerr << "skyhabd: --auth-file, --token, SKYHAB_TOKEN, or legacy SKYLAB_TOKEN is required\n"; return 2; }
  std::signal(SIGINT, stop);
  std::signal(SIGTERM, stop);
  std::signal(SIGPIPE, SIG_IGN);
  try {
    Service service(inventory, database, token, auth_file, secrets_file, views_file); service.start_polling();
    const int listener = ::socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) throw std::runtime_error(std::string("socket failed: ") + std::strerror(errno));
    ::fcntl(listener, F_SETFD, ::fcntl(listener, F_GETFD) | FD_CLOEXEC);
    listener_socket = listener;
    int yes = 1; setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    sockaddr_in address{}; address.sin_family = AF_INET; address.sin_port = htons(static_cast<uint16_t>(port));
    if (inet_pton(AF_INET, bind_address.c_str(), &address.sin_addr) != 1 ||
        bind(listener, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 || listen(listener, 64) != 0)
      throw std::runtime_error(std::string("listen failed: ") + std::strerror(errno));
    std::cout << "skyhabd " << SKYL_VERSION << " listening on " << bind_address << ':' << port << "\n";
    while (running) {
      const int client = accept(listener, nullptr, nullptr);
      if (client >= 0) {
        ::fcntl(client, F_SETFD, ::fcntl(client, F_GETFD) | FD_CLOEXEC);
        std::thread(client_loop, client, std::ref(service)).detach();
      }
      else if (!running || errno != EINTR) break;
    }
    if (listener_socket.exchange(-1) >= 0) close(listener);
  } catch (const std::exception& e) { std::cerr << "skyhabd: " << e.what() << "\n"; return 1; }
  return 0;
}
