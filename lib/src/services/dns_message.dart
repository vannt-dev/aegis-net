import 'dart:typed_data';

/// Pure DNS wire-format helpers. No platform imports, so this compiles
/// everywhere including web, and can be tested without a socket.
class DnsMessage {
  /// Response echoing the request's header and question with RCODE 2
  /// (SERVFAIL) and no records. Null when [query] is not a well-formed query,
  /// since there would be nothing truthful to send.
  ///
  /// SERVFAIL, not NXDOMAIN: the name may well exist, we just could not find
  /// out. Clients treat it as transient and retry instead of caching a negative
  /// answer.
  static Uint8List? buildServfail(Uint8List query) {
    final end = questionEndOffset(query);
    if (end == null) return null;

    final reply = Uint8List.fromList(query.sublist(0, end));
    reply[2] = 0x81; // QR=1, RD=1
    reply[3] = 0x82; // RA=1, RCODE=2 (SERVFAIL)
    for (final i in [6, 7, 8, 9, 10, 11]) {
      reply[i] = 0; // AN / NS / AR counts
    }
    return reply;
  }

  /// Offset just past the first question (QNAME + QTYPE + QCLASS), mirroring
  /// `DnsFilterService::question_end_offset` on the Rust side. Null when the
  /// buffer is not a parseable query.
  static int? questionEndOffset(Uint8List buffer) {
    if (buffer.length < 12) return null;
    if ((buffer[4] << 8 | buffer[5]) == 0) return null; // QDCOUNT

    var offset = 12;
    while (true) {
      if (offset >= buffer.length) return null;
      final len = buffer[offset];
      if (len == 0) {
        offset += 1; // root label terminator
        break;
      }
      if (len > 63 || offset + 1 + len > buffer.length) return null;
      offset += 1 + len;
    }

    if (offset + 4 > buffer.length) return null;
    return offset + 4;
  }
}
