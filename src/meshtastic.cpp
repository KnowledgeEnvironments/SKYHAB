// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/meshtastic.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <optional>
#include <poll.h>
#include <stdexcept>
#include <string_view>
#include <thread>
#include <vector>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

namespace skylab {
namespace {
constexpr unsigned char start1 = 0x94;
constexpr unsigned char start2 = 0xc3;
constexpr std::size_t maximum_frame = 512;

std::int64_t now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

Observation observation(const nlohmann::json& device, std::string metric,
                        nlohmann::json value, std::string unit = {}) {
  return {device.value("id", ""), std::move(metric), std::move(value),
          std::move(unit), "good", now_ms()};
}

struct Field {
  unsigned number{};
  unsigned wire{};
  std::uint64_t integer{};
  std::uint32_t fixed32{};
  std::string_view bytes;
};

class ProtoReader {
 public:
  explicit ProtoReader(std::string_view bytes) : bytes_(bytes) {}

  bool next(Field& field) {
    if (offset_ == bytes_.size()) return false;
    const auto key = varint();
    field = {}; field.number = static_cast<unsigned>(key >> 3); field.wire = static_cast<unsigned>(key & 7);
    if (field.number == 0) throw std::runtime_error("Meshtastic protobuf has field zero");
    switch (field.wire) {
      case 0: field.integer = varint(); break;
      case 1: require(8); offset_ += 8; break;
      case 2: {
        const auto size = varint(); require(size);
        field.bytes = bytes_.substr(offset_, static_cast<std::size_t>(size));
        offset_ += static_cast<std::size_t>(size); break;
      }
      case 5: {
        require(4); const auto* p = reinterpret_cast<const unsigned char*>(bytes_.data() + offset_);
        field.fixed32 = static_cast<std::uint32_t>(p[0]) | (static_cast<std::uint32_t>(p[1]) << 8) |
                        (static_cast<std::uint32_t>(p[2]) << 16) | (static_cast<std::uint32_t>(p[3]) << 24);
        offset_ += 4; break;
      }
      default: throw std::runtime_error("unsupported Meshtastic protobuf wire type");
    }
    return true;
  }

 private:
  void require(std::uint64_t count) const {
    if (count > bytes_.size() - offset_) throw std::runtime_error("truncated Meshtastic protobuf");
  }
  std::uint64_t varint() {
    std::uint64_t value = 0;
    for (unsigned shift = 0; shift < 64; shift += 7) {
      require(1); const auto byte = static_cast<unsigned char>(bytes_[offset_++]);
      value |= static_cast<std::uint64_t>(byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return value;
    }
    throw std::runtime_error("oversized Meshtastic protobuf varint");
  }
  std::string_view bytes_;
  std::size_t offset_{};
};

float as_float(std::uint32_t bits) {
  float value{}; std::memcpy(&value, &bits, sizeof(value)); return value;
}

struct DeviceMetrics {
  std::optional<unsigned> battery;
  std::optional<float> voltage, channel_utilization, air_utilization;
  std::optional<unsigned> uptime;
};

DeviceMetrics parse_metrics(std::string_view bytes) {
  DeviceMetrics result; ProtoReader reader(bytes); Field field;
  while (reader.next(field)) {
    if (field.number == 1 && field.wire == 0) result.battery = static_cast<unsigned>(field.integer);
    else if (field.number == 2 && field.wire == 5) result.voltage = as_float(field.fixed32);
    else if (field.number == 3 && field.wire == 5) result.channel_utilization = as_float(field.fixed32);
    else if (field.number == 4 && field.wire == 5) result.air_utilization = as_float(field.fixed32);
    else if (field.number == 5 && field.wire == 0) result.uptime = static_cast<unsigned>(field.integer);
  }
  return result;
}

struct User {
  std::string id, long_name, short_name;
  unsigned hardware{}, role{};
};

User parse_user(std::string_view bytes) {
  User result; ProtoReader reader(bytes); Field field;
  while (reader.next(field)) {
    if (field.number == 1 && field.wire == 2) result.id = std::string(field.bytes);
    else if (field.number == 2 && field.wire == 2) result.long_name = std::string(field.bytes);
    else if (field.number == 3 && field.wire == 2) result.short_name = std::string(field.bytes);
    else if (field.number == 5 && field.wire == 0) result.hardware = static_cast<unsigned>(field.integer);
    else if (field.number == 7 && field.wire == 0) result.role = static_cast<unsigned>(field.integer);
  }
  return result;
}

struct Node {
  std::uint32_t number{};
  User user;
  std::optional<float> snr;
  std::optional<std::uint32_t> last_heard, hops;
  DeviceMetrics metrics;
  bool via_mqtt{};
};

Node parse_node(std::string_view bytes) {
  Node result; ProtoReader reader(bytes); Field field;
  while (reader.next(field)) {
    if (field.number == 1 && field.wire == 0) result.number = static_cast<std::uint32_t>(field.integer);
    else if (field.number == 2 && field.wire == 2) result.user = parse_user(field.bytes);
    else if (field.number == 4 && field.wire == 5) result.snr = as_float(field.fixed32);
    else if (field.number == 5 && field.wire == 5) result.last_heard = field.fixed32;
    else if (field.number == 6 && field.wire == 2) result.metrics = parse_metrics(field.bytes);
    else if (field.number == 8 && field.wire == 0) result.via_mqtt = field.integer != 0;
    else if (field.number == 9 && field.wire == 0) result.hops = static_cast<std::uint32_t>(field.integer);
  }
  return result;
}

struct Snapshot {
  std::uint32_t local_number{}, expected_nodes{}, completed_id{};
  unsigned reboot_count{}, minimum_app_version{}, hardware{}, role{};
  std::string firmware, environment;
  std::vector<Node> nodes;
};

void parse_my_info(std::string_view bytes, Snapshot& result) {
  ProtoReader reader(bytes); Field field;
  while (reader.next(field)) {
    if (field.number == 1 && field.wire == 0) result.local_number = static_cast<std::uint32_t>(field.integer);
    else if (field.number == 8 && field.wire == 0) result.reboot_count = static_cast<unsigned>(field.integer);
    else if (field.number == 11 && field.wire == 0) result.minimum_app_version = static_cast<unsigned>(field.integer);
    else if (field.number == 13 && field.wire == 2) result.environment = std::string(field.bytes);
    else if (field.number == 15 && field.wire == 0) result.expected_nodes = static_cast<std::uint32_t>(field.integer);
  }
}

void parse_metadata(std::string_view bytes, Snapshot& result) {
  ProtoReader reader(bytes); Field field;
  while (reader.next(field)) {
    if (field.number == 1 && field.wire == 2) result.firmware = std::string(field.bytes);
    else if (field.number == 7 && field.wire == 0) result.role = static_cast<unsigned>(field.integer);
    else if (field.number == 9 && field.wire == 0) result.hardware = static_cast<unsigned>(field.integer);
  }
}

void parse_from_radio(std::string_view bytes, Snapshot& result) {
  ProtoReader reader(bytes); Field field;
  while (reader.next(field)) {
    if (field.number == 3 && field.wire == 2) parse_my_info(field.bytes, result);
    else if (field.number == 4 && field.wire == 2) result.nodes.push_back(parse_node(field.bytes));
    else if (field.number == 7 && field.wire == 0) result.completed_id = static_cast<std::uint32_t>(field.integer);
    else if (field.number == 13 && field.wire == 2) parse_metadata(field.bytes, result);
  }
}

std::string encode_varint(std::uint64_t value) {
  std::string bytes;
  do { unsigned char byte = value & 0x7f; value >>= 7; if (value) byte |= 0x80; bytes.push_back(static_cast<char>(byte)); } while (value);
  return bytes;
}

class Socket {
 public:
  Socket() : value_(::socket(AF_INET, SOCK_STREAM, 0)) { if (value_ < 0) throw std::runtime_error("cannot create Meshtastic socket"); }
  ~Socket() { if (value_ >= 0) ::close(value_); }
  int get() const { return value_; }
 private:
  int value_;
};

void connect_with_timeout(int socket, const std::string& address, unsigned port) {
  sockaddr_in endpoint{}; endpoint.sin_family = AF_INET; endpoint.sin_port = htons(static_cast<std::uint16_t>(port));
  if (::inet_pton(AF_INET, address.c_str(), &endpoint.sin_addr) != 1) throw std::runtime_error("Meshtastic endpoint must be an IPv4 address");
  const int flags = ::fcntl(socket, F_GETFL, 0); ::fcntl(socket, F_SETFL, flags | O_NONBLOCK);
  const int connected = ::connect(socket, reinterpret_cast<sockaddr*>(&endpoint), sizeof(endpoint));
  if (connected != 0 && errno != EINPROGRESS) throw std::runtime_error("cannot connect to Meshtastic TCP service");
  if (connected != 0) {
    pollfd descriptor{socket, POLLOUT, 0};
    if (::poll(&descriptor, 1, 2500) <= 0) throw std::runtime_error("Meshtastic TCP connect timed out");
    int error = 0; socklen_t size = sizeof(error);
    if (::getsockopt(socket, SOL_SOCKET, SO_ERROR, &error, &size) != 0 || error != 0) throw std::runtime_error("cannot connect to Meshtastic TCP service");
  }
  ::fcntl(socket, F_SETFL, flags);
}

void send_all(int socket, std::string_view bytes) {
  while (!bytes.empty()) {
    const auto count = ::send(socket, bytes.data(), bytes.size(), 0);
    if (count <= 0) throw std::runtime_error("Meshtastic TCP write failed");
    bytes.remove_prefix(static_cast<std::size_t>(count));
  }
}

Snapshot request_snapshot(const std::string& address, unsigned port, std::uint32_t request_id) {
  Socket socket; connect_with_timeout(socket.get(), address, port);
  const std::string wake(32, static_cast<char>(start2)); send_all(socket.get(), wake);
  std::this_thread::sleep_for(std::chrono::milliseconds(100));
  const auto protobuf = std::string(1, static_cast<char>(3u << 3)) + encode_varint(request_id);
  std::string frame{static_cast<char>(start1), static_cast<char>(start2),
                    static_cast<char>((protobuf.size() >> 8) & 0xff), static_cast<char>(protobuf.size() & 0xff)};
  frame += protobuf; send_all(socket.get(), frame);

  Snapshot snapshot; std::string buffer;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(6);
  while (std::chrono::steady_clock::now() < deadline && snapshot.completed_id != request_id) {
    const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now()).count();
    pollfd descriptor{socket.get(), POLLIN, 0};
    const int ready = ::poll(&descriptor, 1, static_cast<int>(std::max<std::int64_t>(1, remaining)));
    if (ready < 0) throw std::runtime_error("Meshtastic TCP read failed");
    if (ready == 0) break;
    std::array<char, 4096> bytes{}; const auto count = ::recv(socket.get(), bytes.data(), bytes.size(), 0);
    if (count <= 0) break; buffer.append(bytes.data(), static_cast<std::size_t>(count));
    while (true) {
      const auto marker = buffer.find(std::string{static_cast<char>(start1), static_cast<char>(start2)});
      if (marker == std::string::npos) { if (buffer.size() > 1) buffer.erase(0, buffer.size() - 1); break; }
      if (marker) buffer.erase(0, marker);
      if (buffer.size() < 4) break;
      const std::size_t length = (static_cast<unsigned char>(buffer[2]) << 8) | static_cast<unsigned char>(buffer[3]);
      if (length > maximum_frame) { buffer.erase(0, 1); continue; }
      if (buffer.size() < length + 4) break;
      parse_from_radio(std::string_view(buffer).substr(4, length), snapshot); buffer.erase(0, length + 4);
    }
  }
  if (snapshot.completed_id != request_id) throw std::runtime_error("Meshtastic configuration snapshot timed out");
  return snapshot;
}

std::string hardware_name(unsigned value) {
  switch (value) {
    case 9: return "RAK4631"; case 12: return "LilyGo T-Beam S3 Core";
    case 16: return "LilyGo T-LoRa T3-S3"; case 24: return "Heltec Wireless Bridge";
    case 43: return "Heltec V3"; case 48: return "Heltec Wireless Tracker";
    case 69: return "Heltec Mesh Node T114"; case 71: return "Seeed Tracker T1000-E";
    default: return "Hardware model " + std::to_string(value);
  }
}

std::string role_name(unsigned value) {
  static constexpr std::array<const char*, 13> roles{"Client","Muted client","Router","Router/client","Repeater","Tracker","Sensor","TAK","Hidden client","Lost and found","TAK tracker","Late router","Client base"};
  return value < roles.size() ? roles[value] : "Role " + std::to_string(value);
}
}

PollResult poll_meshtastic(const nlohmann::json& device) {
  try {
    if (!device.contains("endpoints") || device["endpoints"].empty()) throw std::runtime_error("Meshtastic endpoint is missing");
    const auto& endpoint = device["endpoints"][0]; const auto address = endpoint.value("host", "");
    const auto config = device.value("config", nlohmann::json::object());
    const unsigned port = endpoint.value("port", config.value("service_port", 4403u));
    const auto request_id = static_cast<std::uint32_t>(now_ms()) | 1u;
    const auto snapshot = request_snapshot(address, port, request_id);
    const auto now_seconds = static_cast<std::uint32_t>(std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count());
    const auto* local = [&]() -> const Node* { for (const auto& node : snapshot.nodes) if (node.number == snapshot.local_number) return &node; return nullptr; }();
    std::size_t recent = 0, direct = 0, mqtt = 0; std::optional<std::uint32_t> last_activity;
    for (const auto& node : snapshot.nodes) {
      if (node.via_mqtt) ++mqtt;
      if (node.hops && *node.hops == 0) ++direct;
      if (node.number == snapshot.local_number || !node.last_heard) continue;
      const auto age = now_seconds >= *node.last_heard ? now_seconds - *node.last_heard : 0;
      if (age <= 86400) ++recent;
      if (!last_activity || age < *last_activity) last_activity = age;
    }
    std::vector<Observation> out{observation(device, "health", "responding"),
      observation(device, "mesh_role", role_name(snapshot.role)),
      observation(device, "node_count", snapshot.nodes.size(), "count"),
      observation(device, "recent_node_count", recent, "count"),
      observation(device, "direct_node_count", direct, "count"),
      observation(device, "mqtt_node_count", mqtt, "count"),
      observation(device, "firmware_version", snapshot.firmware),
      observation(device, "hardware_model", hardware_name(snapshot.hardware)),
      observation(device, "reboot_count", snapshot.reboot_count, "count"),
      observation(device, "minimum_app_version", snapshot.minimum_app_version, "count"),
      observation(device, "platform_environment", snapshot.environment),
      observation(device, "expected_node_count", snapshot.expected_nodes, "count")};
    if (last_activity) out.push_back(observation(device, "last_mesh_activity_age", *last_activity, "s"));
    if (local) {
      if (!local->user.long_name.empty()) out.push_back(observation(device, "local_node_name", local->user.long_name));
      if (!local->user.short_name.empty()) out.push_back(observation(device, "local_node_short_name", local->user.short_name));
      if (!local->user.id.empty()) out.push_back(observation(device, "local_node_id", local->user.id));
      if (local->snr) out.push_back(observation(device, "radio_snr", *local->snr, "dB"));
      if (local->metrics.battery && *local->metrics.battery <= 100) out.push_back(observation(device, "battery_level", *local->metrics.battery, "%"));
      if (local->metrics.voltage) out.push_back(observation(device, "voltage", *local->metrics.voltage, "V"));
      if (local->metrics.channel_utilization) out.push_back(observation(device, "channel_utilization", *local->metrics.channel_utilization, "%"));
      if (local->metrics.air_utilization) out.push_back(observation(device, "air_utilization", *local->metrics.air_utilization, "%"));
      if (local->metrics.uptime) out.push_back(observation(device, "radio_uptime", *local->metrics.uptime, "s"));
    }
    return {"responding", "", std::move(out)};
  } catch (const std::exception& error) {
    return {"unreachable", error.what(), {observation(device, "health", "unreachable")}};
  }
}
}
