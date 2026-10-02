-- =============================================================================
-- MANA & COINS MODEL - DATA VALIDATION & AUDIT SUITE
-- Senior Data Analyst Test - Task 2 (Validation Queries & Anomaly Checks)
-- Dialect: ANSI SQL / PostgreSQL / Google BigQuery Compatible
-- =============================================================================


-- -----------------------------------------------------------------------------
-- CHECK 1: Negative Balance Invariant Audit
-- Goal: Verify that no user ever has a negative running balance at any timestamp.
-- Severity: CRITICAL (Indicates race condition, unvalidated spend, or double spend)
-- -----------------------------------------------------------------------------
WITH running_balances AS (
    SELECT
        transaction_id,
        user_id,
        currency_type,
        timestamp,
        amount,
        verification_status,
        SUM(CASE WHEN verification_status = 'SETTLED' THEN amount ELSE 0 END) OVER (
            PARTITION BY user_id, currency_type
            ORDER BY timestamp ASC, transaction_id ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS current_running_balance
    FROM ledger_transactions
    WHERE currency_type IN ('MANA', 'COIN')
)
SELECT
    transaction_id,
    user_id,
    currency_type,
    timestamp,
    amount,
    current_running_balance,
    'CRITICAL: Running balance dropped below zero!' AS audit_alert
FROM running_balances
WHERE current_running_balance < 0;


-- -----------------------------------------------------------------------------
-- CHECK 2: Strict Payment Idempotency & Duplicate Credit Check
-- Goal: Ensure exactly 1 settled credit event per external transaction ID.
-- Severity: CRITICAL (Indicates financial loss due to duplicate coin grants)
-- -----------------------------------------------------------------------------
SELECT
    external_txn_id,
    COUNT(*) AS total_settled_credit_events,
    SUM(amount) AS total_coins_granted,
    STRING_AGG(transaction_id, ', ') AS duplicate_txn_ids,
    'CRITICAL: Duplicate coin credit detected for single external order!' AS audit_alert
FROM ledger_transactions
WHERE currency_type = 'COIN'
  AND amount > 0
  AND verification_status = 'SETTLED'
  AND external_txn_id IS NOT NULL
GROUP BY external_txn_id
HAVING COUNT(*) > 1;


-- -----------------------------------------------------------------------------
-- CHECK 3: Mathematical Formula Drift Audit (Action Spend: m_a = round(3 * L^1.1))
-- Goal: Ensure every action deduction matches the mathematical specification.
-- Severity: HIGH (Indicates client bug, outdated app version, or client tampering)
-- -----------------------------------------------------------------------------
WITH action_formula_check AS (
    SELECT
        transaction_id,
        user_id,
        timestamp,
        user_level,
        amount AS actual_mana_deducted,
        -- Formula: round(3 * (user_level ^ 1.1))
        ROUND(3.0 * POWER(user_level, 1.1)) AS expected_mana_cost
    FROM ledger_transactions
    WHERE event_type = 'ACTION_SPEND'
      AND currency_type = 'MANA'
      AND verification_status = 'SETTLED'
)
SELECT
    transaction_id,
    user_id,
    timestamp,
    user_level,
    actual_mana_deducted,
    -expected_mana_cost AS expected_signed_amount,
    ABS(actual_mana_deducted - (-expected_mana_cost)) AS delta_discrepancy,
    'HIGH: Action mana cost does not match formula 3 * L^1.1' AS audit_alert
FROM action_formula_check
WHERE actual_mana_deducted != -expected_mana_cost;


-- -----------------------------------------------------------------------------
-- CHECK 4: Untrusted Client Claim Zero-Credit Invariant
-- Goal: Ensure no direct coin additions were granted directly from client-side claims.
-- Severity: CRITICAL (Indicates bypassed zero-trust architecture / fake payment hack)
-- -----------------------------------------------------------------------------
SELECT
    transaction_id,
    user_id,
    timestamp,
    source,
    amount,
    verification_status,
    'CRITICAL: Untrusted client source directly modified currency balance!' AS audit_alert
FROM ledger_transactions
WHERE source = 'CLIENT_CALLBACK'
  AND (amount != 0 OR verification_status = 'SETTLED');


-- -----------------------------------------------------------------------------
-- CHECK 5: Reconciliation SLA Breach & Ghost Claim Detector
-- Goal: Identify pending client claims that were never reconciled within 15 minutes.
-- Severity: MEDIUM (Indicates delayed webhook, network drop, or hacker probe)
-- -----------------------------------------------------------------------------
SELECT
    transaction_id,
    user_id,
    external_txn_id,
    timestamp AS claim_timestamp,
    NOW() - timestamp AS elapsed_time,
    verification_status,
    'WARNING: Transaction stuck in PENDING_VERIFICATION beyond 15-minute SLA' AS audit_alert
FROM ledger_transactions
WHERE verification_status = 'PENDING_VERIFICATION'
  AND timestamp < (NOW() - INTERVAL '15 minutes');


-- -----------------------------------------------------------------------------
-- CHECK 6: Capacity Upgrade Cost Assertion (Cost: 3 * L_C^2.2)
-- Goal: Verify that coin cost deducted for capacity upgrade strictly matches formula.
-- Severity: HIGH (Prevents unauthorized discount or exploit)
-- -----------------------------------------------------------------------------
SELECT
    transaction_id,
    user_id,
    capacity_level,
    amount AS actual_coins_deducted,
    -ROUND(3.0 * POWER(capacity_level, 2.2)) AS expected_coins_cost,
    'HIGH: Capacity upgrade cost mismatch' AS audit_alert
FROM ledger_transactions
WHERE event_type = 'UPGRADE_CAPACITY'
  AND currency_type = 'COIN'
  AND verification_status = 'SETTLED'
  AND amount != -ROUND(3.0 * POWER(capacity_level, 2.2));


-- -----------------------------------------------------------------------------
-- CHECK 7: Speedhack & Impossible Velocity Anomaly
-- Goal: Detect users whose mana consumption exceeds physical regeneration limits.
-- Severity: HIGH (Identifies memory injection or client clock bypass)
-- -----------------------------------------------------------------------------
WITH hourly_spending AS (
    SELECT
        user_id,
        DATE_TRUNC('hour', timestamp) AS tx_hour,
        MAX(capacity_level) AS cap_level,
        MAX(speed_level) AS spd_level,
        -- Total mana spent in the hour (absolute value)
        SUM(CASE WHEN event_type = 'ACTION_SPEND' THEN ABS(amount) ELSE 0 END) AS total_mana_spent,
        -- Max possible mana = capacity limit + (speed * 1.5 * 2x boost margin)
        ROUND(MAX((3.0 * POWER(capacity_level, 1.1)) * 30.0) + 
              MAX((3.0 * POWER(speed_level, 1.1)) * 1.5 * 2.0)) AS theoretical_max_mana_possible
    FROM ledger_transactions
    WHERE currency_type = 'MANA'
    GROUP BY user_id, DATE_TRUNC('hour', timestamp)
)
SELECT
    user_id,
    tx_hour,
    total_mana_spent,
    theoretical_max_mana_possible,
    total_mana_spent - theoretical_max_mana_possible AS excess_mana_consumed,
    'FLAG: User mana consumption exceeds theoretical physical regeneration limit!' AS audit_alert
FROM hourly_spending
WHERE total_mana_spent > theoretical_max_mana_possible;
