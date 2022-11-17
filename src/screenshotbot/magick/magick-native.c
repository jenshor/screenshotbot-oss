#include <stdio.h>
#include <string.h>

#if __has_include("MagickWand/MagickWand.h")
# include <MagickWand/MagickWand.h>
#else
# include <wand/MagickWand.h>
#endif

typedef struct _pixel {
        size_t x;
        size_t y;
} pixel;

extern int screenshotbot_verify_magick(CompositeOperator srcCompositeOp,
									   AlphaChannelOption onAlphaChannel) {
		size_t depth;
		GetMagickQuantumDepth(&depth);
		if (MAGICKCORE_QUANTUM_DEPTH != depth) {
				return -1;
		}

		if (srcCompositeOp != SrcCompositeOp) {
				return -2;
		}

		if (onAlphaChannel != OnAlphaChannel) {
				return -3;
		}

		const char* features = GetMagickFeatures();
		char* feat = strstr(features, "HDRI");

#if MAGICK_HDRI_ENABLED
		return feat != NULL;
#else
		return feat == NULL;
#endif
}

extern size_t screenshotbot_find_non_transparent_pixels(MagickWand* wand, pixel* output, size_t max) {
        max--;
        PixelIterator* iterator = NewPixelIterator(wand);
        size_t ret = 0;
        size_t height = MagickGetImageHeight(wand);
        for (int y = 0; y < height; ++y) {
                size_t width = 0;
                PixelWand** row = PixelGetNextIteratorRow(iterator, &width);
                for (int x = 0; x < width; x++) {
                        Quantum px = PixelGetAlphaQuantum(row[x]);
                        if (px > 100) {
                                output[ret].x = x;
                                output[ret].y = y;
                                ret++;

                                if (ret >= max) {
                                        goto cleanup;
                                }
                        }
                }
        }

        cleanup:
        DestroyPixelIterator(iterator);
        return ret;
}
