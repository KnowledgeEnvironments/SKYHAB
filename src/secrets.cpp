// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/secrets.hpp"

#include <cstdlib>
#include <fstream>
#include <stdexcept>
#include <nlohmann/json.hpp>

namespace skylab {
namespace {
std::string environment_name(std::string_view prefix, std::string_view reference) {
  std::string name(prefix);
  for (unsigned char c : reference) name += std::isalnum(c) ? static_cast<char>(std::toupper(c)) : '_';
  return name;
}
}

SecretStore::SecretStore(const std::filesystem::path& path) { load(path); }
void SecretStore::load(const std::filesystem::path& path) {
  const auto permissions = std::filesystem::status(path).permissions();
  using P = std::filesystem::perms;
  if ((permissions & (P::group_all | P::others_all)) != P::none)
    throw std::runtime_error("secrets file must not be accessible by group or others");
  std::ifstream input(path); if (!input) throw std::runtime_error("cannot open secrets file: " + path.string());
  nlohmann::json value; input >> value;
  const auto& secrets = value.contains("secrets") ? value["secrets"] : value;
  if (!secrets.is_object()) throw std::runtime_error("invalid secrets file");
  values_.clear();
  for (auto it = secrets.begin(); it != secrets.end(); ++it) {
    if (!it.value().is_string()) throw std::runtime_error("secret values must be strings");
    values_[it.key()] = it.value().get<std::string>();
  }
}
std::string SecretStore::get(std::string_view reference) const {
  const auto preferred_env = environment_name("SKYHAB_SECRET_", reference);
  if (const char* value = std::getenv(preferred_env.c_str())) return value;
  const auto legacy_env = environment_name("SKYLAB_SECRET_", reference);
  if (const char* value = std::getenv(legacy_env.c_str())) return value;
  if (const auto it = values_.find(std::string(reference)); it != values_.end()) return it->second;
  return {};
}
}  // namespace skylab
