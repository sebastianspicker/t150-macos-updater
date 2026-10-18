/* Developer packaging guard: test an existing updater lock without creating it. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int hold = argc > 1 && !strcmp(argv[1], "--hold");
    int start = hold ? 2 : 1;
    for (int i = start; i < argc; i++) {
        if (hold && !strcmp(argv[i], "--")) {
            if (i + 1 == argc) return 2;
            execvp(argv[i + 1], argv + i + 1);
            perror("Cannot start guarded packaging"); return 1;
        }
        int fd = open(argv[i], (hold ? O_RDWR | O_CREAT : O_RDONLY) | O_NOFOLLOW, 0600);
        if (fd < 0) {
            if (errno == ENOENT) continue;
            perror("Cannot inspect updater lock"); return 1;
        }
        struct stat info;
        if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() ||
            (info.st_mode & 0777) != 0600 || info.st_nlink != 1) {
            fprintf(stderr, "Unsafe updater lock; refusing rebuild.\n"); close(fd); return 1;
        }
        if (flock(fd, LOCK_EX | LOCK_NB)) {
            fprintf(stderr, "Updater lock is held or unavailable; refusing rebuild.\n");
            close(fd); return 1;
        }
        if (!hold) close(fd); /* Retain across exec for the complete packaging process. */
    }
    return hold ? 2 : 0;
}
