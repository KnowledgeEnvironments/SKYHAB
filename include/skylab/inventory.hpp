// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#pragma once

#include <filesystem>
#include <mutex>
#include <optional>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>

namespace skylab {

class InventoryStore {
 public:
  explicit InventoryStore(std::filesystem::path path);
  void load();
  [[nodiscard]] nlohmann::json snapshot() const;
  [[nodiscard]] std::vector<nlohmann::json> devices() const;
  [[nodiscard]] std::optional<nlohmann::json> device(std::string_view id) const;
  [[nodiscard]] std::uint64_t revision() const;
  std::uint64_t patch(std::string_view id, std::uint64_t expected_revision,
                      const nlohmann::json& changes);
  std::uint64_t set_pin(std::string_view resource, bool pinned,
                        std::uint64_t expected_revision);
  std::uint64_t patch_component(std::string_view resource, std::uint64_t expected_revision,
                                const nlohmann::json& changes);

 private:
  static void validate(const nlohmann::json& value);
  void persist_locked(const nlohmann::json& next);
  std::filesystem::path path_;
  mutable std::mutex mutex_;
  nlohmann::json value_;
};

}  // namespace skylab
