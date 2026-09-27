package com.flynes.emu;

import android.content.Context;
import android.util.AttributeSet;
import android.view.SurfaceView;

/** Fits the camera image into its pane without stretching the QR code. */
public final class NearbyCameraPreview extends SurfaceView {
    private int previewWidth = 4;
    private int previewHeight = 3;
    public NearbyCameraPreview(Context context, AttributeSet attrs) { super(context, attrs); }
    void setPreviewSize(int width, int height) {
        previewWidth = width;
        previewHeight = height;
        requestLayout();
    }
    @Override protected void onMeasure(int widthSpec, int heightSpec) {
        int width = MeasureSpec.getSize(widthSpec), height = MeasureSpec.getSize(heightSpec);
        if ((long) width * previewHeight > (long) height * previewWidth)
            width = height * previewWidth / previewHeight;
        else height = width * previewHeight / previewWidth;
        setMeasuredDimension(width, height);
    }
}
