// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace skylab::wire {

using Message = std::vector<std::string>;

std::string netstring(std::string_view value);
std::string encode(const Message& tokens);

class Decoder {
 public:
  static constexpr std::size_t max_frame = 16ull * 1024 * 1024;
  static constexpr std::size_t max_tokens = 256;

  void feed(std::span<const std::byte> bytes);
  void feed(std::string_view bytes);
  std::optional<Message> next();
  [[nodiscard]] const std::string& error() const { return error_; }
  [[nodiscard]] bool failed() const { return !error_.empty(); }
  void reset();

 private:
  std::string buffer_;
  std::string error_;
};

std::string typed_string(std::string_view value);
std::string typed_uint(std::uint64_t value);
std::string typed_int(std::int64_t value);
std::string typed_float(double value);
std::string typed_bool(bool value);
std::string typed_null();

}  // namespace skylab::wire
