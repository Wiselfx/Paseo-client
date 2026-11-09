# R16: relay crypto core

Branch `r16-relay-crypto`. Spec: `docs/research/11-relay-pairing.md` §10 item 1 (and the sections it
references). The lead approved adding Apple's `swift-crypto` (module `Crypto`) to the `PaseoKit`
target only; pin a released version range in `Packages/PaseoCore/Package.swift`. On Apple
platforms swift-crypto forwards to CryptoKit, so write against the shared `Crypto` API only.

Build `NoiseNK` (initiator), `RelayRecordCodec`, `ConnectionOffer` exactly as §10.1 says, with every
rejection rule, plus tests from the vendored upstream vectors (NK vectors, low-order X25519 points,
base64 canonicality, framing rejections, handshake transcript). Vectors go in the test target
(`Tests/PaseoFixtures` or a new fixtures folder); copy only public test data, never this host's
keypair or offer. Protected mode only: legacy mode is rejected (4002), as the doc recommends.
Nonce discipline and tag-verify-before-advance must be covered by tests.

No sockets, no UI, no host interaction. Done = `rm -rf .build && swift build --build-tests &&
swift test` fully green (first build fetches swift-crypto; that's expected), no warnings in your
files. No background tasks or subagents; don't end your turn while waiting. Commit "R16: relay
crypto core", don't push. Final message: what you built, vector coverage, test totals, anything
in the doc you found wrong.
