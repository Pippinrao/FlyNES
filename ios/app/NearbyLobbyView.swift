import SwiftUI

/// Session facts and the local action share one fixed landscape view.
/// iOS session transport is not connected yet, so the view explains the unavailable action.
struct NearbyLobbyView: View {
    private let background = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255)
    private let surface = Color(red: 27 / 255, green: 29 / 255, blue: 34 / 255)
    private let ink = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
    private let muted = Color(red: 190 / 255, green: 184 / 255, blue: 174 / 255)
    private let accent = Color(red: 255 / 255, green: 107 / 255, blue: 94 / 255)

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 12) {
                field("nearby.lobby.network_owner", value: "nearby.blocked.session_read",
                      identifier: "nearby_lobby_row_network_owner")
                field("nearby.lobby.seat", value: "nearby.blocked.session_read",
                      identifier: "nearby_lobby_row_seat")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("nearby.lobby.rom_identity")
                    .nearbyRole(NearbyTypography.sectionTitle)
                    .foregroundStyle(ink)
                    .accessibilityIdentifier("nearby_lobby_row_rom_identity")
                Text("nearby.blocked.rom_transfer")
                    .nearbyRole(NearbyTypography.muted)
                    .foregroundStyle(muted)
                Spacer(minLength: 0)
                Text("nearby.blocked.session_read")
                    .nearbyRole(NearbyTypography.muted)
                    .foregroundStyle(muted)
                    .accessibilityIdentifier("nearby_lobby_confirm_reason")
                Button("nearby.lobby.confirm") { }
                    .disabled(true)
                    .nearbyRole(NearbyTypography.primaryAction)
                    .nearbyMinTap()
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .accessibilityIdentifier("nearby_lobby_confirm")
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.ignoresSafeArea())
        .navigationTitle("nearby.lobby.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: LocalizedStringKey, value: LocalizedStringKey,
                       identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .nearbyRole(NearbyTypography.sectionTitle)
                .foregroundStyle(ink)
            Text(value)
                .nearbyRole(NearbyTypography.muted)
                .foregroundStyle(muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier(identifier)
    }
}
