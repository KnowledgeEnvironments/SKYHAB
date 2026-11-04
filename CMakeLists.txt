# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

cmake_minimum_required(VERSION 3.24)
project(skyhab VERSION 1.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(nlohmann_json INTERFACE)
target_include_directories(nlohmann_json INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/third_party)
add_library(nlohmann_json::nlohmann_json ALIAS nlohmann_json)
find_package(SQLite3 REQUIRED)
find_package(Threads REQUIRED)

add_library(skywire src/skywire.cpp)
target_include_directories(skywire PUBLIC include)
target_compile_options(skywire PRIVATE -Wall -Wextra -Wpedantic)

add_library(skylab_core src/inventory.cpp src/telemetry.cpp src/mqtt.cpp src/dyson.cpp src/ephemeris.cpp src/meshtastic.cpp src/adapters.cpp src/auth.cpp src/secrets.cpp src/presentation.cpp)
target_include_directories(skylab_core PUBLIC include)
target_link_libraries(skylab_core PUBLIC skywire nlohmann_json::nlohmann_json SQLite::SQLite3)
target_compile_definitions(skylab_core PUBLIC SKYL_VERSION="${PROJECT_VERSION}")
target_compile_options(skylab_core PRIVATE -Wall -Wextra -Wpedantic)

add_executable(skyhabd src/daemon.cpp)
target_link_libraries(skyhabd PRIVATE skylab_core Threads::Threads)

add_executable(skyhabctl src/cli.cpp)
target_link_libraries(skyhabctl PRIVATE skywire nlohmann_json::nlohmann_json)
target_compile_definitions(skyhabctl PRIVATE SKYL_VERSION="${PROJECT_VERSION}")

enable_testing()
add_executable(skywire_tests tests/skywire_tests.cpp)
target_link_libraries(skywire_tests PRIVATE skywire)
add_test(NAME skywire_tests COMMAND skywire_tests)
add_test(NAME example_inventory COMMAND ${CMAKE_COMMAND} -E env python3 ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_inventory.py ${CMAKE_CURRENT_SOURCE_DIR})
add_test(NAME presentation_contract COMMAND ${CMAKE_COMMAND} -E env python3 ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_presentation.py ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS skyhabd skyhabctl RUNTIME DESTINATION bin)
