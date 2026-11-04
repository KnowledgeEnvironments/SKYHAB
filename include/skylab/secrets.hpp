// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#pragma once

#include <filesystem>
#include <string>
#include <string_view>
#include <unordered_map>

namespace skylab {

class SecretStore {
 public:
  SecretStore() = default;
  explicit SecretStore(const std::filesystem::path& path);
  void load(const std::filesystem::path& path);
  [[nodiscard]] std::string get(std::string_view reference) const;

 private:
  std::unordered_map<std::string, std::string> values_;
};

}  // namespace skylab
