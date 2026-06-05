# vmail_imap

Pure V IMAP helper library.

This package keeps protocol command construction and response parsing testable,
and includes a small plain TCP IMAP transport for LOGIN, SELECT, SEARCH and FETCH.
It is designed to pair with `vmail_mime` for EML parsing.
