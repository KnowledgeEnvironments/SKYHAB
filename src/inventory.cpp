// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/inventory.hpp"

#include <chrono>
#include <fstream>
#include <stdexcept>
#include <system_error>
#include <fcntl.h>
#include <unistd.h>

namespace skylab {
namespace {
std::string now_utc() {
  const auto now = std::chrono::system_clock::now();
  const auto seconds = std::chrono::system_clock::to_time_t(now);
  std::tm tm{};
  gmtime_r(&seconds, &tm);
  char text[32];
  std::strftime(text, sizeof(text), "%Y-%m-%dT%H:%M:%SZ", &tm);
  return text;
}
}

InventoryStore::InventoryStore(std::filesystem::path path) : path_(std::move(path)) { load(); }

void InventoryStore::validate(const nlohmann::json& value) {
  if (!value.is_object() || value.value("schema_version", 0) != 2 ||
      !value.contains("revision") || !value["revision"].is_number_unsigned() ||
      !value.contains("devices") || !value["devices"].is_array() ||
      !value.contains("pins") || !value["pins"].is_array())
    throw std::runtime_error("invalid inventory envelope");
  std::vector<std::string> ids;
  for (const auto& device : value["devices"]) {
    for (const char* key : {"id", "class", "adapter", "pretty_name", "comment"})
      if (!device.contains(key) || !device[key].is_string())
        throw std::runtime_error(std::string("device missing string field: ") + key);
    const auto id = device["id"].get<std::string>();
    if (std::find(ids.begin(), ids.end(), id) != ids.end())
      throw std::runtime_error("duplicate device id: " + id);
    ids.push_back(id);
  }
}

void InventoryStore::load() {
  std::ifstream input(path_);
  if (!input) throw std::runtime_error("cannot open inventory: " + path_.string());
  nlohmann::json value;
  input >> value;
  validate(value);
  std::lock_guard lock(mutex_);
  value_ = std::move(value);
}

nlohmann::json InventoryStore::snapshot() const { std::lock_guard lock(mutex_); return value_; }
std::vector<nlohmann::json> InventoryStore::devices() const {
  std::lock_guard lock(mutex_); return value_["devices"].get<std::vector<nlohmann::json>>();
}
std::optional<nlohmann::json> InventoryStore::device(std::string_view id) const {
  std::lock_guard lock(mutex_);
  for (const auto& item : value_["devices"]) if (item["id"] == id) return item;
  return std::nullopt;
}
std::uint64_t InventoryStore::revision() const { std::lock_guard lock(mutex_); return value_["revision"].get<std::uint64_t>(); }

void InventoryStore::persist_locked(const nlohmann::json& next) {
  const auto temp = path_.string() + ".tmp";
  const std::string bytes = next.dump(2) + "\n";
  const int fd = ::open(temp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) throw std::runtime_error("cannot create inventory temporary file");
  std::size_t offset = 0;
  while (offset < bytes.size()) {
    const auto count = ::write(fd, bytes.data() + offset, bytes.size() - offset);
    if (count <= 0) { ::close(fd); throw std::runtime_error("inventory write failed"); }
    offset += static_cast<std::size_t>(count);
  }
  if (::fsync(fd) != 0 || ::close(fd) != 0) throw std::runtime_error("inventory sync failed");
  std::filesystem::rename(temp, path_);
  const int dirfd = ::open(path_.parent_path().c_str(), O_RDONLY);
  if (dirfd >= 0) { ::fsync(dirfd); ::close(dirfd); }
}

std::uint64_t InventoryStore::patch(std::string_view id, std::uint64_t expected,
                                    const nlohmann::json& changes) {
  static const std::vector<std::string> allowed{"pretty_name", "comment", "asset_tag", "notes", "photo", "location", "room", "groups", "enabled", "labels", "poll", "component_overrides"};
  std::lock_guard lock(mutex_);
  const auto current = value_["revision"].get<std::uint64_t>();
  if (current != expected) throw std::runtime_error("conflict: inventory revision changed");
  auto next = value_;
  auto found = false;
  for (auto& item : next["devices"]) {
    if (item["id"] != id) continue;
    found = true;
    for (auto it = changes.begin(); it != changes.end(); ++it) {
      if (std::find(allowed.begin(), allowed.end(), it.key()) == allowed.end())
        throw std::runtime_error("field is not client-editable: " + it.key());
      item[it.key()] = it.value();
    }
  }
  if (!found) throw std::runtime_error("not_found: device");
  next["revision"] = current + 1;
  next["updated_at"] = now_utc();
  validate(next);
  persist_locked(next);
  value_ = std::move(next);
  return current + 1;
}

std::uint64_t InventoryStore::set_pin(std::string_view resource, bool pinned,
                                      std::uint64_t expected) {
  std::lock_guard lock(mutex_);
  const auto current = value_["revision"].get<std::uint64_t>();
  if (current != expected) throw std::runtime_error("conflict: inventory revision changed");
  auto next = value_; auto& pins = next["pins"];
  for (auto it = pins.begin(); it != pins.end();) {
    if (it->value("resource", "") == resource) it = pins.erase(it); else ++it;
  }
  if (pinned) pins.push_back({{"resource", resource}, {"order", pins.size()}});
  for (std::size_t i = 0; i < pins.size(); ++i) pins[i]["order"] = i;
  next["revision"] = current + 1; next["updated_at"] = now_utc();
  validate(next); persist_locked(next); value_ = std::move(next); return current + 1;
}

std::uint64_t InventoryStore::patch_component(std::string_view resource, std::uint64_t expected,
                                              const nlohmann::json& changes) {
  static const std::vector<std::string> allowed{"pretty_name", "comment", "asset_tag", "notes", "photo", "room", "groups"};
  std::lock_guard lock(mutex_);
  const auto current = value_["revision"].get<std::uint64_t>();
  if (current != expected) throw std::runtime_error("conflict: inventory revision changed");
  auto next = value_; nlohmann::json* owner = nullptr; std::size_t longest = 0;
  for (auto& item : next["devices"]) {
    const auto id = item.value("id", "");
    if (resource.size() > id.size() && resource.substr(0, id.size()) == id && resource[id.size()] == '/' && id.size() > longest) {
      owner = &item; longest = id.size();
    }
  }
  if (!owner) throw std::runtime_error("not_found: component owner");
  auto& override = (*owner)["component_overrides"][std::string(resource)];
  if (!override.is_object()) override = nlohmann::json::object();
  for (auto it = changes.begin(); it != changes.end(); ++it) {
    if (std::find(allowed.begin(), allowed.end(), it.key()) == allowed.end())
      throw std::runtime_error("field is not component-editable: " + it.key());
    override[it.key()] = it.value();
  }
  next["revision"] = current + 1; next["updated_at"] = now_utc();
  validate(next); persist_locked(next); value_ = std::move(next); return current + 1;
}

}  // namespace skylab
