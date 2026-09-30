#include <flynes/flynes_product.h>

/* Compile and link the additive public ABI from C, with the old ABI visible. */
int main(void) {
    fly_product_catalog_query query = {0};
    fly_product_catalog_window window = {0};
    query.struct_size = FLY_PRODUCT_CATALOG_QUERY_V1_SIZE;
    query.version = FLY_PRODUCT_CATALOG_VERSION_1;
    window.struct_size = FLY_PRODUCT_CATALOG_WINDOW_V1_SIZE;
    window.version = FLY_PRODUCT_CATALOG_VERSION_1;
    return fly_product_catalog_project(NULL, &query, &window) == FLY_RESULT_INVALID_ARGUMENT ? 0 : 1;
}
