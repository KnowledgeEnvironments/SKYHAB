// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/presentation.hpp"

#include <fstream>
#include <stdexcept>

namespace skylab {

PresentationCatalog::PresentationCatalog(const std::filesystem::path& path) {
  std::ifstream input(path); if (!input) throw std::runtime_error("cannot open presentation catalog: " + path.string());
  input >> value_;
  if (value_.value("schema", "") != "skylab.presentation/1" || !value_.contains("views") || !value_["views"].is_array())
    throw std::runtime_error("invalid presentation catalog");
  for (const auto& view : value_["views"])
    if (!view.contains("id") || !view["id"].is_string() || !view.contains("sections") || !view["sections"].is_array())
      throw std::runtime_error("invalid presentation view");
}

nlohmann::json PresentationCatalog::list() const {
  nlohmann::json result = nlohmann::json::array();
  for (const auto& view : value_["views"])
    result.push_back({{"id", view["id"]}, {"title", view.value("title", view["id"])},
                      {"icon", view.value("icon", "resource")}, {"priority", view.value("priority", 50)}});
  return result;
}

nlohmann::json PresentationCatalog::describe(std::string_view id) const {
  for (const auto& view : value_["views"]) if (view.value("id", "") == id) return view;
  throw std::runtime_error("view not found");
}

std::uint64_t PresentationCatalog::revision() const { return value_.value("revision", 1ULL); }

}  // namespace skylab
