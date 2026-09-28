#include "save_history/save_history.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>
#include <thread>
#include <chrono>
#include "sqlite3.h"
#define CHECK(x)                                                                                   \
    do {                                                                                           \
        if (!(x)) {                                                                                \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #x);                      \
            std::exit(1);                                                                          \
        }                                                                                          \
    } while (0)
static sh_entry entry(const char *key = "content", int64_t time = 1, sh_kind kind = SH_AUTO) {
    static const unsigned char state[] = {0, 1, 2, 255, 0, 91};
    static const unsigned char thumb[] = {8, 0, 7};
    sh_entry e{};
    e.struct_size = sizeof e;
    e.content_key = key;
    e.format = "opaque-v1";
    e.session = "session-a";
    e.created_ms = time;
    e.played_ms = 100;
    e.kind = kind;
    e.state = state;
    e.state_size = sizeof state;
    e.thumbnail = thumb;
    e.thumbnail_size = sizeof thumb;
    return e;
}
static int collect(void *p, const sh_metadata *m) {
    static_cast<std::vector<sh_id> *>(p)->push_back(m->id);
    return 0;
}
static std::vector<sh_id> list(sh_store *s, const char *key = "content") {
    std::vector<sh_id> r;
    CHECK(sh_list(s, key, "opaque-v1", 0, collect, &r) == SH_OK);
    return r;
}
static void basic() {
    const char *path = "save-history-basic-test.sqlite";
    std::remove(path);
    sh_store *s = nullptr;
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    auto e = entry();
    e.make_head = 1;
    sh_id a = 0, b = 0;
    CHECK(sh_put(s, &e, &a) == SH_OK);
    CHECK(a > 0);
    e.created_ms = 2;
    e.make_head = 0;
    e.parent_id = a;
    CHECK(sh_put(s, &e, &b) == SH_OK);
    CHECK(b > a);
    auto ids = list(s);
    CHECK(ids.size() == 2 && ids[0] == b && ids[1] == a);
    sh_id head = 0;
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == a);
    CHECK(sh_set_head(s, e.content_key, e.format, b) == SH_OK);
    size_t needed = 0;
    CHECK(sh_read(s, a, e.content_key, e.format, SH_STATE, nullptr, 0, &needed) == SH_OK &&
          needed == e.state_size);
    unsigned char bytes[20];
    std::memset(bytes, 42, sizeof bytes);
    CHECK(sh_read(s, a, e.content_key, e.format, SH_STATE, bytes, 1, &needed) ==
              SH_BUFFER_TOO_SMALL &&
          bytes[0] == 42);
    CHECK(sh_read(s, a, "wrong", e.format, SH_STATE, bytes, sizeof bytes, &needed) == SH_NOT_FOUND);
    CHECK(sh_read(s, a, e.content_key, "wrong", SH_STATE, bytes, sizeof bytes, &needed) ==
          SH_NOT_FOUND);
    CHECK(list(s, "wrong").empty());
    CHECK(sh_rename(s, a, "keep this") == SH_OK);
    CHECK(sh_pin(s, a, 1) == SH_OK);
    CHECK(sh_delete(s, a) == SH_PROTECTED);
    CHECK(sh_pin(s, a, 0) == SH_OK);
    CHECK(sh_delete(s, b) == SH_PROTECTED);
    sh_close(s);
    s = nullptr;
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == b);
    CHECK(sh_read(s, a, e.content_key, e.format, SH_STATE, bytes, sizeof bytes, &needed) == SH_OK);
    CHECK(needed == e.state_size && std::memcmp(bytes, e.state, needed) == 0);
    CHECK(sh_read(s, a, e.content_key, e.format, SH_THUMBNAIL, bytes, sizeof bytes, &needed) ==
          SH_OK);
    CHECK(needed == e.thumbnail_size && std::memcmp(bytes, e.thumbnail, needed) == 0);
    CHECK(sh_delete(s, a) == SH_OK);
    CHECK(list(s).size() == 1);
    sh_close(s);
    std::remove(path);
}
static void retention() {
    sh_store *s = nullptr;
    CHECK(sh_open(":memory:", nullptr, &s) == SH_OK);
    auto e = entry();
    sh_id id = 0, manual = 0, pin = 0, head = 0, protection = 0;
    e.kind = SH_MANUAL;
    CHECK(sh_put(s, &e, &manual) == SH_OK);
    e.kind = SH_AUTO;
    e.pinned = 1;
    CHECK(sh_put(s, &e, &pin) == SH_OK);
    e.pinned = 0;
    e.make_head = 1;
    CHECK(sh_put(s, &e, &head) == SH_OK);
    e.make_head = 0;
    e.kind = SH_PROTECTION;
    CHECK(sh_put(s, &e, &protection) == SH_OK);
    e.kind = SH_AUTO;
    for (int i = 0; i < 65; ++i) {
        e.created_ms = 100 + i;
        CHECK(sh_put(s, &e, &id) == SH_OK);
    }
    auto ids = list(s);
    CHECK(ids.size() == 64);
    size_t n = 0;
    for (sh_id kept : {manual, pin, head, protection})
        CHECK(sh_read(s, kept, e.content_key, e.format, SH_STATE, nullptr, 0, &n) == SH_OK);
    CHECK(sh_delete(s, protection) == SH_PROTECTED);
    sh_close(s);
}
static void quota() {
    sh_options options{sizeof(sh_options), 2, 27, 36};
    sh_store *s = nullptr;
    CHECK(sh_open(":memory:", &options, &s) == SH_OK);
    auto e = entry();
    e.make_head = 1;
    sh_id head = 0, id = 0;
    CHECK(sh_put(s, &e, &head) == SH_OK);
    e.make_head = 0;
    e.kind = SH_MANUAL;
    e.created_ms = 2;
    CHECK(sh_put(s, &e, &id) == SH_OK);
    e.created_ms = 3;
    CHECK(sh_put(s, &e, &id) == SH_OK);
    e.created_ms = 4;
    e.state_size = 20;
    unsigned char large[20]{};
    e.state = large;
    e.make_head = 1;
    CHECK(sh_put(s, &e, &id) == SH_QUOTA && id == 0);
    sh_id actual = 0;
    CHECK(sh_get_head(s, e.content_key, e.format, &actual) == SH_OK && actual == head);
    CHECK(list(s).size() == 3);
    e = entry("other", 5, SH_MANUAL);
    CHECK(sh_put(s, &e, &id) == SH_OK);
    e.created_ms = 6;
    CHECK(sh_put(s, &e, &id) == SH_QUOTA && list(s, "other").size() == 1);
    sh_close(s);
    options.max_content_bytes = 18;
    options.max_total_bytes = 100;
    CHECK(sh_open(":memory:", &options, &s) == SH_OK);
    e = entry();
    for (int i = 0; i < 4; ++i) {
        e.created_ms = i;
        CHECK(sh_put(s, &e, &id) == SH_OK);
    }
    CHECK(list(s).size() == 2);
    sh_close(s);
}
static void integrity() {
    const char *path = "save-history-corrupt-test.sqlite";
    std::remove(path);
    sh_store *s = nullptr;
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    auto e = entry();
    sh_id id = 0;
    CHECK(sh_put(s, &e, &id) == SH_OK);
    sh_close(s);
    sqlite3 *db = nullptr;
    CHECK(sqlite3_open(path, &db) == SQLITE_OK);
    CHECK(sqlite3_exec(db, "UPDATE entries SET state=x'01',thumbnail=x'02'", nullptr, nullptr,
                       nullptr) == SQLITE_OK);
    CHECK(sqlite3_close(db) == SQLITE_OK);
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    size_t size = 0;
    CHECK(sh_read(s, id, e.content_key, e.format, SH_STATE, nullptr, 0, &size) == SH_CORRUPT);
    CHECK(sh_read(s, id, e.content_key, e.format, SH_THUMBNAIL, nullptr, 0, &size) == SH_CORRUPT);
    sh_close(s);
    std::remove(path);
}
static void restore() {
    const char *path = "save-history-restore-test.sqlite";
    std::remove(path);
    sh_store *s = nullptr;
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    auto e = entry();
    sh_id target = 0, old = 0, op = 0, backup = 0, head = 0;
    CHECK(sh_put(s, &e, &target) == SH_OK);
    e.created_ms = 2;
    e.make_head = 1;
    CHECK(sh_put(s, &e, &old) == SH_OK);
    e.created_ms = 3;
    CHECK(sh_prepare_restore(s, target, &e, &op, &backup) == SH_OK);
    CHECK(op > 0 && backup > old);
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == old);
    CHECK(sh_delete(s, target) == SH_PROTECTED);
    CHECK(sh_delete(s, backup) == SH_PROTECTED);
    sh_id other = 0;
    CHECK(sh_put(s, &e, &other) == SH_BUSY);
    CHECK(sh_set_head(s, e.content_key, e.format, target) == SH_BUSY);
    sh_close(s);
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    sh_id pending = 0, ptarget = 0, pbackup = 0;
    CHECK(sh_get_pending_restore(s, e.content_key, e.format, &pending, &ptarget, &pbackup) ==
              SH_OK &&
          pending == op && ptarget == target && pbackup == backup);
    CHECK(sh_cancel_restore(s, op) == SH_OK);
    CHECK(sh_cancel_restore(s, op) == SH_OK);
    CHECK(sh_finish_restore(s, op) == SH_CONFLICT);
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == old);
    CHECK(sh_delete(s, backup) == SH_PROTECTED);
    CHECK(sh_prepare_restore(s, target, &e, &op, &backup) == SH_OK);
    CHECK(sh_finish_restore(s, op) == SH_OK);
    CHECK(sh_finish_restore(s, op) == SH_OK);
    CHECK(sh_cancel_restore(s, op) == SH_CONFLICT);
    CHECK(sh_get_pending_restore(s, e.content_key, e.format, &pending, &ptarget, &pbackup) ==
          SH_NOT_FOUND);
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == target);
    sh_close(s);
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == target);
    sh_close(s);
    std::remove(path);
}
static void restore_failure() {
    sh_options options{sizeof(sh_options), 60, 27, 27};
    sh_store *s = nullptr;
    CHECK(sh_open(":memory:", &options, &s) == SH_OK);
    auto e = entry();
    sh_id target = 0, old = 0, protection = 0, op = 0, backup = 0;
    e.kind = SH_MANUAL;
    CHECK(sh_put(s, &e, &target) == SH_OK);
    e.make_head = 1;
    CHECK(sh_put(s, &e, &old) == SH_OK);
    e.make_head = 0;
    e.kind = SH_PROTECTION;
    CHECK(sh_put(s, &e, &protection) == SH_OK);
    CHECK(sh_pin(s, protection, 1) == SH_OK);
    CHECK(sh_prepare_restore(s, target, &e, &op, &backup) == SH_QUOTA && op == 0 && backup == 0);
    CHECK(list(s).size() == 3);
    sh_id head = 0;
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == old);
    CHECK(sh_delete(s, protection) == SH_PROTECTED);
    e.content_key = "wrong";
    CHECK(sh_prepare_restore(s, target, &e, &op, &backup) == SH_NOT_FOUND);
    sh_close(s);
}
static void commit_failure() {
    const char *path = "save-history-commit-test.sqlite";
    std::remove(path);
    sh_store *s = nullptr;
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    auto e = entry();
    e.make_head = 1;
    sh_id original = 0, id = 0;
    CHECK(sh_put(s, &e, &original) == SH_OK);
    sqlite3 *reader = nullptr;
    CHECK(sqlite3_open(path, &reader) == SQLITE_OK);
    CHECK(sqlite3_exec(reader, "BEGIN;SELECT * FROM entries", nullptr, nullptr, nullptr) ==
          SQLITE_OK);
    e.created_ms = 2;
    CHECK(sh_put(s, &e, &id) == SH_BUSY && id == 0);
    CHECK(sqlite3_exec(reader, "COMMIT", nullptr, nullptr, nullptr) == SQLITE_OK);
    CHECK(sqlite3_close(reader) == SQLITE_OK);
    CHECK(list(s).size() == 1);
    CHECK(sh_get_head(s, e.content_key, e.format, &id) == SH_OK && id == original);
    sh_close(s);
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    CHECK(list(s).size() == 1);
    sh_close(s);
    std::remove(path);
}
static void recovery() {
    const char *path = "save-history-recovery-test.sqlite";
    std::remove(path);
    sh_store *s = nullptr;
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    auto e = entry();
    sh_id target = 0, original = 0, operation = 0, backup = 0, head = 0;
    CHECK(sh_put(s, &e, &target) == SH_OK);
    e.created_ms = 2;
    e.make_head = 1;
    CHECK(sh_put(s, &e, &original) == SH_OK);
    e.created_ms = 3;
    CHECK(sh_prepare_restore(s, target, &e, &operation, &backup) == SH_OK);

    // A real reader lets the write begin but blocks COMMIT. Recovery must leave
    // both original head and pending intent intact, including after reopen.
    sqlite3 *reader = nullptr;
    CHECK(sqlite3_open(path, &reader) == SQLITE_OK);
    CHECK(sqlite3_exec(reader, "BEGIN;SELECT * FROM entries", nullptr, nullptr, nullptr) ==
          SQLITE_OK);
    CHECK(sh_recover_restore(s, operation) == SH_BUSY);
    CHECK(sqlite3_exec(reader, "COMMIT", nullptr, nullptr, nullptr) == SQLITE_OK);
    CHECK(sqlite3_close(reader) == SQLITE_OK);
    sh_close(s);
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == original);
    sh_id pending = 0, pending_target = 0, pending_backup = 0;
    CHECK(sh_get_pending_restore(s, e.content_key, e.format, &pending, &pending_target,
                                 &pending_backup) == SH_OK);
    CHECK(pending == operation && pending_target == target && pending_backup == backup);

    CHECK(sh_recover_restore(s, operation) == SH_OK);
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == backup);
    CHECK(sh_get_pending_restore(s, e.content_key, e.format, &pending, &pending_target,
                                 &pending_backup) == SH_NOT_FOUND);
    sh_close(s);
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    CHECK(sh_recover_restore(s, operation) == SH_OK);
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == backup);
    CHECK(sh_finish_restore(s, operation) == SH_CONFLICT);
    CHECK(sh_cancel_restore(s, operation) == SH_CONFLICT);

    CHECK(sh_prepare_restore(s, target, &e, &operation, &backup) == SH_OK);
    CHECK(sh_cancel_restore(s, operation) == SH_OK);
    CHECK(sh_recover_restore(s, operation) == SH_CONFLICT);
    CHECK(sh_prepare_restore(s, target, &e, &operation, &backup) == SH_OK);
    CHECK(sh_finish_restore(s, operation) == SH_OK);
    CHECK(sh_recover_restore(s, operation) == SH_CONFLICT);
    CHECK(sh_get_head(s, e.content_key, e.format, &head) == SH_OK && head == target);
    sh_close(s);
    std::remove(path);
}
static void migration() {
    const char *path = "save-history-migration-test.sqlite";
    std::remove(path);
    sqlite3 *db = nullptr;
    CHECK(sqlite3_open(path, &db) == SQLITE_OK);
    CHECK(sqlite3_exec(db, "PRAGMA user_version=0", nullptr, nullptr, nullptr) == SQLITE_OK);
    CHECK(sqlite3_close(db) == SQLITE_OK);
    sh_store *s = nullptr;
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    auto e = entry();
    sh_id id = 0;
    CHECK(sh_put(s, &e, &id) == SH_OK);
    sh_close(s);
    CHECK(sqlite3_open(path, &db) == SQLITE_OK);
    sqlite3_stmt *q = nullptr;
    CHECK(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &q, nullptr) == SQLITE_OK);
    CHECK(sqlite3_step(q) == SQLITE_ROW && sqlite3_column_int(q, 0) == 1);
    CHECK(sqlite3_finalize(q) == SQLITE_OK);
    CHECK(sqlite3_exec(db, "PRAGMA user_version=2", nullptr, nullptr, nullptr) == SQLITE_OK);
    CHECK(sqlite3_close(db) == SQLITE_OK);
    CHECK(sh_open(path, nullptr, &s) == SH_UNSUPPORTED && s == nullptr);
    std::remove(path);
}
static void kill_fixture(const char *path, bool check) {
    sh_store *s = nullptr;
    CHECK(sh_open(path, nullptr, &s) == SH_OK);
    auto e = entry();
    e.make_head = 1;
    sh_id id = 0;
    if (!check)
        CHECK(sh_put(s, &e, &id) == SH_OK);
    else {
        CHECK(sh_get_head(s, e.content_key, e.format, &id) == SH_OK);
        unsigned char data[20]{};
        size_t size = 0;
        CHECK(sh_read(s, id, e.content_key, e.format, SH_STATE, data, sizeof(data), &size) ==
              SH_OK);
        CHECK(size == e.state_size && std::memcmp(data, e.state, size) == 0);
        CHECK(list(s).size() == 1);
    }
    sh_close(s);
}
static void hold_transaction(const char *path, const char *ready) {
    sqlite3 *db = nullptr;
    CHECK(sqlite3_open(path, &db) == SQLITE_OK);
    CHECK(sqlite3_exec(db,
                       "PRAGMA cache_size=10;BEGIN IMMEDIATE;UPDATE entries SET "
                       "state=zeroblob(1048576);DELETE FROM heads;",
                       nullptr, nullptr, nullptr) == SQLITE_OK);
    FILE *f = nullptr;
#ifdef _WIN32
    CHECK(fopen_s(&f, ready, "wb") == 0);
#else
    f = std::fopen(ready, "wb");
#endif
    CHECK(f);
    std::fputs("ready", f);
    CHECK(std::fclose(f) == 0);
    for (;;)
        std::this_thread::sleep_for(std::chrono::seconds(1));
}
int main(int argc, char **argv) {
    if (argc > 1 && std::string(argv[1]) == "open") {
        sh_store *s = nullptr;
        CHECK(sh_open(":memory:", nullptr, &s) == SH_OK);
        CHECK(s);
        sh_close(s);
    } else if (argc > 1 && std::string(argv[1]) == "retention")
        retention();
    else if (argc > 1 && std::string(argv[1]) == "quota")
        quota();
    else if (argc > 1 && std::string(argv[1]) == "integrity")
        integrity();
    else if (argc > 1 && std::string(argv[1]) == "restore")
        restore();
    else if (argc > 1 && std::string(argv[1]) == "restore_failure")
        restore_failure();
    else if (argc > 1 && std::string(argv[1]) == "commit_failure")
        commit_failure();
    else if (argc > 1 && std::string(argv[1]) == "recovery")
        recovery();
    else if (argc > 1 && std::string(argv[1]) == "migration")
        migration();
    else if (argc > 2 && std::string(argv[1]) == "kill_prepare")
        kill_fixture(argv[2], false);
    else if (argc > 2 && std::string(argv[1]) == "kill_check")
        kill_fixture(argv[2], true);
    else if (argc > 3 && std::string(argv[1]) == "kill_hold")
        hold_transaction(argv[2], argv[3]);
    else
        basic();
    std::puts("PASS save history");
}
