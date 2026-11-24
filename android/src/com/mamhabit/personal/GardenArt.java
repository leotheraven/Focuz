package com.mamhabit.personal;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.util.LruCache;
import android.view.View;

import java.io.IOException;
import java.io.InputStream;

final class GardenArt extends View {
    private static final float[] SIZES = {.20f, .27f, .43f, .51f, .62f, .70f, .78f, .84f};
    private static final LruCache<String, Bitmap> CACHE = new LruCache<String, Bitmap>(24 * 1024 * 1024) {
        @Override protected int sizeOf(String key, Bitmap bitmap) { return bitmap.getByteCount(); }
    };
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
    private final Bitmap backdrop, plant, decoration, rainbow;
    private final String decorationName;
    private final int stage;

    GardenArt(Context context, FocuzStore store) {
        super(context);
        stage = (FocuzStore.level(store.xp(store.plant())) - 1) * 8 / 100;
        backdrop = bitmap(context, "garden-" + store.backdrop());
        plant = bitmap(context, "tree-" + store.plant() + "-" + stage / 2);
        decorationName = store.decoration();
        decoration = decorationName.isEmpty() ? null : bitmap(context, "deco-" + decorationName);
        rainbow = store.state().optString("equipped").equals("rainbow") ? bitmap(context, "deco-rainbow") : null;
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
    }

    static Bitmap bitmap(Context context, String name) {
        Bitmap cached = CACHE.get(name);
        if (cached != null) return cached;
        try (InputStream source = context.getAssets().open("art/" + name + (name.startsWith("garden-") ? ".jpg" : ".png"))) {
            Bitmap bitmap = BitmapFactory.decodeStream(source);
            if (bitmap != null) CACHE.put(name, bitmap);
            return bitmap;
        } catch (IOException e) {
            return null;
        }
    }

    @Override protected void onDraw(Canvas canvas) {
        float w = getWidth();
        float h = getHeight();
        canvas.drawColor(0xFFE3EEDC);
        draw(canvas, backdrop, w / 2, h / 2, w, h, true);
        draw(canvas, rainbow, w * .24f, h * .24f, w * .42f, h * .35f, false);
        float treeHeight = h * SIZES[stage];
        draw(canvas, plant, w * .53f, h * .89f - treeHeight / 2, w * .83f, treeHeight, false);
        boolean flying = decorationName.equals("butterfly") || decorationName.equals("stars");
        draw(canvas, decoration, w * .20f, h * (flying ? .45f : .79f),
                w * (decorationName.equals("fence") ? .37f : .23f), h * .32f, false);
    }

    private void draw(Canvas canvas, Bitmap bitmap, float x, float y, float w, float h, boolean cover) {
        if (bitmap == null) return;
        float sx = w / bitmap.getWidth();
        float sy = h / bitmap.getHeight();
        float scale = cover ? Math.max(sx, sy) : Math.min(sx, sy);
        float halfWidth = bitmap.getWidth() * scale / 2;
        float halfHeight = bitmap.getHeight() * scale / 2;
        canvas.drawBitmap(bitmap, null, new RectF(x - halfWidth, y - halfHeight, x + halfWidth, y + halfHeight), paint);
    }
}
