// The desktop resolver needs dart:io and dart:isolate, neither of which exists
// on web. Same conditional-export shape as bridge/ffi_bindings.dart.
export 'desktop_dns_proxy_stub.dart'
    if (dart.library.io) 'desktop_dns_proxy_io.dart';
