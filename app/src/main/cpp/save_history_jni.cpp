// Thin platform adapter: the independent library owns storage, validation and retention.
#include <jni.h>
#include <save_history/save_history.h>

#include <chrono>
#include <exception>
#include <string>
#include <vector>
namespace {
constexpr const char* format = "nes-state-v1";
sh_store* store(jlong h) { return reinterpret_cast<sh_store*>(h); }
std::string str(JNIEnv* e, jstring v) {
    if (!v) return {};
    const char* p = e->GetStringUTFChars(v, nullptr);
    if (!p) return {};
    std::string s(p);
    e->ReleaseStringUTFChars(v, p);
    return s;
}
std::vector<jbyte> bytes(JNIEnv* e, jbyteArray v) {
    if (!v) return {};
    std::vector<jbyte> b(e->GetArrayLength(v));
    if (!b.empty()) e->GetByteArrayRegion(v, 0, b.size(), b.data());
    return b;
}
bool check(JNIEnv* e, sh_result r) {
    if (r == SH_OK) return true;
    const char* m = "Save history operation failed";
    switch (r) {
        case SH_NOT_FOUND:
            m = "Save record is unavailable";
            break;
        case SH_CORRUPT:
            m = "Save record is damaged";
            break;
        case SH_QUOTA:
            m = "Save storage is full; manage retained records";
            break;
        case SH_PROTECTED:
            m = "Current or protected save cannot be deleted";
            break;
        case SH_IO:
            m = "Could not write save history; check free space";
            break;
        case SH_BUSY:
        case SH_CONFLICT:
            m = "Another save operation needs recovery";
            break;
        default:
            break;
    }
    e->ThrowNew(e->FindClass("java/lang/IllegalStateException"), m);
    return false;
}
sh_entry entry(const std::string& key, const std::string& session, const std::string& label,
               const std::vector<jbyte>& state, const std::vector<jbyte>& thumb, jlong played) {
    sh_entry v{};
    v.struct_size = sizeof(v);
    v.content_key = key.c_str();
    v.format = format;
    v.session = session.c_str();
    v.label = label.c_str();
    v.created_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                       std::chrono::system_clock::now().time_since_epoch())
                       .count();
    v.played_ms = played;
    v.state = state.data();
    v.state_size = state.size();
    v.thumbnail = thumb.data();
    v.thumbnail_size = thumb.size();
    return v;
}
void unexpected(JNIEnv* e) {
    if (!e->ExceptionCheck())
        e->ThrowNew(e->FindClass("java/lang/IllegalStateException"),
                    "Save history memory allocation failed");
}
}  // namespace
extern "C" {
JNIEXPORT jlong JNICALL Java_com_flynes_emu_save_HistoryStore_nOpen(JNIEnv* e, jclass, jstring p,
                                                                    jlong quota) {
    try {
        auto path = str(e, p);
        sh_store* s = nullptr;
        sh_options options{};
        options.struct_size = sizeof(options);
        options.max_content_bytes = quota;
        return check(e, sh_open(path.c_str(), &options, &s)) ? reinterpret_cast<jlong>(s) : 0;
    } catch (...) {
        unexpected(e);
        return 0;
    }
}
JNIEXPORT void JNICALL Java_com_flynes_emu_save_HistoryStore_nClose(JNIEnv*, jclass, jlong h) {
    sh_close(store(h));
}
JNIEXPORT jlong JNICALL Java_com_flynes_emu_save_HistoryStore_nPut(
    JNIEnv* e, jclass, jlong h, jstring k, jbyteArray s, jbyteArray t, jint kind, jstring l,
    jlong played, jstring ss, jlong parent, jboolean head) {
    try {
        auto key = str(e, k), session = str(e, ss), label = str(e, l);
        auto state = bytes(e, s), thumb = bytes(e, t);
        auto v = entry(key, session, label, state, thumb, played);
        v.kind = static_cast<sh_kind>(kind);
        v.parent_id = parent;
        v.make_head = head;
        sh_id id = 0;
        check(e, sh_put(store(h), &v, &id));
        return id;
    } catch (...) {
        unexpected(e);
        return 0;
    }
}
JNIEXPORT jobjectArray JNICALL Java_com_flynes_emu_save_HistoryStore_nList(JNIEnv* e, jclass,
                                                                           jlong h, jstring k) {
    try {
        auto key = str(e, k);
        auto cls = e->FindClass("com/flynes/emu/save/HistoryStore$Entry");
        auto ctor = e->GetMethodID(cls, "<init>", "(JJJIZZLjava/lang/String;Ljava/lang/String;J)V");
        struct Context {
            JNIEnv* e;
            jclass cls;
            jmethodID ctor;
            std::vector<jobject> rows;
            bool failed = false;
        } c{e, cls, ctor, {}};
        auto r = sh_list(
            store(h), key.c_str(), format, 0,
            [](void* ptr, const sh_metadata* m) {
                auto& c = *static_cast<Context*>(ptr);
                auto label = c.e->NewStringUTF(m->label);
                auto session = c.e->NewStringUTF(m->session);
                auto row = c.e->NewObject(
                    c.cls, c.ctor, static_cast<jlong>(m->id), static_cast<jlong>(m->created_ms),
                    static_cast<jlong>(m->played_ms), static_cast<jint>(m->kind),
                    static_cast<jboolean>(m->pinned), static_cast<jboolean>(m->is_head), label,
                    session, static_cast<jlong>(m->parent_id));
                c.e->DeleteLocalRef(label);
                c.e->DeleteLocalRef(session);
                if (c.e->ExceptionCheck()) {
                    c.failed = true;
                    return 1;
                }
                c.rows.push_back(c.e->NewGlobalRef(row));
                c.e->DeleteLocalRef(row);
                return 0;
            },
            &c);
        jobjectArray result = nullptr;
        if (check(e, r) && !c.failed) {
            result = e->NewObjectArray(c.rows.size(), cls, nullptr);
            for (size_t i = 0; result && i < c.rows.size(); ++i)
                e->SetObjectArrayElement(result, i, c.rows[i]);
        }
        for (auto row : c.rows) e->DeleteGlobalRef(row);
        return result;
    } catch (...) {
        unexpected(e);
        return nullptr;
    }
}
JNIEXPORT jbyteArray JNICALL Java_com_flynes_emu_save_HistoryStore_nRead(JNIEnv* e, jclass, jlong h,
                                                                         jstring k, jlong id,
                                                                         jboolean thumb) {
    try {
        auto key = str(e, k);
        size_t size = 0;
        auto blob = thumb ? SH_THUMBNAIL : SH_STATE;
        if (!check(e, sh_read(store(h), id, key.c_str(), format, blob, nullptr, 0, &size)))
            return nullptr;
        std::vector<jbyte> data(size);
        if (!check(e, sh_read(store(h), id, key.c_str(), format, blob, data.data(), size, &size)))
            return nullptr;
        auto result = e->NewByteArray(size);
        if (result && size) e->SetByteArrayRegion(result, 0, size, data.data());
        return result;
    } catch (...) {
        unexpected(e);
        return nullptr;
    }
}
JNIEXPORT jlong JNICALL Java_com_flynes_emu_save_HistoryStore_nHead(JNIEnv* e, jclass, jlong h,
                                                                    jstring k) {
    try {
        auto key = str(e, k);
        sh_id id = 0;
        auto r = sh_get_head(store(h), key.c_str(), format, &id);
        if (r != SH_NOT_FOUND) check(e, r);
        return id;
    } catch (...) {
        unexpected(e);
        return 0;
    }
}
JNIEXPORT jlongArray JNICALL Java_com_flynes_emu_save_HistoryStore_nPrepare(
    JNIEnv* e, jclass, jlong h, jstring k, jlong target, jbyteArray s, jbyteArray t, jlong played,
    jstring ss, jstring l) {
    try {
        auto key = str(e, k), session = str(e, ss), label = str(e, l);
        auto state = bytes(e, s), thumb = bytes(e, t);
        auto v = entry(key, session, label, state, thumb, played);
        sh_id operation = 0, backup = 0;
        if (!check(e, sh_prepare_restore(store(h), target, &v, &operation, &backup)))
            return nullptr;
        jlong values[]{operation, backup};
        auto result = e->NewLongArray(2);
        if (result) e->SetLongArrayRegion(result, 0, 2, values);
        return result;
    } catch (...) {
        unexpected(e);
        return nullptr;
    }
}
JNIEXPORT jlongArray JNICALL Java_com_flynes_emu_save_HistoryStore_nPending(JNIEnv* e, jclass,
                                                                            jlong h, jstring k) {
    try {
        auto key = str(e, k);
        sh_id op = 0, target = 0, backup = 0;
        auto r = sh_get_pending_restore(store(h), key.c_str(), format, &op, &target, &backup);
        if (r != SH_NOT_FOUND && !check(e, r)) return nullptr;
        jlong values[]{op, target, backup};
        auto result = e->NewLongArray(3);
        if (result) e->SetLongArrayRegion(result, 0, 3, values);
        return result;
    } catch (...) {
        unexpected(e);
        return nullptr;
    }
}
JNIEXPORT void JNICALL Java_com_flynes_emu_save_HistoryStore_nAction(JNIEnv* e, jclass, jlong h,
                                                                     jint action, jlong id,
                                                                     jstring t, jboolean flag) {
    try {
        auto text = str(e, t);
        sh_result r = SH_INVALID;
        switch (action) {
            case 0:
                r = sh_finish_restore(store(h), id);
                break;
            case 1:
                r = sh_cancel_restore(store(h), id);
                break;
            case 2:
                r = sh_rename(store(h), id, text.c_str());
                break;
            case 3:
                r = sh_pin(store(h), id, flag);
                break;
            case 4:
                r = sh_set_head(store(h), text.c_str(), format, id);
                break;
            case 6:
                r = sh_recover_restore(store(h), id);
                break;
            case 5:
                r = sh_delete(store(h), id);
                break;
        }
        check(e, r);
    } catch (...) {
        unexpected(e);
    }
}
}
