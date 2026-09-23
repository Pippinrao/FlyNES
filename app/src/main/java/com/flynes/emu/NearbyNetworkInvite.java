package com.flynes.emu;

import java.io.UnsupportedEncodingException;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/** QR transport wrapper; the LAN invitation remains owned by the shared session. */
final class NearbyNetworkInvite {
    private static final String WIFI_PREFIX = "flynes-wifi-v1:";
    private static final String LAN_PREFIX = "flynes-lan-v1:";
    private final String ssid;
    private final String passphrase;
    private final String lanInvite;

    private NearbyNetworkInvite(String ssid, String passphrase, String lanInvite) {
        this.ssid = ssid;
        this.passphrase = passphrase;
        this.lanInvite = lanInvite;
    }

    static NearbyNetworkInvite parse(String text) {
        if (text == null || text.length() > 768) return null;
        if (text.startsWith(LAN_PREFIX)) return validLanPort(text) == 0
                ? null : new NearbyNetworkInvite(null, null, text);
        if (!text.startsWith(WIFI_PREFIX)) return null;
        String[] parts = text.substring(WIFI_PREFIX.length()).split(":", -1);
        if (parts.length != 3) return null;
        try {
            String ssid = decode(parts[0]);
            String passphrase = decode(parts[1]);
            String invite = decode(parts[2]);
            if (ssid.isEmpty() || ssid.getBytes(StandardCharsets.UTF_8).length > 32
                    || passphrase.length() < 8 || passphrase.length() > 63
                    || validLanPort(invite) == 0) return null;
            return new NearbyNetworkInvite(ssid, passphrase, invite);
        } catch (IllegalArgumentException | UnsupportedEncodingException error) {
            return null;
        }
    }

    static String withWifi(String ssid, String passphrase, String invite) {
        if (ssid == null || passphrase == null || invite == null) return null;
        try {
            String text = WIFI_PREFIX + encode(ssid) + ':' + encode(passphrase) + ':' + encode(invite);
            return parse(text) == null ? null : text;
        } catch (UnsupportedEncodingException error) {
            return null;
        }
    }

    private static String encode(String value) throws UnsupportedEncodingException {
        return URLEncoder.encode(value, "UTF-8").replace("+", "%20");
    }

    private static String decode(String value) throws UnsupportedEncodingException {
        if (value.indexOf('+') >= 0) throw new IllegalArgumentException("Noncanonical space");
        return URLDecoder.decode(value, "UTF-8");
    }

    static int validLanPort(String invite) {
        if (invite == null || invite.length() > 256) return 0;
        String[] fields = invite.split(":", -1);
        if (fields.length != 5 || !fields[0].equals("flynes-lan-v1")
                || !fields[3].matches("[0-9a-fA-F]{64}")
                || !fields[4].matches("[0-9a-fA-F]{32}")
                || !fields[2].matches("[1-9][0-9]{0,4}")) return 0;
        String[] octets = fields[1].split("\\.", -1);
        if (octets.length != 4) return 0;
        int[] ip = new int[4];
        for (int index = 0; index < 4; index++) {
            if (!octets[index].matches("0|[1-9][0-9]{0,2}")) return 0;
            ip[index] = Integer.parseInt(octets[index]);
            if (ip[index] > 255) return 0;
        }
        if (ip[0] == 0 || ip[0] == 127 || ip[0] >= 224
                || (ip[0] == 169 && ip[1] == 254) || ip[3] == 0 || ip[3] == 255) return 0;
        int port = Integer.parseInt(fields[2]);
        return port <= 65535 ? port : 0;
    }

    boolean hasWifi() { return ssid != null; }
    String ssid() { return ssid; }
    String passphrase() { return passphrase; }
    String lanInvite() { return lanInvite; }
}
