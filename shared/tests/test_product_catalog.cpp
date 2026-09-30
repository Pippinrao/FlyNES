#include <flynes/flynes_product.h>
#include "app/catalog_snapshot.hpp"

#include <cstdio>
#include <cstring>
#include <memory>
#include <string>

namespace {
int failures = 0;
void check(bool value, const char* message) {
    if (!value) { std::fprintf(stderr, "FAIL: %s\n", message); ++failures; }
}

fly_product_catalog_query query() {
    fly_product_catalog_query q{};
    q.struct_size = FLY_PRODUCT_CATALOG_QUERY_V1_SIZE;
    q.version = FLY_PRODUCT_CATALOG_VERSION_1;
    q.category = FLY_PRODUCT_CATEGORY_ALL;
    q.limit = FLY_PRODUCT_CATALOG_WINDOW_MAX;
    return q;
}

fly_product_catalog_window project(const fly_catalog_snapshot_t* snapshot,
                                   const fly_product_catalog_query& q) {
    fly_product_catalog_window out{};
    out.struct_size = FLY_PRODUCT_CATALOG_WINDOW_V1_SIZE;
    out.version = FLY_PRODUCT_CATALOG_VERSION_1;
    check(fly_product_catalog_project(snapshot, &q, &out) == FLY_RESULT_OK,
          "projection succeeds for valid catalog query");
    return out;
}

void add(flynes::app::CatalogData& data, const char* id, const char* name,
         bool builtin = false) {
    flynes::app::CatalogEntryData row;
    row.canonical_id = id;
    row.display_name = name;
    row.source_relative_path = name;
    row.source.scope = builtin ? FLY_SOURCE_SCOPE_BUILTIN : FLY_SOURCE_SCOPE_USER_FILE;
    data.entries.push_back(row);
}

void test_business_projection() {
    auto data = std::make_shared<flynes::app::CatalogData>();
    data->generation = 47;
    add(*data, "z", "ordinary.nes");
    add(*data, "a", "Contra.nes");
    const char* known_hash = "6ba53139fa88b8de1ae527c438bda6f1541d1ee7df26d63dec5164a32d166bfe";
    for (std::size_t i = 0; i < 32; ++i) {
        data->entries.back().payload_sha256[i] = static_cast<std::uint8_t>(
            std::stoul(std::string(known_hash + i * 2, 2), nullptr, 16));
    }
    add(*data, "z", "Alternate.nes", true);
    add(*data, "b", "Mario.nes");
    data->users.push_back({"z", true, 1, 5, 1});
    data->users.push_back({"b", false, 0, 9, 1});
    fly_catalog_snapshot_handle snapshot(data);
    auto q = query();
    q.limit = 1;
    q.selected_canonical_id_utf8 = "z";
    q.selected_canonical_id_utf8_length = 1;
    auto out = project(&snapshot, q);
    check(out.catalog_generation == 47, "returns actual catalog generation");
    check(out.filtered_total == 3 && out.count == 1, "deduplicates canonical IDs before window");
    check(out.snapshot_indices[0] == 1, "shared popularity puts Contra before Mario");
    check(std::strcmp(out.selected_canonical_id_utf8, "z") == 0,
          "preserves explicit selection outside first window");
    check(out.selected_snapshot_index == 0, "selection maps back to catalog row");

    q.category = FLY_PRODUCT_CATEGORY_FAVORITES;
    out = project(&snapshot, q);
    check(out.filtered_total == 1 && out.snapshot_indices[0] == 0, "favorites from immutable user records");
    q.category = FLY_PRODUCT_CATEGORY_RECENT;
    q.limit = 128;
    out = project(&snapshot, q);
    check(out.count == 2 && out.snapshot_indices[0] == 3 && out.snapshot_indices[1] == 0,
          "recent sorts by last played descending");
    q.category = FLY_PRODUCT_CATEGORY_BUILTIN;
    out = project(&snapshot, q);
    check(out.count == 1 && std::strcmp(out.selected_canonical_id_utf8, "z") == 0,
          "builtin includes a canonical with a later builtin source variant");
    q.category = FLY_PRODUCT_CATEGORY_ALL;
    q.query_utf8 = "  aLtErNaTe  ";
    q.query_utf8_length = 13;
    out = project(&snapshot, q);
    check(out.count == 1 && out.snapshot_indices[0] == 0,
          "search matches secondary source variant without changing canonical row");
    q.query_utf8 = "Contra (J)";
    q.query_utf8_length = 10;
    out = project(&snapshot, q);
    check(out.count == 1 && out.snapshot_indices[0] == 1,
          "search matches catalog title-index aliases");

    fly_product_capability manifest{};
    manifest.canonical_id_utf8 = "z";
    manifest.canonical_id_utf8_length = 1;
    manifest.eligibility = FLY_PRODUCT_MULTIPLAYER_UNKNOWN;
    manifest.title_en_utf8 = "Localized Display";
    manifest.title_en_utf8_length = 17;
    manifest.title_zh_hans_utf8 = "\xE6\xB8\xB8\xE6\x88\x8F";
    manifest.title_zh_hans_utf8_length = 6;
    q.capabilities = &manifest;
    q.capability_count = 1;
    q.query_utf8 = manifest.title_zh_hans_utf8;
    q.query_utf8_length = 6;
    out = project(&snapshot, q);
    check(out.count == 1 && out.snapshot_indices[0] == 0,
          "search matches Chinese builtin manifest title supplied as facts");
    q.query_utf8 = "localized display";
    q.query_utf8_length = 17;
    out = project(&snapshot, q);
    check(out.count == 1 && out.snapshot_indices[0] == 0,
          "search matches English builtin manifest title supplied as facts");

    q.query_utf8 = nullptr;
    q.query_utf8_length = 0;
    q.multiplayer_only = 1;
    fly_product_capability caps[]{{"a", 1, FLY_PRODUCT_MULTIPLAYER_SUPPORTED, 3, nullptr, 0, nullptr, 0},
                                  {"b", 1, FLY_PRODUCT_MULTIPLAYER_SUPPORTED, 2, nullptr, 0, nullptr, 0},
                                  {"z", 1, FLY_PRODUCT_MULTIPLAYER_UNSUPPORTED, 3, nullptr, 0, nullptr, 0}};
    q.registry_profile_version = 3;
    q.capabilities = caps;
    q.capability_count = 3;
    out = project(&snapshot, q);
    check(out.count == 1 && out.snapshot_indices[0] == 1,
          "multiplayer respects registry version and excludes unsupported or unknown");
    check(std::strcmp(out.selected_canonical_id_utf8, "a") == 0,
          "selection reconciles when prior choice is filtered away");
    q.capability_count = 0;
    out = project(&snapshot, q);
    check(out.filtered_total == 0 && out.count == 0 && out.selected_canonical_id_utf8[0] == '\0'
          && out.selected_snapshot_index == FLY_PRODUCT_NO_SNAPSHOT_INDEX,
          "empty multiplayer registry stays unknown and empty selection is explicit");
}

void test_bounds() {
    auto data = std::make_shared<flynes::app::CatalogData>();
    for (unsigned i = 0; i < 145; ++i) {
        const std::string id = "id" + std::to_string(1000 + i);
        add(*data, id.c_str(), "ordinary.nes");
    }
    fly_catalog_snapshot_handle snapshot(data);
    auto q = query();
    auto out = project(&snapshot, q);
    check(out.count == 128 && out.filtered_total == 145, "bounded window retains full total above 128");
    q.offset = 128;
    out = project(&snapshot, q);
    check(out.count == 17 && out.snapshot_indices[0] == 128, "second window continues sorted catalog");
    q.offset = UINT64_MAX;
    out = project(&snapshot, q);
    check(out.count == 0 && out.filtered_total == 145 && out.selected_snapshot_index == 0,
          "huge offset cannot overflow and does not clear selection");
    const auto unchanged = out;
    const auto invalid = [&](const fly_catalog_snapshot_t* input, fly_result expected, const char* name) {
        check(fly_product_catalog_project(input, &q, &out) == expected, name);
        check(std::memcmp(&unchanged, &out, sizeof(out)) == 0, "invalid input leaves output unchanged");
    };
    invalid(nullptr, FLY_RESULT_INVALID_ARGUMENT, "null snapshot rejected");
    q.limit = 129;
    invalid(&snapshot, FLY_RESULT_INVALID_ARGUMENT, "limit above 128 rejected");
    q.limit = 0;
    invalid(&snapshot, FLY_RESULT_INVALID_ARGUMENT, "zero limit rejected");
    q.limit = 1;
    q.category = 99;
    invalid(&snapshot, FLY_RESULT_INVALID_ARGUMENT, "invalid category rejected");
    q.category = FLY_PRODUCT_CATEGORY_ALL;
    q.query_utf8_length = 1;
    invalid(&snapshot, FLY_RESULT_INVALID_ARGUMENT, "nonzero string size with null pointer rejected");
    q.query_utf8 = "\xC0\x80";
    q.query_utf8_length = 2;
    invalid(&snapshot, FLY_RESULT_INVALID_ARGUMENT, "malformed UTF8 rejected");
    q.query_utf8_length = 0;
    q.struct_size = 0;
    invalid(&snapshot, FLY_RESULT_STRUCT_TOO_SMALL, "short request rejected");
    q.struct_size = FLY_PRODUCT_CATALOG_QUERY_V1_SIZE;
    q.version = 99;
    invalid(&snapshot, FLY_RESULT_UNSUPPORTED_VERSION, "unknown request version rejected");
}
}

int main() {
    test_business_projection();
    test_bounds();
    if (failures == 0) std::puts("flynes_product_catalog_test: PASS");
    return failures == 0 ? 0 : 1;
}
