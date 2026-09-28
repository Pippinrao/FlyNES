#ifndef SAVE_HISTORY_H
#define SAVE_HISTORY_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sh_store sh_store;
typedef int64_t sh_id;
typedef enum sh_result {
    SH_OK = 0,
    SH_INVALID = 1,
    SH_NOT_FOUND = 2,
    SH_BUFFER_TOO_SMALL = 3,
    SH_CORRUPT = 4,
    SH_QUOTA = 5,
    SH_PROTECTED = 6,
    SH_BUSY = 7,
    SH_IO = 8,
    SH_UNSUPPORTED = 9,
    SH_NO_MEMORY = 10,
    SH_CONFLICT = 11
} sh_result;
typedef enum sh_kind { SH_AUTO = 0, SH_MANUAL = 1, SH_PROTECTION = 2, SH_LEGACY = 3 } sh_kind;
typedef enum sh_blob { SH_STATE = 0, SH_THUMBNAIL = 1 } sh_blob;

typedef struct sh_options {
    uint32_t struct_size;
    uint32_t max_auto_entries;  /* 0 selects default 60. */
    uint64_t max_content_bytes; /* 0 selects default 256 MiB. */
    uint64_t max_total_bytes;   /* 0 selects default 1 GiB. */
} sh_options;

typedef struct sh_entry {
    uint32_t struct_size;
    const char *content_key;
    const char *format;
    const char *session;
    sh_id parent_id; /* 0 means no parent. */
    int64_t created_ms;
    uint64_t played_ms;
    sh_kind kind;
    const char *label; /* NULL is an empty label. */
    int pinned;
    const void *state;
    size_t state_size;
    const void *thumbnail; /* optional opaque bytes */
    size_t thumbnail_size;
    int make_head; /* sh_put publishes this entry as head in the same transaction. */
} sh_entry;

typedef struct sh_metadata {
    sh_id id;
    const char *content_key;
    const char *format;
    const char *session;
    sh_id parent_id;
    int64_t created_ms;
    uint64_t played_ms;
    sh_kind kind;
    const char *label;
    int pinned;
    uint64_t state_size;
    uint64_t thumbnail_size;
    int is_head;
} sh_metadata;

/* Strings and metadata are valid only during callback. Return nonzero to stop.
 * Do not re-enter any API on this store from a callback. */
typedef int (*sh_list_callback)(void *context, const sh_metadata *entry);

/* NULL options use defaults. UTF-8 path; caller serializes each store handle.
 * All inputs are borrowed for the call. No exception crosses the C ABI. */
sh_result sh_open(const char *path, const sh_options *options, sh_store **out_store);
void sh_close(sh_store *store);
sh_result sh_put(sh_store *store, const sh_entry *entry, sh_id *out_id);
/* Exact content/format match, newest created_ms then id first; limit=0 means all. */
sh_result sh_list(sh_store *store, const char *content_key, const char *format, uint32_t limit,
                  sh_list_callback callback, void *context);
/* Checks content, format, and integrity even on size query. NULL buffer with
 * capacity=0 returns SH_OK and required size. Short buffer is untouched. */
sh_result sh_read(sh_store *store, sh_id id, const char *content_key, const char *format,
                  sh_blob blob, void *buffer, size_t capacity, size_t *out_size);
sh_result sh_get_head(sh_store *store, const char *content_key, const char *format, sh_id *out_id);
/* id=0 clears head; nonzero must match content/format. */
sh_result sh_set_head(sh_store *store, const char *content_key, const char *format, sh_id id);
sh_result sh_rename(sh_store *store, sh_id id, const char *label);
sh_result sh_pin(sh_store *store, sh_id id, int pinned);
sh_result sh_delete(sh_store *store, sh_id id);

/* Prepare atomically stores current state as SH_PROTECTION and verifies target.
 * Target and current must have identical content/format. Existing head remains
 * unchanged until finish. One pending operation per content/format. Returned
 * backup remains protected across reopen; caller coordinates actual state load.
 * A fresh-start target can be inserted with sh_put before prepare. */
sh_result sh_prepare_restore(sh_store *store, sh_id target_id, const sh_entry *current,
                             sh_id *out_operation_id, sh_id *out_backup_id);
/* Repeating the same completion is OK; opposite completion is SH_CONFLICT. */
sh_result sh_finish_restore(sh_store *store, sh_id operation_id);
sh_result sh_cancel_restore(sh_store *store, sh_id operation_id);
/* Atomically publish the backup as head and mark the pending operation recovered.
 * Repeating recovery succeeds. Recovery conflicts with prior finish/cancel;
 * finish/cancel likewise conflict with a recovered operation. */
sh_result sh_recover_restore(sh_store *store, sh_id operation_id);
/* Allows caller to recover an interrupted operation after reopening. */
sh_result sh_get_pending_restore(sh_store *store, const char *content_key, const char *format,
                                 sh_id *out_operation_id, sh_id *out_target_id,
                                 sh_id *out_backup_id);

#ifdef __cplusplus
}
#endif
#endif
