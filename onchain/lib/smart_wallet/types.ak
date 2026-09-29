//// Smart wallet — on-chain types.

use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/address.{Credential}

/// The wallet's self-governing config, stored in the `current` field of the
/// settings UTxO datum so it is updatable without redeploying consumers.
pub type WalletConfig {
  /// The n signers of the base M-of-N floor.
  members: List<VerificationKeyHash>,
  /// The minimum m of `members` required to authorize a spend.
  threshold: Int,
}

/// Datum carried by each wallet UTxO: the delegated authorization list and the
/// deposit authorization. The credential allowed to update them is a parameter
/// of the spending script.
pub type WalletDatum {
  /// Delegated withdraw-0 scripts that must run on every spend of this UTxO,
  /// each carrying its own mutable data (if any) in `Data`.
  withdrawals: Pairs<ScriptHash, Data>,
  /// Credential allowed to deposit funds into this UTxO (see `Deposit`).
  depositor: Credential,
}

/// Actions on a wallet UTxO (spend endpoint).
pub type SpendRedeemer {
  /// Pay out: base M-of-N floor plus the delegated withdrawals.
  Spend
  /// Rewrite this UTxO's config (`withdrawals` and `depositor`); `out_ix`
  /// locates the continuation.
  UpdateConfig { out_ix: Int }
  /// Deposit funds: the `depositor` authorizes, funds are added and the datum
  /// is preserved; `out_ix` locates the continuation.
  Deposit { out_ix: Int }
  /// Close the wallet: the `admin` authorizes, and the wallet NFT is burned.
  Close
}

/// Actions on the mint endpoint: create or close a wallet, one-shot.
pub type MintRedeemer {
  /// Mint the wallet NFT; `out_ix` locates the new wallet UTxO.
  Mint { out_ix: Int }
  /// Burn the wallet NFT, permanently closing the wallet.
  Burn
}
