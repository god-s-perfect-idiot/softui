#ifndef SOFTUI_HOST_ABI_H
#define SOFTUI_HOST_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* SoftUI → host (implemented by bootstrap; imported by WASM). */
void host_log(const uint8_t *ptr, uint32_t len);
void host_present(void);

/* SoftUI exports (implemented by runtime). */
int32_t softui_start(uint32_t width, uint32_t height);
int32_t softui_tick(uint64_t now_ns);
uint32_t softui_fb_ptr(void);
uint32_t softui_fb_width(void);
uint32_t softui_fb_height(void);
uint32_t softui_fb_stride(void);
uint32_t softui_alloc(uint32_t size);
int32_t softui_mount_disk(uint32_t ptr, uint32_t len);
void softui_push_key(uint32_t key, uint32_t mods);
void softui_set_boot_mode(uint32_t mode); /* 0=CLI (default), 1=GUI (later) */

#ifdef __cplusplus
}
#endif

#endif /* SOFTUI_HOST_ABI_H */
