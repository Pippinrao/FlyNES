package com.flynes.emu;

/** Process scoped owner for one LAN MVP session in either role. */
public final class NearbyMvpOwner implements AutoCloseable {
    private NearbyMvpSession session;
    private AutoCloseable networkLease;
    private String gameTitle = "";
    private String gameKey = "";
    public synchronized String gameKey() { return gameKey; }
    public synchronized void gameKey(String key) { gameKey = key; }
    public synchronized String gameTitle() { return gameTitle; }
    public synchronized void gameTitle(String title) { gameTitle = title; }

    public synchronized NearbyMvpSession session() { return session; }

    public synchronized boolean startHost(String ipv4) {
        resetSessionKeepingNetwork();
        if (ipv4 == null) return false;
        NearbyMvpSession replacement = new NearbyMvpSession();
        if (!replacement.host(ipv4)) {
            replacement.close();
            return false;
        }
        session = replacement;
        return true;
    }

    public synchronized boolean startGuest(String localIpv4, String invite) {
        resetSessionKeepingNetwork();
        if (localIpv4 == null || invite == null) return false;
        NearbyMvpSession replacement = new NearbyMvpSession();
        if (!replacement.join(localIpv4, invite)) {
            replacement.close();
            return false;
        }
        session = replacement;
        return true;
    }

    public synchronized boolean active() {
        if (session == null) return false;
        int[] snapshot = session.snapshot();
        return snapshot != null && snapshot.length >= 2 && snapshot[0] != NearbyMvpSession.ENDED;
    }

    public synchronized void attachNetworkLease(AutoCloseable lease) {
        releaseNetworkLease();
        networkLease = lease;
    }

    public synchronized void resetSessionKeepingNetwork() {
        gameTitle = "";
        gameKey = "";
        if (session != null) {
            session.close();
            session = null;
        }
    }

    @Override public synchronized void close() {
        resetSessionKeepingNetwork();
        releaseNetworkLease();
    }

    private void releaseNetworkLease() {
        AutoCloseable old = networkLease;
        networkLease = null;
        if (old != null) {
            try { old.close(); } catch (Exception ignored) {}
        }
    }
}
