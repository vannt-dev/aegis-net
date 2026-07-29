#ifndef PacketTunnel_Bridging_Header_h
#define PacketTunnel_Bridging_Header_h

#include <stdint.h>
#include <stddef.h>

// Rust DNS engine (libaegis_core, staticlib) — C ABI called from
// PacketTunnelProvider.swift. Link libaegis_core.a (or the xcframework built by
// ios/build_rust_ios.sh) into the PacketTunnel extension target.
size_t aegis_process_ip_packet(const uint8_t *in_buf, size_t in_len,
                               uint8_t *out_buf, size_t out_max_len);

#endif /* PacketTunnel_Bridging_Header_h */
