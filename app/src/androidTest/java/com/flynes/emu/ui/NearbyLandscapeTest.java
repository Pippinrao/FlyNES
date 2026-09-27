package com.flynes.emu.ui;

import android.content.Context;
import android.graphics.Rect;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.appcompat.view.ContextThemeWrapper;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.flynes.emu.R;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** Measures actual Android views in a short landscape viewport, without opening a session. */
@RunWith(AndroidJUnit4.class)
public class NearbyLandscapeTest {
    @Test public void allPagesFitShortLandscapeWithLargeText() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            int[] layouts = {R.layout.activity_nearby_friends, R.layout.activity_nearby_pairing,
                    R.layout.activity_nearby_lobby, R.layout.activity_nearby_qr_scanner};
            for (String language : new String[]{"zh-CN", "en"}) {
                for (float scale : new float[]{1f, 1.3f, 2f}) {
                    for (int width : new int[]{640, 736, 844}) {
                        for (int layout : layouts) {
                            android.content.res.Configuration config = new android.content.res.Configuration(
                                    InstrumentationRegistry.getInstrumentation().getTargetContext()
                                            .getResources().getConfiguration());
                            config.fontScale = scale;
                            config.setLocale(java.util.Locale.forLanguageTag(language));
                            Context context = new ContextThemeWrapper(InstrumentationRegistry.getInstrumentation()
                                    .getTargetContext().createConfigurationContext(config), R.style.Theme_FlyNES);
                            ViewGroup page = (ViewGroup)LayoutInflater.from(context).inflate(layout, null);
                            if (layout == R.layout.activity_nearby_lobby) {
                                android.widget.LinearLayout rows = page.findViewById(R.id.nearby_lobby_rows);
                                android.widget.LinearLayout gameRows = page.findViewById(R.id.nearby_lobby_game_rows);
                                for (int label : new int[]{R.string.nearby_lobby_rom_identity,
                                        R.string.nearby_lobby_network_owner, R.string.nearby_lobby_seat}) {
                                    android.widget.LinearLayout parent = label == R.string.nearby_lobby_rom_identity
                                            ? gameRows : rows;
                                    android.widget.LinearLayout row = (android.widget.LinearLayout)
                                            LayoutInflater.from(context).inflate(R.layout.view_nearby_lobby_row, parent, false);
                                    android.widget.LinearLayout.LayoutParams params =
                                            new android.widget.LinearLayout.LayoutParams(-1, -2);
                                    params.topMargin = parent.getChildCount() == 0 ? 0 :
                                            Math.round(8 * context.getResources().getDisplayMetrics().density);
                                    row.setLayoutParams(params);
                                    row.setGravity(android.view.Gravity.CENTER_VERTICAL);
                                    row.setPadding(0, 0, 0, 0);
                                    ((android.widget.LinearLayout.LayoutParams) row.getChildAt(1).getLayoutParams()).topMargin =
                                            Math.round(4 * context.getResources().getDisplayMetrics().density);
                                    ((TextView)row.getChildAt(0)).setText(label);
                                    if (label == R.string.nearby_lobby_rom_identity) row.getChildAt(0).setVisibility(View.GONE);
                                    else ((TextView)row.getChildAt(0)).setText(label == R.string.nearby_lobby_network_owner ? "P1" : "P2");
                                    ((TextView)row.getChildAt(1)).setText(label == R.string.nearby_lobby_rom_identity
                                            ? R.string.nearby_choose_game : R.string.nearby_player_peer);
                                    parent.addView(row);
                                }
                                TextView status = page.findViewById(R.id.nearby_lobby_confirm_reason);
                                status.setText(R.string.nearby_game_paused);
                                status.setVisibility(View.VISIBLE);
                                page.findViewById(R.id.nearby_lobby_resume).setVisibility(View.VISIBLE);
                                page.findViewById(R.id.nearby_lobby_choose_game).setVisibility(View.VISIBLE);
                            }
                            if (layout == R.layout.activity_nearby_pairing) {
                                page.findViewById(R.id.nearby_create_block).setVisibility(View.VISIBLE);
                                page.findViewById(R.id.nearby_invite_qr_wrap).setVisibility(View.VISIBLE);
                                ((TextView)page.findViewById(R.id.nearby_invite_code_value))
                                        .setText(R.string.nearby_mvp_connection_failed);
                            }
                            if (layout == R.layout.activity_nearby_qr_scanner) {
                                page.findViewById(R.id.nearby_scanner_retry).setVisibility(View.VISIBLE);
                                ((TextView) page.findViewById(R.id.nearby_scanner_status))
                                        .setText(R.string.nearby_scanner_camera_unavailable);
                            }
                            measure(page, width, 312);
                            try {
                                assertContentFits(page, page);
                                assertNoScrolling(page);
                            } catch (AssertionError error) {
                                throw new AssertionError(language + " scale=" + scale + " width=" + width
                                        + " layout=" + context.getResources().getResourceEntryName(layout), error);
                            }
                        }
                    }
                }
            }
        });
    }

    @Test public void scannerKeepsCameraLeftAndHeaderOutsidePreview() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            ViewGroup page = inflate(R.layout.activity_nearby_qr_scanner);
            measure(page, 736, 312);
            Rect camera = bounds(page, page.findViewById(R.id.nearby_scanner_preview));
            Rect status = bounds(page, page.findViewById(R.id.nearby_scanner_status));
            Rect header = bounds(page, page.findViewById(R.id.nearby_scanner_toolbar));
            assertTrue("camera must be left of status, not behind it", camera.right <= status.left);
            assertTrue("header must be outside camera preview", header.bottom <= camera.top);
        });
    }

    private static Rect bounds(ViewGroup root, View view) {
        Rect result = new Rect(0, 0, view.getWidth(), view.getHeight());
        root.offsetDescendantRectToMyCoords(view, result);
        return result;
    }

    @Test public void captureActualPages() throws Exception {
        androidx.core.os.LocaleListCompat previous = androidx.appcompat.app.AppCompatDelegate.getApplicationLocales();
        android.app.LocaleManager locales = android.os.Build.VERSION.SDK_INT >= 33 ?
                InstrumentationRegistry.getInstrumentation().getTargetContext()
                        .getSystemService(android.app.LocaleManager.class) : null;
        android.os.LocaleList systemPrevious = locales == null ? null : locales.getApplicationLocales();
        if (locales != null) locales.setApplicationLocales(android.os.LocaleList.forLanguageTags("zh-CN"));
        else InstrumentationRegistry.getInstrumentation().runOnMainSync(() ->
                    androidx.appcompat.app.AppCompatDelegate.setApplicationLocales(
                            androidx.core.os.LocaleListCompat.forLanguageTags("zh-CN")));
        Class[] pages = {com.flynes.emu.NearbyFriendsActivity.class,
                com.flynes.emu.NearbyPairingActivity.class,
                com.flynes.emu.NearbyLobbyActivity.class};
        try { for (Class page : pages) {
            android.content.Intent intent = new android.content.Intent(
                    InstrumentationRegistry.getInstrumentation().getTargetContext(), page);
            intent.putExtra("nearby_mode", "create");
            try (androidx.test.core.app.ActivityScenario scenario =
                         androidx.test.core.app.ActivityScenario.launch(intent)) {
                InstrumentationRegistry.getInstrumentation().waitForIdleSync();
                android.os.SystemClock.sleep(600);
                scenario.onActivity(activity -> {
                    ViewGroup content = ((android.app.Activity)activity).findViewById(android.R.id.content);
                    assertContentFits(content, content);
                    assertNoScrolling(content);
                });
                android.graphics.Bitmap screenshot = InstrumentationRegistry.getInstrumentation()
                        .getUiAutomation().takeScreenshot();
                java.io.File file = new java.io.File(InstrumentationRegistry.getInstrumentation()
                        .getTargetContext().getExternalFilesDir(null), page.getSimpleName() + ".png");
                try (java.io.FileOutputStream output = new java.io.FileOutputStream(file)) {
                    screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output);
                }
            }
        } } finally {
            if (locales != null) locales.setApplicationLocales(systemPrevious);
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() ->
                    androidx.appcompat.app.AppCompatDelegate.setApplicationLocales(previous));
        }
    }
    @Test public void inviteActionsAreFullyVisibleWithoutScrolling() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            ViewGroup root = inflate(R.layout.activity_nearby_pairing);
            root.findViewById(R.id.nearby_create_block).setVisibility(View.VISIBLE);
            root.findViewById(R.id.nearby_invite_qr_wrap).setVisibility(View.VISIBLE);
            measure(root, 640, 312);
            assertInside(root, root.findViewById(R.id.nearby_invite_regenerate));
            assertInside(root, root.findViewById(R.id.nearby_invite_cancel));
            assertNoScrolling(root);
        });
    }

    @Test public void failureMessageUsesReadableBodyTypography() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            ViewGroup root = inflate(R.layout.activity_nearby_pairing);
            root.findViewById(R.id.nearby_create_block).setVisibility(View.VISIBLE);
            TextView status = root.findViewById(R.id.nearby_invite_code_value);
            status.setText("连接失败，请重新创建邀请");
            measure(root, 640, 312);
            assertEquals("status is not a six-digit code", 0f, status.getLetterSpacing(), .001f);
            assertTrue("status must allow wrapping", status.getMaxLines() > 1);
            assertTrue("full status visible", status.getLayout().getLineEnd(status.getLineCount()-1)
                    == status.getText().length());
        });
    }

    private static ViewGroup inflate(int layout) {
        Context context = new ContextThemeWrapper(InstrumentationRegistry.getInstrumentation()
                .getTargetContext(), R.style.Theme_FlyNES);
        return (ViewGroup) LayoutInflater.from(context).inflate(layout, null);
    }
    private static void measure(View view, int width, int height) {
        float d = view.getResources().getDisplayMetrics().density;
        int w = Math.round(width*d), h = Math.round(height*d);
        view.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY));
        view.layout(0, 0, w, h);
    }
    private static void assertInside(ViewGroup root, View view) {
        Rect bounds = new Rect(0, 0, view.getWidth(), view.getHeight());
        root.offsetDescendantRectToMyCoords(view, bounds);
        assertTrue("control outside viewport: " + bounds,
                bounds.left >= 0 && bounds.top >= 0 && bounds.right <= root.getWidth()
                        && bounds.bottom <= root.getHeight());
    }
    private static void assertNoScrolling(View view) {
        if (view.getVisibility() != View.VISIBLE) return;
        // Icon-only MaterialButtons inherit a text scroll range even with no text.
        if (view instanceof TextView && ((TextView)view).getText().length() == 0) return;
        assertFalse("page requires vertical scrolling: " + view.getClass().getSimpleName()
                + " " + (view instanceof TextView ? ((TextView)view).getText() : view.getId()),
                view.canScrollVertically(1));
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup)view;
            for (int i=0; i<group.getChildCount(); i++) assertNoScrolling(group.getChildAt(i));
        }
    }
    private static void assertContentFits(ViewGroup root, View view) {
        if (view.getVisibility() != View.VISIBLE) return;
        if (view instanceof TextView) {
            TextView text = (TextView)view;
            if (text.getText().length() > 0) {
                assertInside(root, text);
                assertTrue("clipped text: " + text.getText()
                                + " textHeight=" + (text.getLayout() == null ? 0 : text.getLayout().getHeight())
                                + " viewHeight=" + text.getHeight()
                                + " parentHeight=" + ((View)text.getParent()).getHeight(),
                        text.getLayout() == null || text.getLayout().getHeight()
                                <= text.getHeight() - text.getCompoundPaddingTop()
                                - text.getCompoundPaddingBottom() + 2);
            }
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup)view;
            for (int i=0; i<group.getChildCount(); i++) assertContentFits(root, group.getChildAt(i));
        }
    }
}
