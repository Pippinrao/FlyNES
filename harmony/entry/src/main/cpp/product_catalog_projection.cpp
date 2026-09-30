#include "product_catalog_projection.hpp"
#include <array>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>
namespace flynes::harmony {
namespace {
void checked(fly_result value) {
    if (value != FLY_RESULT_OK) throw std::runtime_error("catalog_unavailable");
}
std::unordered_map<std::string, ProductRow> rows(const fly_catalog_snapshot_t* snapshot,
    const std::vector<ProductCapability>& capabilities) {
    std::unordered_map<std::string, ProductRow> result;
    std::unordered_map<std::string, std::unordered_set<std::string>> variants;
    std::unordered_map<std::string, bool> chosen_builtin;
    std::uint64_t count = 0;
    checked(fly_catalog_snapshot_count(snapshot, &count));
    for (std::uint64_t index = 0; index < count; ++index) {
        std::array<char, FLY_CANONICAL_ID_MAX_UTF8_BYTES + 1> id{}, variant{};
        std::array<char, FLY_SCAN_DISPLAY_NAME_MAX_UTF8_BYTES + 1> display{};
        std::array<char, FLY_SCAN_RELATIVE_PATH_MAX_UTF8_BYTES + 1> relative{};
        fly_catalog_entry entry{};
        entry.struct_size = FLY_CATALOG_ENTRY_V1_SIZE; entry.version = FLY_CATALOG_ENTRY_VERSION_1;
        entry.canonical_id_utf8 = id.data(); entry.canonical_id_capacity = static_cast<std::uint32_t>(id.size());
        entry.variant_id_utf8 = variant.data(); entry.variant_id_capacity = static_cast<std::uint32_t>(variant.size());
        entry.display_name_utf8 = display.data(); entry.display_name_capacity = static_cast<std::uint32_t>(display.size());
        entry.source_relative_path_utf8 = relative.data(); entry.source_relative_path_capacity = static_cast<std::uint32_t>(relative.size());
        checked(fly_catalog_snapshot_get(snapshot, index, &entry));
        auto& row = result[id.data()];
        const bool builtin = entry.source_scope == FLY_SOURCE_SCOPE_BUILTIN;
        const bool available = entry.freshness != FLY_CATALOG_FRESHNESS_STALE;
        // Prefer a bundled locator when identical content also exists in a lost source.
        if (row.canonical_id.empty() || (available && !row.available) ||
            (available == row.available && builtin && !chosen_builtin[id.data()])) {
            row.canonical_id = id.data(); row.original_filename = display.data(); row.relative_path = relative.data();
            row.package_format = entry.package_format;
            row.available = available;
            chosen_builtin[id.data()] = builtin;
            row.source_uuid.clear();
            constexpr char hex[] = "0123456789abcdef";
            for (auto value : entry.source_uuid) { row.source_uuid += hex[value >> 4]; row.source_uuid += hex[value & 15]; }
            fly_game_title title{};
            checked(fly_catalog_snapshot_get_title(snapshot, index, &title));
            row.title_en = title.title_en_utf8 == nullptr ? "" : title.title_en_utf8;
            row.title_zh = title.title_zh_hans_utf8 == nullptr ? "" : title.title_zh_hans_utf8;
            if (row.title_en.empty() && row.title_zh.empty()) row.title_en = display.data();
        }
        row.builtin = row.builtin || builtin;
        variants[id.data()].insert(variant.data());
        row.variant_count = static_cast<std::uint32_t>(variants[id.data()].size());
        if (!row.search_aliases.empty()) row.search_aliases += '\n';
        row.search_aliases += display.data();
    }
    checked(fly_catalog_snapshot_user_count(snapshot, &count));
    for (std::uint64_t index = 0; index < count; ++index) {
        std::array<char, FLY_CANONICAL_ID_MAX_UTF8_BYTES + 1> id{};
        std::uint32_t required = 0;
        fly_catalog_user_state state{};
        state.struct_size = FLY_CATALOG_USER_STATE_V1_SIZE; state.version = FLY_CATALOG_USER_STATE_VERSION_1;
        checked(fly_catalog_snapshot_user_get(snapshot, index, id.data(), static_cast<std::uint32_t>(id.size()), &required, &state));
        auto found = result.find(id.data());
        if (found != result.end()) {
            found->second.favorite = state.favorite != 0;
            found->second.last_played_sequence = state.last_played_sequence;
        }
    }
    for (const auto& fact : capabilities) {
        auto found = result.find(fact.canonical_id);
        if (found == result.end()) continue;
        auto& row = found->second;
        row.multiplayer_supported = fact.multiplayer_supported;
        if (!fact.title_en.empty()) row.title_en = fact.title_en;
        if (!fact.title_zh.empty()) row.title_zh = fact.title_zh;
    }
    return result;
}
}
ProductProjection project_catalog(const fly_catalog_snapshot_t* snapshot, const ProductQuery& input) {
    std::vector<fly_product_capability> facts;
    for (const auto& fact : input.capabilities) facts.push_back({fact.canonical_id.data(),
        static_cast<std::uint32_t>(fact.canonical_id.size()),
        static_cast<std::uint32_t>(fact.multiplayer_supported ? FLY_PRODUCT_MULTIPLAYER_SUPPORTED : FLY_PRODUCT_MULTIPLAYER_UNKNOWN), 1,
        fact.title_en.data(), static_cast<std::uint32_t>(fact.title_en.size()),
        fact.title_zh.data(), static_cast<std::uint32_t>(fact.title_zh.size())});
    fly_product_catalog_query query{};
    query.struct_size = FLY_PRODUCT_CATALOG_QUERY_V1_SIZE; query.version = FLY_PRODUCT_CATALOG_VERSION_1;
    if (input.category == "recent") query.category = FLY_PRODUCT_CATEGORY_RECENT;
    else if (input.category == "favorites") query.category = FLY_PRODUCT_CATEGORY_FAVORITES;
    else if (input.category == "all") query.category = FLY_PRODUCT_CATEGORY_ALL;
    else if (input.category == "builtin") query.category = FLY_PRODUCT_CATEGORY_BUILTIN;
    else throw std::runtime_error("invalid_argument");
    query.multiplayer_only = input.multiplayer_only ? 1 : 0;
    query.query_utf8 = input.query.data(); query.query_utf8_length = static_cast<std::uint32_t>(input.query.size());
    query.selected_canonical_id_utf8 = input.selected_id.data();
    query.selected_canonical_id_utf8_length = static_cast<std::uint32_t>(input.selected_id.size());
    query.offset = input.offset; query.limit = input.limit; query.registry_profile_version = 1;
    query.capabilities = facts.data(); query.capability_count = static_cast<std::uint32_t>(facts.size());
    fly_product_catalog_window window{};
    window.struct_size = FLY_PRODUCT_CATALOG_WINDOW_V1_SIZE; window.version = FLY_PRODUCT_CATALOG_VERSION_1;
    checked(fly_product_catalog_project(snapshot, &query, &window));
    ProductProjection output;
    output.generation = window.catalog_generation; output.view_revision = input.view_revision;
    output.total = window.filtered_total; output.offset = window.offset;
    output.selected_id = window.selected_canonical_id_utf8;
    if (input.expected_generation != 0 && input.expected_generation != output.generation) throw std::runtime_error("snapshot_expired");
    auto all = rows(snapshot, input.capabilities);
    for (std::uint32_t i = 0; i < window.count; ++i) {
        std::array<char, FLY_CANONICAL_ID_MAX_UTF8_BYTES + 1> id{};
        fly_catalog_entry entry{};
        entry.struct_size = FLY_CATALOG_ENTRY_V1_SIZE; entry.version = FLY_CATALOG_ENTRY_VERSION_1;
        entry.canonical_id_utf8 = id.data(); entry.canonical_id_capacity = static_cast<std::uint32_t>(id.size());
        // The public getter requires caller-owned buffers for every string.
        std::array<char, FLY_CANONICAL_ID_MAX_UTF8_BYTES + 1> variant{};
        std::array<char, FLY_SCAN_DISPLAY_NAME_MAX_UTF8_BYTES + 1> display{};
        std::array<char, FLY_SCAN_RELATIVE_PATH_MAX_UTF8_BYTES + 1> relative{};
        entry.variant_id_utf8 = variant.data(); entry.variant_id_capacity = static_cast<std::uint32_t>(variant.size());
        entry.display_name_utf8 = display.data(); entry.display_name_capacity = static_cast<std::uint32_t>(display.size());
        entry.source_relative_path_utf8 = relative.data(); entry.source_relative_path_capacity = static_cast<std::uint32_t>(relative.size());
        checked(fly_catalog_snapshot_get(snapshot, window.snapshot_indices[i], &entry));
        output.items.push_back(all.at(id.data()));
    }
    return output;
}
ProductRow product_catalog_item(const fly_catalog_snapshot_t* snapshot, const std::string& id,
    const std::vector<ProductCapability>& capabilities) {
    auto all = rows(snapshot, capabilities);
    const auto found = all.find(id);
    if (found == all.end()) throw std::runtime_error("not_found");
    return found->second;
}
}
