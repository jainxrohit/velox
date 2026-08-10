# Copyright (c) Facebook, Inc. and its affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
include_guard(GLOBAL)

set(VELOX_FLATBUFFERS_VERSION 25.9.23)
set(
  VELOX_FLATBUFFERS_BUILD_SHA256_CHECKSUM
  9102253214dea6ae10c2ac966ea1ed2155d22202390b532d1dea64935c518ada
)
string(
  CONCAT
  VELOX_FLATBUFFERS_SOURCE_URL
  "https://github.com/google/flatbuffers/archive/refs/tags/"
  "v${VELOX_FLATBUFFERS_VERSION}.tar.gz"
)

velox_resolve_dependency_url(FLATBUFFERS)

message(STATUS "Building FlatBuffers from source")

# The flatc code generator is required, not just the runtime library: Nimble
# generates C++ headers from .fbs schemas at build time via build_flatbuffers().
# FlatBuffers exports flatc as both the `flatc` target and the
# `flatbuffers::flatc` alias, which build_flatbuffers() picks up on its own, so
# there is no need to set FLATBUFFERS_FLATC_EXECUTABLE here.
set(FLATBUFFERS_BUILD_FLATC ON)
set(FLATBUFFERS_BUILD_FLATLIB ON)
set(FLATBUFFERS_BUILD_SHAREDLIB OFF)
set(FLATBUFFERS_BUILD_FLATHASH OFF)
set(FLATBUFFERS_BUILD_TESTS OFF)
set(FLATBUFFERS_INSTALL OFF)

FetchContent_Declare(
  flatbuffers
  URL ${VELOX_FLATBUFFERS_SOURCE_URL}
  URL_HASH ${VELOX_FLATBUFFERS_BUILD_SHA256_CHECKSUM}
  OVERRIDE_FIND_PACKAGE
  SYSTEM
  EXCLUDE_FROM_ALL
)

FetchContent_MakeAvailable(flatbuffers)

# Consumers written against a system FlatBuffers use FLATBUFFERS_INCLUDE_DIR,
# which only FindFlatBuffers.cmake defines. Export it for the bundled build too
# so the same target_include_directories() call works either way.
set(
  FLATBUFFERS_INCLUDE_DIR
  "${flatbuffers_SOURCE_DIR}/include"
  CACHE INTERNAL
  "FlatBuffers include directory"
)
