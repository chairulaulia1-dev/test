-- =============================================================================
-- MANA & COINS MODEL - PRODUCT, FINANCIAL & ECONOMY METRICS QUERIES
-- Senior Data Analyst Test - Task 3 Deliverable
-- Dialect: ANSI SQL / PostgreSQL / Google BigQuery / SQLite Compatible
-- =============================================================================


-- -----------------------------------------------------------------------------
-- METRIC 1: Financial & Monetization Overview (Gross/Net Revenue, ARPPU, CR)
-- Business Goal: Executive performance summary of purchasing players and revenue.
-- -----------------------------------------------------------------------------
WITH user_activity AS (
    SELECT
        COUNT(DISTINCT user_id) AS total_active_users
    FROM fact_transactions
),
payer_activity AS (
    SELECT
        COUNT(DISTINCT user_id) AS unique_paying_users,
        COUNT(DISTINCT external_transaction_id) AS total_paid_orders,
        SUM(amount) AS gross_revenue_usd
    FROM fact_transactions
    WHERE currency = 'FIAT_USD'
      AND status = 'SETTLED'
)
SELECT
    pa.gross_revenue_usd,
    ROUND(pa.gross_revenue_usd * 0.70, 2) AS net_revenue_usd_after_store_cut,
    ua.total_active_users,
    pa.unique_paying_users,
    ROUND((CAST(pa.unique_paying_users AS REAL) / ua.total_active_users) * 100.0, 2) AS payer_conversion_rate_pct,
    ROUND(pa.gross_revenue_usd / pa.unique_paying_users, 2) AS arppu_usd,
    ROUND(pa.gross_revenue_usd / ua.total_active_users, 2) AS arpu_usd
FROM payer_activity pa
CROSS JOIN user_activity ua;


-- -----------------------------------------------------------------------------
-- METRIC 2: Economy Health - Currency Sink-to-Source Ratio (MANA & COINS)
-- Business Goal: Detect inflation or deflation. Healthy range: 0.90 - 1.05.
-- -----------------------------------------------------------------------------
WITH currency_flows AS (
    SELECT
        currency,
        -- Sources: amount > 0
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS total_sources_ingested,
        -- Sinks: amount < 0 (take absolute value)
        SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END) AS total_sinks_consumed
    FROM fact_transactions
    WHERE currency IN ('MANA', 'COIN')
      AND status = 'SETTLED'
    GROUP BY currency
)
SELECT
    currency,
    total_sources_ingested,
    total_sinks_consumed,
    ROUND(CAST(total_sinks_consumed AS REAL) / NULLIF(total_sources_ingested, 0), 3) AS sink_to_source_ratio,
    CASE
        WHEN CAST(total_sinks_consumed AS REAL) / NULLIF(total_sources_ingested, 0) < 0.80 THEN 'DEFLATION / HOARDING (Too generous)'
        WHEN CAST(total_sinks_consumed AS REAL) / NULLIF(total_sources_ingested, 0) > 1.10 THEN 'STARVATION (Too scarce)'
        ELSE 'BALANCED / HEALTHY'
    END AS economy_health_status
FROM currency_flows;


-- -----------------------------------------------------------------------------
-- METRIC 3: Coin Sinks Allocation Share (Where do players spend Coins?)
-- Business Goal: Understand what features players prioritize (Capacity, Speed, Boost, Mana).
-- -----------------------------------------------------------------------------
WITH coin_sinks AS (
    SELECT
        event_type,
        SUM(ABS(amount)) AS coins_spent
    FROM fact_transactions
    WHERE currency = 'COIN'
      AND amount < 0
      AND status = 'SETTLED'
    GROUP BY event_type
),
total_spent AS (
    SELECT SUM(coins_spent) AS total_coins_spent FROM coin_sinks
)
SELECT
    cs.event_type,
    cs.coins_spent,
    ROUND((CAST(cs.coins_spent AS REAL) / ts.total_coins_spent) * 100.0, 2) AS share_pct
FROM coin_sinks cs
CROSS JOIN total_spent ts
ORDER BY cs.coins_spent DESC;


-- -----------------------------------------------------------------------------
-- METRIC 4: Effective Realized CPD (Coins Per Dollar) vs Volume
-- Business Goal: Verify if dynamic pricing correctly scales with player levels.
-- -----------------------------------------------------------------------------
SELECT
    user_level,
    SUM(CASE WHEN currency = 'COIN' AND amount > 0 THEN amount ELSE 0 END) AS coins_granted,
    SUM(CASE WHEN currency = 'FIAT_USD' THEN amount ELSE 0 END) AS usd_paid,
    ROUND(
        SUM(CASE WHEN currency = 'COIN' AND amount > 0 THEN amount ELSE 0 END) /
        NULLIF(SUM(CASE WHEN currency = 'FIAT_USD' THEN amount ELSE 0 END), 0),
        2
    ) AS realized_cpd
FROM fact_transactions
WHERE event_type IN ('IAP_PURCHASE', 'IAP_REVENUE')
  AND status = 'SETTLED'
  GROUP BY user_level;


-- -----------------------------------------------------------------------------
-- METRIC 5: Fraud & Security Health - Ghost Claim Attempt Rate
-- Business Goal: Monitor the percentage of fake/hacked payment callbacks.
-- -----------------------------------------------------------------------------
SELECT
    COUNT(DISTINCT c.external_transaction_id) AS total_orders_claimed,
    COUNT(DISTINCT CASE WHEN r.status = 'REJECTED' THEN c.external_transaction_id END) AS ghost_attempts_detected,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN r.status = 'REJECTED' THEN c.external_transaction_id END) AS REAL) /
        COUNT(DISTINCT c.external_transaction_id)) * 100.0,
        1
    ) AS ghost_claim_rate_pct
FROM fact_transactions c
LEFT JOIN fact_transactions r
    ON c.external_transaction_id = r.external_transaction_id AND r.status = 'REJECTED'
WHERE c.source_system = 'CLIENT_CALLBACK' AND c.external_transaction_id IS NOT NULL;
