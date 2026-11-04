// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#pragma once

#include <string>
#include <vector>
#include <nlohmann/json.hpp>
#include "skylab/telemetry.hpp"
#include "skylab/secrets.hpp"

namespace skylab {

struct PollResult {
  std::string health{"unknown"};
  std::string error;
  std::vector<Observation> observations;
};

class AdapterRegistry {
 public:
  AdapterRegistry() = default;
  explicit AdapterRegistry(const std::string& secrets_file);
  PollResult poll(const nlohmann::json& device) const;
  nlohmann::json describe(const nlohmann::json& device) const;
  nlohmann::json invoke(const nlohmann::json& device, std::string_view action,
                        const nlohmann::json& parameters) const;
  nlohmann::json camera_stream(const nlohmann::json& device) const;
  nlohmann::json storage_files(const nlohmann::json& device, std::string_view resource,
                               std::size_t limit) const;
 private:
  SecretStore secrets_;
};

}  // namespace skylab
