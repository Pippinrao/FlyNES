package com.flynes.emu;

/** Tracks a guest's attempt to load the host's exact configuration. */
final class NearbyPeerGameAttempt {
    private String lastIdentity = "";
    private int lastLocalConfigured = -1;

    boolean shouldAttempt(int state, int localConfigured, String gameKey, String configToken) {
        if (state != NearbyMvpSession.CONFIGURING) {
            lastIdentity = "";
            lastLocalConfigured = -1;
            return false;
        }
        if (lastLocalConfigured == 1 && localConfigured == 0) lastIdentity = "";
        lastLocalConfigured = localConfigured;
        if (gameKey.isEmpty() || configToken.isEmpty()) return false;
        String identity = gameKey + ":" + configToken;
        if (lastIdentity.isEmpty() && localConfigured != 0) {
            lastIdentity = identity;
            return false;
        }
        if (identity.equals(lastIdentity)) return false;
        lastIdentity = identity;
        return true;
    }
}
