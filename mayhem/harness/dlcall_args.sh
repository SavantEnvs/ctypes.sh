# Fuzz target: type-prefixed argument / return-type parsing of dlcall, callback and dlsym
# (src/ctypes.c, src/callback.c, src/types.c). Run as: bash dlcall_args.sh <input>. Input lines:
#   1: return type for dlcall / callback ("int", "pointer", ...)
#   2..: arguments ("int:7", "double:1.5", "string:x", ...)
# The callee (mayhem/harness/fuzzlib.c `nop`) ignores its arguments and the callback is never
# invoked, so fuzzed pointer values are parsed but never dereferenced.
OUT=${0%/*}/../out/fuzz
enable -f "$OUT/ctypes.so" callback dlcall dlclose dlopen dlsym pack unpack struct sizeof || exit 1
dlopen "$OUT/fuzzlib.so" >/dev/null || exit 1
# Start the (deferred) AFL forkserver now that the plugin is loaded; a no-op outside afl-fuzz.
enable -f "$OUT/afl_init.so" afl_init && afl_init
mapfile -t L < "$1"
rtype=${L[0]-int}
args=("${L[@]:1}")
dlcall -n out -r "$rtype" nop "${args[@]}" 2>/dev/null && declare -p out
callback -n cb nop "$rtype" "${args[@]}" 2>/dev/null && declare -p cb
dlsym -d "$rtype" -n o buf 2>/dev/null && declare -p o
exit 0
