/**
 * Fixed throwaway devnet faucet keypair.
 *
 * TEST-ONLY credentials, worthless outside a local trix devnet (network
 * id 0, funded purely from `settings/devnet.toml` genesis). The address
 * below is derived from this exact Ed25519 key (enterprise address,
 * key-credential, testnet); the same literal is committed in
 * `settings/devnet.toml`, which funds it at genesis.
 *
 * To rotate: generate a fresh 32-byte Ed25519 seed, then update BOTH
 * literals together (address = blake2b-224(pubkey) behind header 0x60,
 * bech32 "addr_test").
 */
export const FAUCET = {
  privateKeyHex:
    "5618250b53a27b90f34714fa4430614e19f13ffbc80b66a4aac23f60bf5c1252",
  address: "addr_test1vq3tagm5q2dknru3w9ech3f9zr93zsj8pcfzvxjg0fd5vugnec6pd",
} as const;
