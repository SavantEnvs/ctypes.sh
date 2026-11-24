/* Linked into the fuzz bash (built with afl-clang-fast). AFL's forkserver is deferred until the
 * harness script has loaded ctypes.so: the plugin's constructor needs an initialized shell (it
 * creates the DLHANDLES variable), so it cannot be preloaded, and AFL refuses instrumented code
 * dlopen'ed after the forkserver is up. __AFL_INIT also embeds the deferred-forkserver signature
 * that tells afl-fuzz not to start the forkserver at main(). */
void ctypes_fuzz_afl_init(void) {
#ifdef __AFL_INIT
  __AFL_INIT();
#endif
}

/* Defer unconditionally (afl-fuzz sets this itself when it finds the signature above; other
 * runners -- standalone replays, coverage collection -- do not). Runs before the AFL runtime's
 * default-priority auto-init constructor. */
#include <stdlib.h>
__attribute__((constructor(101))) static void ctypes_fuzz_defer_forkserver(void) {
  setenv("__AFL_DEFER_FORKSRV", "1", 1);
}
