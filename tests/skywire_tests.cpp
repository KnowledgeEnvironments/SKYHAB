// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/skywire.hpp"
#include <cassert>
#include <iostream>

int main() {
  using namespace skylab::wire;
  Message expected{"Q", "42", "PING", "echo", typed_string("hello\nold mac")};
  const auto bytes = encode(expected);
  Decoder decoder;
  for (char c : bytes) {
    decoder.feed(std::string_view(&c, 1));
    if (&c != &bytes.back()) assert(!decoder.failed());
  }
  auto actual = decoder.next(); assert(actual && *actual == expected);
  decoder.feed(encode({"Q","1","PING"}) + encode({"Q","2","PING"}));
  assert(decoder.next()->at(1) == "1"); assert(decoder.next()->at(1) == "2");
  Decoder bad; bad.feed("01:a,"); assert(!bad.next() && bad.failed());
  std::cout << "SkyWire tests passed\n";
}
