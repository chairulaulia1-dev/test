# Release 1: Data Modeling & Ledger Schema Specification
### *Senior Data Analyst Deliverable - Task 1*

---

## 1. Overview & Architectural Principles

To fulfill the requirements of a high-volume, cheat-sensitive gaming economy with an immutable, append-only constraint, the data architecture adopts an **Event-Sourced Append-Only Ledger**:

1. **Zero Mutations (Immutable):** No `UPDATE` or `DELETE` operations are ever executed on transaction records. Every economic event is written as a signed delta (`amount`: positive for incoming credits, negative for debits).
2. **Unified Single Ledger Table:** All currency movements (`MANA`, `COIN`, and `FIAT_USD`) reside in a single table differentiated by the `currency_type` column.
3. **Idempotency & Deduplication First:** Payment triangulation across 3 sources (*Client Callback*, *PG Webhook*, and *Cron Recon Job*) guarantees zero balance duplication using `idempotency_key` and `external_txn_id`.
4. **Server-Authoritative Timestamps:** Event timestamps rely strictly on server time (`TIMESTAMPTZ`), never local client device time, preventing clock tampering (*time travel hacks*).

---

## 2. Core Ledger Schema: `ledger_transactions`

### Data Definition Language (DDL)

```sql
CREATE TABLE ledger_transactions (
    transaction_id          VARCHAR(64) PRIMARY KEY,
    user_id                 VARCHAR(64) NOT NULL,
    timestamp               TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    currency_type           VARCHAR(16) NOT NULL,          -- 'MANA', 'COIN', 'FIAT_USD'
    amount                  NUMERIC(14, 2) NOT NULL,       -- Signed delta (+ for credit, - for debit)
    event_type              VARCHAR(32) NOT NULL,          -- 'ACTION_SPEND', 'RECHARGE_TICK', 'IAP_PURCHASE', etc.
    user_level              INTEGER NOT NULL,              -- Player Level (L) at event
    capacity_level          INTEGER NOT NULL,              -- Capacity Level (L_C) at event
    speed_level             INTEGER NOT NULL,              -- Speed Level (L_CS) at event
    source                  VARCHAR(32) NOT NULL,          -- 'GAME_ENGINE', 'CLIENT_CALLBACK', 'PG_WEBHOOK', 'RECON_JOB'
    verification_status     VARCHAR(32) NOT NULL,          -- 'SETTLED', 'PENDING_VERIFICATION', 'DUPLICATE_IGNORED', 'REJECTED'
    external_txn_id         VARCHAR(128),                  -- Order ID from Apple/Google (e.g. 'GPA.3391-4820-9912')
    idempotency_key         VARCHAR(128) NOT NULL UNIQUE,  -- Unique key to prevent double processing
    metadata_json           JSONB                          -- Contextual parameters (SKU, formulas, balances)
);

-- Indexing for high-performance balance aggregation and audit lookups
CREATE INDEX idx_ledger_user_currency ON ledger_transactions (user_id, currency_type, timestamp);
CREATE INDEX idx_ledger_external_txn ON ledger_transactions (external_txn_id) WHERE external_txn_id IS NOT NULL;
CREATE INDEX idx_ledger_recon ON ledger_transactions (source, verification_status, timestamp);
```

### Data Dictionary

| Column | Data Type | Nullable | Description & Business Rules |
| :--- | :--- | :--- | :--- |
| `transaction_id` | VARCHAR(64) | NO | Unique immutable transaction identifier (*Primary Key*). |
| `user_id` | VARCHAR(64) | NO | Unique player identifier (e.g. `usr_alex_01`). |
| `timestamp` | TIMESTAMPTZ | NO | Authoritative server timestamp (UTC). |
| `currency_type` | VARCHAR(16) | NO | Denominated currency: `MANA`, `COIN`, or `FIAT_USD`. |
| `amount` | NUMERIC(14,2)| NO | Signed change in balance. Positive for additions, negative for deductions. Zero for audit/unverified claims. |
| `event_type` | VARCHAR(32) | NO | Business action classification (see Section 3). |
| `user_level` | INTEGER | NO | Player level ($L$) at the moment of the event. Used to enforce inflation cost validity. |
| `capacity_level` | INTEGER | NO | Mana Capacity level ($L_C$) at the event. |
| `speed_level` | INTEGER | NO | Charging speed level ($L_{CS}$) at the event. |
| `source` | VARCHAR(32) | NO | Origin of the record: `GAME_ENGINE`, `CLIENT_CALLBACK`, `PG_WEBHOOK`, or `RECON_JOB`. |
| `verification_status`| VARCHAR(32)| NO | State integrity: `SETTLED` (balance effective), `PENDING_VERIFICATION`, `DUPLICATE_IGNORED`, `REJECTED`. |
| `external_txn_id` | VARCHAR(128)| YES | Payment Gateway order identifier (Apple App Store / Google Play). |
| `idempotency_key` | VARCHAR(128)| NO | Unique deduplication key. Duplicate inserts are blocked by database constraints. |
| `metadata_json` | JSONB | YES | Contextual attributes (SKU ID, calculated formulas, active booster multipliers, audit notes). |

---

## 3. Business Scenario to Ledger Mapping

The table below illustrates how in-game operations map directly into rows in `ledger_transactions`:

| Business Scenario | `currency_type` | `amount` | `event_type` | `source` | `verification_status` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Player Action at Level 1** | `MANA` | `-3` | `ACTION_SPEND` | `GAME_ENGINE` | `SETTLED` |
| **Player Action at Level 5** | `MANA` | `-18` | `ACTION_SPEND` | `GAME_ENGINE` | `SETTLED` |
| **Auto-Recharge Tick** | `MANA` | `+6` | `RECHARGE_TICK` | `GAME_ENGINE` | `SETTLED` |
| **Client Reports $4.99 Purchase** | `COIN` | `0` | `IAP_PURCHASE_CLAIM` | `CLIENT_CALLBACK` | `PENDING_VERIFICATION` |
| **Apple/Google Webhook Received** | `COIN` | `+388` | `IAP_PURCHASE` | `PG_WEBHOOK` | `SETTLED` |
| **Fiat Revenue Booked** | `FIAT_USD` | `+4.99`| `IAP_REVENUE` | `PG_WEBHOOK` | `SETTLED` |
| **Cron Recon Audit (Duplicate)** | `COIN` | `0` | `RECONCILIATION_AUDIT`| `RECON_JOB` | `DUPLICATE_IGNORED` |
| **Upgrade Capacity to Level 2** | `COIN` | `-14` | `UPGRADE_CAPACITY` | `GAME_ENGINE` | `SETTLED` |
| **Upgrade Speed to Level 2** | `COIN` | `-6` | `UPGRADE_SPEED` | `GAME_ENGINE` | `SETTLED` |
| **Buy 2x Speed Boost (5 Min)** | `COIN` | `-20` | `BUY_BOOST` | `GAME_ENGINE` | `SETTLED` |
| **Convert 30 Coins to 100 Mana** | `COIN` / `MANA`| `-30` / `+100` | `COIN_TO_MANA_EXCHANGE`| `GAME_ENGINE`| `SETTLED` |
| **Malicious Ghost Claim Detected**| `COIN` | `0` | `RECONCILIATION_AUDIT`| `RECON_JOB` | `REJECTED` |

---

## 4. Auxiliary Dimension Tables

To support performant analytics and validation without continually aggregating the high-velocity ledger, three auxiliary tables are maintained:

### A. `dim_iap_catalog` (In-App Purchase Bundles)
Stores predefined SKU pricing tiers agreed upon with payment processors:
* `sku_id` (PK): e.g., `coin_drops`, `coin_bag`, `coin_chest`, `coin_barrel`.
* `name`: Display label.
* `usd_price`: Predefined fiat price (\$0.99, \$4.99, \$9.99, \$19.99).

### B. `dim_user_state` (Player Balance & Level Snapshot)
Maintained as a high-speed read cache for low-latency queries:
* `user_id` (PK).
* `current_level`, `mana_capacity_level`, `charging_speed_level`.
* `mana_balance`: Running aggregate of settled Mana.
* `coins_balance`: Running aggregate of settled Coins.
* `total_usd_spent`: Cumulative lifetime fiat spend (LTV).

### C. `dim_level_economy_curve` (Inflation Matrix)
Reference lookup table for engineering and economy designers across Levels 1–100:
* `level` ($L$).
* `action_mana_cost_m_a`: $m_a = \text{round}(3 \times L^{1.1})$.
* `coins_per_dollar_cpd`: $\text{CPD} = 4.32 \times m_a$.
* `capacity_val`: $(3 \times L^{1.1}) \times 30$.
* `capacity_upgrade_cost`: $3 \times L^{2.2}$.
* `speed_mana_per_hour`: $(3 \times L^{1.1}) \times 1.5$.
* `speed_upgrade_cost`: $3 \times L^{1.1}$.

> **Mathematical Precedence & Formula Specification:**  
> Exponentiation binds directly to the level variable ($3 \times L^c \equiv 3 \cdot (L^c)$), guaranteeing that baseline action cost at Level 1 is exactly $3 \times 1^{1.1} = 3$ Mana.

---

## 5. Execution & Verification

The data modeling and sample generation can be executed directly with 1-click in the Jupyter Notebook:
* **Interactive Task 1 Notebook:** [`release1_data_modeling/task1_data_modeling.ipynb`](file:///c:/Users/Chairul%20Aulia/.gemini/antigravity-ide/scratch/data_analyst_test/release1_data_modeling/task1_data_modeling.ipynb)
* **Master Unified Notebook:** [`Mana_and_Coins_Executive_Analysis.ipynb`](file:///c:/Users/Chairul%20Aulia/.gemini/antigravity-ide/scratch/data_analyst_test/Mana_and_Coins_Executive_Analysis.ipynb)

Open the notebook in VS Code or Google Colab and click **Run All**. The generated datasets will automatically write to the directory with zero manual file transfers required.
