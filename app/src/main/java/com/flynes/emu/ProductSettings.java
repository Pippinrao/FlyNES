package com.flynes.emu;

import com.flynes.emu.settings.AppSettings;
import com.flynes.emu.settings.FlySettingsMapper;
import com.flynes.emu.settings.FlySettingsSnapshot;
import java.util.LinkedHashMap;
import java.util.Map;

/** Scalar product-channel projection over the existing settings schema. */
final class ProductSettings {
    static AppSettings read(com.flynes.emu.settings.SettingsRepository repository) {
        return repository.loadCommitted();
    }
    static boolean save(com.flynes.emu.settings.SettingsRepository repository, String key, Object value) {
        return repository.updateCommitted(current -> patch(current,key,value));
    }
    static AppSettings patch(AppSettings current, String key, Object value) {
        var v = new LinkedHashMap<>(values(current));
        if (!v.containsKey(key)) throw new IllegalArgumentException("Unknown setting");
        Object old = v.get(key);
        if (old instanceof Boolean && !(value instanceof Boolean)) throw new IllegalArgumentException("Boolean required");
        if (old instanceof Integer) {
            int max = switch(key) {
                case "videoQualityPreset", "customSpatialMode", "hapticLevel" -> 4;
                case "customRefreshPolicy" -> 5;
                case "customTemporalMode", "customPostEffect" -> 2;
                default -> 3;
            };
            if (!(value instanceof Integer || value instanceof Long) ||
                    ((Number)value).longValue() < 1 || ((Number)value).longValue() > max)
                throw new IllegalArgumentException("Invalid enum");
            value = ((Number)value).intValue();
        }
        if (old instanceof String && !("system".equals(value) || "en".equals(value) || "zh-Hans".equals(value)))
            throw new IllegalArgumentException("Invalid locale");
        v.put(key, value);
        var s = FlySettingsMapper.toNative(current);
        return FlySettingsMapper.fromNative(new FlySettingsSnapshot(
            i(v,"aspectMode"),i(v,"videoQualityPreset"),i(v,"customRefreshPolicy"),i(v,"customTemporalMode"),
            i(v,"customSpatialMode"),i(v,"customPostEffect"),b(v,"adaptiveProtection"),s.layoutPreset(),i(v,"directionMode"),
            s.buttonScale(),s.verticalOffset(),s.controlOpacity(),s.joystickScale(),s.deadZone(),i(v,"hapticLevel"),
            b(v,"distinctAbHaptics"),b(v,"audioEnabled"),i(v,"audioFocusPolicy"),b(v,"autosaveEnabled"),
            (String)v.get("localeTag"),s.lastPlayedId()));
    }
    private static int i(Map<String,Object> v,String k) { return (Integer)v.get(k); }
    private static int b(Map<String,Object> v,String k) { return (Boolean)v.get(k) ? 1 : 0; }
    static Map<String, Object> values(AppSettings current) {
        var s = FlySettingsMapper.toNative(current);
        var v = new LinkedHashMap<String,Object>();
        v.put("aspectMode",s.aspectMode()); v.put("videoQualityPreset",s.videoQualityPreset());
        v.put("customRefreshPolicy",s.customRefreshPolicy()); v.put("customTemporalMode",s.customTemporalMode());
        v.put("customSpatialMode",s.customSpatialMode()); v.put("customPostEffect",s.customPostEffect());
        v.put("adaptiveProtection",s.adaptiveProtection()!=0); v.put("directionMode",s.directionMode());
        v.put("hapticLevel",s.hapticLevel()); v.put("distinctAbHaptics",s.distinctAbHaptics()!=0);
        v.put("audioEnabled",s.audioEnabled()!=0); v.put("audioFocusPolicy",s.audioFocusPolicy());
        v.put("autosaveEnabled",s.autosaveEnabled()!=0); v.put("localeTag",s.localeTag());
        return v;
    }
}
