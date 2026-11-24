/* No-op callee and scratch buffer for the dlcall/callback/dlsym fuzz target: the callee ignores
 * every argument, so fuzzed pointer arguments are never dereferenced. */
long nop(void) { return 0; }
unsigned char buf[4096];
