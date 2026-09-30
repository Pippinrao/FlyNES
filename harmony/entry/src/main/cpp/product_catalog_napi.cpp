#include "product_catalog_napi.hpp"
#include "product_catalog_projection.hpp"
#include <cmath>
#include <map>
#include <memory>
#include <stdexcept>

namespace flynes::harmony {
namespace {
using Snapshot = std::shared_ptr<fly_catalog_snapshot_t>;
struct View { Snapshot snapshot; ProductQuery query; };
std::map<std::uint64_t, View> views; // Accessed only by the N-API event thread.
std::shared_ptr<fly_app_t> (*owner)() = nullptr;
void ok(napi_status status) { if (status != napi_ok) throw std::runtime_error("invalid_argument"); }
napi_value prop(napi_env env, napi_value value, const char* name) {
    napi_value result{}; ok(napi_get_named_property(env, value, name, &result)); return result;
}
std::string string(napi_env env, napi_value value) {
    std::size_t length = 0; ok(napi_get_value_string_utf8(env, value, nullptr, 0, &length));
    if (length > FLY_PRODUCT_QUERY_MAX_UTF8_BYTES) throw std::runtime_error("invalid_argument");
    std::string result(length + 1, '\0');
    ok(napi_get_value_string_utf8(env, value, result.data(), result.size(), &length));
    result.resize(length); return result;
}
std::uint64_t integer(napi_env env, napi_value value) {
    double result = 0; ok(napi_get_value_double(env, value, &result));
    if (!std::isfinite(result) || result < 0 || result > 9007199254740991.0 || std::floor(result) != result)
        throw std::runtime_error("invalid_argument");
    return static_cast<std::uint64_t>(result);
}
bool boolean(napi_env env, napi_value value) { bool result = false; ok(napi_get_value_bool(env, value, &result)); return result; }
napi_value text(napi_env env, const std::string& value) {
    napi_value result{}; ok(napi_create_string_utf8(env, value.data(), value.size(), &result)); return result;
}
void set(napi_env env, napi_value value, const char* key, const std::string& input) { ok(napi_set_named_property(env, value, key, text(env,input))); }
void set(napi_env env, napi_value value, const char* key, std::uint64_t input) {
    napi_value result{}; ok(napi_create_double(env, static_cast<double>(input), &result)); ok(napi_set_named_property(env, value, key, result));
}
void set(napi_env env, napi_value value, const char* key, bool input) {
    napi_value result{}; ok(napi_get_boolean(env, input, &result)); ok(napi_set_named_property(env, value, key, result));
}
std::vector<ProductCapability> capabilities(napi_env env, napi_value input) {
    bool array = false; ok(napi_is_array(env,input,&array)); if (!array) throw std::runtime_error("invalid_argument");
    std::uint32_t count = 0; ok(napi_get_array_length(env,input,&count));
    if (count > FLY_PRODUCT_CAPABILITY_MAX) throw std::runtime_error("invalid_argument");
    std::vector<ProductCapability> output; output.reserve(count);
    for (std::uint32_t i=0;i<count;++i) {
        napi_value value{}; ok(napi_get_element(env,input,i,&value));
        output.push_back({string(env,prop(env,value,"canonicalId")),string(env,prop(env,value,"titleEn")),
            string(env,prop(env,value,"titleZhHans")),boolean(env,prop(env,value,"multiplayerSupported"))});
    }
    return output;
}
Snapshot snapshot() {
    auto app = owner == nullptr ? nullptr : owner();
    if (app == nullptr) throw std::runtime_error("service_unavailable");
    fly_catalog_snapshot_t* value = nullptr;
    if (fly_catalog_snapshot(app.get(),&value) != FLY_RESULT_OK || value == nullptr) throw std::runtime_error("catalog_unavailable");
    return Snapshot(value,fly_catalog_snapshot_release);
}
std::uint64_t generation(const Snapshot& value) {
    std::uint64_t result = 0;
    if (fly_catalog_snapshot_generation(value.get(),&result) != FLY_RESULT_OK) throw std::runtime_error("catalog_unavailable");
    return result;
}
napi_value make_row(napi_env env, const ProductRow& row) {
    napi_value result{}; ok(napi_create_object(env,&result));
    set(env,result,"canonicalId",row.canonical_id); set(env,result,"titleEn",row.title_en); set(env,result,"titleZhHans",row.title_zh);
    set(env,result,"originalFilename",row.original_filename); set(env,result,"sourceUuidHex",row.source_uuid);
    set(env,result,"sourceRelativePath",row.relative_path); set(env,result,"searchAliases",row.search_aliases);
    set(env,result,"packageFormat",static_cast<std::uint64_t>(row.package_format));
    set(env,result,"variantCount",static_cast<std::uint64_t>(row.variant_count));
    set(env,result,"lastPlayedSequence",row.last_played_sequence);
    set(env,result,"builtin",row.builtin); set(env,result,"favorite",row.favorite);
    set(env,result,"available",row.available); set(env,result,"multiplayerSupported",row.multiplayer_supported);
    return result;
}
napi_value make_projection(napi_env env, const ProductProjection& projection) {
    napi_value result{},items{}; ok(napi_create_object(env,&result));
    set(env,result,"catalogGeneration",projection.generation); set(env,result,"viewRevision",projection.view_revision);
    set(env,result,"total",projection.total); set(env,result,"offset",projection.offset); set(env,result,"selectedId",projection.selected_id);
    ok(napi_create_array_with_length(env,projection.items.size(),&items));
    for (std::uint32_t i=0;i<projection.items.size();++i) ok(napi_set_element(env,items,i,make_row(env,projection.items[i])));
    ok(napi_set_named_property(env,result,"items",items)); return result;
}
struct Work {
    napi_async_work handle{}; napi_deferred deferred{};
    Snapshot snapshot; ProductQuery query; std::string id,error;
    std::shared_ptr<fly_app_t> app;
    std::string legacy, target;
    bool item = false;
    ProductProjection projection; ProductRow row;
};
void execute(napi_env, void* data) {
    auto& work = *static_cast<Work*>(data);
    try {
        if (work.app) {
            if (fly_catalog_user_state_copy_if_absent(work.app.get(),work.legacy.data(),static_cast<std::uint32_t>(work.legacy.size()),
                work.target.data(),static_cast<std::uint32_t>(work.target.size())) != FLY_RESULT_OK)
                throw std::runtime_error("storage_failed");
        }
        else if (work.item) work.row = product_catalog_item(work.snapshot.get(),work.id,work.query.capabilities);
        else work.projection = project_catalog(work.snapshot.get(),work.query);
    } catch (const std::exception& error) { work.error = error.what(); }
    catch (...) { work.error = "catalog_unavailable"; }
}
void complete(napi_env env, napi_status status, void* data) {
    std::unique_ptr<Work> work(static_cast<Work*>(data));
    try {
        if (status != napi_ok) work->error = "cancelled";
        if (work->error.empty()) {
            napi_value result{};
            if (work->app) ok(napi_get_undefined(env,&result));
            else result = work->item ? make_row(env,work->row) : make_projection(env,work->projection);
            ok(napi_resolve_deferred(env,work->deferred,result));
        }
        else {
            napi_value error{}; ok(napi_create_error(env,text(env,work->error),text(env,work->error),&error));
            ok(napi_reject_deferred(env,work->deferred,error));
        }
    } catch (...) {
        napi_value error{};
        if (napi_create_error(env,nullptr,text(env,"catalog_unavailable"),&error) == napi_ok)
            napi_reject_deferred(env,work->deferred,error);
    }
    napi_delete_async_work(env,work->handle);
}
napi_value queue(napi_env env,std::unique_ptr<Work> work) {
    napi_value promise{}; ok(napi_create_promise(env,&work->deferred,&promise));
    ok(napi_create_async_work(env,nullptr,text(env,"FlyNES product catalog"),execute,complete,work.get(),&work->handle));
    const auto status = napi_queue_async_work(env,work->handle);
    if (status != napi_ok) { napi_delete_async_work(env,work->handle); throw std::runtime_error("service_unavailable"); }
    work.release(); return promise;
}
napi_value project(napi_env env,napi_callback_info info) {
    try {
        std::size_t count=1; napi_value args[1]{}; ok(napi_get_cb_info(env,info,&count,args,nullptr,nullptr));
        if (count != 1) throw std::runtime_error("invalid_argument");
        auto work=std::make_unique<Work>(); auto& query=work->query;
        query.category=string(env,prop(env,args[0],"category")); query.query=string(env,prop(env,args[0],"query"));
        query.selected_id=string(env,prop(env,args[0],"selectedId")); query.multiplayer_only=boolean(env,prop(env,args[0],"multiplayerOnly"));
        query.offset=integer(env,prop(env,args[0],"offset"));
        const auto limit=integer(env,prop(env,args[0],"limit"));
        if (limit == 0 || limit > 128) throw std::runtime_error("invalid_argument");
        query.limit=static_cast<std::uint32_t>(limit);
        query.view_revision=integer(env,prop(env,args[0],"viewRevision"));
        query.expected_generation=integer(env,prop(env,args[0],"catalogGeneration"));
        if (query.view_revision == 0) throw std::runtime_error("invalid_argument");
        if (query.expected_generation == 0) {
            query.capabilities=capabilities(env,prop(env,args[0],"capabilities"));
            work->snapshot=snapshot();
            if (views.find(query.view_revision) != views.end()) throw std::runtime_error("snapshot_expired");
            views.emplace(query.view_revision,View{work->snapshot,query});
            while (views.size()>3) views.erase(views.begin());
        } else {
            auto found=views.find(query.view_revision);
            if (found == views.end() || generation(found->second.snapshot) != query.expected_generation ||
                generation(snapshot()) != query.expected_generation) throw std::runtime_error("snapshot_expired");
            const auto offset=query.offset; const auto window_limit=query.limit;
            const auto& original=found->second.query;
            if (query.category != original.category || query.query != original.query || query.multiplayer_only != original.multiplayer_only)
                throw std::runtime_error("snapshot_expired");
            query=original; query.offset=offset; query.limit=window_limit;
            work->snapshot=found->second.snapshot;
        }
        return queue(env,std::move(work));
    } catch (const std::exception& error) { napi_throw_error(env,error.what(),error.what()); return nullptr; }
}
napi_value item(napi_env env,napi_callback_info info) {
    try {
        std::size_t count=2; napi_value args[2]{}; ok(napi_get_cb_info(env,info,&count,args,nullptr,nullptr));
        if (count != 2) throw std::runtime_error("invalid_argument");
        auto work=std::make_unique<Work>(); work->item=true; work->id=string(env,args[0]);
        work->query.capabilities=capabilities(env,args[1]); work->snapshot=snapshot();
        return queue(env,std::move(work));
    } catch (const std::exception& error) { napi_throw_error(env,error.what(),error.what()); return nullptr; }
}
napi_value copy_user(napi_env env,napi_callback_info info) {
    try {
        std::size_t count=2; napi_value args[2]{}; ok(napi_get_cb_info(env,info,&count,args,nullptr,nullptr));
        if (count != 2) throw std::runtime_error("invalid_argument");
        auto work=std::make_unique<Work>(); work->legacy=string(env,args[0]); work->target=string(env,args[1]);
        work->app = owner == nullptr ? nullptr : owner();
        if (!work->app) throw std::runtime_error("service_unavailable");
        return queue(env,std::move(work));
    } catch (const std::exception& error) { napi_throw_error(env,error.what(),error.what()); return nullptr; }
}
}
void clear_product_catalog_views() { views.clear(); }
void register_product_catalog(napi_env env,napi_value exports,std::shared_ptr<fly_app_t> (*get_owner)()) {
    owner=get_owner;
    const napi_property_descriptor properties[] = {
        {"productCatalogProject",nullptr,project,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"productCatalogItem",nullptr,item,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"catalogUserStateCopyIfAbsent",nullptr,copy_user,nullptr,nullptr,nullptr,napi_default,nullptr}
    };
    ok(napi_define_properties(env,exports,sizeof(properties)/sizeof(properties[0]),properties));
}
}
