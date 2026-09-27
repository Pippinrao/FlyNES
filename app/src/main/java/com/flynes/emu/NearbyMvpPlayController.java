package com.flynes.emu;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.util.Log;
import android.view.View;

import com.flynes.emu.settings.FilterMode;
import com.flynes.emu.video.FramePublisher;
import com.flynes.emu.video.GameSurfaceView;
import com.flynes.emu.video.PublishedFrame;

import java.nio.ByteBuffer;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/** Nearby replaces the source of the solo GPU presenter, never its viewport or filter path. */
final class NearbyMvpPlayController implements AutoCloseable {
    private static final int FRAME_BYTES = 256 * 240 * 2;
    private final MainActivity activity;
    private final NearbyMvpSession session;
    private final Runnable returnToLobby;
    private final GameSurfaceView frameView;
    private final byte[] frameBuffer = new byte[FRAME_BYTES];
    private final ByteBuffer directFrame = ByteBuffer.allocateDirect(FRAME_BYTES);
    private final short[] pcmBuffer = new short[2048];
    private final ArrayBlockingQueue<short[]> audioQueue = new ArrayBlockingQueue<>(12);
    private ScheduledExecutorService loop;
    private Thread audioWorker;
    private AudioTrack audio;
    private volatile int buttons;
    private volatile boolean audioRunning;
    private boolean navigationQueued;
    private long published = -1;
    private boolean wasPaused;
    private volatile long writtenSamples;

    NearbyMvpPlayController(MainActivity activity, NearbyMvpSession session, Runnable returnToLobby) {
        this.activity = activity;
        this.session = session;
        this.returnToLobby = returnToLobby;
        FramePublisher publisher = new FramePublisher(() -> {
            long sequence = session.copyLatestFrame(frameBuffer);
            if (sequence < 0 || sequence == published) return null;
            directFrame.clear();
            directFrame.put(frameBuffer);
            directFrame.flip();
            published = sequence;
            return new PublishedFrame(sequence, 256, 240, 512,
                    PublishedFrame.Format.RGB565, directFrame, true);
        });
        frameView = new GameSurfaceView(activity, publisher, null);
        frameView.setId(R.id.game_surface);
    }

    View surface() { return frameView; }
    long writtenSamplesForTest() { return writtenSamples; }
    void setFilterMode(FilterMode mode) { frameView.setFilterMode(mode); }
    void setButtons(int value) {
        Log.i("FlyNesNearby", "event=touch buttons=" + value);
        buttons = value;
    }
    void pause(boolean value) { session.setPaused(value); }
    void resumeGame() { session.resumeGame(); }
    void returnLobby() {
        buttons = 0;
        if (session.setPaused(true) && !navigationQueued) {
            navigationQueued = true;
            activity.runOnUiThread(returnToLobby);
        }
    }

    void start(boolean audioEnabled) {
        if (loop != null) return;
        navigationQueued = false;
        frameView.onResume();
        if (audioEnabled) startAudio();
        long periodNs = session.sourceFramePeriodNs();
        loop = Executors.newSingleThreadScheduledExecutor();
        loop.scheduleAtFixedRate(this::tick, 0, periodNs, TimeUnit.NANOSECONDS);
    }

    private void startAudio() {
        if (audio == null) {
            int minimum = AudioTrack.getMinBufferSize(48000, AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT);
            audio = new AudioTrack.Builder()
                    .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).build())
                    .setAudioFormat(new AudioFormat.Builder().setSampleRate(48000)
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setBufferSizeInBytes(Math.max(minimum, 4096)).build();
        }
        if (audio.getState() != AudioTrack.STATE_INITIALIZED) return;
        audioRunning = true;
        audio.play();
        audioWorker = new Thread(this::writeAudio, "FlyNES-nearby-audio");
        audioWorker.start();
    }

    private void tick() {
        int[] state = session.snapshot();
        if (state[0] != NearbyMvpSession.RUNNING) {
            if (!navigationQueued) {
                navigationQueued = true;
                activity.runOnUiThread(returnToLobby);
            }
            return;
        }
        boolean paused = state.length > 11 && state[11] != 0;
        if (wasPaused && !paused) activity.runOnUiThread(activity::onNearbyResumed);
        wasPaused = paused;
        if (paused) { audioQueue.clear(); return; }
        session.submitInput(buttons);
        long frame = session.completedFrames();
        if (frame > 0) frameView.onFrameAvailable(frame);
        if (audioQueue.remainingCapacity() > 0) {
            int count = session.pullPcm(pcmBuffer);
            if (count > 0 && audio != null && !audioQueue.offer(java.util.Arrays.copyOf(pcmBuffer, count)))
                Log.e("FlyNesNearby", "event=audio_queue_overflow");
        }
    }

    private void writeAudio() {
        while (audioRunning || !audioQueue.isEmpty()) {
            try {
                short[] block = audioQueue.poll(20, TimeUnit.MILLISECONDS);
                if (block == null) continue;
                int offset = 0;
                while (offset < block.length && audioRunning) {
                    int written = audio.write(block, offset, block.length - offset,
                            AudioTrack.WRITE_BLOCKING);
                    if (written > 0) { offset += written; writtenSamples += written; }
                    else if (written == 0) Thread.yield();
                    else {
                        Log.e("FlyNesNearby", "event=audio_write_error code=" + written);
                        audioRunning = false;
                    }
                }
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                break;
            }
        }
    }

    void stop() {
        buttons = 0;
        if (loop != null) {
            loop.shutdownNow();
            try { loop.awaitTermination(2, TimeUnit.SECONDS); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            loop = null;
        }
        frameView.onPause();
        audioRunning = false;
        if (audio != null) audio.pause();
        if (audioWorker != null) {
            audioWorker.interrupt();
            try { audioWorker.join(2000); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            audioWorker = null;
        }
        audioQueue.clear();
        if (audio != null) audio.flush();
    }

    @Override public void close() {
        stop();
        frameView.release();
        if (audio != null) { audio.release(); audio = null; }
    }
}
