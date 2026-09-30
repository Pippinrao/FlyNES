package com.flynes.emu.catalog.android;

import java.util.Objects;
import java.util.UUID;
import java.util.function.BiConsumer;
import java.util.function.Consumer;
import java.util.function.Function;

/** Platform-only UUID hex → persistable URI map. Never written into FLYCAT01. */
public final class AndroidUuidSafMap {
    @FunctionalInterface public interface Committer {
        boolean commit(java.util.Map<String,String> writes,java.util.Set<String> removals);
    }
    public AndroidUuidSafMap(Function<String,String> get,Committer commit) {
        this.get=Objects.requireNonNull(get,"get");
        this.commit=Objects.requireNonNull(commit,"commit");
    }
    static final String BUILTIN_KEY = "builtin.uuid";
    static final String LOCATOR_PREFIX = "locator:";

    private final Function<String, String> get;
    private final Committer commit;

    public AndroidUuidSafMap(
            Function<String, String> get,
            BiConsumer<String, String> put,
            Consumer<String> remove) {
        this(get,(writes,removals)->{
            for(String key:removals)remove.accept(key);
            for(var entry:writes.entrySet())put.accept(entry.getKey(),entry.getValue());
            return true;
        });
        Objects.requireNonNull(put,"put");
        Objects.requireNonNull(remove,"remove");
    }

    public void put(byte[] uuid, String persistableUri) {
        String hex = toHex(requireAssigned(uuid));
        if (BUILTIN_KEY.equals(hex)) {
            throw new IllegalArgumentException("uuid collides with builtin key");
        }
        String locator = Objects.requireNonNull(persistableUri, "persistable URI").trim();
        if (locator.isEmpty()) throw new IllegalArgumentException("persistable URI");
        String previous = get.apply(hex);
        String assigned = get.apply(LOCATOR_PREFIX + locator);
        if(assigned!=null&&!assigned.equals(hex))throw new IllegalArgumentException("locator already assigned");
        if(locator.equals(previous)&&hex.equals(assigned))return;
        java.util.Map<String,String> writes=new java.util.LinkedHashMap<>();
        java.util.Set<String> removals=new java.util.HashSet<>();
        if (previous != null && !previous.isEmpty() && !previous.equals(locator)) {
            removals.add(LOCATOR_PREFIX + previous);
        }
        writes.put(hex,locator);
        writes.put(LOCATOR_PREFIX+locator,hex);
        commitChecked(writes,removals);
    }

    public String get(byte[] uuid) {
        return get.apply(toHex(requireUuid(uuid)));
    }

    public void remove(byte[] uuid) {
        String hex = toHex(requireUuid(uuid));
        if (BUILTIN_KEY.equals(hex)) return;
        String locator = get.apply(hex);
        java.util.Set<String> removals=new java.util.HashSet<>();
        removals.add(hex);
        if(locator!=null&&!locator.isEmpty())removals.add(LOCATOR_PREFIX+locator);
        commitChecked(java.util.Collections.emptyMap(),removals);
    }

    public byte[] uuidForLocator(String persistableUri) {
        String locator = Objects.requireNonNull(persistableUri, "persistable URI").trim();
        if (locator.isEmpty()) return null;
        String hex = get.apply(LOCATOR_PREFIX + locator);
        return hex == null || hex.isEmpty() ? null : parseHex(hex);
    }

    public boolean isAssigned(byte[] uuid) {
        byte[] checked = requireUuid(uuid);
        for (byte value : checked) {
            if (value != 0) return true;
        }
        return false;
    }

    public byte[] builtinUuid() {
        String stored = get.apply(BUILTIN_KEY);
        if (stored != null && !stored.isEmpty()) return parseHex(stored);
        byte[] generated = uuidBytes(UUID.randomUUID());
        commitChecked(java.util.Collections.singletonMap(BUILTIN_KEY,toHex(generated)),java.util.Collections.emptySet());
        return generated;
    }

    /** One preference transaction contains the forward and reverse locator indexes. */
    private void commitChecked(java.util.Map<String,String> writes,java.util.Set<String> removals) {
        java.util.Map<String,String> previous=new java.util.LinkedHashMap<>();
        java.util.Set<String> absent=new java.util.HashSet<>();
        java.util.Set<String> touched=new java.util.HashSet<>(writes.keySet());touched.addAll(removals);
        for(String key:touched) {
            String value=get.apply(key);
            if(value==null)absent.add(key);else previous.put(key,value);
        }
        if(commit.commit(writes,removals))return;
        // SharedPreferences may expose failed commits in memory. Restore that view too.
        PersistenceFailure failure=new PersistenceFailure();
        if(!commit.commit(previous,absent))failure.addSuppressed(new IllegalStateException("source_mapping_rollback_failed"));
        throw failure;
    }

    public static final class PersistenceFailure extends IllegalStateException {
        PersistenceFailure(){super("source_write_failed");}
    }

    public static String toHex(byte[] uuid) {
        return com.flynes.emu.catalog.HexEncoding.lower(requireUuid(uuid));
    }

    public static byte[] parseHex(String hex) {
        if (hex == null || hex.length() != 32) {
            throw new IllegalArgumentException("uuid hex");
        }
        byte[] bytes = new byte[16];
        for (int index = 0; index < 16; index++) {
            int high = Character.digit(hex.charAt(index * 2), 16);
            int low = Character.digit(hex.charAt(index * 2 + 1), 16);
            if (high < 0 || low < 0) throw new IllegalArgumentException("uuid hex");
            bytes[index] = (byte) ((high << 4) | low);
        }
        return bytes;
    }

    private static byte[] requireAssigned(byte[] uuid) {
        byte[] checked = requireUuid(uuid);
        if (!hasNonZero(checked)) throw new IllegalArgumentException("uuid must not be all zero");
        return checked;
    }

    private static byte[] requireUuid(byte[] uuid) {
        if (uuid == null || uuid.length != 16) throw new IllegalArgumentException("uuid");
        return uuid;
    }

    private static boolean hasNonZero(byte[] uuid) {
        for (byte value : uuid) {
            if (value != 0) return true;
        }
        return false;
    }

    private static byte[] uuidBytes(UUID value) {
        byte[] bytes = new byte[16];
        long high = value.getMostSignificantBits();
        long low = value.getLeastSignificantBits();
        for (int index = 0; index < 8; index++) {
            bytes[index] = (byte) (high >>> (8 * (7 - index)));
            bytes[8 + index] = (byte) (low >>> (8 * (7 - index)));
        }
        if (!hasNonZero(bytes)) throw new IllegalStateException("generated zero uuid");
        return bytes;
    }
}
