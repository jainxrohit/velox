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

# FSST has no releases or tags, so this pins the commit the standalone Nimble
# repository already builds against. Note that the source archive is ~32MB: most
# of it is the authors' paper and presentation media, not code.
set(VELOX_FSST_VERSION 50dd308befd5121bd1121428a833f42cce6e1f9d)
set(
  VELOX_FSST_BUILD_SHA256_CHECKSUM
  3b14f636acbcfca7092e42664bf0a7139907c526963b1e227a6d6659e2bbedc1
)
string(
  CONCAT
  VELOX_FSST_SOURCE_URL
  "https://github.com/cwida/fsst/archive/"
  "${VELOX_FSST_VERSION}.tar.gz"
)

velox_resolve_dependency_url(FSST)

message(STATUS "Building FSST from source")

# FSST declares cmake_minimum_required(VERSION 3.0), which CMake 4 rejects
# outright. The setup scripts install CMake 4.x, so this is required, not
# defensive.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

# FSST appends -march=native whenever the compiler accepts it, which would
# override the architecture flags Velox derives from CPU_TARGET and produce
# binaries that fault on other hosts. check_cxx_compiler_flag() skips its probe
# when the result variable is already cached, so seeding it disables the flag
# without patching FSST. The consequence is that FSST's AVX-512 path is only
# compiled when the toolchain baseline already enables it.
set(COMPILER_SUPPORTS_MARCH_NATIVE FALSE CACHE INTERNAL "Disabled for FSST")

# EXCLUDE_FROM_ALL keeps FSST's `binary`, `binary12` and `fsst12` targets out of
# the build; only the `fsst` library is linked, so only it gets built.
FetchContent_Declare(
  fsst
  URL ${VELOX_FSST_SOURCE_URL}
  URL_HASH ${VELOX_FSST_BUILD_SHA256_CHECKSUM}
  OVERRIDE_FIND_PACKAGE
  SYSTEM
  EXCLUDE_FROM_ALL
)

FetchContent_MakeAvailable(fsst)

# FSST sets no include directories of its own; fsst.h sits at the source root.
if(TARGET fsst)
  target_include_directories(fsst SYSTEM PUBLIC "${fsst_SOURCE_DIR}")
endif()
