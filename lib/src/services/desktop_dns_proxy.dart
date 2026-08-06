// Same conditional-export shape as bridge/ffi_bindings.dart.
//
// What actually breaks the web build is dart:ffi, which the resolver reaches
// through the engine bindings. dart:io and dart:isolate imports compile for web
// on their own — measured, not assumed — so this split is not only about
// compiling: it gives web an implementation that honestly reports "not running"
// instead of one that would throw the moment anything called it.
export 'desktop_dns_proxy_stub.dart'
    if (dart.library.io) 'desktop_dns_proxy_io.dart';
