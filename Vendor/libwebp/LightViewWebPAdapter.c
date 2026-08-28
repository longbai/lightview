#include "LightViewWebPAdapter.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "upstream/src/webp/decode.h"
#include "upstream/src/webp/demux.h"

int LVWebPGetInfo(
    const uint8_t *bytes,
    size_t length,
    int *width,
    int *height,
    int *has_alpha
) {
    if (bytes == NULL || length == 0 || width == NULL || height == NULL || has_alpha == NULL) {
        return LVWebPStatusInvalidArgument;
    }
    WebPBitstreamFeatures features;
    VP8StatusCode status = WebPGetFeatures(bytes, length, &features);
    if (status != VP8_STATUS_OK) return (int)status;
    if (features.width <= 0 || features.height <= 0) return LVWebPStatusInvalidArgument;
    *width = features.width;
    *height = features.height;
    *has_alpha = features.has_alpha;
    return LVWebPStatusOK;
}

int LVWebPDecodePremultipliedRGBA(
    const uint8_t *bytes,
    size_t length,
    int output_width,
    int output_height,
    uint8_t *output,
    size_t output_capacity,
    int output_stride
) {
    if (bytes == NULL || length == 0 || output == NULL || output_width <= 0 ||
        output_height <= 0 || output_stride <= 0) {
        return LVWebPStatusInvalidArgument;
    }
    if (output_width > INT_MAX / 4 || output_stride < output_width * 4 ||
        (size_t)output_stride > SIZE_MAX / (size_t)output_height ||
        (size_t)output_stride * (size_t)output_height > output_capacity) {
        return LVWebPStatusInvalidArgument;
    }

    WebPDecoderConfig config;
    if (!WebPInitDecoderConfig(&config)) return LVWebPStatusInvalidArgument;
    VP8StatusCode status = WebPGetFeatures(bytes, length, &config.input);
    if (status != VP8_STATUS_OK) return (int)status;

    config.output.colorspace = MODE_rgbA;
    config.output.is_external_memory = 1;
    config.output.u.RGBA.rgba = output;
    config.output.u.RGBA.stride = output_stride;
    config.output.u.RGBA.size = output_capacity;
    config.options.use_scaling = 1;
    config.options.scaled_width = output_width;
    config.options.scaled_height = output_height;

    status = WebPDecode(bytes, length, &config);
    WebPFreeDecBuffer(&config.output);
    return (int)status;
}

int LVWebPCopyICC(
    const uint8_t *bytes,
    size_t length,
    uint8_t **icc_bytes,
    size_t *icc_length
) {
    if (bytes == NULL || length == 0 || icc_bytes == NULL || icc_length == NULL) {
        return LVWebPStatusInvalidArgument;
    }
    *icc_bytes = NULL;
    *icc_length = 0;
    WebPData source = {bytes, length};
    WebPDemuxer *demuxer = WebPDemux(&source);
    if (demuxer == NULL) return LVWebPStatusInvalidArgument;
    WebPChunkIterator iterator;
    if (!WebPDemuxGetChunk(demuxer, "ICCP", 1, &iterator)) {
        WebPDemuxDelete(demuxer);
        return LVWebPStatusOK;
    }
    if (iterator.chunk.size > 0) {
        uint8_t *copy = (uint8_t *)malloc(iterator.chunk.size);
        if (copy == NULL) {
            WebPDemuxReleaseChunkIterator(&iterator);
            WebPDemuxDelete(demuxer);
            return LVWebPStatusAllocationFailed;
        }
        memcpy(copy, iterator.chunk.bytes, iterator.chunk.size);
        *icc_bytes = copy;
        *icc_length = iterator.chunk.size;
    }
    WebPDemuxReleaseChunkIterator(&iterator);
    WebPDemuxDelete(demuxer);
    return LVWebPStatusOK;
}

void LVWebPFree(void *pointer) {
    free(pointer);
}
