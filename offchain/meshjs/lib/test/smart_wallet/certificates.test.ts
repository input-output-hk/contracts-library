import { CredentialType, Serialization } from "@meshsdk/core-cst";
import { describe, expect, it } from "vitest";
import { rewriteWithdrawalCertificates } from "../../src/smart_wallet/withdrawal_scripts";

const TARGET_SCRIPT = "aa".repeat(28);
const OTHER_SCRIPT = "cc".repeat(28);
const OTHER_KEY = "bb".repeat(28);

function legacyRegistration(hash: string, type: CredentialType) {
  return Serialization.Certificate.newStakeRegistration(
    new Serialization.StakeRegistration({ type, hash }),
  );
}

function legacyDeregistration(hash: string, type: CredentialType) {
  return Serialization.Certificate.newStakeDeregistration(
    new Serialization.StakeDeregistration({ type, hash }),
  );
}

function txWithCertificates(
  certificates: Array<ReturnType<typeof legacyRegistration>>,
): string {
  const inputs = Serialization.CborSet.fromCore(
    [],
    Serialization.TransactionInput.fromCore,
  );
  const body = new Serialization.TransactionBody(inputs, [], 0n);
  const certs = Serialization.CborSet.fromCore(
    [],
    Serialization.Certificate.fromCore,
  );
  certs.setValues(certificates);
  body.setCerts(certs);
  return new Serialization.Transaction(
    body,
    new Serialization.TransactionWitnessSet(),
  ).toCbor();
}

function certificatesOf(txHex: string) {
  const tx = Serialization.Transaction.fromCbor(txHex);
  return [...tx.body().certs()!.values()];
}

describe("rewriteWithdrawalCertificates", () => {
  it("rewrites only the target script registration with the given key deposit", () => {
    const rewritten = rewriteWithdrawalCertificates(
      txWithCertificates([
        legacyRegistration(TARGET_SCRIPT, CredentialType.ScriptHash),
        legacyRegistration(OTHER_SCRIPT, CredentialType.ScriptHash),
        legacyRegistration(OTHER_KEY, CredentialType.KeyHash),
      ]),
      new Set([TARGET_SCRIPT]),
      3_000_000n,
    );

    const [target, otherScript, otherKey] = certificatesOf(rewritten);
    const registration = target.asRegistrationCert();
    expect(registration).toBeDefined();
    expect(registration!.stakeCredential().hash).toBe(TARGET_SCRIPT);
    expect(registration!.deposit()).toBe(3_000_000n);

    expect(otherScript.kind()).toBe(0);
    expect(otherScript.asStakeRegistration()).toBeDefined();
    expect(otherKey.kind()).toBe(0);
    expect(otherKey.asStakeRegistration()).toBeDefined();
  });

  it("rewrites only the target script deregistration with the given refund", () => {
    const rewritten = rewriteWithdrawalCertificates(
      txWithCertificates([
        legacyDeregistration(TARGET_SCRIPT, CredentialType.ScriptHash),
        legacyDeregistration(OTHER_SCRIPT, CredentialType.ScriptHash),
      ]),
      new Set([TARGET_SCRIPT]),
      4_000_000n,
    );

    const [target, other] = certificatesOf(rewritten);
    const unregistration = target.asUnregistrationCert();
    expect(unregistration).toBeDefined();
    expect(unregistration!.stakeCredential().hash).toBe(TARGET_SCRIPT);
    expect(unregistration!.deposit()).toBe(4_000_000n);

    expect(other.kind()).toBe(1);
    expect(other.asStakeDeregistration()).toBeDefined();
  });

  it("leaves the transaction unchanged when no target matches", () => {
    const tx = txWithCertificates([
      legacyRegistration(OTHER_SCRIPT, CredentialType.ScriptHash),
    ]);
    expect(
      rewriteWithdrawalCertificates(tx, new Set([TARGET_SCRIPT]), 2_000_000n),
    ).toBe(tx);
  });
});
