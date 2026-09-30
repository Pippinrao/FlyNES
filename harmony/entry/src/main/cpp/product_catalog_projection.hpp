#pragma once
#include <flynes/flynes_product.h>
#include <cstdint>
#include <string>
#include <vector>

namespace flynes::harmony {
struct ProductCapability {
    std::string canonical_id, title_en, title_zh;
    bool multiplayer_supported = false;
};
struct ProductQuery {
    std::string category = "all", query, selected_id;
    bool multiplayer_only = false;
    std::uint64_t offset = 0, view_revision = 0, expected_generation = 0;
    std::uint32_t limit = 128;
    std::vector<ProductCapability> capabilities;
};
struct ProductRow {
    std::string canonical_id, title_en, title_zh, original_filename, source_uuid, relative_path, search_aliases;
    std::uint32_t package_format = 0, variant_count = 0;
    std::uint64_t last_played_sequence = 0;
    bool builtin = false, favorite = false, available = true, multiplayer_supported = false;
};
struct ProductProjection {
    std::uint64_t generation = 0, view_revision = 0, total = 0, offset = 0;
    std::string selected_id;
    std::vector<ProductRow> items;
};
ProductProjection project_catalog(const fly_catalog_snapshot_t* snapshot, const ProductQuery& query);
ProductRow product_catalog_item(const fly_catalog_snapshot_t* snapshot, const std::string& canonical_id,
    const std::vector<ProductCapability>& capabilities);
}
