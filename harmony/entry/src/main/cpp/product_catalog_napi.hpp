#pragma once
#include <flynes/flynes_app.h>
#include "napi/native_api.h"
#include <memory>
namespace flynes::harmony {
void register_product_catalog(napi_env env, napi_value exports, std::shared_ptr<fly_app_t> (*owner)());
void clear_product_catalog_views();
}
