package com.flynes.emu;

import android.net.wifi.WifiManager;

/** Keeps a local-only hotspot alive across invitation, lobby and game UI pages. */
final class NearbyUiHotspot {
    private WifiManager.LocalOnlyHotspotReservation reservation;
    private String ssid;
    private String passphrase;

    synchronized void hold(WifiManager.LocalOnlyHotspotReservation value) {
        close();
        reservation = value;
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            ssid = value.getSoftApConfiguration().getSsid();
            passphrase = value.getSoftApConfiguration().getPassphrase();
        } else {
            android.net.wifi.WifiConfiguration configuration = value.getWifiConfiguration();
            ssid = configuration == null ? null : configuration.SSID;
            passphrase = configuration == null ? null : configuration.preSharedKey;
        }
    }

    synchronized boolean active() { return reservation != null; }
    synchronized String ssid() { return ssid; }
    synchronized String passphrase() { return passphrase; }

    synchronized void close() {
        WifiManager.LocalOnlyHotspotReservation previous = reservation;
        reservation = null;
        ssid = null;
        passphrase = null;
        if (previous != null) previous.close();
    }
}
