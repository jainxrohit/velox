#!/usr/bin/env bash
# Validates the Nimble dependency PR (branch nimble-cmake-deps).
#   ./test-nimble-deps.sh [path-to-velox-checkout]
set -uo pipefail

VELOX="${1:-}"
if [[ -z "$VELOX" ]]; then
  for c in "$HOME/velox" "$HOME/source/velox" "$HOME/src/velox" "$PWD"; do
    [[ -f "$c/CMakeLists.txt" && -d "$c/velox" ]] && VELOX="$c" && break
  done
fi
if [[ -z "$VELOX" ]]; then
  echo "FAIL: no velox checkout found; pass the path as \$1" >&2
  exit 1
fi
VELOX="$(cd "$VELOX" && pwd)"

echo "=============== ENVIRONMENT ==============="
echo "velox checkout : $VELOX"
cmake --version | head -1
${CXX:-c++} --version | head -1
echo "cores          : $(nproc)"
echo "free disk      : $(df -h "$HOME" | tail -1 | awk '{print $4}')"
lscpu 2>/dev/null | grep -E "^(Model name|Architecture|Flags)" | cut -c1-160

echo
echo "=============== CHECKOUT ==============="
git -C "$VELOX" fetch origin nimble-cmake-deps || { echo "FAIL: fetch"; exit 1; }
git -C "$VELOX" checkout -B nimble-cmake-deps origin/nimble-cmake-deps || { echo "FAIL: checkout"; exit 1; }
git -C "$VELOX" log --oneline -1

rc_harness=1
rc_on=1
rc_off=1

echo
echo "=============== TEST 1: dependency modules (bundled) ==============="
# Exercises all three modules through Velox's own resolution machinery, plus
# end-to-end flatc codegen via build_flatbuffers(). Independent of whether the
# rest of Velox's dependencies are installed on this host.
H=/tmp/nimble-dep-harness
rm -rf "$H" && mkdir -p "$H" && cd "$H"

cat >Sample.fbs <<'EOF'
namespace harness;
table Thing { id:int; name:string; }
root_type Thing;
EOF

cat >main.cpp <<'EOF'
#include <cstdio>
#include "SampleGenerated.h"
#include <fsst.h>
#include "openzl/cpp/CCtx.hpp"

int main() {
  flatbuffers::FlatBufferBuilder fbb;
  auto name = fbb.CreateString("nimble");
  harness::ThingBuilder tb(fbb);
  tb.add_id(42);
  tb.add_name(name);
  fbb.Finish(tb.Finish());
  const auto* t = harness::GetThing(fbb.GetBufferPointer());
  printf("  flatbuffers ok: id=%d name=%s\n", t->id(), t->name()->c_str());

  unsigned char in[] = "hello hello hello fsst fsst fsst";
  size_t inLen = sizeof(in) - 1;
  unsigned char* inPtr = in;
  size_t outLens[1];
  unsigned char* outPtrs[1];
  unsigned char buf[512];
  unsigned char serial[FSST_MAXHEADER];
  fsst_encoder_t* enc =
      fsst_create(1, &inLen, (const unsigned char**)&inPtr, 0);
  size_t hdr = fsst_export(enc, serial);
  size_t n = fsst_compress(enc, 1, &inLen, (const unsigned char**)&inPtr,
                           sizeof(buf), buf, outLens, outPtrs);
  printf("  fsst ok: %zu string(s), %zu-byte header, %zu-byte payload\n",
         n, hdr, outLens[0]);
  fsst_destroy(enc);

  openzl::CCtx cctx;
  printf("  openzl ok: CCtx constructed\n");
  return 0;
}
EOF

cat >CMakeLists.txt <<EOF
cmake_minimum_required(VERSION 3.28)
project(nimble_dep_harness CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED TRUE)
list(PREPEND CMAKE_MODULE_PATH "$VELOX/CMake" "$VELOX/CMake/third-party")
include(ResolveDependency)

velox_set_source(flatbuffers)
velox_resolve_dependency(flatbuffers)
include(BuildFlatBuffers)
set(FLATBUFFERS_FLATC_SCHEMA_EXTRA_ARGS "--filename-suffix" "Generated")

velox_set_source(openzl)
velox_resolve_dependency(openzl)

velox_set_source(fsst)
velox_resolve_dependency(fsst)

build_flatbuffers("\${CMAKE_CURRENT_SOURCE_DIR}/Sample.fbs" "" harness_fb ""
                  "\${CMAKE_CURRENT_BINARY_DIR}" "" "")

add_executable(harness main.cpp)
add_dependencies(harness harness_fb)
target_include_directories(harness PRIVATE \${CMAKE_CURRENT_BINARY_DIR}
                                            \${FLATBUFFERS_INCLUDE_DIR})
target_link_libraries(harness PRIVATE flatbuffers fsst openzl_cpp openzl)
EOF

# BUNDLED forces the download-and-build path, which is the one under test.
if VELOX_DEPENDENCY_SOURCE=BUNDLED cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >configure.log 2>&1; then
  echo "  configure: OK"
  if cmake --build build -j "$(nproc)" >build.log 2>&1; then
    echo "  build: OK"
    if ./build/harness; then rc_harness=0; else echo "  RUN FAILED"; fi
  else
    echo "  BUILD FAILED - tail of $H/build.log:"; tail -30 build.log
  fi
else
  echo "  CONFIGURE FAILED - tail of $H/configure.log:"; tail -30 configure.log
fi

echo
echo "=============== TEST 2: velox configure, NIMBLE=ON ==============="
cd "$VELOX"
if cmake -S . -B /tmp/velox-nimble-on -DCMAKE_BUILD_TYPE=Release \
     -DVELOX_ENABLE_NIMBLE=ON -DVELOX_BUILD_TESTING=OFF >/tmp/velox-on.log 2>&1; then
  echo "  configure: OK"
  grep -E "Using (SYSTEM|BUNDLED) (flatbuffers|openzl|fsst)" /tmp/velox-on.log | sed 's/^/  /'
  rc_on=0
else
  echo "  CONFIGURE FAILED - tail of /tmp/velox-on.log:"; tail -30 /tmp/velox-on.log
fi

echo
echo "=============== TEST 3: velox configure, NIMBLE=OFF (regression) ==============="
if cmake -S . -B /tmp/velox-nimble-off -DCMAKE_BUILD_TYPE=Release \
     -DVELOX_BUILD_TESTING=OFF >/tmp/velox-off.log 2>&1; then
  echo "  configure: OK"
  if grep -qE "flatbuffers|openzl|fsst" /tmp/velox-off.log; then
    echo "  UNEXPECTED: nimble deps mentioned with the flag off:"
    grep -nE "flatbuffers|openzl|fsst" /tmp/velox-off.log | sed 's/^/    /'
  else
    echo "  no nimble deps resolved, as expected"
    rc_off=0
  fi
else
  echo "  CONFIGURE FAILED - tail of /tmp/velox-off.log:"; tail -30 /tmp/velox-off.log
fi

echo
echo "=============== SUMMARY ==============="
printf "  dependency harness (build+run) : %s\n" "$([[ $rc_harness -eq 0 ]] && echo PASS || echo FAIL)"
printf "  velox configure NIMBLE=ON      : %s\n" "$([[ $rc_on -eq 0 ]] && echo PASS || echo FAIL)"
printf "  velox configure NIMBLE=OFF     : %s\n" "$([[ $rc_off -eq 0 ]] && echo PASS || echo FAIL)"
exit $(( rc_harness | rc_on | rc_off ))
