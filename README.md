# WalletMera

**A trust layer for digital capital and AI agents.**

Non-custodial smart contract with three key tiers, timelock, veto rights, and four-stage transaction verification. Already running in production inside [merafund](https://github.com/merafund) contracts. Open-sourcing after audit.

> One compromised key should not cost everything.  
> One AI agent should not act without a veto.  
> The infrastructure for both now exists — and it is open.

---

## Table of Contents

- [The Problem](#the-problem)
- [What WalletMera Is](#what-walletmera-is)
- [Three Key Tiers](#three-key-tiers)
- [Four Verification Stages](#four-verification-stages)
- [AI × Crypto](#ai--crypto)
- [Key Features](#key-features)
- [Who It Is For](#who-it-is-for)
- [Status](#status)
- [Get Involved](#get-involved)
- [Contact](#contact)

---

## The Problem

Every serious crypto loss follows the same pattern: one key, one mistake, one second. A seed phrase as the only line of defense does not scale to real capital, real families, or real institutions.

There is a second problem, newer and growing faster: AI agents are already moving money. They build transactions, analyze markets, execute strategies. But there is no trust infrastructure for them. No pause. No veto. No recovery. Delegating an AI agent to manage assets today means accepting all the risk at once, with no way back.

WalletMera addresses both problems in a single contract.

---

## What WalletMera Is

A non-custodial smart contract (~2,000 lines of Solidity) with:

- Three key tiers with distinct roles and permissions
- Timelock — a mandatory pause before sensitive operations execute
- Veto rights — trusted observers can block operations before execution
- Four-stage transaction verification — before signing, after signing, on-chain, and post-execution
- Role-based access control with allowlists and blocklists
- Automated pause on anomalous activity
- AI agent delegation with enforceable constraints

Full control stays with the owner. Rules are enforced by the blockchain — not a company, not a service, not a person.

---

## Three Key Tiers

| Key | Role | Storage |
|-----|------|---------|
| **Primary** | Everyday operations — like a bank card for daily use | Accessible |
| **Backup** | Second factor — can cancel or block any operation | Stored separately |
| **Emergency** | Replaces any key, activates pause mode | Offline (safe / vault) |

Losing one key is not a disaster.

---

## Four Verification Stages

Every transaction passes through four sequential checkpoints:

**1 — Before signing**  
Intent validation, role and permission checks, optional allowlists and blocklists, contract call analysis.

**2 — After signing, before submission**  
Static re-check of the assembled transaction. Risk scoring. Cancellation or escalation window.

**3 — On-chain execution**  
Invariant enforcement — for example, minimum acceptable swap output. Automatic abort on violation.

**4 — After execution**  
On-chain result reconciliation. Account and series monitoring. Anomalies trigger automatic pause and alerts.

---

## AI × Crypto

WalletMera is the first non-custodial contract designed to make AI agents governable. An agent receives a key with defined permissions and operates within the rules you set. You keep the right to pause, review, or override at every stage.

| Capability | Description |
|------------|-------------|
| **Transaction building** | AI assistant constructs transactions from text or voice. All parameters validated before signing. |
| **Risk analysis** | Agent evaluates transactions before submission. Suspicious activity paused automatically. |
| **Veto agents** | External monitoring services can block operations before execution. No custodian required. |
| **Human-readable alerts** | Plain-language notifications after every transaction, including Telegram. Cancel button included. |
| **Full delegation** | Primary key can be handed to an AI agent with a full constraint set. Emergency key stays with you. |

This is not AI integrated into a wallet. It is a trust contract between a person and an agent, enforced on-chain.

---

## Key Features

- **Timelock** — configurable delay between signing and execution for sensitive operations
- **Veto rights** — designated observers can halt operations before they execute
- **Allowlists / blocklists** — payments only to pre-approved addresses; optional per role
- **Pause mode** — full stop; nothing executes without explicit owner action
- **M-of-N recovery** — emergency key restores access without touching assets
- **Dangerous approval revocation** — auto-revokes risky token approvals, a common theft vector
- **Post-execution monitoring** — balance anomalies and unusual series trigger automatic freeze
- **Role-based access** — sensitive functions accessible only to trusted roles
- **No forced limits** — by default, no spending limits are applied; only the rules you choose

---

## Who It Is For

- Founders and beneficiaries who hold meaningful on-chain assets and want a recovery plan
- Family offices and private structures managing digital wealth
- Funds and companies with digital assets and on-chain rights
- Developers and startups building on EVM who want a reliable security layer
- Teams building AI agents that interact with on-chain capital
- Anyone who has ever lost sleep over a single point of failure in their setup

---

## Status

| | |
|--|--|
| **Code** | ~2,000 lines of Solidity. Already running in production inside merafund contracts. |
| **Technical review** | Completed with external colleagues. Findings addressed. |
| **Audit** | MixBytes — in preparation. Beta testing runs in parallel. |
| **Open-source license** | After audit. We open the code to protect users and set a standard. |
| **Compatibility** | EVM networks at launch. Rust, TON, and other ecosystems on the roadmap. |

The license is closed until the audit is complete — to avoid exposing potential vulnerabilities before they are fixed. After that, fully open.

---

## Get Involved

**Beta testing**  
We are looking for people who hold real assets on-chain and are willing to test protection scenarios in practice. Beta opens in parallel with the audit. Write to us.

**Developers and founders**  
Open to collaboration on any stack — Solidity, Rust, TON, and others.
- Use WalletMera in your products — built to be integrated
- Propose features and improvements — pull requests welcome
- Build agents, monitors, or veto services that plug into the ecosystem

**Audit support**  
The MixBytes audit is a direct cost. Participants who support at this stage will be early members of the ecosystem. Details on request.

**Token and economy**  
Commercial layer is built around the agent ecosystem. The token is used to pay for AI agents, veto services, analytics, and monitoring. Tokenization through Proof of Capital. Early contributors receive a stake. Details after audit.

---

## Contact

| | |
|--|--|
| **Telegram** | [@WalletMera](https://t.me/WalletMera) |
| **Email** | team@proofofcapital.org |
| **Website** | walletmera.com *(coming soon)* |
| **Organization** | [github.com/merafund](https://github.com/merafund) |

---

*Built by the [Proof of Capital](https://proofofcapital.org) team.*  
*Security infrastructure should be public. That is why we are open-sourcing this.*
