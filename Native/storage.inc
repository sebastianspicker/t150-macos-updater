/* Session artifacts are anchored to an owned private directory descriptor. */
#include <sys/file.h>
#include <sys/stat.h>
#include <limits.h>

static int session_fd = -1, result_fd = -1, lock_fd = -1;
static const char *session_path = "", *operation = "", *state_name = "unsupported", *result_log = "", *result_profile = "";
static int restart_issued;
static unsigned status_pid;

static int write_all(int fd, const void *buffer, size_t length) {
    const unsigned char *data = buffer;
    while (length) {
        ssize_t amount = write(fd, data, length);
        if (amount < 0 && errno == EINTR) continue;
        if (amount <= 0) return 1;
        data += amount; length -= (size_t)amount;
    }
    return 0;
}

/* Walk every path component without following symlinks, including parents. */
static int directory_path(const char *path) {
    if (!path || !*path || strlen(path) >= PATH_MAX) return -1;
    char copy[PATH_MAX]; strcpy(copy, path);
    int fd = open(path[0] == '/' ? "/" : ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (fd < 0) return -1;
    char *save = NULL;
    for (char *part = strtok_r(copy, "/", &save); part; part = strtok_r(NULL, "/", &save)) {
        if (!strcmp(part, ".")) continue;
        if (!strcmp(part, "..")) { close(fd); errno = EINVAL; return -1; }
        int next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
        close(fd); fd = next;
        if (fd < 0) return -1;
    }
    return fd;
}

static int private_directory(int fd) {
    struct stat st;
    return fd >= 0 && !fstat(fd, &st) && S_ISDIR(st.st_mode) &&
        st.st_uid == getuid() && (st.st_mode & 0777) == 0700;
}

static int fresh_result(const char *path) {
    if (!path || !*path || strlen(path) >= PATH_MAX) return -1;
    char copy[PATH_MAX]; strcpy(copy, path);
    char *slash = strrchr(copy, '/');
    const char *name = slash ? slash + 1 : copy;
    if (!*name || !strcmp(name, ".") || !strcmp(name, "..")) return -1;
    char filename[NAME_MAX + 1];
    if (strlen(name) > NAME_MAX) return -1;
    strcpy(filename, name);
    if (slash) { if (slash == copy) slash[1] = 0; else *slash = 0; }
    int parent = directory_path(slash ? copy : ".");
    if (!private_directory(parent)) { if (parent >= 0) close(parent); errno = EPERM; return -1; }
    int fd = openat(parent, filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd >= 0 && fsync(parent)) { close(fd); fd = -1; }
    close(parent); return fd;
}

static int safe_read_at(int dir, const char *name, void *output, size_t length) {
    int fd = openat(dir, name, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return 1;
    struct stat st;
    int bad = fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() ||
        (st.st_mode & 0777) != 0600 || st.st_nlink != 1 || st.st_size != (off_t)length;
    size_t done = 0;
    while (!bad && done < length) {
        ssize_t amount = read(fd, (char *)output + done, length - done);
        if (amount < 0 && errno == EINTR) continue;
        if (amount <= 0) bad = 1; else done += (size_t)amount;
    }
    close(fd); return bad;
}

static int external_read(const char *path, void *output, size_t length) {
    if (!path || strlen(path) >= PATH_MAX) return 1;
    char copy[PATH_MAX]; strcpy(copy,path);
    char *slash = strrchr(copy,'/'); const char *name = slash ? slash + 1 : copy;
    char filename[NAME_MAX + 1];
    if (!*name || strlen(name) > NAME_MAX) return 1;
    strcpy(filename,name);
    if (slash) { if (slash == copy) slash[1] = 0; else *slash = 0; }
    int dir = directory_path(slash ? copy : ".");
    if (dir < 0) return 1;
    int bad = safe_read_at(dir,filename,output,length); close(dir); return bad;
}

static int save_at(const char *name, const void *data, size_t length) {
    int fd = openat(session_fd,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if (fd < 0) return 1;
    int bad = write_all(fd,data,length) || fsync(fd);
    if (close(fd)) bad = 1;
    if (fsync(session_fd)) bad = 1;
    return bad; /* Preserve incomplete artifacts; later operations reject them. */
}

static int artifact_exists(const char *name) {
    struct stat st;
    return !fstatat(session_fd,name,&st,AT_SYMLINK_NOFOLLOW) || errno != ENOENT;
}

static int global_lock(void) {
    char path[128]; snprintf(path,sizeof(path),"/private/tmp/t150-native-engine-%u.lock",(unsigned)getuid());
    lock_fd = open(path,O_RDWR|O_CREAT|O_NOFOLLOW,0600);
    struct stat st;
    if (lock_fd < 0 || fstat(lock_fd,&st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() ||
        (st.st_mode & 0777) != 0600 || st.st_nlink != 1 || flock(lock_fd,LOCK_EX|LOCK_NB)) return 1;
    return 0;
}

static void json_string(FILE *out, const char *value) {
    fputc('"',out);
    for (const unsigned char *p=(const unsigned char *)value; *p; ++p) {
        if (*p == '"' || *p == '\\') { fputc('\\',out); fputc(*p,out); }
        else if (*p < 32) fprintf(out,"\\u%04x",*p);
        else fputc(*p,out);
    }
    fputc('"',out);
}

static Run result_runs[14];
static unsigned result_run_count;
static int emit_result(int ok, const char *code, const char *message) {
    if (result_fd < 0) { fprintf(stderr,"%s: %s\n",code,message); return 1; }
    if (*result_log && (fsync(STDOUT_FILENO) || fsync(session_fd)) && ok) {
        ok=0;code="persistence";message="Operation completed but its log could not be durably synchronized. Retain the session and check status.";
    }
    FILE *out = fdopen(dup(result_fd),"w");
    if (!out) return 1;
    fprintf(out,"{\"schema\":1,\"operation\":"); json_string(out,operation);
    fprintf(out,",\"ok\":%s,\"code\":",ok?"true":"false");json_string(out,code);
    fprintf(out,",\"message\":");json_string(out,message);
    fprintf(out,",\"session\":");json_string(out,session_path);
    fprintf(out,",\"profile\":");json_string(out,result_profile);
    fprintf(out,",\"state\":");json_string(out,state_name);
    fprintf(out,",\"restartIssued\":%s,\"device\":{\"pid\":%u,\"applicationVersion\":",restart_issued?"true":"false",status_pid);
    if (observed_application < 0) fputs("null",out); else fprintf(out,"%d",observed_application);
    fputs(",\"bootloaderVersion\":",out);
    if (observed_bootloader<0) fputs("null",out);else fprintf(out,"%d",observed_bootloader);
    fprintf(out,",\"registryID\":\"%llu\"},\"artifacts\":{\"log\":",(unsigned long long)bound_registry);
    json_string(out,result_log);
    fputs(",\"manifest\":\"manifest.json\",\"backupA\":\"backup-a.bin\",\"backupB\":\"backup-b.bin\",\"readback\":\"readback.bin\"},\"plan\":[",out);
    for (unsigned i=0;i<result_run_count;++i) fprintf(out,"%s{\"address\":%u,\"length\":%u}",i?",":"",result_runs[i].address,result_runs[i].length);
    fputs("]}\n",out);
    int bad = fflush(out) || ferror(out); if (fclose(out)) bad = 1;
    if (fsync(result_fd)) bad = 1;
    close(result_fd);result_fd=-1;
    return bad || !ok;
}

static int capture_log(const char *name) {
    int fd = openat(session_fd,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if (fd < 0) return 1;
    if (fsync(session_fd) || dup2(fd,STDOUT_FILENO)<0 || dup2(fd,STDERR_FILENO)<0) { close(fd); return 1; }
    close(fd);setvbuf(stdout,NULL,_IONBF,0);setvbuf(stderr,NULL,_IONBF,0);result_log=name;return 0;
}
