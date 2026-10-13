#ifndef PMSM_CAPTURE_H
#define PMSM_CAPTURE_H

#include <stddef.h>
#include <stdint.h>

#define PMSM_CAPTURE_FRAME_SIZE 48u
#define PMSM_CAPTURE_VALID 1u
#define PMSM_CAPTURE_SATURATED 2u

/* One coherent snapshot, converted by the board adapter to amplitude-invariant
 * dq SI units. timestamp_us is the sampling time, never the transmit time. */
typedef struct {
    uint32_t sequence;
    uint32_t run_id;
    uint64_t timestamp_us;
    float id_A;
    float iq_A;
    float ud_V;
    float uq_V;
    float omega_e_rad_s;
    uint8_t flags;
} pmsm_capture_sample;

/* Pack a snapshot in foreground from a stable buffer. No HAL, allocation,
 * transport, motor commands, or shared-state synchronization are provided.
 * Return 48 on success, 0 for invalid arguments or reserved flag bits. */
size_t pmsm_capture_pack(uint8_t *output, size_t capacity,
                         const pmsm_capture_sample *sample);

#endif
