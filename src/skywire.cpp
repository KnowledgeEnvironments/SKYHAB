// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/skywire.hpp"

#include <charconv>
#include <iomanip>
#include <limits>
#include <sstream>

namespace skylab::wire {
namespace {

std::optional<std::pair<std::string, std::size_t>> parse_netstring(
    std::string_view input, std::string& error, std::size_t limit) {
  const auto colon = input.find(':');
  if (colon == std::string_view::npos) return std::nullopt;
  if (colon == 0 || colon > 9) { error = "invalid netstring length"; return std::nullopt; }
  if (colon > 1 && input.front() == '0') { error = "leading zero in netstring length"; return std::nullopt; }
  std::size_t length = 0;
  const auto parsed = std::from_chars(input.data(), input.data() + colon, length);
  if (parsed.ec != std::errc{} || parsed.ptr != input.data() + colon || length > limit) {
    error = "invalid or oversized netstring";
    return std::nullopt;
  }
  const std::size_t total = colon + 1 + length + 1;
  if (input.size() < total) return std::nullopt;
  if (input[total - 1] != ',') { error = "missing netstring comma"; return std::nullopt; }
  return std::pair{std::string(input.substr(colon + 1, length)), total};
}

}  // namespace

std::string netstring(std::string_view value) {
  return std::to_string(value.size()) + ":" + std::string(value) + ",";
}

std::string encode(const Message& tokens) {
  std::string payload;
  for (const auto& token : tokens) payload += netstring(token);
  return netstring(payload);
}

void Decoder::feed(std::span<const std::byte> bytes) {
  buffer_.append(reinterpret_cast<const char*>(bytes.data()), bytes.size());
  if (buffer_.size() > max_frame + 64 && buffer_.find(':') == std::string::npos)
    error_ = "frame prefix exceeds limit";
}

void Decoder::feed(std::string_view bytes) {
  buffer_.append(bytes);
}

std::optional<Message> Decoder::next() {
  if (failed()) return std::nullopt;
  auto outer = parse_netstring(buffer_, error_, max_frame);
  if (!outer) return std::nullopt;
  Message result;
  std::size_t offset = 0;
  while (offset < outer->first.size()) {
    auto inner = parse_netstring(std::string_view(outer->first).substr(offset), error_, max_frame);
    if (!inner) {
      if (error_.empty()) error_ = "truncated inner netstring";
      return std::nullopt;
    }
    result.push_back(std::move(inner->first));
    if (result.size() > max_tokens) { error_ = "too many tokens"; return std::nullopt; }
    offset += inner->second;
  }
  if (result.empty()) { error_ = "empty message"; return std::nullopt; }
  buffer_.erase(0, outer->second);
  return result;
}

void Decoder::reset() { buffer_.clear(); error_.clear(); }
std::string typed_string(std::string_view value) { return "s" + std::string(value); }
std::string typed_uint(std::uint64_t value) { return "u" + std::to_string(value); }
std::string typed_int(std::int64_t value) { return "i" + std::to_string(value); }
std::string typed_float(double value) { std::ostringstream s; s << std::setprecision(15) << value; return "f" + s.str(); }
std::string typed_bool(bool value) { return value ? "b1" : "b0"; }
std::string typed_null() { return "n"; }

}  // namespace skylab::wire
