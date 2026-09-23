package com.flynes.emu;

/** Coordinates OS Wi-Fi join before passing the original invitation to the LAN session. */
final class NearbyGuestConnectFlow {
    interface LanPort { boolean join(String localIpv4, String invitation); }
    interface WifiReady {
        boolean onReady(String localIpv4);
        void onFailed();
    }
    interface WifiPort extends AutoCloseable {
        void connect(String ssid, String passphrase, WifiReady ready);
        @Override void close();
    }

    private final WifiPort wifi;
    private final LanPort lan;
    private final Runnable onFailure;
    private long generation;
    private boolean waiting;

    NearbyGuestConnectFlow(WifiPort wifi, LanPort lan) {
        this(wifi, lan, () -> {});
    }

    NearbyGuestConnectFlow(WifiPort wifi, LanPort lan, Runnable onFailure) {
        this.wifi = wifi;
        this.lan = lan;
        this.onFailure = onFailure;
    }

    boolean start(String payload, String currentIpv4) {
        cancel();
        NearbyNetworkInvite invite = NearbyNetworkInvite.parse(payload);
        if (invite == null) return false;
        if (!invite.hasWifi()) return currentIpv4 != null && lan.join(currentIpv4, invite.lanInvite());
        waiting = true;
        long current = generation;
        wifi.connect(invite.ssid(), invite.passphrase(), new WifiReady() {
            @Override public boolean onReady(String localIpv4) {
                if (!waiting || generation != current || localIpv4 == null) return false;
                waiting = false;
                boolean joined = lan.join(localIpv4, invite.lanInvite());
                if (!joined) {
                    wifi.close();
                    onFailure.run();
                }
                return joined;
            }
            @Override public void onFailed() {
                if (generation != current) return;
                waiting = false;
                wifi.close();
                onFailure.run();
            }
        });
        return true;
    }

    boolean waitingForWifi() { return waiting; }

    void cancel() {
        generation++;
        waiting = false;
        wifi.close();
    }
}
