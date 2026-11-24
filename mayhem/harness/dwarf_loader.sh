# Fuzz target: the vendored pahole DWARF/ELF loader behind `struct`
# (src/struct/dwarf_loader.c, dwarves.c, elf_symtab.c via cus__load_file).
# Run as: <fuzz bash> dwarf_loader.sh <input ELF>. `struct` re-reads every loaded object's debug info
# from its on-disk path, so a fixture library (mayhem/harness/dwarf_fixture.c) is dlopen'ed from a
# private scratch copy and that path is then replaced, by rename so the existing mapping stays
# valid, with the fuzz input. One lookup per input: every library loaded before the fixture is
# scanned first (~2 s in this build).
OUT=${0%/*}/../out/fuzz
enable -f "$OUT/ctypes.so" callback dlcall dlclose dlopen dlsym pack unpack struct sizeof || exit 1
# Start the (deferred) AFL forkserver now that the plugin is loaded; a no-op outside afl-fuzz.
enable -f "$OUT/afl_init.so" afl_init fz_stage fz_unlink || exit 1
afl_init
# Scratch paths are per-process ($BASHPID: each forkserver child differs). The EXIT trap below does
# not run when a sanitizer aborts or an input is killed on timeout, so each input first sweeps copies
# left by dead processes (a crashed forkserver child, a killed run)
# (bash globbing + `kill -0`, both builtins: still no child process).
scratch=${TMPDIR:-/tmp}
for f in "$scratch"/ctypes-dwarf.*; do
  pid=${f##*/ctypes-dwarf.}; pid=${pid%%.*}  # also catches fz_stage's DST.tmp
  [[ -f $f && $pid =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null && fz_unlink "$f"
done
# No child processes touch the input: the fuzzed bash opens it itself (fz_stage), which Mayhem's
# sanity check requires.
lib="$scratch/ctypes-dwarf.$BASHPID.so"
trap 'fz_unlink "$lib"' EXIT
fz_stage "$OUT/dwarf_fixture.so" "$lib" || exit 1
dlopen "$lib" >/dev/null || exit 1
fz_stage "$1" "$lib" || exit 1
struct fz_record v 2>/dev/null && declare -p v
exit 0
