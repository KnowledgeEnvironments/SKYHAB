// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#pragma once

#include <nlohmann/json.hpp>
#include "skylab/adapters.hpp"

namespace skylab {
PollResult poll_meshtastic(const nlohmann::json& device);
}
