#!/usr/bin/env python3
"""Decrypt a cosign / sigstore encrypted private key into standard PKCS#8 PEM.

Cosign envelope format: PEM block (`ENCRYPTED COSIGN PRIVATE KEY` or
`ENCRYPTED SIGSTORE PRIVATE KEY`) containing a JSON document with:
  - kdf: scrypt(N, r, p) over UTF-8 password + random salt -> 32-byte key
  - cipher: nacl/secretbox (XSalsa20-Poly1305) with random 24-byte nonce
  - ciphertext: nacl-encrypted PKCS#8 DER of the ECDSA private key

Output: standard unencrypted PKCS#8 PEM ("BEGIN PRIVATE KEY"), suitable for
storing in 1Password (as a Document) or for use with tooling that expects a
plain PEM key.

Why this exists: cosign provides no `export-private-key` subcommand. To get
the unencrypted key you have to decrypt the envelope yourself. This script
matches what cosign does internally — no novel crypto.

Cross-check: derive the public key from the decrypted output and compare:
    openssl pkey -in cosign.key.decrypted -pubout
should byte-equal cosign.pub.

Usage:
    COSIGN_PASSWORD='<passphrase>' python3 scripts/decrypt-cosign-key.py cosign.key > cosign.key.decrypted

Dependencies (pip / Fedora RPM names):
    pip install pynacl cryptography      # or:
    sudo dnf install python3-nacl python3-cryptography
"""
import base64
import hashlib
import json
import os
import re
import sys

from cryptography.hazmat.primitives.serialization import (
    load_der_private_key, Encoding, PrivateFormat, NoEncryption,
)
from nacl.secret import SecretBox


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: COSIGN_PASSWORD=... decrypt-cosign-key.py <cosign.key>")
    password = os.environ.get("COSIGN_PASSWORD")
    if password is None:
        sys.exit("COSIGN_PASSWORD env var required")

    with open(sys.argv[1], "rb") as f:
        pem = f.read()

    m = re.search(
        rb"-----BEGIN ENCRYPTED (?:SIGSTORE|COSIGN) PRIVATE KEY-----\s*(.+?)\s*-----END ENCRYPTED (?:SIGSTORE|COSIGN) PRIVATE KEY-----",
        pem, re.DOTALL,
    )
    if not m:
        sys.exit("no cosign/sigstore PEM block found")
    envelope = base64.b64decode(re.sub(rb"\s+", b"", m.group(1)))
    obj = json.loads(envelope)

    salt = base64.b64decode(obj["kdf"]["salt"])
    N = obj["kdf"]["params"]["N"]
    r = obj["kdf"]["params"]["r"]
    p = obj["kdf"]["params"]["p"]
    nonce = base64.b64decode(obj["cipher"]["nonce"])
    ciphertext = base64.b64decode(obj["ciphertext"])

    derived = hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt, n=N, r=r, p=p, dklen=32,
        # default maxmem (32 MiB) is too small for cosign's N=65536; bump it.
        maxmem=128 * N * r * 2,
    )
    pkcs8_der = SecretBox(derived).decrypt(ciphertext, nonce=nonce)

    priv = load_der_private_key(pkcs8_der, password=None)
    pem_out = priv.private_bytes(
        encoding=Encoding.PEM,
        format=PrivateFormat.PKCS8,
        encryption_algorithm=NoEncryption(),
    )
    sys.stdout.buffer.write(pem_out)


if __name__ == "__main__":
    main()
