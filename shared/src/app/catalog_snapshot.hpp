#pragma once

#include "app/catalog_state.hpp"
#include <memory>
#include <utility>

// Private storage for the public opaque, immutable snapshot handle.
struct fly_catalog_snapshot_handle final
{
    explicit fly_catalog_snapshot_handle(std::shared_ptr<const flynes::app::CatalogData> data)
        : catalog(std::move(data)) {}
    std::shared_ptr<const flynes::app::CatalogData> catalog;
};
