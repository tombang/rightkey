#include "ArchiveValidation.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

// Stable libarchive C ABI supplied by macOS. Xcode ships libarchive.2.tbd but
// omits its public headers; keep these opaque declarations limited to the API
// used here (https://www.libarchive.org/man/archive_read.3.html).
struct archive;
struct archive_entry;
extern struct archive *archive_read_new(void);
extern int archive_read_support_format_all(struct archive *);
extern int archive_read_support_format_tar(struct archive *);
extern int archive_read_support_filter_all(struct archive *);
extern int archive_read_open_filename(struct archive *, const char *, size_t);
extern int archive_read_next_header(struct archive *, struct archive_entry **);
extern int archive_read_free(struct archive *);
extern const char *archive_error_string(struct archive *);
extern const char *archive_entry_pathname(struct archive_entry *);
extern const char *archive_entry_symlink(struct archive_entry *);
extern const char *archive_entry_hardlink(struct archive_entry *);
extern unsigned short archive_entry_filetype(struct archive_entry *);
extern int archive_entry_is_encrypted(struct archive_entry *);
extern int64_t archive_entry_size(struct archive_entry *);

// Treat both separators as directory separators, including Windows archives.
static int safe_path(const char *name, int initial_depth, int *end_depth) {
    if (!name || !*name || name[0] == '/' || name[0] == '\\') return 0;
    int depth = initial_depth;
    const char *p = name;
    while (*p) {
        const char *start = p;
        while (*p && *p != '/' && *p != '\\') {
            if (*p == ':') return 0; // drive paths / alternate streams
            ++p;
        }
        size_t length = (size_t)(p - start);
        if (length == 2 && start[0] == '.' && start[1] == '.') {
            if (--depth < 0) return 0;
        } else if (length && !(length == 1 && start[0] == '.')) ++depth;
        if (*p) ++p;
    }
    if (end_depth) *end_depth = depth;
    return 1;
}

int rk_validate_archive(const char *path, int tar_only, int *has_links, uint64_t available_bytes,
                        char *error, size_t error_size) {
    *has_links = 0;
    struct archive *reader = archive_read_new();
    if (!reader) { snprintf(error, error_size, "无法分配归档读取器。"); return -1; }
    archive_read_support_filter_all(reader);
    if (tar_only) archive_read_support_format_tar(reader);
    else archive_read_support_format_all(reader);
    int result = -1;
    if (archive_read_open_filename(reader, path, 10240) != 0) {
        const char *message = archive_error_string(reader);
        if (tar_only && message && strstr(message, "Unrecognized archive format")) result = 1;
        else snprintf(error, error_size, "归档无法读取（可能已损坏、加密或不受支持）：%s", message ? message : "unknown error");
        archive_read_free(reader);
        return result;
    }
    struct archive_entry *entry;
    uint64_t total = 0, count = 0;
    int status;
    while ((status = archive_read_next_header(reader, &entry)) == 0) {
        const char *name = archive_entry_pathname(entry);
        int depth = 0;
        if (!safe_path(name, 0, &depth)) {
            snprintf(error, error_size, "归档包含不安全路径，已拒绝解压：%.200s", name ? name : "(invalid name)");
            goto done;
        }
        // Reject every parent component in entry names, even a/../b. Links
        // may use .. only when their resolved target remains inside the root.
        char *copy = strdup(name), *save = NULL;
        if (!copy) { snprintf(error, error_size, "内存不足。"); goto done; }
        int traversal = 0;
        for (char *part = strtok_r(copy, "/\\", &save); part; part = strtok_r(NULL, "/\\", &save)) {
            if (!strcmp(part, "..")) { traversal = 1; break; }
        }
        free(copy);
        const char *symbolic = archive_entry_symlink(entry);
        const char *hard = archive_entry_hardlink(entry);
        if (symbolic || hard) *has_links = 1;
        if (traversal || (symbolic && !safe_path(symbolic, depth > 0 ? depth - 1 : 0, NULL)) ||
            (hard && !safe_path(hard, 0, NULL))) {
            snprintf(error, error_size, "归档包含指向目录外的路径或链接：%.200s", name);
            goto done;
        }
        unsigned short type = archive_entry_filetype(entry);
        if (type != 0 && type != S_IFREG && type != S_IFDIR && type != S_IFLNK) {
            snprintf(error, error_size, "归档包含不支持的特殊文件：%.200s", name);
            goto done;
        }
        if (archive_entry_is_encrypted(entry) > 0) {
            snprintf(error, error_size, "第一版暂不支持加密压缩包，请先用其他工具解密。");
            goto done;
        }
        int64_t size = archive_entry_size(entry);
        if (size > 0) {
            if ((uint64_t)size > UINT64_MAX - total) { snprintf(error, error_size, "归档大小超出支持范围。"); goto done; }
            total += (uint64_t)size;
        }
        if (++count > 200000 || (available_bytes && total > available_bytes)) {
            snprintf(error, error_size, "归档条目超过 200000 项，或解压所需空间超过磁盘剩余空间。");
            goto done;
        }
    }
    if (status == 1) result = 0; // ARCHIVE_EOF
    else snprintf(error, error_size, "归档读取失败（可能已损坏或加密）：%s", archive_error_string(reader) ?: "unknown error");
done:
    archive_read_free(reader);
    return result;
}
