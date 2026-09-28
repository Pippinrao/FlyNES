package com.flynes.emu.save;

import android.content.Context;
import android.graphics.BitmapFactory;
import android.widget.*;
import androidx.appcompat.app.AlertDialog;
import com.flynes.emu.R;
import java.text.DateFormat;
import java.util.Date;

/** Presentation only; operations run after the caller has stopped core advancement. */
public final class HistoryDialogs {
    public interface Actions {
        void save(String label);
        void restore(long id);
        void restart();
    }
    private final Context context;
    private final HistoryStore store;
    private final String key;
    private final Actions actions;
    public HistoryDialogs(Context context, HistoryStore store, String key, Actions actions) {
        this.context = context;
        this.store = store;
        this.key = key;
        this.actions = actions;
    }
    public void save() {
        EditText label = new EditText(context);
        label.setSingleLine(true);
        label.setHint(R.string.history_rename);
        new AlertDialog.Builder(context)
            .setTitle(R.string.history_save_current)
            .setView(label)
            .setNegativeButton(R.string.history_cancel, null)
            .setPositiveButton(R.string.history_save,
                (d, w)
                    -> attempt(
                        () -> actions.save(label.getText().toString()), R.string.history_saved))
            .show();
    }
    public void restart() {
        new AlertDialog.Builder(context)
            .setTitle(R.string.history_restart)
            .setMessage(R.string.history_restart_confirm)
            .setNegativeButton(R.string.history_cancel, null)
            .setPositiveButton(R.string.history_restart,
                (d, w) -> attempt(actions::restart, R.string.history_restarted))
            .show();
    }
    public void show() {
        try {
            LinearLayout rows = column();
            TextView policy = new TextView(context);
            policy.setText(R.string.history_retention);
            rows.addView(policy);
            HistoryStore.Entry[] entries = store.list(key);
            if (entries.length == 0) {
                TextView empty = new TextView(context);
                empty.setText(R.string.history_empty);
                rows.addView(empty);
            }
            AlertDialog dialog = new AlertDialog.Builder(context)
                                     .setTitle(R.string.history_title)
                                     .setNegativeButton(R.string.history_cancel, null)
                                     .create();
            for (HistoryStore.Entry entry : entries) {
                LinearLayout row = column();
                addImage(row, entry.id());
                Button text = new Button(context);
                text.setAllCaps(false);
                text.setText(description(entry));
                row.addView(text);
                text.setOnClickListener(v -> {
                    dialog.dismiss();
                    preview(entry);
                });
                rows.addView(row);
            }
            ScrollView scroll = new ScrollView(context);
            scroll.addView(rows);
            dialog.setView(scroll);
            dialog.show();
        } catch (Exception failure) {
            failed(failure);
        }
    }
    private void preview(HistoryStore.Entry entry) {
        LinearLayout detail = column();
        addImage(detail, entry.id());
        TextView text = new TextView(context);
        text.setText(
            description(entry) + "\n\n" + context.getString(R.string.history_restore_confirm));
        detail.addView(text);
        new AlertDialog.Builder(context)
            .setTitle(R.string.history_title)
            .setView(detail)
            .setNegativeButton(R.string.history_cancel, (d, w) -> show())
            .setNeutralButton("…", (d, w) -> manage(entry))
            .setPositiveButton(R.string.history_restore,
                (d, w) -> attempt(() -> actions.restore(entry.id()), R.string.history_restored))
            .show();
    }
    private void manage(HistoryStore.Entry entry) {
        String[] choices = {context.getString(R.string.history_rename),
            context.getString(entry.pinned() ? R.string.history_unpin : R.string.history_pin),
            context.getString(R.string.history_delete)};
        new AlertDialog.Builder(context)
            .setTitle(description(entry))
            .setItems(choices,
                (d, w) -> {
                    if (w == 0) {
                        EditText label = new EditText(context);
                        label.setText(entry.label());
                        new AlertDialog.Builder(context)
                            .setTitle(R.string.history_rename)
                            .setView(label)
                            .setNegativeButton(R.string.history_cancel, null)
                            .setPositiveButton(R.string.history_save,
                                (d2, w2) -> {
                                    attempt(
                                        ()
                                            -> store.rename(entry.id(), label.getText().toString()),
                                        0);
                                    show();
                                })
                            .show();
                    } else if (w == 1) {
                        attempt(() -> store.pin(entry.id(), !entry.pinned()), 0);
                        show();
                    } else
                        new AlertDialog.Builder(context)
                            .setTitle(R.string.history_delete)
                            .setMessage(description(entry) + "\n\n"
                                + context.getString(R.string.history_delete_confirm))
                            .setNegativeButton(R.string.history_cancel, null)
                            .setPositiveButton(R.string.history_delete,
                                (d2, w2) -> {
                                    attempt(() -> store.delete(entry.id()), 0);
                                    show();
                                })
                            .show();
                })
            .setNegativeButton(R.string.history_cancel, (d, w) -> show())
            .show();
    }
    private String description(HistoryStore.Entry e) {
        int type = switch (e.kind()) {case HistoryStore.MANUAL->R.string.history_manual;case HistoryStore.PROTECTION->R.string.history_protection;case HistoryStore.LEGACY->R.string.history_legacy;default->R.string.history_auto;};
        return DateFormat.getDateTimeInstance().format(new Date(e.createdMs()))+"\n"+context.getString(type)
                +" · "+context.getString(R.string.history_played,e.playedMs()/1000)
                +(e.label().isEmpty()?"":"\n"+e.label())+(e.pinned()?" ★":"")
                +(e.head()?"\n"+context.getString(R.string.history_head):"");
        }
        private void addImage(LinearLayout parent, long id) {
            try {
                byte[] bytes = store.read(key, id, true);
                android.graphics.Bitmap bitmap = bytes.length == 0
                    ? null
                    : BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
                if (bitmap != null) {
                    ImageView image = new ImageView(context);
                    image.setImageBitmap(bitmap);
                    image.setAdjustViewBounds(true);
                    image.setMaxHeight(dp(150));
                    image.setContentDescription(context.getString(R.string.history_title));
                    parent.addView(image, new LinearLayout.LayoutParams(-1, dp(150)));
                    return;
                }
            } catch (RuntimeException ignored) {
            }
            TextView empty = new TextView(context);
            empty.setText(R.string.history_no_image);
            parent.addView(empty);
        }
        private LinearLayout column() {
            LinearLayout layout = new LinearLayout(context);
            layout.setOrientation(LinearLayout.VERTICAL);
            layout.setPadding(dp(12), dp(8), dp(12), dp(8));
            return layout;
        }
        private int dp(int n) {
            return Math.round(n * context.getResources().getDisplayMetrics().density);
        }
        private void attempt(Runnable action, int success) {
            try {
                action.run();
                if (success != 0)
                    Toast.makeText(context, success, Toast.LENGTH_LONG).show();
            } catch (Exception failure) {
                failed(failure);
            }
        }
        private void failed(Exception failure) {
            new AlertDialog.Builder(context)
                .setTitle(R.string.history_title)
                .setMessage(context.getString(R.string.history_failure, failure.getMessage()))
                .setPositiveButton(android.R.string.ok, null)
                .show();
        }
    }
