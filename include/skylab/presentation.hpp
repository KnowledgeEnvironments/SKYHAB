// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#pragma once

#include <filesystem>
#include <string_view>
#include <nlohmann/json.hpp>

namespace skylab {

class PresentationCatalog {
 public:
  explicit PresentationCatalog(const std::filesystem::path& path);
  [[nodiscard]] nlohmann::json list() const;
  [[nodiscard]] nlohmann::json describe(std::string_view id) const;
  [[nodiscard]] std::uint64_t revision() const;

 private:
  nlohmann::json value_;
};

}  // namespace skylab
