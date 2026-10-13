#include "pmsm_capture.h"

#include <stdio.h>

int main(int argc, char **argv)
{
    pmsm_capture_sample sample = {
        UINT32_MAX, 17u, UINT64_C(4294967297),
        1.25f, -2.5f, 3.75f, -4.5f, 123.0f, 3u
    };
    uint8_t frame[PMSM_CAPTURE_FRAME_SIZE];
    FILE *file;
    unsigned i;
    if (argc != 2 || pmsm_capture_pack(NULL, sizeof(frame), &sample) != 0 ||
        pmsm_capture_pack(frame, sizeof(frame), NULL) != 0 ||
        pmsm_capture_pack(frame, sizeof(frame) - 1u, &sample) != 0) {
        return 1;
    }
    sample.flags = 4u;
    if (pmsm_capture_pack(frame, sizeof(frame), &sample) != 0) {
        return 2;
    }
    sample.flags = 3u;
    file = fopen(argv[1], "wb");
    if (file == NULL) {
        return 3;
    }
    for (i = 0; i < 3; ++i) {
        if (pmsm_capture_pack(frame, sizeof(frame), &sample) != sizeof(frame) ||
            fwrite(frame, 1, sizeof(frame), file) != sizeof(frame)) {
            fclose(file);
            return 4;
        }
        sample.sequence = (i == 0) ? 0u : 2u;
        sample.timestamp_us += 100u;
    }
    return fclose(file) == 0 ? 0 : 5;
}
