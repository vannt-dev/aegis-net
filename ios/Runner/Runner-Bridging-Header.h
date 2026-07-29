#import "GeneratedPluginRegistrant.h"

#include <stdint.h>
#include <stddef.h>

// Rust DNS engine (libaegis_core, staticlib) — C ABI used by the packet
// tunnel. Requires linking libaegis_core.a (built via
// `cargo build --release --target aarch64-apple-ios`).
size_t aegis_process_ip_packet(const uint8_t *in_buf, size_t in_len,
                               uint8_t *out_buf, size_t out_max_len);
