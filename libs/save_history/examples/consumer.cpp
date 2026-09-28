#include <save_history/save_history.h>
#include <memory>
int main() {
    sh_store *raw = nullptr;
    if (sh_open(":memory:", nullptr, &raw) != SH_OK)
        return 1;
    std::unique_ptr<sh_store, decltype(&sh_close)> store(raw, sh_close);
    sh_id head = 0;
    return sh_get_head(store.get(), "arbitrary-content", "opaque-1", &head) == SH_NOT_FOUND ? 0 : 2;
}
