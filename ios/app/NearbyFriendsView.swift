import SwiftUI

/// The single nearby entry shared by hosts and guests on every platform.
struct NearbyFriendsView: View {
    private let background = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255)
    private let surface = Color(red: 27 / 255, green: 29 / 255, blue: 34 / 255)
    private let ink = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
    private let muted = Color(red: 190 / 255, green: 184 / 255, blue: 174 / 255)
    private let accent = Color(red: 255 / 255, green: 107 / 255, blue: 94 / 255)

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                if geometry.size.height > 270 {
                    Text("nearby.entry.headline")
                        .nearbyRole(NearbyTypography.paneTitle)
                        .foregroundStyle(ink)
                        .accessibilityIdentifier("nearby_entry_headline")
                    Text("nearby.entry.subtitle")
                        .nearbyRole(NearbyTypography.muted)
                        .foregroundStyle(muted)
                        .lineLimit(2)
                        .accessibilityIdentifier("nearby_entry_subtitle")
                    Text("nearby.network.autoHint")
                        .nearbyRole(NearbyTypography.muted)
                        .foregroundStyle(muted)
                        .lineLimit(2)
                }
                HStack(spacing: 16) {
                    roleCard(title: "nearby.action.create", symbol: "rectangle.portrait.on.rectangle.portrait",
                             hint: "nearby.role.host.hint", identifier: "nearby_action_create",
                             destination: NearbyPairingView(mode: .create))
                    roleCard(title: "nearby.action.scanQr", symbol: "qrcode.viewfinder",
                             hint: "nearby.role.guest.hint", identifier: "nearby_action_scan_qr",
                             destination: NearbyPairingView(mode: .scan))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background.ignoresSafeArea())
        }
        .accessibilityIdentifier("nearby_root")
        .navigationTitle("nearby.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roleCard<Destination: View>(title: LocalizedStringKey, symbol: String,
                                             hint: LocalizedStringKey, identifier: String,
                                             destination: Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(accent)
                Text(title)
                    .nearbyRole(NearbyTypography.sectionTitle)
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .accessibilityIdentifier(identifier)
                Text(hint)
                    .nearbyRole(NearbyTypography.muted)
                    .foregroundStyle(muted)
                    .lineLimit(2)
                    .accessibilityIdentifier(identifier == "nearby_action_create"
                                             ? "nearby_role_host_hint" : "nearby_role_guest_hint")
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.42)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
