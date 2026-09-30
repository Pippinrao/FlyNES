#include "product_catalog_projection.hpp"
#include "app/catalog_snapshot.hpp"
#include <cstdio>
#include <memory>
int main() {
    auto data = std::make_shared<flynes::app::CatalogData>();
    data->generation = 41;
    for (int i = 0; i < 3; ++i) {
        flynes::app::CatalogEntryData row;
        row.canonical_id = i < 2 ? "game:a" : "game:b";
        row.variant_id = "v" + std::to_string(i);
        row.display_name = i == 0 ? "Renamed.nes" : "Original.nes";
        row.source_relative_path = row.display_name;
        row.source.scope = i == 1 ? FLY_SOURCE_SCOPE_BUILTIN : FLY_SOURCE_SCOPE_USER_FILE;
        row.source.uuid[0] = static_cast<std::uint8_t>(i + 1);
        data->entries.push_back(row);
    }
    data->users.push_back({"game:a", true, 5, 12, 3});
    fly_catalog_snapshot_handle snapshot(data);
    flynes::harmony::ProductQuery query;
    query.category = "favorites";
    query.view_revision = 9;
    query.capabilities.push_back({"game:a", "Trusted title", "可信标题", true});
    const auto result = flynes::harmony::project_catalog(&snapshot, query);
    if (result.generation != 41 || result.view_revision != 9 || result.total != 1 || result.items.size() != 1) {
        std::fprintf(stderr, "FAIL: projection keeps real generation and shared favorite filtering\n"); return 1;
    }
    const auto& row = result.items.front();
    if (!row.builtin || !row.favorite || !row.multiplayer_supported || row.variant_count != 2 ||
        row.title_en != "Trusted title" || row.last_played_sequence != 12) {
        std::fprintf(stderr, "FAIL: row retains user state, builtin variant, titles and capability\n"); return 1;
    }
    query.offset = 128;
    if (!flynes::harmony::project_catalog(&snapshot, query).items.empty()) return 1;
    const auto item = flynes::harmony::product_catalog_item(&snapshot, "game:b", query.capabilities);
    if (item.canonical_id != "game:b" || item.variant_count != 1) return 1;
    auto duplicates = std::make_shared<flynes::app::CatalogData>(*data);
    duplicates->entries[0].freshness = FLY_CATALOG_FRESHNESS_STALE;
    duplicates->entries[1].source.scope = FLY_SOURCE_SCOPE_USER_DIRECTORY;
    duplicates->entries[1].freshness = FLY_CATALOG_FRESHNESS_FRESH;
    fly_catalog_snapshot_handle duplicate_snapshot(duplicates);
    const auto playable = flynes::harmony::product_catalog_item(&duplicate_snapshot, "game:a", query.capabilities);
    if (!playable.available || playable.relative_path != "Original.nes") {
        std::fprintf(stderr, "FAIL: stale first variant cannot hide a playable duplicate source\n"); return 1;
    }
    std::puts("product_catalog_projection: PASS"); return 0;
}
