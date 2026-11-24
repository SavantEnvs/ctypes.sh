/* Helper bash builtins for the fuzz harness scripts:
 *   afl_init            start the (deferred) AFL forkserver once the script has loaded ctypes.so
 *                       and before it reads the fuzz input; a no-op outside afl-fuzz.
 *   fz_stage SRC DST    copy SRC to DST in-process (write DST.tmp, then rename over DST, so an
 *                       existing mapping of DST stays valid). The fuzzed bash process itself must
 *                       open the input file: Mayhem's sanity check rejects a target whose input is
 *                       only read by a child process (cp/cat).
 *   fz_unlink PATH      remove PATH in-process. */
#include <fcntl.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct word_desc { char *word; int flags; } WORD_DESC;
typedef struct word_list { struct word_list *next; WORD_DESC *word; } WORD_LIST;
struct builtin {
  char *name;
  int (*function)(WORD_LIST *);
  int flags;
  char *const *long_doc;
  const char *short_doc;
  char *handle;
};

extern void ctypes_fuzz_afl_init(void);  /* exported by the fuzz bash (mayhem/harness/afl_defer.c) */

static int afl_init_builtin(WORD_LIST *list) {
  (void)list;
  ctypes_fuzz_afl_init();
  return 0;
}

static int fz_stage_builtin(WORD_LIST *list) {
  if (!list || !list->next) return 2;
  const char *src = list->word->word, *dst = list->next->word->word;
  size_t n = strlen(dst);
  char *tmp = malloc(n + 5);
  if (!tmp) return 1;
  memcpy(tmp, dst, n);
  memcpy(tmp + n, ".tmp", 5);
  int in = open(src, O_RDONLY), out = -1, rc = 1;
  if (in < 0) goto done;
  out = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (out < 0) goto done;
  char buf[65536];
  ssize_t r;
  while ((r = read(in, buf, sizeof buf)) > 0) {
    char *p = buf;
    while (r > 0) {
      ssize_t w = write(out, p, (size_t)r);
      if (w <= 0) goto done;
      p += w; r -= w;
    }
  }
  if (r < 0) goto done;
  if (close(out) != 0) { out = -1; goto done; }
  out = -1;
  rc = rename(tmp, dst) == 0 ? 0 : 1;
done:
  if (in >= 0) close(in);
  if (out >= 0) close(out);
  if (rc) unlink(tmp);
  free(tmp);
  return rc;
}

static int fz_unlink_builtin(WORD_LIST *list) {
  int rc = 0;
  for (; list; list = list->next) rc |= unlink(list->word->word) != 0;
  return rc;
}

static char *afl_init_doc[] = { "Start the deferred AFL forkserver.", NULL };
static char *fz_stage_doc[] = { "Copy SRC to DST in-process (atomic rename).", NULL };
static char *fz_unlink_doc[] = { "Remove files in-process.", NULL };

struct builtin afl_init_struct = { "afl_init", afl_init_builtin, 0x01, afl_init_doc, "afl_init", NULL };
struct builtin fz_stage_struct = { "fz_stage", fz_stage_builtin, 0x01, fz_stage_doc, "fz_stage SRC DST", NULL };
struct builtin fz_unlink_struct = { "fz_unlink", fz_unlink_builtin, 0x01, fz_unlink_doc, "fz_unlink PATH...", NULL };
