#include "save_history_napi.hpp"
#include "save_history/save_history.h"
#include "catalog/content_identity.hpp"
#include <array>
#include <chrono>
#include <cmath>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
namespace {
constexpr const char* format = "fly-runtime-checkpoint-v1";
void check(napi_status s) { if(s != napi_ok) throw std::runtime_error("Invalid history argument"); }
void check(sh_result s) { if(s != SH_OK) throw std::runtime_error("Save history error " + std::to_string(s)); }
napi_value num(napi_env e,int64_t n) { napi_value v; check(napi_create_int64(e,n,&v)); return v; }
napi_value boolean(napi_env e,bool n) { napi_value v; check(napi_get_boolean(e,n,&v)); return v; }
napi_value str(napi_env e,const char* n) { napi_value v; check(napi_create_string_utf8(e,n,NAPI_AUTO_LENGTH,&v)); return v; }
napi_value prop(napi_env e,napi_value o,const char* k) { napi_value v; check(napi_get_named_property(e,o,k,&v)); return v; }
void field(napi_env e,napi_value o,const char* k,napi_value v) { check(napi_set_named_property(e,o,k,v)); }
std::string text(napi_env e,napi_value v) {
    size_t n=0; check(napi_get_value_string_utf8(e,v,nullptr,0,&n)); std::vector<char> b(n+1);
    check(napi_get_value_string_utf8(e,v,b.data(),b.size(),&n)); return std::string(b.data(),n);
}
int64_t integer(napi_env e,napi_value v) {
    double n; check(napi_get_value_double(e,v,&n));
    if(!std::isfinite(n)||n<0||n>9007199254740991.0||std::floor(n)!=n) throw std::runtime_error("Invalid history number");
    return static_cast<int64_t>(n);
}
bool flag(napi_env e,napi_value v) { bool b; check(napi_get_value_bool(e,v,&b)); return b; }
struct Bytes { void* data=nullptr; size_t size=0; };
Bytes bytes(napi_env e,napi_value v) {
    Bytes b; bool typed=false; check(napi_is_typedarray(e,v,&typed));
    if(typed) { napi_typedarray_type t; napi_value buffer; size_t offset;
        check(napi_get_typedarray_info(e,v,&t,&b.size,&b.data,&buffer,&offset));
        if(t!=napi_uint8_array) throw std::runtime_error("Expected byte array");
    } else check(napi_get_arraybuffer_info(e,v,&b.data,&b.size));
    return b;
}
struct Input {
    std::string key,session,label; sh_entry entry{};
    Input(napi_env e,const std::string& k,napi_value v):key(k) {
        session=text(e,prop(e,v,"session")); label=text(e,prop(e,v,"label"));
        auto state=bytes(e,prop(e,v,"state")); auto thumb=bytes(e,prop(e,v,"thumbnail"));
        entry.struct_size=sizeof(entry); entry.content_key=key.c_str(); entry.format=format;
        entry.session=session.c_str(); entry.label=label.c_str();
        entry.state=state.data; entry.state_size=state.size; entry.thumbnail=thumb.data; entry.thumbnail_size=thumb.size;
        entry.played_ms=integer(e,prop(e,v,"playedMs")); entry.parent_id=integer(e,prop(e,v,"parent"));
        const auto kind=integer(e,prop(e,v,"kind"));
        if(kind > SH_LEGACY) throw std::runtime_error("Invalid history kind");
        entry.kind=static_cast<sh_kind>(kind); entry.make_head=flag(e,prop(e,v,"makeHead"));
        entry.created_ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
    }
};
using Store=std::unique_ptr<sh_store,decltype(&sh_close)>;
Store open(napi_env e,napi_value path) { sh_store* s=nullptr; check(sh_open(text(e,path).c_str(),nullptr,&s)); return Store(s,sh_close); }
template<typename F> napi_value invoke(napi_env e,napi_callback_info info,size_t count,F fn) {
    try { std::array<napi_value,6> a{}; size_t n=a.size(); check(napi_get_cb_info(e,info,&n,a.data(),nullptr,nullptr));
        if(n!=count) throw std::runtime_error("Invalid history argument count"); return fn(a);
    } catch(const std::exception& x) { napi_throw_error(e,nullptr,x.what()); return nullptr; }
    catch(...) { napi_throw_error(e,nullptr,"Save history failed"); return nullptr; }
}
napi_value save(napi_env e,napi_callback_info i) { return invoke(e,i,3,[&](const auto& a) {
    auto s=open(e,a[0]); Input input(e,text(e,a[1]),a[2]); sh_id id=0; check(sh_put(s.get(),&input.entry,&id)); return num(e,id);
}); }
napi_value head(napi_env e,napi_callback_info i) { return invoke(e,i,2,[&](const auto& a) {
    auto s=open(e,a[0]); auto key=text(e,a[1]); sh_id id=0; auto r=sh_get_head(s.get(),key.c_str(),format,&id);
    if(r!=SH_NOT_FOUND) check(r); return num(e,id);
}); }
struct List { napi_env env; napi_value array; uint32_t count=0; bool failed=false; };
int add_row(void* ctx,const sh_metadata* r) noexcept {
    auto& l=*static_cast<List*>(ctx);
    try { auto e=l.env; napi_value o; check(napi_create_object(e,&o));
        field(e,o,"id",num(e,r->id)); field(e,o,"createdMs",num(e,r->created_ms)); field(e,o,"playedMs",num(e,r->played_ms));
        field(e,o,"kind",num(e,r->kind)); field(e,o,"parent",num(e,r->parent_id)); field(e,o,"session",str(e,r->session));
        field(e,o,"label",str(e,r->label)); field(e,o,"pinned",boolean(e,r->pinned)); field(e,o,"isHead",boolean(e,r->is_head));
        check(napi_set_element(e,l.array,l.count++,o)); return 0;
    } catch(...) { l.failed=true; return 1; }
}
napi_value list(napi_env e,napi_callback_info i) { return invoke(e,i,2,[&](const auto& a) {
    auto s=open(e,a[0]); auto key=text(e,a[1]); List l{e,nullptr}; check(napi_create_array(e,&l.array));
    check(sh_list(s.get(),key.c_str(),format,0,add_row,&l)); if(l.failed) throw std::runtime_error("Cannot build history list"); return l.array;
}); }
napi_value read(napi_env e,napi_callback_info i) { return invoke(e,i,4,[&](const auto& a) {
    auto s=open(e,a[0]); auto key=text(e,a[1]); auto id=integer(e,a[2]); auto blob=flag(e,a[3])?SH_THUMBNAIL:SH_STATE;
    size_t size=0; check(sh_read(s.get(),id,key.c_str(),format,blob,nullptr,0,&size));
    napi_value out; void* data; check(napi_create_arraybuffer(e,size,&data,&out));
    check(sh_read(s.get(),id,key.c_str(),format,blob,data,size,&size)); return out;
}); }
napi_value edit(napi_env e,napi_callback_info i) { return invoke(e,i,5,[&](const auto& a) {
    auto s=open(e,a[0]); auto id=integer(e,a[1]);
    if(flag(e,a[4])) check(sh_delete(s.get(),id));
    else { check(sh_rename(s.get(),id,text(e,a[2]).c_str())); check(sh_pin(s.get(),id,flag(e,a[3]))); } return num(e,0);
}); }
napi_value prepare(napi_env e,napi_callback_info i) { return invoke(e,i,4,[&](const auto& a) {
    auto s=open(e,a[0]); Input input(e,text(e,a[1]),a[3]); sh_id op=0,backup=0;
    check(sh_prepare_restore(s.get(),integer(e,a[2]),&input.entry,&op,&backup)); napi_value out; check(napi_create_object(e,&out));
    field(e,out,"operation",num(e,op)); field(e,out,"backup",num(e,backup)); return out;
}); }
napi_value finish(napi_env e,napi_callback_info i) { return invoke(e,i,3,[&](const auto& a) {
    auto s=open(e,a[0]); auto id=integer(e,a[1]); check(flag(e,a[2])?sh_finish_restore(s.get(),id):sh_cancel_restore(s.get(),id)); return num(e,0);
}); }
napi_value recover(napi_env e,napi_callback_info i) { return invoke(e,i,2,[&](const auto& a) {
    auto s=open(e,a[0]); auto key=text(e,a[1]); sh_id op=0,target=0,backup=0;
    const auto result=sh_get_pending_restore(s.get(),key.c_str(),format,&op,&target,&backup);
    if(result==SH_NOT_FOUND) return num(e,0);
    check(result);
    if(op==0) return num(e,0);
    size_t size=0; check(sh_read(s.get(),backup,key.c_str(),format,SH_STATE,nullptr,0,&size));
    check(sh_recover_restore(s.get(),op));
    return num(e,backup);
}); }
napi_value content_key(napi_env e,napi_callback_info i) { return invoke(e,i,1,[&](const auto& a) {
    auto b=bytes(e,a[0]); auto h=flynes::catalog::sha256_hex({static_cast<const uint8_t*>(b.data),b.size});
    if(!h.ok()) throw std::runtime_error("Cannot identify game"); return str(e,h.value.c_str());
}); }
}
void register_save_history(napi_env env,napi_value exports) {
    napi_property_descriptor fields[] = {
        {"historySave",nullptr,save,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"historyHead",nullptr,head,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"historyList",nullptr,list,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"historyRead",nullptr,read,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"historyEdit",nullptr,edit,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"historyPrepare",nullptr,prepare,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"historyFinish",nullptr,finish,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"historyRecover",nullptr,recover,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"historyContentKey",nullptr,content_key,nullptr,nullptr,nullptr,napi_default,nullptr}
    };
    napi_define_properties(env,exports,sizeof(fields)/sizeof(fields[0]),fields);
}
