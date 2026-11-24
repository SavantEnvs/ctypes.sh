# Fuzz target: struct / sizeof / pack / unpack (src/struct/struct.c, src/unpack.c, src/types.c).
# Run as: <fuzz bash> struct_pack.sh <input>. Input lines:
#   1: type name from upstream's test/structs.c (prefix '@' to look up a typedef with -a);
#      other names are rejected -- each unknown name costs a full debug-info scan of every
#      loaded library and exercises nothing but the lookup loop
#   2: -u union-selection string ('' = none)
#   3..: values assigned to the struct's fields (as "<field type>:<value>"), then packed and unpacked
# Each field keeps the type `struct` gave it: pack writes every element at its own type's width
# back to back, so a different prefix would misalign or overrun the layout by design. The pack
# destination is a harness-owned buffer (sizeof -A 64 -m); the pointer never comes from the input.
OUT=${0%/*}/../out/fuzz
enable -f "$OUT/ctypes.so" callback dlcall dlclose dlopen dlsym pack unpack struct sizeof || exit 1
dlopen "$OUT/structs.so" >/dev/null || exit 1
# Start the (deferred) AFL forkserver now that the plugin is loaded; a no-op outside afl-fuzz.
enable -f "$OUT/afl_init.so" afl_init && afl_init
mapfile -t L < "$1"
name=${L[0]-}
opts=()
if [[ $name == @* ]]; then opts+=(-a); name=${name#@}; fi
case $name in
  nested|hasunion|manytypes|hasarray|hasenum|unnamed_t|mixedpack|complexarray) ;;
  *) exit 0 ;;
esac
aflag=("${opts[@]}")
[[ -n ${L[1]-} ]] && opts+=(-u "${L[1]}")
struct "${opts[@]}" "$name" v 2>/dev/null || exit 0
declare -p v
sizeof -A 64 -m p "${aflag[@]}" "$name" >/dev/null 2>&1 || exit 0
[[ $p == pointer:* ]] || exit 0
i=2
for k in "${!v[@]}"; do
  (( i < ${#L[@]} )) || break
  v[$k]=${v[$k]%%:*}:${L[i]}
  (( i++ ))
done
pack "$p" v 2>/dev/null
unpack "$p" v 2>/dev/null
declare -p v
# Re-define the same variable: the key-replace path of the struct builder (fix d3b74c2).
struct "${opts[@]}" "$name" v 2>/dev/null
declare -p v
exit 0
