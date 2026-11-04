// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/mqtt.hpp"

#include <arpa/inet.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <chrono>
#include <stdexcept>

namespace skylab::mqtt {
namespace {
void append_string(std::string& out, std::string_view value) {
  if (value.size() > 65535) throw std::runtime_error("MQTT string is too long");
  out.push_back(static_cast<char>((value.size() >> 8) & 0xff));
  out.push_back(static_cast<char>(value.size() & 0xff));
  out.append(value);
}
void append_remaining(std::string& out, std::size_t value) {
  do { auto byte = static_cast<unsigned char>(value % 128); value /= 128;
    if (value) byte |= 0x80; out.push_back(static_cast<char>(byte)); } while (value);
}
void send_all(int fd, std::string_view bytes) {
  std::size_t offset = 0;
  while (offset < bytes.size()) { const auto sent = ::send(fd, bytes.data() + offset, bytes.size() - offset, 0);
    if (sent <= 0) throw std::runtime_error("MQTT socket write failed"); offset += static_cast<std::size_t>(sent); }
}
}

Client::Client(std::string host, std::uint16_t port, std::string client_id,
               std::string username, std::string password) {
  addrinfo hints{}; hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM;
  addrinfo* addresses = nullptr;
  const auto service = std::to_string(port);
  if (::getaddrinfo(host.c_str(), service.c_str(), &hints, &addresses) != 0)
    throw std::runtime_error("MQTT host resolution failed");
  for (auto* address = addresses; address; address = address->ai_next) {
    socket_ = ::socket(address->ai_family, address->ai_socktype, address->ai_protocol);
    if (socket_ >= 0 && ::connect(socket_, address->ai_addr, address->ai_addrlen) == 0) break;
    if (socket_ >= 0) ::close(socket_); socket_ = -1;
  }
  ::freeaddrinfo(addresses);
  if (socket_ < 0) throw std::runtime_error("MQTT connection failed");
  timeval timeout{4, 0}; ::setsockopt(socket_, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
  ::setsockopt(socket_, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

  // Dyson's embedded brokers use the original MQTT 3.1 wire identity. Some
  // newer units tolerate 3.1.1, while the RB01 rejects it during CONNACK.
  std::string payload; append_string(payload, "MQIsdp"); payload.push_back(3);
  payload.push_back(static_cast<char>(0xc2)); payload.push_back(0); payload.push_back(30);
  append_string(payload, client_id); append_string(payload, username); append_string(payload, password);
  send_packet(0x10, payload);
  char response[4]; const auto count = ::recv(socket_, response, sizeof(response), MSG_WAITALL);
  if (count != 4 || static_cast<unsigned char>(response[0]) != 0x20 || response[3] != 0)
    throw std::runtime_error("MQTT authentication failed");
}

Client::~Client() {
  if (socket_ >= 0) { try { send_packet(0xe0, {}); } catch (...) {} ::shutdown(socket_, SHUT_RDWR); ::close(socket_); }
}

void Client::send_packet(std::uint8_t type, std::string_view payload) {
  std::string packet; packet.push_back(static_cast<char>(type)); append_remaining(packet, payload.size()); packet.append(payload); send_all(socket_, packet);
}

void Client::subscribe(const std::vector<std::string>& topics) {
  std::string payload; const auto id = packet_id_++; payload.push_back(static_cast<char>(id >> 8)); payload.push_back(static_cast<char>(id));
  for (const auto& topic : topics) { append_string(payload, topic); payload.push_back(0); }
  send_packet(0x82, payload);
  char response[5]; const auto count = ::recv(socket_, response, sizeof(response), MSG_WAITALL);
  if (count < 5 || (static_cast<unsigned char>(response[0]) >> 4) != 9) throw std::runtime_error("MQTT subscribe failed");
}

void Client::publish(std::string_view topic, std::string_view payload) {
  std::string body; append_string(body, topic); const auto id = packet_id_++;
  body.push_back(static_cast<char>(id >> 8)); body.push_back(static_cast<char>(id));
  body.append(payload); send_packet(0x32, body);
}

std::vector<Message> Client::drain_packets() {
  std::vector<Message> out;
  while (buffer_.size() >= 2) {
    std::size_t remaining = 0, multiplier = 1, cursor = 1;
    unsigned char byte = 0;
    do { if (cursor >= buffer_.size() || cursor > 4) return out; byte = static_cast<unsigned char>(buffer_[cursor++]); remaining += (byte & 127) * multiplier; multiplier *= 128; } while (byte & 128);
    if (buffer_.size() < cursor + remaining) return out;
    const auto type = static_cast<unsigned char>(buffer_[0]) >> 4;
    if (type == 3 && remaining >= 2) {
      const auto topic_length = (static_cast<unsigned char>(buffer_[cursor]) << 8) | static_cast<unsigned char>(buffer_[cursor + 1]);
      auto data = cursor + 2;
      if (data + topic_length <= cursor + remaining) {
        std::string topic = buffer_.substr(data, topic_length); data += topic_length;
        const auto qos = (static_cast<unsigned char>(buffer_[0]) >> 1) & 3;
        if (qos && data + 2 <= cursor + remaining) data += 2;
        out.push_back({std::move(topic), buffer_.substr(data, cursor + remaining - data)});
      }
    }
    buffer_.erase(0, cursor + remaining);
  }
  return out;
}

std::vector<Message> Client::receive_for(int milliseconds) {
  std::vector<Message> out; const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(milliseconds);
  while (std::chrono::steady_clock::now() < deadline) {
    const auto left = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now()).count();
    pollfd descriptor{socket_, POLLIN, 0}; const auto ready = ::poll(&descriptor, 1, static_cast<int>(left));
    if (ready <= 0) break; char bytes[8192]; const auto count = ::recv(socket_, bytes, sizeof(bytes), 0); if (count <= 0) break;
    buffer_.append(bytes, static_cast<std::size_t>(count)); auto messages = drain_packets();
    out.insert(out.end(), std::make_move_iterator(messages.begin()), std::make_move_iterator(messages.end()));
  }
  return out;
}

}  // namespace skylab::mqtt
