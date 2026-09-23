package com.flynes.emu;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.wifi.WifiNetworkSpecifier;
import android.os.Build;
import android.os.Handler;

import java.net.Inet4Address;

/** Android system-confirmed Wi-Fi request held for the guest session lifetime. */
final class NearbyWifiJoiner implements NearbyGuestConnectFlow.WifiPort {
    private final ConnectivityManager connectivity;
    private final Handler main;
    private ConnectivityManager.NetworkCallback callback;
    private long generation;
    private boolean joined;

    NearbyWifiJoiner(Context context, Handler main) {
        connectivity = (ConnectivityManager) context.getApplicationContext()
                .getSystemService(Context.CONNECTIVITY_SERVICE);
        this.main = main;
    }

    @Override public void connect(String ssid, String passphrase,
                                  NearbyGuestConnectFlow.WifiReady ready) {
        close();
        if (Build.VERSION.SDK_INT < 29 || connectivity == null) { ready.onFailed(); return; }
        long current = generation;
        try {
            WifiNetworkSpecifier specifier = new WifiNetworkSpecifier.Builder()
                    .setSsid(ssid).setWpa2Passphrase(passphrase).build();
            NetworkRequest request = new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .setNetworkSpecifier(specifier).build();
            ConnectivityManager.NetworkCallback pending = new ConnectivityManager.NetworkCallback() {
                @Override public void onAvailable(Network network) { maybeReady(network); }
                @Override public void onLinkPropertiesChanged(Network network, LinkProperties properties) {
                    maybeReady(network);
                }
                @Override public void onUnavailable() { fail(); }
                @Override public void onLost(Network network) {
                    if (!joined) fail();
                }

                private void maybeReady(Network network) {
                    if (generation != current || joined) return;
                    LinkProperties properties = connectivity.getLinkProperties(network);
                    if (properties == null) return;
                    for (LinkAddress address : properties.getLinkAddresses()) {
                        if (!(address.getAddress() instanceof Inet4Address)) continue;
                        String ipv4 = address.getAddress().getHostAddress();
                        if (!connectivity.bindProcessToNetwork(network)) { fail(); return; }
                        joined = true;
                        main.post(() -> {
                            if (generation == current && !ready.onReady(ipv4)) close();
                        });
                        return;
                    }
                }

                private void fail() {
                    if (generation != current) return;
                    main.post(() -> {
                        if (generation == current) ready.onFailed();
                    });
                }
            };
            callback = pending;
            connectivity.requestNetwork(request, pending, 30_000);
        } catch (RuntimeException error) {
            close();
            ready.onFailed();
        }
    }

    @Override public void close() {
        ++generation;
        joined = false;
        ConnectivityManager.NetworkCallback old = callback;
        callback = null;
        if (old != null && connectivity != null) {
            try { connectivity.unregisterNetworkCallback(old); } catch (RuntimeException ignored) {}
        }
        if (connectivity != null) connectivity.bindProcessToNetwork(null);
    }

    boolean isActive() { return callback != null && joined; }
}
