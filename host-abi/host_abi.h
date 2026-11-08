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
