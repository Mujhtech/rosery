# Independent App Attest verification fixture

`ios-14.4.json` contains the attestation and assertion records from Vincent
Haupert's `devicecheck-appattest` real-device iOS 14.4 samples, downloaded on
2026-10-24:

https://github.com/veehaitch/devicecheck-appattest/blob/main/src/test/resources/ios-14.4.yaml

The JSON preserves the original record field values and includes the source
file's SHA-256 digest. YAML formatting is converted to JSON so the tests do not
need a YAML dependency. Receipt-only records are omitted. These samples use the
upstream author's app identity and publicly published test key; they are never
accepted as Rosery production app keys.

The sample demonstrates a certificate chain to Apple's real embedded App Attest
root (validated at the historical sample date) and an assertion actually made by
an Apple device. It independently exercises nonce hashing, public key derivation,
COSE parsing and Apple's SHA256withECDSA assertion signature semantics.

Source project copyright 2021 Vincent Haupert. Licensed under the Apache License,
Version 2.0; see the preserved `UPSTREAM-LICENSE`. The samples are provided without
warranty, as set out in that license.
