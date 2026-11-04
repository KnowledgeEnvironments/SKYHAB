// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#pragma once

#include <cstdint>
#include <filesystem>
#include <chrono>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>
#include <nlohmann/json.hpp>
#include <sqlite3.h>

namespace skylab {

struct Observation {
  std::string resource;
  std::string metric;
  nlohmann::json value;
  std::string unit;
  std::string quality{"good"};
  std::int64_t observed_at_ms{};
};

class TelemetryStore {
 public:
  explicit TelemetryStore(const std::filesystem::path& path);
  ~TelemetryStore();
  TelemetryStore(const TelemetryStore&) = delete;
  TelemetryStore& operator=(const TelemetryStore&) = delete;
  void record(const Observation& observation);
  [[nodiscard]] nlohmann::json current() const;
  [[nodiscard]] nlohmann::json current(std::string_view resource) const;
  [[nodiscard]] nlohmann::json query(std::string_view resource, std::string_view metric,
                                     std::int64_t start_ms, std::int64_t end_ms,
                                     std::size_t limit) const;
  void record_audit(std::string_view actor, std::string_view resource, std::string_view action,
                    const nlohmann::json& request, const nlohmann::json& result,
                    std::int64_t at_ms);
  [[nodiscard]] nlohmann::json audit(std::size_t limit) const;
  [[nodiscard]] nlohmann::json events(std::size_t limit) const;

 private:
  void exec(const char* sql);
  sqlite3* db_{};
  mutable std::mutex mutex_;
  // Full-state read cache: STATE.GET rebuilds ~4,600 enriched rows (~1.1 MiB JSON)
  // per call, so concurrent 5 s-polling clients each paid the full re-read, re-parse,
  // and presentation enrichment. The cache is invalidated by every record() and may
  // be at most kCurrentCacheTTL stale, which keeps post-action readback fresh (the
  // action path records new observations before clients re-read) while collapsing
  // bursts of simultaneous polls into one rebuild.
  static constexpr auto kCurrentCacheTTL = std::chrono::milliseconds(400);
  mutable nlohmann::json current_cache_;
  mutable std::chrono::steady_clock::time_point current_cache_at_{};
  // Prepared statements reused across record() calls; record() previously prepared
  // and finalized three statements per observation (~40 observations/second).
  sqlite3_stmt* previous_stmt_{};
  sqlite3_stmt* sample_stmt_{};
  sqlite3_stmt* event_stmt_{};
  sqlite3_stmt* upsert_stmt_{};
};

}  // namespace skylab
