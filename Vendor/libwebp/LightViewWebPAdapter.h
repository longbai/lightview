#ifndef LIGHTVIEW_WEBP_ADAPTER_H
#define LIGHTVIEW_WEBP_ADAPTER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    LVWebPStatusOK = 0,
    LVWebPStatusInvalidArgument = -1,
    LVWebPStatusAllocationFailed = -2
};

int LVWebPGetInfo(
    const uint8_t *bytes,
    size_t length,
    int *width,
    int *height,
    int *has_alpha
);

int LVWebPDecodePremultipliedRGBA(
    const uint8_t *bytes,
    size_t length,
    int output_width,
    int output_height,
    uint8_t *output,
    size_t output_capacity,
    int output_stride
);

int LVWebPCopyICC(
    const uint8_t *bytes,
    size_t length,
    uint8_t **icc_bytes,
    size_t *icc_length
);

void LVWebPFree(void *pointer);

#ifdef __cplusplus
}
#endif

#endif
