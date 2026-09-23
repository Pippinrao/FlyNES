package com.flynes.emu;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;

import java.net.Inet4Address;
import java.util.ArrayList;

/** Candidate choice used by the host invitation screen. */
final class NearbyUiNetworkPath {
    private NearbyUiNetworkPath() { }

    static String choose(String[] connectedLanAddresses, String hotspotAddress) {
        if (connectedLanAddresses != null) {
            for (String address : connectedLanAddresses) {
                if (privateIpv4(address)) return address;
            }
        }
        return hotspotAddress;
    }

    static String connectedLan(Context context) {
        ConnectivityManager connectivity = context.getSystemService(ConnectivityManager.class);
        if (connectivity == null) return null;
        ArrayList<String> candidates = new ArrayList<>();
        for (Network network : connectivity.getAllNetworks()) {
            NetworkCapabilities capabilities = connectivity.getNetworkCapabilities(network);
            if (capabilities == null || (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
                    && !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))) continue;
            LinkProperties links = connectivity.getLinkProperties(network);
            if (links == null) continue;
            for (LinkAddress link : links.getLinkAddresses()) {
                if (link.getAddress() instanceof Inet4Address) {
                    candidates.add(link.getAddress().getHostAddress());
                }
            }
        }
        return choose(candidates.toArray(new String[0]), null);
    }

    private static boolean privateIpv4(String address) {
        if (address == null) return false;
        String[] parts = address.split("\\.", -1);
        if (parts.length != 4) return false;
        int[] octets = new int[4];
        try {
            for (int i = 0; i < 4; i++) {
                octets[i] = Integer.parseInt(parts[i]);
                if (octets[i] < 0 || octets[i] > 255) return false;
            }
        } catch (NumberFormatException invalid) {
            return false;
        }
        return octets[0] == 10 || octets[0] == 192 && octets[1] == 168
                || octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31;
    }
}
