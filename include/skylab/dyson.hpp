// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#pragma once
#include <nlohmann/json.hpp>
#include <string_view>
#include "skylab/adapters.hpp"

namespace skylab {
PollResult poll_dyson(const nlohmann::json& device, const SecretStore& secrets);
nlohmann::json invoke_dyson(const nlohmann::json& device, const SecretStore& secrets,
                            std::string_view action, const nlohmann::json& parameters);
}
