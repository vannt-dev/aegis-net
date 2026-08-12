#ifndef PacketTunnel_Bridging_Header_h
#define PacketTunnel_Bridging_Header_h

#include <stdint.h>
#include <stddef.h>

// Rust DNS engine (libaegis_core, staticlib) — C ABI called from
// PacketTunnelProvider.swift. Link libaegis_core.a (or the xcframework built by
// ios/build_rust_ios.sh) into the PacketTunnel extension target.
size_t aegis_process_ip_packet(const uint8_t *in_buf, size_t in_len,
                               uint8_t *out_buf, size_t out_max_len);

// Sets up logging. Everything else works without it (engine state is lazily
// initialised), but without it the extension produces no engine logs at all.
int32_t aegis_init(void);

// Cross-process state, exchanged through the App Group container. This process
// holds its own copy of the engine, so without these it would filter with an
// empty rule set. 0 on success, negative on failure.
int32_t aegis_import_settings(const char *path);
int32_t aegis_export_stats(const char *path);
uint32_t aegis_load_rules_file(const char *path, int32_t category_id);

// Drops rules loaded from filter lists, keeping the user's allow/deny lists and
// host overrides. Call before re-loading, or a list the user unsubscribed from
// keeps blocking for the life of this process — and the extension reloads many
// times per launch, so it never gets a fresh process to fix it.
void aegis_clear_downloaded_rules(void);

#endif /* PacketTunnel_Bridging_Header_h */
