// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/auth.hpp"

#include <algorithm>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <picosha2.h>

namespace skylab {
namespace {
bool constant_equal(std::string_view a, std::string_view b) {
  if (a.size() != b.size()) return false;
  unsigned char difference = 0;
  for (std::size_t i = 0; i < a.size(); ++i)
    difference |= static_cast<unsigned char>(a[i]) ^ static_cast<unsigned char>(b[i]);
  return difference == 0;
}
}  // namespace

AuthStore::AuthStore(std::filesystem::path path) : path_(std::move(path)) { reload(); }
void AuthStore::reload() {
  const auto replacement = read_validate(path_);
  std::lock_guard<std::mutex> lock(mutex_);
  clients_ = std::move(replacement);
}
nlohmann::json AuthStore::read_validate(const std::filesystem::path& path) {
  const auto permissions = std::filesystem::status(path).permissions();
  using P = std::filesystem::perms;
  if ((permissions & (P::group_all | P::others_all)) != P::none)
    throw std::runtime_error("auth file must not be accessible by group or others");
  std::ifstream input(path); if (!input) throw std::runtime_error("cannot open auth file: " + path.string());
  nlohmann::json value; input >> value;
  if (!value.is_object() || !value.contains("clients") || !value["clients"].is_array())
    throw std::runtime_error("invalid auth file");
  for (const auto& client : value["clients"])
    if (!client.contains("id") || !client.contains("role") || !client.contains("token_sha256"))
      throw std::runtime_error("invalid auth client record");
  return value["clients"];
}
std::optional<Identity> AuthStore::authenticate(std::string_view id, std::string_view token) const {
  std::lock_guard<std::mutex> lock(mutex_);
  const auto digest = picosha2::hash256_hex_string(std::string(token));
  for (const auto& client : clients_) {
    if (client.value("id", "") != id || client.value("revoked", false)) continue;
    if (constant_equal(client.value("token_sha256", ""), digest))
      return Identity{std::string(id), client.value("role", "viewer")};
  }
  return std::nullopt;
}
bool AuthStore::permits(std::string_view role, std::string_view required) {
  auto rank = [](std::string_view value) { return value == "admin" ? 3 : value == "operator" ? 2 : value == "viewer" ? 1 : 0; };
  return rank(role) >= rank(required);
}
}  // namespace skylab
