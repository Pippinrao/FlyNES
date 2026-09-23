package com.flynes.emu;

import android.content.Context;
import android.os.Handler;

/** Backend entry point for a future scan screen; does not own UI or navigation. */
public final class NearbyScanJoinService implements AutoCloseable {
    interface SessionPort {
        boolean join(String localIpv4, String invite);
        void hold(AutoCloseable networkLease);
        void close();
    }
    interface AddressPort { String current(); }

    private final NearbyGuestConnectFlow.WifiPort wifi;
    private final SessionPort session;
    private final AddressPort address;
    private NearbyGuestConnectFlow pending;

    public NearbyScanJoinService(Context context, Handler main, NearbyMvpOwner owner) {
        this(new NearbyWifiJoiner(context, main), new SessionPort() {
            @Override public boolean join(String ipv4, String invite) {
                return owner.startGuest(ipv4, invite);
            }
            @Override public void hold(AutoCloseable lease) { owner.attachNetworkLease(lease); }
            @Override public void close() { owner.close(); }
        }, NearbyMvpLanAddress::current);
    }

    NearbyScanJoinService(NearbyGuestConnectFlow.WifiPort wifi,
                          SessionPort session, AddressPort address) {
        this.wifi = wifi;
        this.session = session;
        this.address = address;
    }

    public boolean joinScannedText(String text, Runnable onJoined, Runnable onNetworkUnavailable) {
        NearbyNetworkInvite parsed = NearbyNetworkInvite.parse(text);
        if (parsed == null) return false;
        close();
        pending = new NearbyGuestConnectFlow(wifi, (ipv4, invite) -> {
            if (!session.join(ipv4, invite)) return false;
            if (parsed.hasWifi()) session.hold(wifi);
            onJoined.run();
            return true;
        }, onNetworkUnavailable);
        return pending.start(text, address.current());
    }

    @Override public void close() {
        if (pending != null) pending.cancel();
        pending = null;
        session.close();
    }
}
