# ContractsLibrary — Composability Architecture Specification

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

### 1.2 Authorization is always pluggable

No contract in this library hardcodes a specific authorization mechanism. All authorization flows through a shared interface that supports single-key signatures, script-based authorization (multisig, DAOs, smart wallets), and native script authorization. This ensures every contract composes freely with every authorization scheme.

### 1.3 Contracts Ship as On-Chain + Off-Chain Pairs

Every contract consists of:

- **On-chain**: On-chain language (e.g. Aiken) modules containing validation logic and optionally a ready-to-deploy validator that wires them together.
- **Off-chain**: An off-chain framework/language (e.g. MeshJS, Tx3) that constructs valid transactions for each action the contract supports.

The off-chain layer is the primary developer-facing API unless they want to change how the protocol works. The on-chain layer is a dependency of it.

### 1.4 Developer experience and security have priority

All unavoidable trade-offs will err on the side of improving ease of use and developer experience over execution cost, speed, and even composability, with the only exception of security. Security is never compromised.

---

## 2. The Authorization System

TODO
