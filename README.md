# vmail_imap

Pure V IMAP helper library.

This package keeps protocol command construction and response parsing testable.
The `vmail_imap.imap_plain` submodule includes a small plain TCP IMAP transport
for LOGIN, SELECT, SEARCH, FETCH, UID STORE and EXPUNGE. The
`vmail_imap.imap_tls` submodule adds implicit TLS and STARTTLS client
transports on top of V's bundled mbedtls backend.

Both transports share `vmail_imap.TransportOptions` and return raw RFC822
messages that pair with `vmail_mime` for EML parsing. Literal `FETCH` payloads
are read by declared byte length, so mail bodies can safely contain lines that
look like IMAP command tags.
