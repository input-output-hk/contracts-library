/**
 * Test-only authorizer scripts for the script-credential (withdraw-0) path.
 *
 * These are NOT part of the library. They are compiled from
 * `fixtures/aiken/validators/authorizers.ak` (Aiken v1.1.22, Plutus V3); the
 * raw compiled code is embedded below so CI needs no Aiken toolchain. The cbor
 * (double-CBOR-encoded, as MeshJS expects) and the script hash are derived here
 * so they always agree with what the library's `applyAuthorization` computes.
 *
 * - `ALWAYS_TRUE`: approves every purpose (always-approving authorizer).
 * - `REJECT_WITHDRAW`: rejects withdrawals (so withdraw-0 auth fails) but
 *   approves everything else, so its stake credential can still be registered.
 */

import { applyCborEncoding, mConStr0, resolveScriptHash } from "@meshsdk/core";

import {
  type Account,
  newTxBuilder,
  signAndSubmit,
  waitForTx,
  type YaciProvider,
} from "./devnet";

function fixture(rawCompiledCode: string) {
  const cbor = applyCborEncoding(rawCompiledCode);
  return { cbor, hash: resolveScriptHash(cbor, "V3") };
}

export const ALWAYS_TRUE = fixture("5101010023259800a518a4d136564004ae69");

export const REJECT_WITHDRAW = fixture(
  "585301010029800aba2aba1aab9eaab9dab9a4888896600264653001300600198031803800cc0180092225980099b8748010c01cdd500144c928180498041baa0028a51401830060013003375400d149a26cac8009",
);

/** Mint `quantity` of `policy`+`tokenName` for `account` via the always-true
 * fixture minting script. Test-only + devnet-only. */
export async function mintTestToken(
  provider: YaciProvider,
  account: Account,
  quantity: bigint,
  policy: string,
  tokenName: string,
): Promise<void> {
  const col = (await account.wallet.getCollateral())[0];
  const mintTx = await newTxBuilder(provider)
    .mintPlutusScriptV3()
    .mint(quantity.toString(), policy, tokenName)
    .mintRedeemerValue(mConStr0([]))
    .mintingScript(ALWAYS_TRUE.cbor)
    .txInCollateral(
      col.input.txHash,
      col.input.outputIndex,
      col.output.amount,
      col.output.address,
    )
    .changeAddress(account.address)
    .selectUtxosFrom(await account.wallet.getUtxos())
    .complete();
  await waitForTx(provider, await signAndSubmit(account, mintTx));
}
