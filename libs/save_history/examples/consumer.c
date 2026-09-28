#include <save_history/save_history.h>
#include <string.h>
int main(void) {
    const unsigned char state[] = {1, 0, 255, 3};
    sh_store *store = NULL;
    sh_entry entry = {0};
    sh_id id = 0, head = 0;
    unsigned char result[sizeof(state)] = {0};
    size_t size = 0;
    if (sh_open(":memory:", NULL, &store) != SH_OK)
        return 1;
    entry.struct_size = sizeof(entry);
    entry.content_key = "arbitrary-content";
    entry.format = "example-opaque-1";
    entry.session = "example-session";
    entry.kind = SH_MANUAL;
    entry.state = state;
    entry.state_size = sizeof(state);
    entry.make_head = 1;
    if (sh_put(store, &entry, &id) != SH_OK)
        return 2;
    if (sh_get_head(store, entry.content_key, entry.format, &head) != SH_OK || head != id)
        return 3;
    if (sh_read(store, id, entry.content_key, entry.format, SH_STATE, result, sizeof(result),
                &size) != SH_OK)
        return 4;
    if (sh_recover_restore(store, 1) != SH_NOT_FOUND)
        return 6;
    sh_close(store);
    return size == sizeof(state) && memcmp(state, result, size) == 0 ? 0 : 5;
}
