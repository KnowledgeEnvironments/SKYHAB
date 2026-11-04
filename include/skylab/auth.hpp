// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#pragma once

#include <filesystem>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <nlohmann/json.hpp>

namespace skylab {

struct Identity { std::string client; std::string role; };

class AuthStore {
 public:
  explicit AuthStore(std::filesystem::path path);
  // Reloads credentials from disk. Never throws: on an unreadable, unparsable,
  // or permission-invalid file it keeps the last good state (logged via the
  // optional sink) so a bad auth file cannot take the daemon down.
  void reload();
  [[nodiscard]] std::optional<Identity> authenticate(std::string_view client,
                                                     std::string_view token) const;
  static bool permits(std::string_view role, std::string_view required);

 private:
  // Load+validate a candidate client table, or throw described as above.
  static nlohmann::json read_validate(const std::filesystem::path& path);

  mutable std::mutex mutex_;
  std::filesystem::path path_;
  nlohmann::json clients_;
};

}  // namespace skylab
