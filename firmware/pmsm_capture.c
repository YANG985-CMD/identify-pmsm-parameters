#include "pmsm_capture.h"

#include <float.h>
#include <limits.h>
#include <string.h>

/* This wire format requires IEEE-754 binary32, not an arbitrary C float. */
typedef char pmsm_float_must_be_binary32[
    (CHAR_BIT == 8 && sizeof(float) == 4 && FLT_RADIX == 2 && FLT_MANT_DIG == 24 &&
     FLT_MAX_EXP == 128) ? 1 : -1];

static void put32(uint8_t *out, uint32_t value)
{
    unsigned i;
    for (i = 0; i < 4; ++i) {
        out[i] = (uint8_t)(value >> (8u * i));
    }
}

static void put_float(uint8_t *out, float value)
{
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    put32(out, bits);
}

static uint32_t crc32(const uint8_t *data, size_t count)
{
    uint32_t crc = UINT32_C(0xffffffff);
    size_t i;
    unsigned bit;
    for (i = 0; i < count; ++i) {
        crc ^= data[i];
        for (bit = 0; bit < 8; ++bit) {
            crc = (crc >> 1) ^ ((crc & 1u) ? UINT32_C(0xedb88320) : 0u);
        }
    }
    return crc ^ UINT32_C(0xffffffff);
}

size_t pmsm_capture_pack(uint8_t *output, size_t capacity,
                         const pmsm_capture_sample *sample)
{
    unsigned i;
    if (output == NULL || sample == NULL || capacity < PMSM_CAPTURE_FRAME_SIZE ||
        (sample->flags & (uint8_t)~3u) != 0u) {
        return 0;
    }
    memcpy(output, "PMI1", 4);
    output[4] = 1;
    output[5] = sample->flags;
    output[6] = PMSM_CAPTURE_FRAME_SIZE;
    output[7] = 0;
    put32(output + 8, sample->sequence);
    put32(output + 12, sample->run_id);
    for (i = 0; i < 8; ++i) {
        output[16 + i] = (uint8_t)(sample->timestamp_us >> (8u * i));
    }
    put_float(output + 24, sample->id_A);
    put_float(output + 28, sample->iq_A);
    put_float(output + 32, sample->ud_V);
    put_float(output + 36, sample->uq_V);
    put_float(output + 40, sample->omega_e_rad_s);
    put32(output + 44, crc32(output, 44));
    return PMSM_CAPTURE_FRAME_SIZE;
}
