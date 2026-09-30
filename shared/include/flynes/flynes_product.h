#ifndef FLYNES_FLYNES_PRODUCT_H
#define FLYNES_FLYNES_PRODUCT_H

#include <flynes/flynes_app.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FLY_PRODUCT_CATALOG_VERSION_1 UINT32_C(1)
#define FLY_PRODUCT_CATALOG_WINDOW_MAX UINT32_C(128)
#define FLY_PRODUCT_QUERY_MAX_UTF8_BYTES UINT32_C(4096)
#define FLY_PRODUCT_CAPABILITY_MAX UINT32_C(65536)
#define FLY_PRODUCT_NO_SNAPSHOT_INDEX UINT64_MAX

enum fly_product_category {
    FLY_PRODUCT_CATEGORY_RECENT = 0,
    FLY_PRODUCT_CATEGORY_FAVORITES = 1,
    FLY_PRODUCT_CATEGORY_ALL = 2,
    FLY_PRODUCT_CATEGORY_BUILTIN = 3
};

enum fly_product_multiplayer_eligibility {
    FLY_PRODUCT_MULTIPLAYER_UNSUPPORTED = 0,
    FLY_PRODUCT_MULTIPLAYER_SUPPORTED = 1,
    FLY_PRODUCT_MULTIPLAYER_UNKNOWN = 2
};

/* Manifest/profile facts supplied by the adapter; never guessed from names.
 * Optional localized title ranges use the query byte limit. They supply search
 * metadata only and do not participate in popularity ranking or identity. */
typedef struct fly_product_capability {
    const char* canonical_id_utf8;
    uint32_t canonical_id_utf8_length;
    uint32_t eligibility;
    uint32_t profile_version;
    const char* title_en_utf8;
    uint32_t title_en_utf8_length;
    const char* title_zh_hans_utf8;
    uint32_t title_zh_hans_utf8_length;
} fly_product_capability;

typedef struct fly_product_catalog_query {
    uint32_t struct_size;
    uint32_t version;
    uint32_t category;
    uint32_t multiplayer_only;
    const char* query_utf8;
    uint32_t query_utf8_length;
    const char* selected_canonical_id_utf8;
    uint32_t selected_canonical_id_utf8_length;
    uint64_t offset;
    uint32_t limit;
    uint32_t registry_profile_version;
    const fly_product_capability* capabilities;
    uint32_t capability_count;
} fly_product_catalog_query;

#define FLY_PRODUCT_CATALOG_QUERY_V1_SIZE \
    ((uint32_t)(offsetof(fly_product_catalog_query, capability_count) + sizeof(uint32_t)))

typedef struct fly_product_catalog_window {
    uint32_t struct_size;
    uint32_t version;
    uint64_t catalog_generation;
    uint64_t filtered_total;
    uint64_t offset;
    uint64_t selected_snapshot_index;
    uint32_t count;
    uint64_t snapshot_indices[FLY_PRODUCT_CATALOG_WINDOW_MAX];
    char selected_canonical_id_utf8[FLY_CANONICAL_ID_MAX_UTF8_BYTES + 1u];
} fly_product_catalog_window;

#define FLY_PRODUCT_CATALOG_WINDOW_V1_SIZE \
    ((uint32_t)(offsetof(fly_product_catalog_window, selected_canonical_id_utf8) \
        + FLY_CANONICAL_ID_MAX_UTF8_BYTES + 1u))

/*
 * Pure synchronous projection of one immutable snapshot. Run on the adapter's
 * worker; no I/O, mutation, runtime, or UI dependency. All input pointers are
 * borrowed for this call only; output is caller-owned. UTF-8 ranges exclude NUL,
 * may be NULL only at zero length, and must not contain embedded NUL.
 *
 * Category/search/order/dedup/multiplayer/selection use shared product rules.
 * Indices map to the SAME supplied snapshot's rows. Reconcile selection against
 * the entire filtered result before slicing, preserving selections outside the
 * window. Missing selection selects its first row; an empty result has empty ID
 * and NO_SNAPSHOT_INDEX. offset beyond total returns an empty window.
 * limit must be 1..128. Errors leave output unchanged. Initialize size/version
 * on both request and output. Catalog generation is the persisted snapshot's
 * generation, NOT a UI revision: the adapter must own its independent revision
 * for query changes, late completions, and favorite refreshes.
 */
FLYNES_API fly_result fly_product_catalog_project(
    const fly_catalog_snapshot_t* snapshot,
    const fly_product_catalog_query* query,
    fly_product_catalog_window* window_out);

#ifdef __cplusplus
}
#endif
#endif
