#!/bin/bash
# Matrix runner: $1 = generator, $2 = case filter (P=positive R=reject B=builderr A=all)
GEN="$1"; FILTER="${2:-A}"
SP="$(cd "$(dirname "$0")" && pwd)"
P="${ICE_PREFIX_DIR:-$(cd "$SP/.." && pwd)/real}"
ROOT="${MATRIX_ROOT:-$SP/f}"
PASS=0; FAIL=0; RESULTS=""

emit() { RESULTS="$RESULTS$1|$2\n"; [ "$2" = PASS ] || [ "${2#KNOWN}" != "$2" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1)); }

proj() { # $1=name $2=cmake-snippet
  local d="$ROOT/$1"; rm -rf "$d"; mkdir -p "$d"
  printf 'cmake_minimum_required(VERSION 3.21)\nproject(t CXX)\nfind_package(Ice REQUIRED CONFIG COMPONENTS Ice)\n%s\n' "$2" > "$d/CMakeLists.txt"
  echo "$d"
}
build() { # $1=dir -> 0 build ok+settled, 1 configure fail, 2 build fail, 3 no settle
  local d="$1" g="$GEN"
  rm -rf "$d/bld"
  cmake -S "$d" -B "$d/bld" -G "$g" -DCMAKE_PREFIX_PATH="$P" > "$d/cfg.log" 2>&1 || return 1
  cmake --build "$d/bld" > "$d/bld.log" 2>&1 || return 2
  local n; n=$(cmake --build "$d/bld" 2>&1 | grep -c "Compiling Slice")
  [ "$n" = 0 ] || return 3
  return 0
}
pcase() { # $1=name $2=dir
  case "$FILTER" in A|P) ;; *) return;; esac
  build "$2"; local rc=$?
  case $rc in 0) emit "$1" PASS;; 1) emit "$1" "FAIL(configure)";; 2) emit "$1" "FAIL(build)";; 3) emit "$1" "FAIL(no-settle)";; esac
}
rcase() { # $1=name $2=dir $3=expected-msg
  case "$FILTER" in A|R) ;; *) return;; esac
  local d="$2"
  rm -rf "$d/bld"
  if cmake -S "$d" -B "$d/bld" -G "$GEN" -DCMAKE_PREFIX_PATH="$P" > "$d/cfg.log" 2>&1; then emit "$1" "FAIL(accepted)"; return; fi
  if tr -d '\n' < "$d/cfg.log" | tr -s ' ' | grep -q "$3"; then emit "$1" PASS; else emit "$1" "FAIL(message)"; fi
}

ice() { mkdir -p "$(dirname "$1")"; printf '#pragma once\n%s\n' "$2" > "$1"; }
cpp() { printf '%s\nint main(){return 0;}\n' "$2" > "$1"; }

# ---------- positive cases ----------
d=$(proj p01-compat 'add_executable(app main.cpp slice/Hello.ice)
slice2cpp_generate(app)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/slice/Hello.ice" 'module C1 { struct S { int v; } }'; cpp "$d/main.cpp" '#include <Hello.h>'
pcase "P01 flat slice/, include <Hello.h> (main compat)" "$d"

d=$(proj p02-mirror-hod 'add_executable(app main.cpp Hello.ice sub/Types.ice)
slice2cpp_generate(app INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR} HEADER_OUTPUT_DIR ${CMAKE_BINARY_DIR}/inc)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/sub/Types.ice" 'module C2 { struct T { int v; } }'
ice "$d/Hello.ice" '#include "sub/Types.ice"
module C2 { interface H { void go(T t); } }'
cpp "$d/main.cpp" '#include <Hello.h>'
pcase "P02 mirror + HEADER_OUTPUT_DIR" "$d"

d=$(proj p03-incdir-flat 'add_executable(app main.cpp Thing.ice)
slice2cpp_generate(app INCLUDE_DIR Demo OPTIONS -DWITH_OP)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/Thing.ice" 'module C3 {
#if defined(WITH_OP)
interface I { void extra(); }
#endif
struct S { int v; } }'
cpp "$d/main.cpp" '#include <Demo/Thing.h>'
pcase "P03 INCLUDE_DIR flat + OPTIONS -D" "$d"

d=$(proj p04-docex 'add_executable(app main.cpp slice/pkg/Greeter.ice slice/pkg/Types.ice)
slice2cpp_generate(app INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/slice HEADER_OUTPUT_DIR ${CMAKE_BINARY_DIR}/include INCLUDE_DIR Demo INCLUDE_SCOPE PUBLIC)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/slice/pkg/Types.ice" 'module C4 { struct T { int v; } }'
ice "$d/slice/pkg/Greeter.ice" '#include <pkg/Types.ice>
module C4 { interface G { void go(T t); } }'
cpp "$d/main.cpp" '#include <Demo/pkg/Greeter.h>'
pcase "P04 doc example, nested pkg/ under -I root" "$d"

d=$(proj p05-5063 'add_executable(app main.cpp slice/Greeter.ice slice/Types.ice)
slice2cpp_generate(app INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/slice HEADER_OUTPUT_DIR ${CMAKE_BINARY_DIR}/inc INCLUDE_DIR Demo)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/slice/Types.ice" 'module C5 { struct T { int v; } }'
ice "$d/slice/Greeter.ice" '#include <Types.ice>
module C5 { interface G { void go(T t); } }'
cpp "$d/main.cpp" '#include <Demo/Greeter.h>
#include <Demo/Types.h>'
pcase "P05 #5063 shape (-I root + INCLUDE_DIR + HOD)" "$d"

d=$(proj p06-hodspace 'add_executable(app main.cpp Thing.ice)
slice2cpp_generate(app HEADER_OUTPUT_DIR "${CMAKE_BINARY_DIR}/out dir" INCLUDE_DIR Demo)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/Thing.ice" 'module C6 { struct S { int v; } }'
cpp "$d/main.cpp" '#include <Demo/Thing.h>'
pcase "P06 space in HEADER_OUTPUT_DIR" "$d"

d=$(proj p07-relinc 'add_executable(app main.cpp slice/Thing.ice)
slice2cpp_generate(app INCLUDE_DIRS slice)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/slice/Thing.ice" 'module C7 { struct S { int v; } }'
cpp "$d/main.cpp" '#include <Thing.h>'
pcase "P07 relative INCLUDE_DIRS" "$d"

d=$(proj p08-srcroot 'add_executable(app main.cpp ../A.ice Foo.ice)
slice2cpp_generate(app INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(app PRIVATE Ice::Ice)'); true
mkdir -p "$ROOT/p08-root"; mv "$d" "$ROOT/p08-root/sub" 2>/dev/null; d="$ROOT/p08-root/sub"
ice "$ROOT/p08-root/sub/Foo.ice" 'module C8 { struct F { int v; } }'
ice "$ROOT/p08-root/A.ice" '#include <sub/Foo.ice>
module C8 { interface A { void go(F f); } }'
cpp "$d/main.cpp" '#include <A.h>'
pcase "P08 ../A.ice from subdir, keeps sub/Foo.h" "$d"

d=$(proj p09-demoshape 'add_executable(app main.cpp Hello.ice Types.ice)
slice2cpp_generate(app)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/Types.ice" 'module C9 { struct T { int v; } }'
ice "$d/Hello.ice" '#include "Types.ice"
module C9 { interface H { void go(T t); } }'
cpp "$d/main.cpp" '#include <Hello.h>'
pcase "P09 ice-demos shape (flat, no args)" "$d"

d=$(proj p10-nested 'add_executable(app main.cpp src/Bar.ice src/x/Foo.ice)
slice2cpp_generate(app INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/src ${CMAKE_CURRENT_SOURCE_DIR}/src/x)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/src/x/Foo.ice" 'module CA { struct F { int v; } }'
ice "$d/src/Bar.ice" '#include <x/Foo.ice>
module CA { interface B { void go(F f); } }'
cpp "$d/main.cpp" '#include <Bar.h>'
pcase "P10 nested -I roots, exact root wins tie" "$d"

d=$(proj p11-dotver 'add_executable(app main.cpp Foo.v1.ice)
slice2cpp_generate(app)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/Foo.v1.ice" 'module CB { struct S { int v; } }'
cpp "$d/main.cpp" '#include <Foo.v1.h>'
pcase "P11 Foo.v1.ice (NAME_WLE)" "$d"

d=$(proj p12-metah 'add_executable(app main.cpp T.ice)
slice2cpp_generate(app)
target_link_libraries(app PRIVATE Ice::Ice)')
printf '[["cpp:header-ext:h"]]\n#pragma once\nmodule CC { struct S { int v; } }\n' > "$d/T.ice"
cpp "$d/main.cpp" '#include <T.h>'
pcase "P12 cpp:header-ext:h metadata (shipped-file pattern)" "$d"

d=$(proj p13-hppspace 'add_executable(app main.cpp T.ice)
slice2cpp_generate(app OPTIONS --header-ext hpp)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/T.ice" 'module CD { struct S { int v; } }'; cpp "$d/main.cpp" '#include <T.hpp>'
pcase "P13 OPTIONS --header-ext hpp" "$d"

d=$(proj p14-hxxeq 'add_executable(app main.cpp T.ice)
slice2cpp_generate(app OPTIONS --header-ext=hxx)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/T.ice" 'module CE { struct S { int v; } }'; cpp "$d/main.cpp" '#include <T.hxx>'
pcase "P14 OPTIONS --header-ext=hxx" "$d"

d=$(proj p15-srcext 'add_executable(app main.cpp T.ice)
slice2cpp_generate(app OPTIONS --source-ext cxx)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/T.ice" 'module CF { struct S { int v; } }'; cpp "$d/main.cpp" '#include <T.h>'
pcase "P15 OPTIONS --source-ext cxx" "$d"

d=$(proj p16-bothext 'add_executable(app main.cpp T.ice)
slice2cpp_generate(app OPTIONS --header-ext hpp --source-ext cxx)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/T.ice" 'module CG { struct S { int v; } }'; cpp "$d/main.cpp" '#include <T.hpp>'
pcase "P16 both extension options" "$d"

d=$(proj p17-metaopt 'add_executable(app main.cpp T.ice)
slice2cpp_generate(app OPTIONS --header-ext hpp)
target_link_libraries(app PRIVATE Ice::Ice)')
printf '[["cpp:header-ext:hpp"]]\n#pragma once\nmodule CH { struct S { int v; } }\n' > "$d/T.ice"
cpp "$d/main.cpp" '#include <T.hpp>'
pcase "P17 metadata hpp + matching option" "$d"

d=$(proj p18-relhod 'add_executable(app main.cpp slice/myproj/Types.ice)
slice2cpp_generate(app INCLUDE_DIRS slice HEADER_OUTPUT_DIR generated/include)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/slice/myproj/Types.ice" 'module CI { struct T { int v; } }'
mkdir -p "$d/include/myproj"; echo "SENTINEL" > "$d/include/myproj/Types.h"
cpp "$d/main.cpp" '#include <myproj/Types.h>'
case "$FILTER" in A|P)
  build "$d"; rc=$?
  if [ $rc = 0 ] && grep -q SENTINEL "$d/include/myproj/Types.h" && [ ! -d "$d/generated" ] && [ -f "$d/bld/generated/include/myproj/Types.h" ]; then
    emit "P18 relative HEADER_OUTPUT_DIR -> build tree, source untouched" PASS
  else emit "P18 relative HEADER_OUTPUT_DIR" "FAIL(rc=$rc)"; fi;;
esac

d=$(proj p19-guards 'add_executable(app main.cpp root/pkg/Greeter.ice root/other/Greeter.ice)
slice2cpp_generate(app INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/root)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/root/pkg/Greeter.ice" 'module PK { struct G { int a; } }'
ice "$d/root/other/Greeter.ice" 'module OT { struct G { int b; } }'
cpp "$d/main.cpp" '#include <pkg/Greeter.h>
#include <other/Greeter.h>
static PK::G a; static OT::G b;'
pcase "P19 same basename, both headers included (guards)" "$d"

d=$(proj p20-overlap 'add_executable(ta m.cpp a/pkg/X.ice)
slice2cpp_generate(ta INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/a HEADER_OUTPUT_DIR ${CMAKE_BINARY_DIR}/inc INCLUDE_DIR pkga)
target_link_libraries(ta PRIVATE Ice::Ice)
add_executable(tb m.cpp b/pkg/X.ice b/pkg/Main.ice)
slice2cpp_generate(tb INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/b HEADER_OUTPUT_DIR ${CMAKE_BINARY_DIR}/inc INCLUDE_DIR Demo)
target_link_libraries(tb PRIVATE Ice::Ice)')
ice "$d/a/pkg/X.ice" 'module OV { struct X { int a; } }'
ice "$d/b/pkg/X.ice" 'module OV { struct X { int a; string bb; } }'
ice "$d/b/pkg/Main.ice" '#include <pkg/X.ice>
module OV { interface M { void put(X x); } }'
cpp "$d/m.cpp" ''
pcase "P20 overlapping header roots bind own header" "$d"

d=$(proj p21-twice 'add_executable(app main.cpp A.ice A.ice)
slice2cpp_generate(app)
target_link_libraries(app PRIVATE Ice::Ice)')
ice "$d/A.ice" 'module CJ { struct S { int v; } }'
cpp "$d/main.cpp" '#include <A.h>'
pcase "P21 same file listed twice" "$d"

# ---------- reject cases (configure-time) ----------
mkr() { local d="$ROOT/$1"; rm -rf "$d"; mkdir -p "$d"
  ice "$d/A.ice" 'module RR { struct S { int v; } }'
  cpp "$d/main.cpp" ''
  printf 'cmake_minimum_required(VERSION 3.21)\nproject(t CXX)\nfind_package(Ice REQUIRED CONFIG COMPONENTS Ice)\n%s\n' "$2" > "$d/CMakeLists.txt"
  echo "$d"; }
d=$(mkr r01 'add_executable(a main.cpp x/A.ice y/A.ice)
slice2cpp_generate(a)'); mkdir -p "$d/x" "$d/y"; cp "$d/A.ice" "$d/x/"; cp "$d/A.ice" "$d/y/"
rcase "R01 same-name flat collision -> named error" "$d" "generated twice"
d=$(mkr r02 'add_executable(a main.cpp x/A.ice y/A.ice)
slice2cpp_generate(a INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/x ${CMAKE_CURRENT_SOURCE_DIR}/y)'); mkdir -p "$d/x" "$d/y"; cp "$d/A.ice" "$d/x/"; cp "$d/A.ice" "$d/y/"
rcase "R02 same name at two -I roots -> named error" "$d" "generated twice"
d=$(mkr r03 'add_executable(t1 main.cpp A.ice)
add_executable(t2 main.cpp A.ice)
slice2cpp_generate(t1 HEADER_OUTPUT_DIR ${CMAKE_BINARY_DIR}/inc)
slice2cpp_generate(t2 HEADER_OUTPUT_DIR ${CMAKE_BINARY_DIR}/inc)')
rcase "R03 shared HEADER_OUTPUT_DIR two targets" "$d" "generated twice"
d=$(mkr r04 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a OPTIONS --output-dir /tmp/x)'); rcase "R04 reject --output-dir" "$d" "managed by slice2cpp_generate"
d=$(mkr r05 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a OPTIONS -I/tmp)'); rcase "R05 reject -I" "$d" "managed by slice2cpp_generate"
d=$(mkr r06 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a OPTIONS --include-dir Demo)'); rcase "R06 reject --include-dir" "$d" "managed by slice2cpp_generate"
d=$(mkr r07 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a OPTIONS --depend-xml)'); rcase "R07 reject --depend-xml" "$d" "managed by slice2cpp_generate"
d=$(mkr r08 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a OPTIONS --validate)'); rcase "R08 reject --validate" "$d" "affect code generation"
d=$(mkr r09 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a OPTIONS Extra.ice)'); rcase "R09 reject stray .ice in OPTIONS" "$d" "affect code generation"
d=$(mkr r10 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a OPTIONS --header-ext)'); rcase "R10 missing extension argument" "$d" "missing its argument"
d=$(mkr r11 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a OPTIONS --header-ext bad.ext)'); rcase "R11 invalid extension value" "$d" "not a valid header extension"
d=$(mkr r12 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a OPTIONS --header-ext cpp)'); rcase "R12 header ext == source ext" "$d" "one file over the other"
d=$(mkr r13 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a OPTIONS --source-ext xyz)'); rcase "R13 non-C++ source extension" "$d" "does not compile"
d=$(mkr r14 'add_executable(realt main.cpp A.ice)
add_executable(alt ALIAS realt)
slice2cpp_generate(alt)'); rcase "R14 alias target" "$d" "is an alias"
d=$(mkr r15 'add_library(il INTERFACE)
slice2cpp_generate(il)'); rcase "R15 INTERFACE library" "$d" "cannot compile"
d=$(mkr r16 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a INCLUDE_DIR ../esc)'); rcase "R16 INCLUDE_DIR with .." "$d" "relative path without"
d=$(mkr r17 'add_executable(a main.cpp A.ice)
slice2cpp_generate(a HEADER_OUTPUT_DIR)'); rcase "R17 keyword missing value" "$d" "missing value"

# ---------- build-time error ----------
if [ "$FILTER" = A ] || [ "$FILTER" = B ]; then
  d="$ROOT/b01"; rm -rf "$d"; mkdir -p "$d"
  printf '[["cpp:header-ext:hpp"]]\n#pragma once\nmodule BB { struct S { int v; } }\n' > "$d/T.ice"
  cpp "$d/main.cpp" ''
  printf 'cmake_minimum_required(VERSION 3.21)\nproject(t CXX)\nfind_package(Ice REQUIRED CONFIG COMPONENTS Ice)\nadd_executable(app main.cpp T.ice)\nslice2cpp_generate(app)\ntarget_link_libraries(app PRIVATE Ice::Ice)\n' > "$d/CMakeLists.txt"
  rm -rf "$d/bld"
  if cmake -S "$d" -B "$d/bld" -G "$GEN" -DCMAKE_PREFIX_PATH="$P" > "$d/cfg.log" 2>&1; then
    if cmake --build "$d/bld" > "$d/bld.log" 2>&1; then emit "B01 metadata hpp mismatch" "FAIL(built)"
    elif grep -q "slice2cpp generates" "$d/bld.log"; then emit "B01 metadata hpp mismatch -> clear error" PASS
    else emit "B01 metadata hpp mismatch" "FAIL(message)"; fi
  else emit "B01 metadata hpp mismatch" "FAIL(configure)"; fi
fi

printf "%b" "$RESULTS"
echo "SUMMARY $GEN: $PASS passed, $FAIL failed"
