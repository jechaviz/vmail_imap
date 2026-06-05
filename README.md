# vmail_imap

Pure V IMAP helper library.

This package keeps protocol command construction and response parsing separate from
socket transport so projects can test inbox synchronization without network
credentials. It is designed to pair with `vmail_mime` for EML parsing.
