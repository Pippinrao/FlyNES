#include "save_history/save_history.h"
#include "sqlite3.h"
#include <climits>
#include <cstring>
#include <memory>
#include <new>
#include <string>

struct sh_store {
    sqlite3 *db = nullptr;
    uint32_t max_auto = 60;
    uint64_t max_content = 256ULL * 1024 * 1024;
    uint64_t max_total = 1024ULL * 1024 * 1024;
    ~sh_store() {
        if (db)
            sqlite3_close_v2(db);
    }
};
namespace {
struct Failure {
    sh_result result;
};
void require(bool value, sh_result result = SH_INVALID) {
    if (!value)
        throw Failure{result};
}
void check(int code) {
    if (code == SQLITE_OK || code == SQLITE_DONE || code == SQLITE_ROW)
        return;
    switch (code & 255) {
    case SQLITE_BUSY:
    case SQLITE_LOCKED:
        throw Failure{SH_BUSY};
    case SQLITE_CORRUPT:
    case SQLITE_NOTADB:
        throw Failure{SH_CORRUPT};
    case SQLITE_NOMEM:
        throw Failure{SH_NO_MEMORY};
    case SQLITE_FULL:
    case SQLITE_TOOBIG:
        throw Failure{SH_QUOTA};
    default:
        throw Failure{SH_IO};
    }
}
void exec(sh_store *s, const char *sql) {
    check(sqlite3_exec(s->db, sql, nullptr, nullptr, nullptr));
}
struct Statement {
    sqlite3_stmt *p = nullptr;
    Statement(sh_store *s, const char *sql) {
        check(sqlite3_prepare_v2(s->db, sql, -1, &p, nullptr));
    }
    ~Statement() { sqlite3_finalize(p); }
    Statement(const Statement &) = delete;
    int step() {
        int r = sqlite3_step(p);
        check(r);
        return r;
    }
    int64_t integer(int c) { return sqlite3_column_int64(p, c); }
    const char *text(int c) {
        auto ptext = sqlite3_column_text(p, c);
        require(ptext != nullptr, SH_NO_MEMORY);
        return reinterpret_cast<const char *>(ptext);
    }
    void number(int i, int64_t v) { check(sqlite3_bind_int64(p, i, v)); }
    void text(int i, const char *v) { check(sqlite3_bind_text(p, i, v, -1, SQLITE_TRANSIENT)); }
    void blob(int i, const void *v, size_t n) {
        check(sqlite3_bind_blob(p, i, n ? v : "", static_cast<int>(n), SQLITE_TRANSIENT));
    }
};
struct Transaction {
    sh_store *s;
    bool committed = false;
    explicit Transaction(sh_store *value) : s(value) { exec(s, "BEGIN IMMEDIATE"); }
    ~Transaction() {
        if (!committed)
            sqlite3_exec(s->db, "ROLLBACK", nullptr, nullptr, nullptr);
    }
    void commit() {
        exec(s, "COMMIT");
        committed = true;
    }
};
bool key(const char *s) { return s && *s && std::strlen(s) <= 4096; }
uint32_t checksum(const void *data, size_t size) {
    uint32_t crc = 0xffffffffu;
    const auto *p = static_cast<const unsigned char *>(data);
    for (size_t i = 0; i < size; ++i) {
        crc ^= p[i];
        for (int j = 0; j < 8; ++j)
            crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}
void validate(const sh_entry *e) {
    require(e && e->struct_size == sizeof(sh_entry));
    require(key(e->content_key) && key(e->format) && key(e->session));
    require(e->parent_id >= 0 && e->played_ms <= INT64_MAX && e->kind >= SH_AUTO &&
            e->kind <= SH_LEGACY);
    require(!e->label || std::strlen(e->label) <= 4096);
    require(e->state && e->state_size > 0 && e->state_size <= INT_MAX);
    require((e->thumbnail || !e->thumbnail_size) && e->thumbnail_size <= INT_MAX);
}
void matched(sh_store *s, sh_id id, const char *content, const char *format) {
    Statement q(s, "SELECT id FROM entries WHERE id=? AND content=? AND format=?");
    q.number(1, id);
    q.text(2, content);
    q.text(3, format);
    require(q.step() == SQLITE_ROW, SH_NOT_FOUND);
}
void set_head(sh_store *s, const char *content, const char *format, sh_id id) {
    if (!id) {
        Statement q(s, "DELETE FROM heads WHERE content=? AND format=?");
        q.text(1, content);
        q.text(2, format);
        q.step();
        return;
    }
    matched(s, id, content, format);
    Statement q(s, "INSERT INTO heads(content,format,entry_id) VALUES(?,?,?) ON "
                   "CONFLICT(content,format) DO UPDATE SET entry_id=excluded.entry_id");
    q.text(1, content);
    q.text(2, format);
    q.number(3, id);
    q.step();
}
sh_id insert(sh_store *s, const sh_entry &e) {
    if (e.parent_id)
        matched(s, e.parent_id, e.content_key, e.format);
    Statement q(s,
                "INSERT INTO "
                "entries(content,format,session,parent_id,created_ms,played_ms,kind,label,pinned,"
                "state,thumbnail,state_crc,thumbnail_crc) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)");
    q.text(1, e.content_key);
    q.text(2, e.format);
    q.text(3, e.session);
    q.number(4, e.parent_id);
    q.number(5, e.created_ms);
    q.number(6, static_cast<int64_t>(e.played_ms));
    q.number(7, e.kind);
    q.text(8, e.label ? e.label : "");
    q.number(9, e.pinned != 0);
    q.blob(10, e.state, e.state_size);
    q.blob(11, e.thumbnail, e.thumbnail_size);
    q.number(12, checksum(e.state, e.state_size));
    q.number(13, checksum(e.thumbnail, e.thumbnail_size));
    q.step();
    return sqlite3_last_insert_rowid(s->db);
}
const char *eligible =
    "e.pinned=0 AND e.id NOT IN(SELECT entry_id FROM heads) AND e.id NOT IN(SELECT entry_id FROM "
    "protections) AND NOT EXISTS(SELECT 1 FROM operations o WHERE o.status=0 AND (o.target_id=e.id "
    "OR o.backup_id=e.id OR o.original_head=e.id))";
int64_t scalar(sh_store *s, const std::string &sql, const char *content = nullptr) {
    Statement q(s, sql.c_str());
    if (content)
        q.text(1, content);
    require(q.step() == SQLITE_ROW, SH_IO);
    return q.integer(0);
}
void evict_one(sh_store *s, const char *content, sh_id keep, bool automatic_only) {
    std::string sql = "SELECT e.id FROM entries e WHERE ";
    sql += eligible;
    sql += automatic_only ? " AND e.kind=0" : " AND e.kind IN(0,2)";
    sql += " AND e.id<>?";
    if (content)
        sql += " AND e.content=?";
    sql += " ORDER BY e.created_ms,e.id LIMIT 1";
    sh_id victim = 0;
    {
        Statement q(s, sql.c_str());
        q.number(1, keep);
        if (content)
            q.text(2, content);
        require(q.step() == SQLITE_ROW, SH_QUOTA);
        victim = q.integer(0);
    }
    Statement q(s, "DELETE FROM entries WHERE id=?");
    q.number(1, victim);
    q.step();
}
void retain(sh_store *s, const char *content, sh_id keep) {
    std::string count = "SELECT count(*) FROM entries e WHERE e.content=? AND e.kind=0 AND ";
    count += eligible;
    while (scalar(s, count, content) > s->max_auto)
        evict_one(s, content, keep, true);
    while (
        static_cast<uint64_t>(scalar(
            s,
            "SELECT coalesce(sum(length(state)+length(thumbnail)),0) FROM entries WHERE content=?",
            content)) > s->max_content)
        evict_one(s, content, keep, false);
    while (static_cast<uint64_t>(
               scalar(s, "SELECT coalesce(sum(length(state)+length(thumbnail)),0) FROM entries")) >
           s->max_total)
        evict_one(s, nullptr, keep, false);
}
void protect(sh_store *s, const sh_entry &e, sh_id id) {
    Statement q(s, "INSERT INTO protections(content,format,entry_id) VALUES(?,?,?) ON "
                   "CONFLICT(content,format) DO UPDATE SET entry_id=excluded.entry_id");
    q.text(1, e.content_key);
    q.text(2, e.format);
    q.number(3, id);
    q.step();
}
void idle(sh_store *s, const char *content, const char *format) {
    Statement q(s, "SELECT id FROM operations WHERE content=? AND format=? AND status=0");
    q.text(1, content);
    q.text(2, format);
    require(q.step() == SQLITE_DONE, SH_BUSY);
}
void verify_state(sh_store *s, sh_id id, const char *content, const char *format) {
    size_t size = 0;
    sh_result r = sh_read(s, id, content, format, SH_STATE, nullptr, 0, &size);
    require(r == SH_OK, r);
}
void complete(sh_store *s, sh_id id, int status) {
    require(id > 0);
    Transaction tx(s);
    std::string content, format;
    sh_id target = 0, backup = 0;
    int previous = 0;
    {
        Statement q(s,
                    "SELECT content,format,target_id,status,backup_id FROM operations WHERE id=?");
        q.number(1, id);
        require(q.step() == SQLITE_ROW, SH_NOT_FOUND);
        content = q.text(0);
        format = q.text(1);
        target = q.integer(2);
        previous = static_cast<int>(q.integer(3));
        backup = q.integer(4);
    }
    if (previous) {
        require(previous == status, SH_CONFLICT);
        tx.commit();
        return;
    }
    if (status == 1 || status == 3) {
        const sh_id next_head = status == 3 ? backup : target;
        verify_state(s, next_head, content.c_str(), format.c_str());
        set_head(s, content.c_str(), format.c_str(), next_head);
    }
    Statement q(s, "UPDATE operations SET status=? WHERE id=?");
    q.number(1, status);
    q.number(2, id);
    q.step();
    tx.commit();
}
} // namespace
#define SH_CATCH                                                                                   \
    catch (const Failure &e) {                                                                     \
        return e.result;                                                                           \
    }                                                                                              \
    catch (const std::bad_alloc &) {                                                               \
        return SH_NO_MEMORY;                                                                       \
    }                                                                                              \
    catch (...) {                                                                                  \
        return SH_IO;                                                                              \
    }
extern "C" sh_result sh_open(const char *path, const sh_options *options, sh_store **out) {
    if (!out)
        return SH_INVALID;
    *out = nullptr;
    if (!path || !*path || (options && options->struct_size != sizeof(sh_options)))
        return SH_INVALID;
    try {
        auto s = std::make_unique<sh_store>();
        if (options) {
            if (options->max_auto_entries)
                s->max_auto = options->max_auto_entries;
            if (options->max_content_bytes)
                s->max_content = options->max_content_bytes;
            if (options->max_total_bytes)
                s->max_total = options->max_total_bytes;
        }
        require(s->max_content <= INT64_MAX && s->max_total <= INT64_MAX);
        check(sqlite3_open_v2(path, &s->db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                              nullptr));
        check(sqlite3_busy_timeout(s->db, 2500));
        exec(s.get(), "PRAGMA journal_mode=DELETE;PRAGMA synchronous=FULL;PRAGMA foreign_keys=ON;");
        {
            Statement q(s.get(), "PRAGMA user_version");
            q.step();
            require(q.integer(0) <= 1, SH_UNSUPPORTED);
        }
        Transaction tx(s.get());
        exec(s.get(),
             "CREATE TABLE IF NOT EXISTS entries(id INTEGER PRIMARY KEY AUTOINCREMENT,content TEXT "
             "NOT NULL,format TEXT NOT NULL,session TEXT NOT NULL,parent_id INTEGER NOT "
             "NULL,created_ms INTEGER NOT NULL,played_ms INTEGER NOT NULL,kind INTEGER NOT "
             "NULL,label TEXT NOT NULL,pinned INTEGER NOT NULL,state BLOB NOT NULL,thumbnail BLOB "
             "NOT NULL,state_crc INTEGER NOT NULL,thumbnail_crc INTEGER NOT NULL);"
             "CREATE INDEX IF NOT EXISTS entries_lookup ON entries(content,format,created_ms "
             "DESC,id DESC);"
             "CREATE TABLE IF NOT EXISTS heads(content TEXT NOT NULL,format TEXT NOT NULL,entry_id "
             "INTEGER NOT NULL REFERENCES entries(id),PRIMARY KEY(content,format));"
             "CREATE TABLE IF NOT EXISTS protections(content TEXT NOT NULL,format TEXT NOT "
             "NULL,entry_id INTEGER NOT NULL REFERENCES entries(id),PRIMARY KEY(content,format));"
             "CREATE TABLE IF NOT EXISTS operations(id INTEGER PRIMARY KEY AUTOINCREMENT,content "
             "TEXT NOT NULL,format TEXT NOT NULL,target_id INTEGER NOT NULL,backup_id INTEGER NOT "
             "NULL,original_head INTEGER NOT NULL,status INTEGER NOT NULL);"
             "CREATE UNIQUE INDEX IF NOT EXISTS operations_pending ON operations(content,format) "
             "WHERE status=0;"
             "PRAGMA user_version=1;");
        tx.commit();
        *out = s.release();
        return SH_OK;
    }
    SH_CATCH
}
extern "C" void sh_close(sh_store *s) { delete s; }
extern "C" sh_result sh_put(sh_store *s, const sh_entry *e, sh_id *out) {
    if (out)
        *out = 0;
    try {
        require(s != nullptr);
        require(out);
        validate(e);
        Transaction tx(s);
        idle(s, e->content_key, e->format);
        sh_id id = insert(s, *e);
        if (e->make_head)
            set_head(s, e->content_key, e->format, id);
        if (e->kind == SH_PROTECTION)
            protect(s, *e, id);
        retain(s, e->content_key, id);
        tx.commit();
        *out = id;
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_list(sh_store *s, const char *content, const char *format, uint32_t limit,
                             sh_list_callback callback, void *context) {
    try {
        require(s != nullptr);
        require(key(content) && key(format) && callback);
        Statement q(s, "SELECT "
                       "e.id,e.content,e.format,e.session,e.parent_id,e.created_ms,e.played_ms,e."
                       "kind,e.label,e.pinned,length(e.state),length(e.thumbnail),EXISTS(SELECT 1 "
                       "FROM heads h WHERE h.entry_id=e.id) FROM entries e WHERE e.content=? AND "
                       "e.format=? ORDER BY e.created_ms DESC,e.id DESC LIMIT ?");
        q.text(1, content);
        q.text(2, format);
        q.number(3, limit ? limit : -1LL);
        while (q.step() == SQLITE_ROW) {
            sh_metadata m{};
            m.id = q.integer(0);
            m.content_key = q.text(1);
            m.format = q.text(2);
            m.session = q.text(3);
            m.parent_id = q.integer(4);
            m.created_ms = q.integer(5);
            m.played_ms = q.integer(6);
            m.kind = static_cast<sh_kind>(q.integer(7));
            m.label = q.text(8);
            m.pinned = static_cast<int>(q.integer(9));
            m.state_size = q.integer(10);
            m.thumbnail_size = q.integer(11);
            m.is_head = static_cast<int>(q.integer(12));
            if (callback(context, &m))
                break;
        }
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_read(sh_store *s, sh_id id, const char *content, const char *format,
                             sh_blob blob, void *buffer, size_t capacity, size_t *out) {
    if (out)
        *out = 0;
    try {
        require(s != nullptr);
        require(id > 0 && key(content) && key(format) && out && (!capacity || buffer) &&
                (blob == SH_STATE || blob == SH_THUMBNAIL));
        Statement q(
            s, blob == SH_STATE
                   ? "SELECT state,state_crc FROM entries WHERE id=? AND content=? AND format=?"
                   : "SELECT thumbnail,thumbnail_crc FROM entries WHERE id=? AND content=? AND "
                     "format=?");
        q.number(1, id);
        q.text(2, content);
        q.text(3, format);
        require(q.step() == SQLITE_ROW, SH_NOT_FOUND);
        size_t n = static_cast<size_t>(sqlite3_column_bytes(q.p, 0));
        const void *bytes = sqlite3_column_blob(q.p, 0);
        require(bytes || n == 0, SH_NO_MEMORY);
        require(checksum(bytes, n) == static_cast<uint32_t>(q.integer(1)), SH_CORRUPT);
        *out = n;
        if (!buffer && !capacity)
            return SH_OK;
        if (capacity < n)
            return SH_BUFFER_TOO_SMALL;
        if (n)
            std::memcpy(buffer, bytes, n);
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_get_head(sh_store *s, const char *content, const char *format, sh_id *out) {
    if (out)
        *out = 0;
    try {
        require(s != nullptr);
        require(key(content) && key(format) && out);
        Statement q(s, "SELECT entry_id FROM heads WHERE content=? AND format=?");
        q.text(1, content);
        q.text(2, format);
        require(q.step() == SQLITE_ROW, SH_NOT_FOUND);
        *out = q.integer(0);
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_set_head(sh_store *s, const char *content, const char *format, sh_id id) {
    try {
        require(s != nullptr);
        require(key(content) && key(format) && id >= 0);
        Transaction tx(s);
        idle(s, content, format);
        set_head(s, content, format, id);
        tx.commit();
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_rename(sh_store *s, sh_id id, const char *label) {
    try {
        require(s != nullptr);
        require(id > 0 && label && std::strlen(label) <= 4096);
        Statement q(s, "UPDATE entries SET label=? WHERE id=?");
        q.text(1, label);
        q.number(2, id);
        q.step();
        require(sqlite3_changes(s->db) > 0, SH_NOT_FOUND);
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_pin(sh_store *s, sh_id id, int pinned) {
    try {
        require(s != nullptr);
        require(id > 0);
        Statement q(s, "UPDATE entries SET pinned=? WHERE id=?");
        q.number(1, pinned != 0);
        q.number(2, id);
        q.step();
        require(sqlite3_changes(s->db) > 0, SH_NOT_FOUND);
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_delete(sh_store *s, sh_id id) {
    try {
        require(s != nullptr);
        require(id > 0);
        Transaction tx(s);
        {
            Statement q(s, "SELECT pinned,EXISTS(SELECT 1 FROM heads WHERE entry_id=?1) OR "
                           "EXISTS(SELECT 1 FROM protections WHERE entry_id=?1) OR EXISTS(SELECT 1 "
                           "FROM operations WHERE status=0 AND (target_id=?1 OR backup_id=?1 OR "
                           "original_head=?1)) FROM entries WHERE id=?1");
            q.number(1, id);
            require(q.step() == SQLITE_ROW, SH_NOT_FOUND);
            require(!q.integer(0) && !q.integer(1), SH_PROTECTED);
        }
        Statement q(s, "DELETE FROM entries WHERE id=?");
        q.number(1, id);
        q.step();
        tx.commit();
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_prepare_restore(sh_store *s, sh_id target, const sh_entry *current,
                                        sh_id *out_operation, sh_id *out_backup) {
    if (out_operation)
        *out_operation = 0;
    if (out_backup)
        *out_backup = 0;
    try {
        require(s != nullptr);
        require(target > 0 && out_operation && out_backup && out_operation != out_backup);
        validate(current);
        Transaction tx(s);
        idle(s, current->content_key, current->format);
        verify_state(s, target, current->content_key, current->format);
        sh_id original = 0;
        sh_result head_result = sh_get_head(s, current->content_key, current->format, &original);
        require(head_result == SH_OK || head_result == SH_NOT_FOUND, head_result);
        sh_entry backup = *current;
        backup.kind = SH_PROTECTION;
        backup.make_head = 0;
        sh_id backup_id = insert(s, backup);
        protect(s, backup, backup_id);
        Statement q(
            s, "INSERT INTO operations(content,format,target_id,backup_id,original_head,status) "
               "VALUES(?,?,?,?,?,0)");
        q.text(1, current->content_key);
        q.text(2, current->format);
        q.number(3, target);
        q.number(4, backup_id);
        q.number(5, original);
        q.step();
        sh_id operation = sqlite3_last_insert_rowid(s->db);
        retain(s, current->content_key, backup_id);
        tx.commit();
        *out_operation = operation;
        *out_backup = backup_id;
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_finish_restore(sh_store *s, sh_id operation) {
    try {
        require(s != nullptr);
        complete(s, operation, 1);
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_cancel_restore(sh_store *s, sh_id operation) {
    try {
        require(s != nullptr);
        complete(s, operation, 2);
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_get_pending_restore(sh_store *s, const char *content, const char *format,
                                            sh_id *operation, sh_id *target, sh_id *backup) {
    if (operation)
        *operation = 0;
    if (target)
        *target = 0;
    if (backup)
        *backup = 0;
    try {
        require(s != nullptr);
        require(key(content) && key(format) && operation && target && backup);
        require(operation != target && operation != backup && target != backup);
        Statement q(s, "SELECT id,target_id,backup_id FROM operations WHERE content=? AND format=? "
                       "AND status=0");
        q.text(1, content);
        q.text(2, format);
        require(q.step() == SQLITE_ROW, SH_NOT_FOUND);
        *operation = q.integer(0);
        *target = q.integer(1);
        *backup = q.integer(2);
        return SH_OK;
    }
    SH_CATCH
}
extern "C" sh_result sh_recover_restore(sh_store *s, sh_id operation) {
    try {
        require(s != nullptr);
        complete(s, operation, 3);
        return SH_OK;
    }
    SH_CATCH
}
