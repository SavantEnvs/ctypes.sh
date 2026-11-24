#!/usr/bin/env bash
#
# mayhem/build.sh — build the ctypes.sh fuzz targets and its test suite.
#
# ctypes.so is a bash *loadable builtin*: it needs symbols exported by the bash executable, so no
# C harness can link it. Each fuzz target is a bash script (mayhem/harness/*.sh) run by a bash built
# here from pinned source (/opt/toolchains/deps/bash-5.2/src) with afl-clang-fast + ASan/UBSan; the
# plugin is built with the same flags, so AFL coverage and the sanitizers cover both. Outputs:
#   mayhem/out/fuzz/{bash,ctypes.so,structs.so,fuzzlib.so}   fuzz build (Mayhemfiles use these)
#   mayhem/out/test/{bash,ctypes.so,structs.so}              normal-flags build for mayhem/test.sh
# Upstream's autotools build only probes for libffi/libelf/libdw and then compiles the file list in
# src/Makefile.am, which is reproduced below (no in-tree configure: it would rewrite the tracked
# ./configure).
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

BASH_SRC=/opt/toolchains/deps/bash-5.2/src
OUT="$SRC/mayhem/out"
cd "$SRC"

# Relaxed UBSan checks (ASan and the rest of UBSan still halt): `function` -- bash's builtin
# dispatch and the plugin's callbacks cast function pointers between prototypes everywhere.
# `pointer-overflow` is relaxed too: obstack_alloc() (lib/obstack.h, used by the DWARF loader for
# every allocation) aligns via __PTR_ALIGN from a NULL base, which UBSan flags on every `struct`.
FUZZ_CFLAGS="$SANITIZER_FLAGS -fno-sanitize=function,pointer-overflow $DEBUG_FLAGS -O1"
[ -n "$SANITIZER_FLAGS" ] || FUZZ_CFLAGS="$DEBUG_FLAGS -O1"

FFI_CFLAGS=$(pkg-config --cflags libffi)
FFI_LIBS=$(pkg-config --libs libffi)
PLUGIN_SRCS=(src/callback.c src/ctypes.c src/types.c src/unpack.c src/util.c
             src/struct/dutil.c src/struct/dwarves.c src/struct/gobuffer.c src/struct/struct.c
             src/struct/strings.c src/struct/dwarf_loader.c src/struct/dwarves_fprintf.c
             src/struct/elf_symtab.c src/struct/rbtree.c)

# bash is the host interpreter, not the code under test, and trips UBSan in its own startup code
# (variables.c: member access through a NULL VAR_CONTEXT); its objects keep ASan + AFL but skip UBSan
# checks. The UBSan runtime stays linked in (it ships inside the ASan runtime), so the plugin's
# UBSan checks still halt.
BASH_FUZZ_EXTRA=""
[ -z "$SANITIZER_FLAGS" ] || BASH_FUZZ_EXTRA="-fno-sanitize=undefined"

# bash 5.2 predates C23-strict clang defaults (implicit declarations in its bundled termcap).
BASH_WFLAGS="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-pointer-types -w"

# build_bash <dir> <cc> <cflags> <extra objs>
build_bash() {
  local dir="$1" cc="$2" cflags="$3" extra="$4"
  mkdir -p "$dir"
  if [ ! -f "$dir/Makefile" ]; then
    (cd "$dir" && "$BASH_SRC/configure" --without-bash-malloc --disable-nls --enable-static-link=no \
        CC="$cc" CFLAGS="$cflags $BASH_WFLAGS" LDFLAGS="$cflags" >configure.log 2>&1) \
      || { tail -50 "$dir/configure.log"; exit 1; }
  fi
  rm -f "$dir/bash"   # always relink: the extra objects are not tracked by bash's Makefile
  make -C "$dir" -j"$MAYHEM_JOBS" bash LOCAL_LIBS="$extra" >"$dir/make.log" 2>&1 \
    || { grep -E "error:|\*\*\*" "$dir/make.log" | tail -30; tail -15 "$dir/make.log"; exit 1; }
}

# build_plugin <dir> <cc> <cflags>
build_plugin() {
  local dir="$1" cc="$2" cflags="$3"
  mkdir -p "$dir/obj"
  : > "$dir/config.h"   # upstream's config.h only carries HAVE_* probes the sources never test
  local objs=() s o
  for s in "${PLUGIN_SRCS[@]}"; do
    o="$dir/obj/$(echo "$s" | tr / _).o"
    $cc $cflags -fPIC -std=gnu99 -D_GNU_SOURCE -w $FFI_CFLAGS -I"$dir" -Isrc -Iinclude -Ilib -c "$s" -o "$o"
    objs+=("$o")
  done
  $cc $cflags -shared -fPIC -o "$dir/ctypes.so" "${objs[@]}" $FFI_LIBS -ldw -lelf -lz -ldl
}

mkdir -p "$OUT/fuzz" "$OUT/test"

# 1) Fuzz build: bash + ctypes.so with AFL instrumentation, ASan+UBSan and DWARF-3.
# AFL's forkserver is deferred (mayhem/harness/afl_defer.c): the harness scripts load ctypes.so
# first and then call the `afl_init` builtin (mayhem/harness/afl_init_builtin.c).
afl-clang-fast $FUZZ_CFLAGS -c mayhem/lsan_off.c -o "$OUT/fuzz/lsan_off.o"
afl-clang-fast $FUZZ_CFLAGS -c mayhem/harness/afl_defer.c -o "$OUT/fuzz/afl_defer.o"
# Plain (uninstrumented) fixtures: upstream's test/structs.c (the types struct-pack reads), the
# dwarf-loader fixture, and a no-op callee for dlcall-args. `struct` scans the debug info of every
# loaded object in load order until it finds the type (~2 s per object-without-the-type in this
# build), so the fuzz bash links structs.so as its FIRST DT_NEEDED: a struct-pack lookup then
# stops at it, and the harness's `dlopen structs.so` returns that already-loaded copy.
$CC -g -gdwarf-3 -O0 -shared -fPIC test/structs.c -o "$OUT/fuzz/structs.so"
$CC -g -gdwarf-3 -O0 -shared -fPIC mayhem/harness/dwarf_fixture.c -o "$OUT/fuzz/dwarf_fixture.so"
build_bash "$OUT/fuzz/bash-build" afl-clang-fast "$FUZZ_CFLAGS $BASH_FUZZ_EXTRA" \
  "-Wl,--no-as-needed -L$OUT/fuzz -l:structs.so -Wl,-rpath,'\$\$ORIGIN' $OUT/fuzz/lsan_off.o $OUT/fuzz/afl_defer.o"
cp -f "$OUT/fuzz/bash-build/bash" "$OUT/fuzz/bash"
$CC -g -gdwarf-3 -O1 -shared -fPIC mayhem/harness/fuzzlib.c -o "$OUT/fuzz/fuzzlib.so"
$CC -g -gdwarf-3 -O1 -shared -fPIC mayhem/harness/afl_init_builtin.c -o "$OUT/fuzz/afl_init.so"
# The plugin reads the DWARF of every loaded object -- including its own -- on each `struct`/
# `sizeof` lookup, so with full type info each lookup spends ~2 s parsing ctypes.so itself.
# -gline-tables-only (still DWARF-3) keeps file:line backtraces but drops the type DIEs.
build_plugin "$OUT/fuzz" afl-clang-fast "$FUZZ_CFLAGS -gline-tables-only"

# 2) Test build (normal flags) for mayhem/test.sh.
build_bash "$OUT/test/bash-build" "$CC" "-O2 -g $COVERAGE_FLAGS" ""
cp -f "$OUT/test/bash-build/bash" "$OUT/test/bash"
build_plugin "$OUT/test" "$CC" "-O2 -g $COVERAGE_FLAGS"
$CC -g -O0 -shared -fPIC test/structs.c -o "$OUT/test/structs.so"
$CC -g -O1 -shared -fPIC mayhem/harness/fuzzlib.c -o "$OUT/test/fuzzlib.so"

echo "build.sh: done"
ls -la "$OUT/fuzz" "$OUT/test"
