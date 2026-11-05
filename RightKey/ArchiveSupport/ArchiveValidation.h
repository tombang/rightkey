#include <stddef.h>
#include <stdint.h>

// 0: safe archive, 1: not a TAR (when tar_only), -1: rejected or unreadable.
int rk_validate_archive(const char *path, int tar_only, int *has_links, uint64_t available_bytes,
                        char *error, size_t error_size);
