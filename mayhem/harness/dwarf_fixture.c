/* Fixture library for the dwarf-loader target: its debug info (and the fuzzed ELF that replaces it)
 * is what `struct fz_record` reads. Type names are unique to this file so the lookup is not
 * satisfied by structs.so, which the fuzz bash loads first. */
#include <stdint.h>

typedef struct { int x; long y; } fz_anon_t;

struct fz_record {
    uint8_t a;
    uint16_t b;
    struct { int c; struct { double d; } inner; } nested;
    union { uint32_t e; float f; } u;
    union { uint8_t g; uint64_t h; };
    enum { FZ_A, FZ_B = 1000 } kind;
    int arr[4];
    unsigned bits : 3;
    unsigned more : 13;
    void *p;
    char *s;
    fz_anon_t anon;
    struct fz_record *next;
} fz_record;

fz_anon_t fz_anon;
