# Release 2: Data Validation, Risk Hardening & Anti-Cheat Specifications
### *Senior Data Analyst Deliverable - Task 2*

---

## 1. Executive Summary & Problem Context

In a large-scale mobile gaming economy operating on a **write-only / append-only** transaction ledger, data integrity faces threats from three primary vectors:
1. **Untrusted Client Devices:** Highly incentivized players attempting to manipulate client-side logic (e.g., memory editors, jailbreak/root access, packet tampering, or system clock manipulation).
2. **Network Instability:** Packet delays, retry loops, out-of-order delivery, or dropped webhook transmissions.
3. **App Bugs & Formula Drift:** Version desynchronization or calculation discrepancies between client builds and the backend game engine.

This document defines the **Threat Modeling Matrix**, **Data Expectation Rules (Plain English)**, and an **Automated SQL Audit Suite** to guarantee absolute financial integrity and zero balance leakage.

---

## 2. Threat Modeling: What Can Go Wrong? (Weak Spots & Failure Modes)

The matrix below evaluates seven critical failure modes and their corresponding architectural mitigations:

| # | Vulnerability / Failure Mode | Scenario & Impact | Risk Level | Detection & Engineering Mitigation |
| :- | :--- | :--- | :--- | :--- |
| **1** | **Device Clock Manipulation (Time Travel Hack)** | Player advances phone clock (e.g., +10 hours) to force background Mana to refill instantly. | **CRITICAL** | **Server-Authoritative Clock:** Regeneration is calculated strictly via server timestamps (`TIMESTAMPTZ`), ignoring client local device time. |
| **2** | **Ghost Purchase Claims (Fake Callback Injection)** | Hacker intercepts or patches client APK to bypass PG UI and send fake success claims to the backend. | **CRITICAL** | **Zero-Trust State Machine:** Records from `CLIENT_CALLBACK` are set to `amount = 0` with status `PENDING_VERIFICATION`. Coins are **NEVER credited** until verified by a trusted S2S webhook. |
| **3** | **Replay Attacks / Duplicate Credit** | Payment gateway retries webhook due to network lag, or a malicious user replays successful HTTP requests. | **HIGH** | **Strict Idempotency Invariant:** Every `external_transaction_id` is restricted to $\le 1$ positive settled coin credit (`amount > 0` and `status = 'SETTLED'`). Subsequent attempts are marked `DUPLICATE_IGNORED`. |
| **4** | **Race Condition / Double Spending** | Player has 3 Mana remaining and taps the action button simultaneously across multiple threads. | **HIGH** | **Atomic Serialization / Invariant Assertion:** The backend executes atomic balance checks. If running balance $<$ action cost, the second request fails with `INSUFFICIENT_FUNDS`. |
| **5** | **Formula & Version Drift** | Outdated client version calculates action Mana deductions using deprecated formulas rather than $m_a = \text{round}(3 \times L^{1.1})$. | **MEDIUM** | **Server-Side Formula Validation:** Every `ACTION_SPEND` deduction is validated against the user's level ($L$). Any discrepancy is rejected and logged to telemetry. |
| **6** | **Capacity Overflow Bypass** | Background recharge keeps adding Mana beyond the capacity ceiling without player purchasing Mana with Coins. | **HIGH** | **Recharge Invariant Check:** `RECHARGE_TICK` events cannot increase balance beyond `capacity_limit(L_C)`. If pre-recharge balance $\ge$ capacity, recharge delta is strictly 0. |
| **7** | **Out-of-Order Delivery** | Authoritative S2S webhook from Google/Apple arrives at the backend before the client callback finishes. | **LOW-MED** | **State Resilience:** The backend accepts out-of-order events. If the webhook arrives first, the purchase settles immediately. The late client callback is logged for secondary reconciliation. |

---

## 3. Data Validation & Expectation Rules (Plain English Statements)

These rules are formulated in plain English logic, structured to align directly with dbt tests or Great Expectations assertions:

### A. Balance Invariance & Data Type Rules
1. **Rule 1.1 (Non-Negative Balance Invariant):**  
   *"For every user and every currency type (MANA and COIN), the cumulative running balance ($\sum \text{amount}$) must never fall below zero (< 0) across all settled events at any chronological point in time."*
2. **Rule 1.2 (Atomic Integer Requirement for Mana):**  
   *"MANA is an atomic, indivisible token. The amount column for MANA transactions must always be an integer without fractional decimals (`MOD(amount, 1) = 0`)."*
3. **Rule 1.3 (Signed Delta Consistency):**  
   *"Consumption events (such as `ACTION_SPEND`, `UPGRADE_CAPACITY`, `UPGRADE_SPEED`, `BUY_BOOST`) must always have a negative amount (< 0). Source/grant events (such as `OCCASIONAL_GIFT`, `IAP_PURCHASE`) must always have a positive amount (> 0)."*

### B. Payment Reconciliation & Anti-Fraud Rules
4. **Rule 2.1 (Strict Idempotency on External Transactions):**  
   *"For any valid `external_transaction_id` issued by the Payment Gateway, there must be exactly one settled credit event (`amount > 0` with `status = 'SETTLED'`). Any count greater than 1 represents a critical duplicate balance breach."*
5. **Rule 2.2 (Untrusted Client Zero-Credit Invariant):**  
   *"Any transaction record originating from `CLIENT_CALLBACK` must carry an amount of 0 and be assigned a verification status of `PENDING_VERIFICATION`."*
6. **Rule 2.3 (Reconciliation SLA Timeout):**  
   *"Any transaction remaining in `PENDING_VERIFICATION` for longer than 15 minutes without an incoming PG webhook must be audited by the Recon Cron Job to transition into either `SETTLED` (if confirmed by gateway) or `REJECTED` (if fraudulent or abandoned)."*

### C. Mathematical Consistency & Inflation Rules
7. **Rule 3.1 (Mathematical Strictness for Action Cost):**  
   *"For every `ACTION_SPEND` transaction, the absolute value of Mana deducted (`abs(amount)`) must exactly equal the formula: $\text{round}(3 \times \text{user\_level}^{1.1})$."*
8. **Rule 3.2 (Capacity Upgrade Cost Assertion):**  
   *"For every `UPGRADE_CAPACITY` transaction to target level $L_C$, the Coins deducted must equal exactly: $3 \times L_C^{2.2}$."*
9. **Rule 3.3 (Speed Upgrade Cost Assertion):**  
   *"For every `UPGRADE_SPEED` transaction to target level $L_{CS}$, the Coins deducted must equal exactly: $3 \times L_{CS}^{1.1}$."*
10. **Rule 3.4 (Auto-Recharge Capacity Ceiling):**  
    *"A `RECHARGE_TICK` event must never cause the Mana balance to exceed $(3 \times L_C^{1.1}) \times 30$. If balance prior to recharge is $\ge$ capacity, the recharge delta must be 0."*

---

## 4. Anomaly Detection & Fraud Heuristics

Beyond deterministic record validation, three analytical heuristics monitor ongoing operational risks:

```
                               ┌────────────────────────┐
                               │ TRANSACTION AUDIT SUITE│
                               └───────────┬────────────┘
                                           │
         ┌─────────────────────────────────┼─────────────────────────────────┐
         │                                 │                                 │
         ▼                                 ▼                                 ▼
┌──────────────────┐             ┌──────────────────┐             ┌──────────────────┐
│  VELOCITY CHECK  │             │ GHOST DETECTOR   │             │ LEVEL DRIFT      │
│ Hourly spend >   │             │ Rejected claim   │             │ Level surge      │
│ theoretical max  │             │ ratio > 5%       │             │ without actions  │
└──────────────────┘             └──────────────────┘             └──────────────────┘
```

1. **Physical Velocity Limit (Speedhack Detection):**
   * *Logic:* Without active boosts, a player can regenerate at most $(3 \times L_{CS}^{1.1}) \times 1.5$ Mana per hour.
   * *Threshold:* If a player's hourly Mana spend exceeds $(\text{Starting Capacity} + \text{Max Hourly Regen} + \text{Mana Bought via Coins})$, the account is flagged for speedhack or memory injection investigation.
2. **Ghost Claim Ratio (Exploiter Fingerprinting):**
   * *Logic:* Legitimate players maintain a payment success rate $> 95\%$.
   * *Threshold:* If a `user_id` records more than 3 consecutive `CLIENT_CALLBACK` claims that result in `REJECTED` status within 24 hours, in-app checkout is temporarily gated for risk review.
3. **Impossible Progression Leap:**
   * *Logic:* Advancing from level $L$ to $L+1$ requires completing a deterministic volume of in-game actions.
   * *Threshold:* Any ledger entry reflecting an increased `user_level` without corresponding historical `ACTION_SPEND` transactions triggers an immediate account suspension.

---

## 5. Architectural Enforcement Summary

These validations operate across two complementary layers:
1. **Application & Database Layer (In-Line Protection):** Unique constraints, foreign keys, and atomic transactions within the backend services.
2. **Analytics & Warehouse Layer (Continuous Audit):** Hourly and daily automated SQL checks (provided in `validation_queries.sql`) that proactively catch data anomalies before they impact financial reporting.
