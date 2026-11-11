/* verify-jobmark.c - drives gplsrc/sd_jobmark.c's sd_job_name() and gplsrc/win32jobmark.c for gplbld/test-jobmark-units.py.
 * 10 Nov 26 Windows port - from Linux 5162a5d1 (S.102 stage 3), carry area 14.  Linux's driver passes a cgroup file and the test's own uid; the
 * Windows mark has no cgroup, so the driver takes the claim, and the administrator-only test is either the real one or a stand-in:
 *
 *   verify-jobmark trust JOBS_DIR CLAIM COMMAND   the definition logic alone: SAFE answers 1 for an existing path of the right kind
 *   verify-jobmark acl   JOBS_DIR CLAIM COMMAND   the same with the kernel's own SAFE, win32_job_admin_path() (owner and DACL)
 *   verify-jobmark token                          win32_job_token_ok() asked of this very process
 *
 * Prints "job=<name>" and exits 0 when sd_job_name() answers a name, prints "job=" and exits 1 when it does not; for token, "token=1" (exit 0)
 * or "token=0 why=<reason>" (exit 1).  Usage errors exit 2.  No other output.                                                              */
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#include "sd_jobmark.h"

static int trust(const char *path, int want_dir)
{
    struct stat st;

    if (stat(path, &st) != 0) return 0;
    return want_dir ? S_ISDIR(st.st_mode) : S_ISREG(st.st_mode);
}

int main(int argc, char **argv)
{
    char name[SD_JOB_NAME_MAX + 1];
    char why[256];
    sd_job_safe_fn safe;

    if (argc == 2 && strcmp(argv[1], "token") == 0) {
        why[0] = '\0';
        if (win32_job_token_ok(why, sizeof why)) {
            printf("token=1\n");
            return 0;
        }
        printf("token=0 why=%s\n", why);
        return 1;
    }
    if (argc != 5 || (strcmp(argv[1], "trust") != 0 && strcmp(argv[1], "acl") != 0)) {
        fprintf(stderr, "usage: verify-jobmark trust|acl JOBS_DIR CLAIM COMMAND | verify-jobmark token\n");
        return 2;
    }
    safe = (strcmp(argv[1], "acl") == 0) ? win32_job_admin_path : trust;
    if (sd_job_name(argv[2], argv[3], argv[4], safe, name, sizeof name) == 0) {
        printf("job=%s\n", name);
        return 0;
    }
    printf("job=\n");
    return 1;
}
