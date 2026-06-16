# ContractsLibrary: Composability Architecture Specification

## Purpose of This Document

This document defines the composability architecture for a Cardano smart contract library written in Aiken (on-chain) with TypeScript off-chain builders. It is intended to be used as a working reference to prototype contracts and validate that the architecture holds under real-world composition scenarios.

The central problem this architecture solves: **Cardano validators are predicates over entire transactions. When multiple validators participate in the same transaction, any implicit assumption one validator makes about the transaction shape can conflict with another validator's assumptions, breaking composability.** This document defines the conventions, types, and patterns that prevent those conflicts.

---

## 1. Core Principles

### 1.1 Validators MUST be composable

A validator CAN assert properties about:

- Its own UTXOs (including value, datum, address, etc.).
- The authorization of the action being performed on its UTXOs.
- The validity range when time-dependent logic is required.
- The presence, absence, and properties of related UTXOs, tokens, scripts, etc.
- The minimum value flowing through the transaction.

A validator MUST NOT (unless unavoidable) assert properties about:

- The total number of inputs or outputs in the transaction.
- The total value flowing through the transaction.
- The exact set of signatories (only that required signatories are present).
- The presence, absence, and properties of unrelated UTXOs, tokens, scripts, etc.

This is the most important principle of the library. The objective behind these is to aid composability between contracts.

### 1.2 Contracts Ship as On-Chain + Off-Chain + Spec

Every contract is made of three parts, each living in its own top-level directory:

- **On-chain** (`onchain/`): the validation logic that the ledger enforces.
- **Off-chain** (`offchain/`): the transaction builders developers call.
- **Spec** (`specs/`): the implementation-independent description of behavior.

The off-chain layer is the primary developer-facing API unless they want to change how the protocol works. The on-chain layer is a dependency of it, and the spec is the source of truth both implement against. Section 2 defines the role and contents of each part.

### 1.3 Developer experience and security have priority

All unavoidable trade-offs will err on the side of improving ease of use and developer experience over execution cost, speed, and even composability, with the only exception of security. Security is never compromised.

---

## 2. Anatomy of a Contract

A contract is a single use case (a vesting schedule, an auction, a token standard) expressed in three decoupled parts. They are decoupled on purpose: the spec can be verified without trusting an implementation, the on-chain logic can be re-implemented in another on-chain language, and new off-chain languages can be added, all without rewriting the others. The three parts must stay consistent, but they are not the same artifact.

### 2.1 On-chain part (`onchain/`)

**Role.** The only part the ledger enforces, and therefore the only part that carries security. Everything in the off-chain layer is convenience that a malicious actor can ignore; the on-chain logic is what actually constrains what transactions are valid. It must hold against an adversary who constructs transactions by hand, and it must follow the composability rules in Section 1 so it does not break when it shares a transaction with other validators.

**It contains:**

- **Reusable validation logic** as Aiken `lib/` modules: parameterized, composable functions that assert the contract's rules. These are the unit other contracts and the reference validator import.
- **Datum and redeemer type definitions** for the contract's on-chain state and the actions performed on it.
- **Optionally, a ready-to-deploy reference validator** under `validators/` that wires the logic together into a deployable script. A contract can also ship as pure logic for consumers to embed in their own validator.

### 2.2 Off-chain part (`offchain/`)

**Role.** The primary developer-facing API. It builds valid transactions for each action the contract supports, so a developer can use the contract without reading the on-chain code or reasoning about transaction shape. Used primarily as a library.

**It contains:**

- **A transaction builder per action** the contract supports, in one or more frameworks/languages (e.g. MeshJS, Tx3). Each builder assembles the inputs, outputs, datums, and redeemers that the on-chain logic requires for that action.
- **Helpers** for constructing and reading the contract's datums and redeemers, and for off-chain parameter application where the contract allows it.
- **A pin to a specific on-chain blueprint** (version/hash) if possible so off-chain code and on-chain logic cannot silently drift apart.

### 2.3 Spec part (`specs/`)

**Role.** The source of truth for what the contract does, written so it can be understood and checked independently of any implementation. It is what makes the contract verifiable and re-implementable: a second on-chain language or a new off-chain package is correct insofar as it matches the spec, not insofar as it matches the existing code. It is decoupled from implementation by design and contains no implementation code.

**It contains:**

- **The action set**: the operations the contract supports, with the inputs, outputs, redeemers, and datums each one requires.
- **The state model**: the state machine or datum/redeemer transitions, and the invariants that must hold across them.
- **The threat model and known assumptions**: what the contract defends against, and the conditions under which its guarantees hold.

---

## 3. The Authorization System

> **Status: Experimental.** This is exploratory and may change or be scrapped entirely. We do not yet know if any of it will prove useful; it is one direction we are trying, not a commitment.

The idea is that a contract should state *that* an action requires authorization without hardcoding *how* authorization is decided, so the same contract composes equally well with a single key, a multisig, a DAO, a smart wallet, or schemes that do not exist yet.

We are exploring modeling the authorizer as a Cardano `Credential` (either a public-key hash or a script hash) supplied by the consumer:

- **Public-key authorizer**: satisfied by a signature in the transaction.
- **Script authorizer**: satisfied by *calling another contract*, requiring that script to run and approve within the same transaction. This is how a multisig, DAO, or smart wallet can stand in for a key without the consuming contract knowing anything about them.

Whether this abstraction is worth its cost (newcomer friction, execution budget, audit surface) is an open question we will answer by building real contracts, not in this document.
