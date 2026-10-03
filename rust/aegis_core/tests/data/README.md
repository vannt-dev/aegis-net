# Test fixtures

`dot-test-cert.pem` and `dot-test-key.pem` are a self-signed certificate and its
private key for `dot.test` / `127.0.0.1`, valid until 2126. The unit tests in
`src/dot.rs` use them to run a DNS-over-TLS server on loopback.

The key is public by design: it protects nothing and no build ships it.
