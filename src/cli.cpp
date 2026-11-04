// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/skywire.hpp"

#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <cctype>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <nlohmann/json.hpp>

namespace {
bool send_all(int fd, std::string_view data) {
  while (!data.empty()) { auto n = send(fd, data.data(), data.size(), 0); if (n <= 0) return false; data.remove_prefix(n); }
  return true;
}
skylab::wire::Message receive(int fd, skylab::wire::Decoder& decoder) {
  char bytes[8192];
  while (true) {
    if (auto message = decoder.next()) return *message;
    auto n = recv(fd, bytes, sizeof(bytes), 0); if (n <= 0) throw std::runtime_error("connection closed");
    decoder.feed(std::string_view(bytes, n));
    if (decoder.failed()) throw std::runtime_error(decoder.error());
  }
}
nlohmann::json response_json(const skylab::wire::Message& m) {
  if (m.size() >= 6 && m[2] == "OK" && m[4] == "json" && !m[5].empty()) return nlohmann::json::parse(m[5].substr(1));
  if (m.size() >= 6 && m[2] == "ERR") throw std::runtime_error(m[5]);
  throw std::runtime_error("unexpected response");
}
std::string base64_encode(std::string_view input) {
  static constexpr char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out; out.reserve((input.size() + 2) / 3 * 4);
  for (std::size_t i = 0; i < input.size(); i += 3) {
    const auto a = static_cast<unsigned char>(input[i]); const auto b = i + 1 < input.size() ? static_cast<unsigned char>(input[i + 1]) : 0;
    const auto c = i + 2 < input.size() ? static_cast<unsigned char>(input[i + 2]) : 0;
    out += table[a >> 2]; out += table[((a & 3) << 4) | (b >> 4)];
    out += i + 1 < input.size() ? table[((b & 15) << 2) | (c >> 6)] : '='; out += i + 2 < input.size() ? table[c & 63] : '=';
  }
  return out;
}
std::string base64_decode(std::string_view input) {
  auto value = [](unsigned char c) -> int { if (c >= 'A' && c <= 'Z') return c - 'A'; if (c >= 'a' && c <= 'z') return c - 'a' + 26; if (c >= '0' && c <= '9') return c - '0' + 52; if (c == '+') return 62; if (c == '/') return 63; return -1; };
  if (input.empty() || input.size() % 4) throw std::runtime_error("invalid photo encoding");
  std::string out; out.reserve(input.size() / 4 * 3);
  for (std::size_t i = 0; i < input.size(); i += 4) {
    const int a = value(input[i]), b = value(input[i + 1]), c = input[i + 2] == '=' ? -2 : value(input[i + 2]), d = input[i + 3] == '=' ? -2 : value(input[i + 3]);
    if (a < 0 || b < 0 || c == -1 || d == -1 || (c == -2 && d != -2)) throw std::runtime_error("invalid photo encoding");
    out += static_cast<char>((a << 2) | (b >> 4)); if (c >= 0) out += static_cast<char>(((b & 15) << 4) | (c >> 2)); if (d >= 0) out += static_cast<char>(((c & 3) << 6) | d);
  }
  return out;
}

void usage(std::ostream& out) {
  out << "skyhabctl " << SKYL_VERSION << " — JSON-first client for skyhabd\n\n"
      << "Usage:\n"
      << "  skyhabctl COMMAND [ARGUMENTS] [--json] [connection options]\n\n"
      << "Read commands:\n"
      << "  status | state | ping | describe | resources | devices\n"
      << "  relationships | classes | views | view VIEW_ID\n"
      << "  audit [LIMIT] | events [LIMIT] | files RESOURCE [LIMIT]\n\n"
      << "Mutation commands:\n"
      << "  action RESOURCE ACTION [PARAMETERS_JSON]\n"
      << "  rename|comment|asset-tag|notes|room|group RESOURCE VALUE\n"
      << "  pin|unpin RESOURCE\n"
      << "  photo-get RESOURCE OUTPUT_FILE\n"
      << "  photo-set RESOURCE JPEG_OR_PNG_FILE\n"
      << "  photo-delete RESOURCE\n\n"
      << "Options:\n"
      << "  --host ADDRESS  --port PORT  --client ID  --token TOKEN  --json\n"
      << "  --help  --version\n\n"
      << "Authentication uses --token, SKYHAB_TOKEN, legacy SKYLAB_TOKEN, or the\n"
      << "mode-0600 skyhabctl token file in Application Support.\n";
}
}

int main(int argc, char** argv) {
  std::string host = "127.0.0.1", token, client = "skyhabctl", command = argc > 1 ? argv[1] : "status";
  if (command == "--help" || command == "-h" || command == "help") { usage(std::cout); return 0; }
  if (command == "--version" || command == "version") { std::cout << "skyhabctl " << SKYL_VERSION << '\n'; return 0; }
  int port = 3636; bool json = false; std::string photo_output;
  std::vector<std::string> positional;
  for (int i = 2; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg == "--host" && i + 1 < argc) host = argv[++i];
    else if (arg == "--port" && i + 1 < argc) port = std::stoi(argv[++i]);
    else if (arg == "--token" && i + 1 < argc) token = argv[++i];
    else if (arg == "--client" && i + 1 < argc) client = argv[++i];
    else if (arg == "--json") json = true;
    else positional.push_back(arg);
  }
  if (token.empty()) { if (const char* env = std::getenv("SKYHAB_TOKEN")) token = env; }
  if (token.empty()) { if (const char* env = std::getenv("SKYLAB_TOKEN")) token = env; }
  if (token.empty()) if (const char* home = std::getenv("HOME")) {
    const auto load_token = [](const std::string& path) {
      std::ifstream input(path); std::string value; std::getline(input, value); return value;
    };
    const std::string support = std::string(home) + "/Library/Application Support/";
    token = load_token(support + "skyHAB/skyhabctl.token");
    if (token.empty()) token = load_token(support + "skyLAB/skyhabctl.token");
    if (token.empty()) {
      token = load_token(support + "skyHAB/skylabctl.token");
      if (token.empty()) token = load_token(support + "skyLAB/skylabctl.token");
      if (!token.empty() && client == "skyhabctl") client = "skylabctl";
    }
  }
  try {
    int fd = socket(AF_INET, SOCK_STREAM, 0); sockaddr_in addr{}; addr.sin_family = AF_INET; addr.sin_port = htons(port);
    if (inet_pton(AF_INET, host.c_str(), &addr.sin_addr) != 1 || connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0)
      throw std::runtime_error("cannot connect to skyhabd");
    skylab::wire::Decoder decoder; (void)receive(fd, decoder);
    auto request = [&](skylab::wire::Message m) { send_all(fd, skylab::wire::encode(m)); return response_json(receive(fd, decoder)); };
    if (command == "ping") { auto v = request({"Q","1","PING"}); std::cout << v.dump(json ? 2 : -1) << '\n'; return 0; }
    auto auth = request({"Q","1","AUTH","client",skylab::wire::typed_string(client),"token",skylab::wire::typed_string(token)}); (void)auth;
    nlohmann::json result;
    if (command == "devices" || command == "resources") result = request({"Q","2","RESOURCE.LIST"});
    else if (command == "relationships") result = request({"Q","2","RELATIONSHIP.LIST"});
    else if (command == "views") result = request({"Q","2","VIEW.LIST"});
    else if (command == "view") {
      if (positional.empty()) throw std::runtime_error("usage: skyhabctl view VIEW_ID");
      result = request({"Q","2","VIEW.DESCRIBE","id",skylab::wire::typed_string(positional[0])});
    }
    else if (command == "describe") result = request({"Q","2","SERVICE.DESCRIBE"});
    else if (command == "classes") result = request({"Q","2","CLASS.LIST"});
    else if (command == "audit") result = request({"Q","2","AUDIT.LIST","limit",skylab::wire::typed_string(positional.empty() ? "100" : positional[0])});
    else if (command == "events") result = request({"Q","2","EVENT.LIST","limit",skylab::wire::typed_string(positional.empty() ? "100" : positional[0])});
    else if (command == "files") {
      if (positional.empty()) throw std::runtime_error("usage: skyhabctl files RESOURCE [LIMIT]");
      result = request({"Q","2","STORAGE.FILES","resource",skylab::wire::typed_string(positional[0]),
                        "limit",skylab::wire::typed_string(positional.size() > 1 ? positional[1] : "50")});
    }
    else if (command == "photo-get") {
      if (positional.size() < 2) throw std::runtime_error("usage: skyhabctl photo-get RESOURCE OUTPUT_FILE");
      result = request({"Q","2","ASSET.PHOTO.GET","resource",skylab::wire::typed_string(positional[0])}); photo_output = positional[1];
    } else if (command == "photo-set") {
      if (positional.size() < 2) throw std::runtime_error("usage: skyhabctl photo-set RESOURCE JPEG_OR_PNG_FILE");
      std::ifstream input(positional[1], std::ios::binary); const std::string bytes((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
      if (!input && bytes.empty()) throw std::runtime_error("cannot read photo file");
      auto lower = positional[1]; for (auto& c : lower) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
      const auto mime = lower.ends_with(".png") ? "image/png" : "image/jpeg";
      const auto inventory = request({"Q","2","INVENTORY.GET"}); const auto revision = std::to_string(inventory.at("revision").get<std::uint64_t>());
      result = request({"Q","3","ASSET.PHOTO.SET","resource",skylab::wire::typed_string(positional[0]),"revision",skylab::wire::typed_string(revision),"mime",skylab::wire::typed_string(mime),"data",skylab::wire::typed_string(base64_encode(bytes))});
    } else if (command == "photo-delete") {
      if (positional.empty()) throw std::runtime_error("usage: skyhabctl photo-delete RESOURCE");
      const auto inventory = request({"Q","2","INVENTORY.GET"}); const auto revision = std::to_string(inventory.at("revision").get<std::uint64_t>());
      result = request({"Q","3","ASSET.PHOTO.DELETE","resource",skylab::wire::typed_string(positional[0]),"revision",skylab::wire::typed_string(revision)});
    } else if (command == "action") {
      if (positional.size() < 2) throw std::runtime_error("usage: skyhabctl action RESOURCE ACTION [PARAMETERS_JSON]");
      result = request({"Q","2","ACTION.INVOKE","resource",skylab::wire::typed_string(positional[0]),"action",skylab::wire::typed_string(positional[1]),"parameters",skylab::wire::typed_string(positional.size() > 2 ? positional[2] : "{}")});
    } else if (command == "rename" || command == "comment" || command == "room" || command == "group" || command == "asset-tag" || command == "notes") {
      if (positional.size() < 2) throw std::runtime_error("usage: skyhabctl rename|comment|room|group|asset-tag|notes RESOURCE VALUE");
      const auto inventory = request({"Q","2","INVENTORY.GET"});
      const auto revision = std::to_string(inventory.at("revision").get<std::uint64_t>());
      const auto field_name = command == "rename" ? "pretty_name" : command == "asset-tag" ? "asset_tag" : command;
      nlohmann::json changes;
      if (command == "group") changes["groups"] = nlohmann::json::array({positional[1]});
      else changes[field_name] = positional[1];
      result = request({"Q","3","METADATA.PATCH","resource",skylab::wire::typed_string(positional[0]),"revision",skylab::wire::typed_string(revision),"changes",skylab::wire::typed_string(changes.dump())});
    } else if (command == "pin" || command == "unpin") {
      if (positional.empty()) throw std::runtime_error("usage: skyhabctl pin|unpin RESOURCE");
      const auto inventory = request({"Q","2","INVENTORY.GET"});
      const auto revision = std::to_string(inventory.at("revision").get<std::uint64_t>());
      result = request({"Q","3","PIN.SET","resource",skylab::wire::typed_string(positional[0]),"pinned",skylab::wire::typed_string(command == "pin" ? "true" : "false"),"revision",skylab::wire::typed_string(revision)});
    }
    else if (command == "status" || command == "state") result = request({"Q","2","STATE.GET"});
    else { usage(std::cerr); throw std::runtime_error("unknown command: " + command); }
    if (!photo_output.empty()) {
      const auto bytes = base64_decode(result.at("data").get<std::string>()); std::ofstream output(photo_output, std::ios::binary | std::ios::trunc); output.write(bytes.data(), static_cast<std::streamsize>(bytes.size())); if (!output) throw std::runtime_error("cannot write photo file");
      if (json) std::cout << nlohmann::json{{"ok",true},{"file",photo_output},{"mime",result.value("mime", "")}}.dump() << '\n';
      else std::cout << photo_output << '\n';
    } else if (json) std::cout << nlohmann::json{{"ok",true},{"data",result}}.dump() << '\n';
    else if (result.is_array()) for (const auto& row : result) std::cout << row.dump() << '\n';
    else std::cout << result.dump(2) << '\n';
    close(fd);
  } catch (const std::exception& e) { std::cerr << "skyhabctl: " << e.what() << '\n'; return 7; }
  return 0;
}
