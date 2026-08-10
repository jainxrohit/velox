#!/usr/bin/env bash
# Minimal toolchain for the Nimble dependency harness (Test 1). This is NOT the
# full Velox dependency set -- scripts/setup-ubuntu.sh is still required before
# a real Velox configure (Tests 2 and 3) will work.
set -euo pipefail

CMAKE_VERSION=4.3.2
CMAKE_SHA256=791ae3604841ca03cb3889a3ad89165346e4b180ae3448efd4b0caa9ef46d245

echo "=============== OS ==============="
. /etc/os-release && echo "$PRETTY_NAME"

echo "=============== APT PACKAGES ==============="
sudo apt-get update -qq
# g++-12 for solid C++20; falls back to the distro default if unavailable.
sudo apt-get install -y -qq build-essential ninja-build git curl ca-certificates pkg-config
if apt-cache show g++-12 >/dev/null 2>&1; then
  sudo apt-get install -y -qq gcc-12 g++-12
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 120
fi

echo "=============== CMAKE ${CMAKE_VERSION} ==============="
# Distro cmake is older than the 3.28 Velox requires. Installing 4.x on purpose:
# it matches what scripts/setup-centos9.sh provisions, and it is the version
# that rejects FSST's cmake_minimum_required(VERSION 3.0), so it exercises the
# CMAKE_POLICY_VERSION_MINIMUM workaround rather than hiding it.
if [[ "$(cmake --version 2>/dev/null | head -1)" != "cmake version ${CMAKE_VERSION}" ]]; then
  tmp=$(mktemp -d)
  curl -sSL -o "$tmp/cmake.tar.gz" \
    "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
  echo "${CMAKE_SHA256}  $tmp/cmake.tar.gz" | sha256sum -c -
  sudo mkdir -p /opt/cmake
  sudo tar xzf "$tmp/cmake.tar.gz" -C /opt/cmake --strip-components=1
  sudo ln -sf /opt/cmake/bin/cmake /usr/local/bin/cmake
  sudo ln -sf /opt/cmake/bin/ctest /usr/local/bin/ctest
  rm -rf "$tmp"
fi

echo "=============== VERSIONS ==============="
cmake --version | head -1
c++ --version | head -1
ninja --version | sed 's/^/ninja /'
git --version
echo
echo "Toolchain ready. Now run:  bash scripts/tests/test-nimble-deps.sh"
