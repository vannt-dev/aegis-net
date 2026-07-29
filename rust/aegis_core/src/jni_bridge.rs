//! JNI entry point so the Android `AegisVpnService` (Kotlin) can push raw TUN
//! packets through the DNS engine.
//!
//! Kotlin side:
//! ```kotlin
//! external fun nativeProcessPacket(packet: ByteArray): ByteArray
//! // System.loadLibrary("aegis_core")
//! ```
//! An empty returned array means "no DNS reply — forward/drop the packet".

use jni::objects::{JByteArray, JClass};
use jni::JNIEnv;

#[no_mangle]
pub extern "system" fn Java_com_aegisnet_app_AegisVpnService_nativeProcessPacket<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    input: JByteArray<'local>,
) -> JByteArray<'local> {
    let empty = |env: &mut JNIEnv<'local>| env.new_byte_array(0).expect("alloc empty array");

    let bytes = match env.convert_byte_array(&input) {
        Ok(b) => b,
        Err(_) => return empty(&mut env),
    };

    // Response can be slightly larger than the request; give generous headroom.
    let mut out = vec![0u8; bytes.len() + 1500];
    let n = crate::api::aegis_process_ip_packet(
        bytes.as_ptr(),
        bytes.len(),
        out.as_mut_ptr(),
        out.len(),
    );

    if n == 0 {
        return empty(&mut env);
    }

    match env.byte_array_from_slice(&out[..n]) {
        Ok(arr) => arr,
        Err(_) => empty(&mut env),
    }
}
