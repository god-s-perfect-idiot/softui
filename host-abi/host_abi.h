#ifndef SOFTUI_HOST_ABI_H
#define SOFTUI_HOST_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* SoftUI → host (implemented by bootstrap; imported by WASM). */
void host_log(const uint8_t *ptr, uint32_t len);
void host_present(void);
void host_storage_write(const uint8_t *ptr, uint32_t len);

/* Wall clock: Unix epoch milliseconds + local TZ offset minutes east of UTC. */
uint64_t host_time_wall_ms(void);
int32_t host_time_tz_min(void);

/* Audio: queue interleaved PCM s16le. sample_rate Hz, channels (1 or 2). */
int32_t host_audio_queue(const uint8_t *ptr, uint32_t len, uint32_t sample_rate, uint32_t channels);
void host_audio_stop(void);

/* Image decode (PNG/JPEG/…): write RGBA8 into dst. Returns nbytes, -2 pending, <0 error.
 * out_w / out_h are WASM pointers to u32 little-endian. */
int32_t host_image_decode(const uint8_t *src, uint32_t src_len, uint8_t *dst, uint32_t dst_cap,
                          uint32_t *out_w, uint32_t *out_h);

/* suigui bridge: paint .sui source into SoftUI FB. ev: 0=none 1=move 2=click. */
int32_t host_sui_paint(const uint8_t *src, uint32_t src_len, uint8_t *fb, uint32_t w, uint32_t h,
                       uint32_t stride, uint32_t ev, uint32_t x, uint32_t y);

/* SoftUI exports (implemented by runtime). */
int32_t softui_start(uint32_t width, uint32_t height);
int32_t softui_resize(uint32_t width, uint32_t height); /* match host viewport; keep session */
int32_t softui_tick(uint64_t now_ns);
uint32_t softui_fb_ptr(void);
uint32_t softui_fb_width(void);
uint32_t softui_fb_height(void);
uint32_t softui_fb_stride(void);
uint32_t softui_alloc(uint32_t size);
int32_t softui_mount_disk(uint32_t ptr, uint32_t len);
int32_t softui_persist(void); /* pack SoftFS + host_storage_write */
void softui_push_key(uint32_t key, uint32_t mods);
/* Pointer in SoftUI FB pixel coords. kind: 0=move, 1=down, 2=up; buttons bit0=primary. */
void softui_push_pointer(uint32_t x, uint32_t y, uint32_t buttons, uint32_t kind);
/* Boot/session UX (bootloader, GUI, CLI) is SoftUI-owned. Hosts must not
 * select GUI/CLI via URL, path, or other platform-specific side channels. */

#ifdef __cplusplus
}
#endif

#endif /* SOFTUI_HOST_ABI_H */
