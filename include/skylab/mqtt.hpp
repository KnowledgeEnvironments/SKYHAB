// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace skylab::mqtt {

struct Message { std::string topic; std::string payload; };

class Client {
 public:
  Client(std::string host, std::uint16_t port, std::string client_id,
         std::string username, std::string password);
  ~Client();
  Client(const Client&) = delete;
  Client& operator=(const Client&) = delete;

  void subscribe(const std::vector<std::string>& topics);
  void publish(std::string_view topic, std::string_view payload);
  std::vector<Message> receive_for(int milliseconds);

 private:
  int socket_{-1};
  std::uint16_t packet_id_{1};
  std::string buffer_;
  void send_packet(std::uint8_t type, std::string_view payload);
  std::vector<Message> drain_packets();
};

}  // namespace skylab::mqtt
