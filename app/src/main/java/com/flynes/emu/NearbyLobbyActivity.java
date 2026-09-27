package com.flynes.emu;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.content.Intent;

import java.io.IOException;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.button.MaterialButton;

/**
 * Fixed landscape game / host / seat summary.
 * The host chooses a game from the game center after pairing.
 */
public final class NearbyLobbyActivity extends AppCompatActivity {

    private int boundLinkState;
    private NearbySessionOwner owner;
    private NearbyMvpOwner mvpOwner;
    private NearbyMvpSession mvpSession;
    private boolean playStarted;
    private boolean gameError;
    private com.flynes.emu.cover.AndroidCoverRepository covers;
    private String shownCoverKey;
    private final NearbyPeerGameAttempt peerGameAttempt = new NearbyPeerGameAttempt();
    private TextView confirmReason;
    private NearbySessionOwner.Snapshot displayedSnapshot;
    private final Handler refreshHandler = new Handler(Looper.getMainLooper());
    private final Runnable refresh = new Runnable() {
        @Override public void run() {
            bindSnapshot();
            if (owner != null || mvpSession != null) refreshHandler.postDelayed(this, 250L);
        }
    };

    private static final int[][] FIRST_SCREEN = {
            {R.id.nearby_lobby_row_rom_identity, R.string.nearby_lobby_rom_identity,
                    R.string.nearby_blocked_rom_transfer},
            {R.id.nearby_lobby_row_network_owner, R.string.nearby_lobby_network_owner,
                    R.string.nearby_blocked_session_read},
            {R.id.nearby_lobby_row_seat, R.string.nearby_lobby_seat,
                    R.string.nearby_blocked_mode_gate},
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_nearby_lobby);
        covers = new com.flynes.emu.cover.AndroidCoverRepository(this);

        MaterialToolbar toolbar = findViewById(R.id.nearby_lobby_toolbar);
        toolbar.setNavigationOnClickListener(view -> leavePage());
        toolbar.inflateMenu(R.menu.nearby_lobby_actions);
        toolbar.setOnMenuItemClickListener(item -> {
            if (item.getItemId() != R.id.nearby_lobby_disconnect) return false;
            if (mvpOwner != null) mvpOwner.close();
            ((FlyNesApplication) getApplication()).nearbyUiHotspot().close();
            returnToEntry();
            return true;
        });

        View root = findViewById(R.id.nearby_lobby_root);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(insets.getSystemWindowInsetLeft(),
                    insets.getSystemWindowInsetTop(),
                    insets.getSystemWindowInsetRight(),
                    insets.getSystemWindowInsetBottom());
            return insets;
        });
        root.requestApplyInsets();

        LinearLayout rows = findViewById(R.id.nearby_lobby_rows);
        LinearLayout gameRows = findViewById(R.id.nearby_lobby_game_rows);
        for (int[] field : FIRST_SCREEN) {
            LinearLayout parent = field[0] == R.id.nearby_lobby_row_rom_identity ? gameRows : rows;
            parent.addView(buildRow(field, parent));
        }

        confirmReason = findViewById(R.id.nearby_lobby_confirm_reason);
        FlyNesApplication app = (FlyNesApplication) getApplication();
        mvpOwner = app.nearbyMvpOwner();
        if (mvpOwner != null && mvpOwner.active()) {
            mvpSession = mvpOwner.session();
            int[] snapshot = mvpSession.snapshot();
            boolean host = snapshot[4] == NearbyMvpSession.HOST_P1;
            View.OnClickListener choose = view -> {
                if (host && !isFinishing()) startActivity(new Intent(this, HomeActivity.class)
                        .putExtra("nearby_choose_game", true));
            };
            if (host) findViewById(R.id.nearby_lobby_row_rom_identity).setOnClickListener(choose);
            findViewById(R.id.nearby_lobby_choose_game).setOnClickListener(choose);
            findViewById(R.id.nearby_lobby_resume).setOnClickListener(view -> {
                if (mvpSession.resumeGame()) bindSnapshot();
            });
            bindSnapshot();
            return;
        }
        NearbyAvailability.Status nearby = app.ensureNearby();
        owner = app.nearbySessionOwner();
        if (!nearby.ready() || owner == null) {
            boundLinkState = NearbySessionOwner.LINK_UNAVAILABLE;
            if (nearby.reasonKey() != null) {
                int reasonId = getResources().getIdentifier(
                        nearby.reasonKey(), "string", getPackageName());
                if (reasonId != 0) confirmReason.setText(reasonId);
            }
            owner = null;
            return;
        }
        bindSnapshot();
    }

    @Override protected void onStart() {
        super.onStart();
        refreshHandler.removeCallbacks(refresh);
        if (owner != null || mvpSession != null) refreshHandler.post(refresh);
    }

    @Override protected void onStop() {
        refreshHandler.removeCallbacks(refresh);
        super.onStop();
    }

    private void bindSnapshot() {
        if (mvpSession != null) {
            int[] snapshot = mvpSession.snapshot();
            if (snapshot == null || snapshot.length < 9) return;
            if (snapshot[0] == NearbyMvpSession.LOBBY || snapshot[0] == NearbyMvpSession.RETURNING) {
                mvpOwner.gameTitle("");
                mvpOwner.gameKey("");
                gameError = false;
            }
            peerGameAttempt.shouldAttempt(snapshot[0], 1, "", "");
            if (snapshot[4] == NearbyMvpSession.GUEST_P2 &&
                    snapshot[0] == NearbyMvpSession.CONFIGURING) {
                String peerGameKey = mvpSession.peerGameKey();
                int configured = snapshot[1] == 7 || snapshot[1] == 8 ? 0 : snapshot[5];
                if (peerGameAttempt.shouldAttempt(snapshot[0], configured, peerGameKey,
                        mvpSession.peerConfigToken())) {
                    try {
                        NearbyMvpGame.Selection selection = NearbyMvpGame.load(this, peerGameKey);
                        if (!mvpSession.selectRom(selection.rom) || !mvpSession.confirm())
                            throw new IOException("ROM mismatch");
                        setGameTitle(selection);
                        mvpOwner.gameKey(peerGameKey);
                        gameError = false;
                    } catch (IOException failure) {
                        gameError = true;
                    }
                    snapshot = mvpSession.snapshot();
                }
            }
            boundLinkState = snapshot[0];
            LinearLayout gameRow = findViewById(R.id.nearby_lobby_row_rom_identity);
            boolean host = snapshot[4] == NearbyMvpSession.HOST_P1;
            String title = mvpOwner.gameTitle();
            ((TextView) gameRow.getChildAt(1)).setText(title.isEmpty()
                    ? getString(host ? R.string.nearby_choose_game : R.string.nearby_wait_host_game) : title);
            boolean running = snapshot[0] == NearbyMvpSession.RUNNING;
            boolean paused = snapshot.length > 11 && snapshot[11] != 0;
            findViewById(R.id.nearby_lobby_resume).setVisibility(running ? View.VISIBLE : View.GONE);
            TextView chooseButton = findViewById(R.id.nearby_lobby_choose_game);
            chooseButton.setVisibility(host ? View.VISIBLE : View.GONE);
            chooseButton.setText(title.isEmpty() ? R.string.nearby_choose_game : R.string.nearby_change_game);
            bindCover(mvpOwner.gameKey(), title);
            gameRow.setContentDescription(host ? getString(R.string.nearby_choose_game)
                    : title.isEmpty() ? getString(R.string.nearby_wait_host_game) : title);
            LinearLayout hostRow = findViewById(R.id.nearby_lobby_row_network_owner);
            ((TextView) hostRow.getChildAt(0)).setText("P1");
            ((TextView) hostRow.getChildAt(1)).setText(host ? R.string.nearby_player_local : R.string.nearby_player_peer);
            LinearLayout seatRow = findViewById(R.id.nearby_lobby_row_seat);
            ((TextView) seatRow.getChildAt(0)).setText("P2");
            ((TextView) seatRow.getChildAt(1)).setText(host ? R.string.nearby_player_peer : R.string.nearby_player_local);
            if (snapshot[0] == NearbyMvpSession.ENDED) {
                confirmReason.setText(R.string.nearby_mvp_connection_failed);
                mvpOwner.close();
                ((FlyNesApplication) getApplication()).nearbyUiHotspot().close();
                returnToEntry();
                return;
            } else if (gameError) {
                confirmReason.setText(R.string.nearby_local_game_missing);
            } else if (snapshot[0] == NearbyMvpSession.LOBBY) {
                confirmReason.setText(host ? R.string.nearby_choose_game : R.string.nearby_wait_host_game);
            } else if (snapshot[0] == NearbyMvpSession.CONFIGURING) {
                confirmReason.setText(R.string.nearby_game_preparing);
            } else if (running && paused) {
                confirmReason.setText(R.string.nearby_game_paused);
            } else {
                confirmReason.setText(R.string.nearby_screen_connecting);
            }
            confirmReason.setVisibility(View.VISIBLE);
            if (running && !paused && !playStarted) {
                playStarted = true;
                startActivity(new Intent(this, MainActivity.class).putExtra("nearby_mvp", true));
                finish();
            }
            return;
        }
        if (owner == null) return;
        try {
            displayedSnapshot = owner.snapshot();
            boundLinkState = displayedSnapshot.linkState;
            String reasonKey = displayedSnapshot.primaryReasonKey;
            int reasonId = reasonKey.isEmpty() ? 0 : getResources().getIdentifier(
                    reasonKey.replace('.', '_'), "string", getPackageName());
            if (reasonId != 0) confirmReason.setText(reasonId);
            else if (!reasonKey.isEmpty()) confirmReason.setText(reasonKey);
            else if (displayedSnapshot.pendingConfigLocalConfirmed != 0)
                confirmReason.setText(R.string.nearby_config_confirmed);
            else if (displayedSnapshot.canConfirmGameConfig())
                confirmReason.setText(R.string.nearby_config_waitingConfirm);
            else confirmReason.setText(R.string.nearby_blocked_session_read);
            boolean hasStatus = displayedSnapshot.canConfirmGameConfig()
                    || displayedSnapshot.pendingConfigLocalConfirmed != 0 || !reasonKey.isEmpty();
            confirmReason.setVisibility(hasStatus ? View.VISIBLE : View.GONE);
        } catch (IllegalStateException unavailable) {
            displayedSnapshot = null;
            boundLinkState = NearbySessionOwner.LINK_UNAVAILABLE;
            confirmReason.setText(R.string.nearby_blocked_session_read);
            confirmReason.setVisibility(View.VISIBLE);
        }
    }

    private void bindCover(String key, String title) {
        TextView placeholder = findViewById(R.id.nearby_lobby_cover_placeholder);
        placeholder.setText(title.isEmpty() ? getString(R.string.nearby_wait_host_game) : title);
        if (key.equals(shownCoverKey)) return;
        shownCoverKey = key;
        android.widget.ImageView cover = findViewById(R.id.nearby_lobby_cover);
        cover.setImageDrawable(null);
        cover.setVisibility(View.GONE);
        placeholder.setVisibility(View.VISIBLE);
        if (key.isEmpty()) return;
        covers.loadAsync(key).whenComplete((bitmap, error) -> runOnUiThread(() -> {
            if (isDestroyed() || !key.equals(shownCoverKey) || bitmap == null) return;
            cover.setImageBitmap(bitmap);
            cover.setVisibility(View.VISIBLE);
            placeholder.setVisibility(View.GONE);
        }));
    }

    @Override protected void onDestroy() {
        if (covers != null) covers.close();
        super.onDestroy();
    }

    private void setGameTitle(NearbyMvpGame.Selection selection) {
        mvpOwner.gameTitle(selection.title);
    }

    private void returnToEntry() {
        if (isFinishing()) return;
        startActivity(new Intent(this, NearbyFriendsActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP));
        finish();
    }

    private void leavePage() {
        startActivity(new Intent(this, HomeActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP));
        finish();
    }

    @Override public void onBackPressed() { leavePage(); }

    public int boundLinkState() {
        return boundLinkState;
    }

    /** Core fields: game / host / seat. */
    public static int fieldCount() {
        return FIRST_SCREEN.length;
    }

    private View buildRow(int[] field, LinearLayout parent) {
        LinearLayout row = (LinearLayout) getLayoutInflater()
                .inflate(R.layout.view_nearby_lobby_row, parent, false);
        row.setId(field[0]);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = parent.getChildCount() == 0 ? 0 : Math.round(
                8 * getResources().getDisplayMetrics().density);
        row.setLayoutParams(params);
        row.setGravity(android.view.Gravity.CENTER_VERTICAL);
        row.setPadding(0, 0, 0, 0);

        TextView label = (TextView) row.getChildAt(0);
        TextView reason = (TextView) row.getChildAt(1);
        ((LinearLayout.LayoutParams) reason.getLayoutParams()).topMargin = Math.round(
                4 * getResources().getDisplayMetrics().density);
        label.setText(field[1]);
        if (field[0] == R.id.nearby_lobby_row_rom_identity) {
            label.setVisibility(View.GONE);
            reason.setMaxLines(2);
            reason.setEllipsize(android.text.TextUtils.TruncateAt.END);
        } else label.setText(field[0] == R.id.nearby_lobby_row_network_owner ? "P1" : "P2");
        reason.setText("—");

        // Label first, then the reason it is unavailable: one stop per field, and the reason can
        // never be announced before the field it belongs to (spec §2.3, `color-not-only`).
        row.setContentDescription(label.getText() + ", " + reason.getText());
        return row;
    }
}
