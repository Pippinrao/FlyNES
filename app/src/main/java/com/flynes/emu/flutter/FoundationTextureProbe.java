package com.flynes.emu.flutter;

import android.content.Context;
import android.view.Surface;
import com.flynes.emu.AudioThread;
import com.flynes.emu.BuildConfig;
import com.flynes.emu.NesCore;
import com.flynes.emu.catalog.BuiltinGames;
import com.flynes.emu.video.*;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.view.TextureRegistry;
import java.io.InputStream;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;

/** Debug-only G1 container experiment. No user saves or product sessions are opened. */
public final class FoundationTextureProbe implements AutoCloseable, MethodChannel.MethodCallHandler {
    private final NesCore core = new NesCore();
    private final FlutterEngine engine;
    private final MethodChannel channel;
    private final NativeVideoPresenter presenter;
    private final FrameAvailableSignal signal = new FrameAvailableSignal();
    private final ExecutorService dispatchThread = Executors.newSingleThreadExecutor(r -> {
        Thread thread = new Thread(r, "FlyNES-TextureProbe");
        thread.setDaemon(true);
        return thread;
    });
    private final FrameDispatchExecutor dispatch;
    private final AtomicLong playedUs = new AtomicLong();
    private TextureRegistry.SurfaceTextureEntry texture;
    private Surface surface;
    private AudioThread audio;
    private boolean active;
    private boolean hostActive;
    private boolean pageActive = true;
    private String owner;
    private boolean closed;
    private long epoch;
    private long attaches;
    private long detaches;
    private int buttons;

    public FoundationTextureProbe(Context context, FlutterEngine engine) {
        if (!BuildConfig.DEBUG) throw new IllegalStateException("G1 probe requires debug build");
        this.engine = engine;
        try {
            if (!core.create()) throw new IllegalStateException("Core creation failed");
            BuiltinGames games;
            try (InputStream in = context.getAssets().open(BuiltinGames.ASSET_NAME)) {
                games = BuiltinGames.parse(in);
            }
            try (InputStream in = context.getAssets().open(games.all().get(0).assetPath())) {
                if (core.loadRom(in.readAllBytes()) < 0) throw new IllegalStateException("ROM rejected");
            }
            core.setAudioFormat(48000, 0);
            core.setVideoFilter(NesCore.FILTER_NONE);
            presenter = new NativeVideoPresenter(new FramePublisher(
                    new NativeFrameSource(core, 4 * 1024 * 1024)), context);
        } catch (Exception failure) {
            core.destroy();
            dispatchThread.shutdown();
            throw new IllegalStateException("Could not initialize texture probe", failure);
        }
        dispatch = new FrameDispatchExecutor(dispatchThread, presenter::onFrameAvailable);
        signal.addListener(dispatch::offer);
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "flynes/foundation_texture");
        channel.setMethodCallHandler(this);
    }

    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
            try {
                if (closed) throw new IllegalStateException("Probe host closed");
                String requestedOwner = call.argument("owner");
                if (requestedOwner == null || requestedOwner.isBlank())
                    throw new IllegalArgumentException("Texture owner required");
                if (!call.method.equals("attach") && !requestedOwner.equals(owner)) {
                    result.success(null); return;
                }
                switch (call.method) {
                    case "attach":
                        // Flutter can mount the replacement before disposing the old page.
                        // Serialized channel calls transfer only the surface lease; old
                        // owner cleanup is ignored after the transfer, core remains live.
                        if (owner != null && !requestedOwner.equals(owner)) detach();
                        owner = requestedOwner;
                        result.success(attach()); break;
                    case "detach": detach(); result.success(null); break;
                    case "active":
                        pageActive = Boolean.TRUE.equals(call.argument("active"));
                        updateActive(); result.success(null); break;
                    case "input":
                        Number value = call.argument("buttons");
                        if (value == null || value.intValue() < 0 || value.intValue() > 255)
                            throw new IllegalArgumentException("Invalid pad mask");
                        buttons = active && texture != null ? value.intValue() : 0;
                        core.setInput(buttons);
                        result.success(null); break;
                    case "stats": result.success(snapshot()); break;
                    default: result.notImplemented();
                }
            } catch (Exception failure) {
                result.error("texture_unavailable", failure.toString(), null);
            }
    }

    private long attach() {
        if (texture != null) return texture.id();
        texture = engine.getRenderer().createSurfaceTexture();
        texture.surfaceTexture().setDefaultBufferSize(256, 240);
        surface = new Surface(texture.surfaceTexture());
        if (!presenter.surfaceCreated(surface, ++epoch)) {
            surface.release(); surface = null;
            texture.release(); texture = null;
            throw new IllegalStateException("Native EGL rejected Flutter texture surface");
        }
        presenter.surfaceChanged(256, 240, epoch);
        attaches++;
        updateActive();
        return texture.id();
    }

    private void startAudio() {
        if (closed || texture == null || !active || (audio != null && audio.isAlive())) return;
        presenter.setActive(true);
        audio = new AudioThread(core, true, signal, null, null, sequence -> -1L,
                playedUs::addAndGet);
        audio.start();
    }

    private void stopAudio() {
        buttons = 0;
        core.setInput(0);
        if (audio == null) return;
        audio.stopLoop();
        try { audio.join(5000); }
        catch (InterruptedException failure) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while stopping audio", failure);
        }
        if (audio.isAlive()) throw new IllegalStateException("Audio did not stop; core retained");
        audio = null;
    }

    public void setActive(boolean value) {
        hostActive = value;
        updateActive();
    }

    private void updateActive() {
        if (closed) return;
        active = hostActive && pageActive;
        if (active) startAudio();
        else { stopAudio(); presenter.setActive(false); }
    }

    private void detach() throws Exception {
        stopAudio();
        if (texture == null) { owner = null; pageActive = true; return; }
        // Drain the last native frame copy before releasing its surface or core.
        dispatchThread.submit(() -> {}).get(5, TimeUnit.SECONDS);
        if (!presenter.surfaceDestroyed(epoch))
            throw new IllegalStateException("Surface release unconfirmed; retain texture for retry");
        surface.release(); surface = null;
        texture.release(); texture = null;
        owner = null; pageActive = true;
        detaches++;
    }

    /** Native diagnostics: no pixels or PCM cross the method channel. */
    public Map<String, Object> snapshot() {
        NativePresenterStats stats = presenter.stats();
        NativeInputSample input = core.lastInputSample();
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("attaches", attaches); values.put("detaches", detaches);
        values.put("attached", texture != null); values.put("coreAlive", core.isCreated());
        values.put("audioAlive", audio != null && audio.isAlive());
        values.put("playedUs", playedUs.get());
        values.put("submittedFrames", stats.submittedFrames());
        values.put("uploadedFrames", stats.uploadedFrames());
        values.put("runtimeFailures", stats.runtimeFailureCount());
        values.put("sampledButtons", input == null ? -1 : input.padBits(0));
        values.put("requestedButtons", buttons);
        return values;
    }

    @Override public void close() {
        if (closed) return;
        channel.setMethodCallHandler(null);
        try { detach(); }
        catch (Exception failure) {
            throw new IllegalStateException("Probe still owns live resources; cannot destroy core", failure);
        }
        closed = true;
        dispatch.close();
        dispatchThread.shutdown();
        presenter.close();
        core.destroy();
    }
}
