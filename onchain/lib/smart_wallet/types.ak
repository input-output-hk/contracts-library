//// Smart wallet — on-chain types.

use aiken/crypto.{ScriptHash, VerificationKeyHash}

/// The wallet's self-governing config, stored in the `current` field of the
/// settings UTxO datum so it is updatable without redeploying consumers.
pub type WalletConfig {
  /// The n signers of the base M-of-N floor.
  members: List<VerificationKeyHash>,
  /// The minimum m of `members` required to authorize a spend.
  threshold: Int,
}

/// Datum carried by each wallet UTxO: the delegated authorization scripts for
/// spends and deposits. The credential allowed to update them is a parameter of
/// the spending script.
pub type WalletDatum {
  /// Delegated withdraw-0 scripts that must run on every spend of this UTxO,
  /// each carrying its own mutable data (if any) in `Data`.
  spenders: Pairs<ScriptHash, Data>,
  /// Delegated withdraw-0 scripts that must run on every deposit into this
  /// UTxO (e.g. asset or source-address allow/denylists), each carrying its own
  /// configuration in `Data`.
  depositors: Pairs<ScriptHash, Data>,
}

/// Actions on a wallet UTxO (spend endpoint).
pub type SpendRedeemer {
  /// Pay out: base M-of-N floor plus the delegated spenders; the wallet must
  /// survive with its `depositors` map unchanged.
  Spend
  /// Rewrite this UTxO's config (`spenders` and `depositors`); `out_ix`
  /// locates the continuation.
  UpdatePermissions { out_ix: Int }
  /// Deposit funds: every `depositors` script runs and approves, funds are
  /// added and the datum is preserved; `out_ix` locates the continuation.
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
