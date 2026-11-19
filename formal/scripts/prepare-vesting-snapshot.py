"""Prepare the frozen M1.2 vesting validator for the Lean proofs."""

import hashlib
import json
from pathlib import Path
from tempfile import NamedTemporaryFile


def main():
    formal = Path(__file__).resolve().parents[1]
    metadata_path = formal / "Formal/LinearVesting/validator-metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    snapshot = {
        "validator_name": "linear_vesting.linear_vesting.spend",
        "source_commit": "d629dce7ef1a6af883215c076adc964bd37152a1",
        "plutus_version": "v3",
        "cbor_format": "single_cbor_hex",
        "parameterization_state": "unparameterized",
        "applied_parameters": [],
    }
    for key, expected in snapshot.items():
        if metadata[key] != expected:
            raise ValueError(f"{key} does not match the recorded M1.2 snapshot")

    cbor = bytes.fromhex(metadata["cbor_hex"])
    # This 1,401-byte program has a single CBOR byte-string wrapper with a uint16 length.
    if cbor[:1] != b"\x59" or int.from_bytes(cbor[1:3], "big") != len(cbor) - 3:
        raise ValueError("expected one CBOR byte string around the vesting Flat bytes")
    script_hash = hashlib.blake2b(b"\x03" + cbor, digest_size=28).hexdigest()
    if script_hash != "95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a":
        raise ValueError(f"vesting script hash {script_hash} does not match M1.2")

    target = formal / "Scripts/linear_vesting_spend.flat"
    flat = cbor[3:].hex().encode("ascii")
    if target.is_file() and target.read_bytes() == flat:
        print(f"Verified vesting snapshot {script_hash} (cached)")
        return

    target.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=target.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(flat)
    try:
        # Lake tracks Script.lean but has no dependency on its imported Flat file.
        build = formal / ".lake/build"
        module = "Formal/LinearVesting/Script"
        for suffix in (".olean", ".olean.hash", ".ilean", ".ilean.hash", ".trace"):
            (build / "lib/lean" / (module + suffix)).unlink(missing_ok=True)
        for suffix in (".c", ".c.hash", ".setup.json"):
            (build / "ir" / (module + suffix)).unlink(missing_ok=True)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Prepared vesting snapshot {script_hash}")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, TypeError, ValueError) as error:
        raise SystemExit(f"Could not prepare the frozen vesting validator: {error}")
