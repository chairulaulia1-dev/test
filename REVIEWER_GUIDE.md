# Reviewer Guide: Mana & Coins Model Assessment
### *Candidate Submission: Senior Data Analyst*

---

## 1. Welcome & Executive Overview

Thank you for reviewing this technical assessment for the **Senior Data Analyst** role.

This project delivers an end-to-end data analytics, modeling, and validation architecture for a mobile gaming economy featuring a dual-currency engine (**Mana & Coins**), exponential inflation curves, a zero-trust distributed payment gateway, and a strictly **Write-Only / Append-Only** transactions database.

### Core Architectural Tenets:
1. **Event-Sourced Append-Only Ledger:** All balance mutations are recorded immutably as signed deltas (`amount` $+/-$) within a unified table (`ledger_transactions`) differentiated by `currency_type`.
2. **Zero-Trust Payment Triangulation:** Client applications are treated as untrusted. Coin balances are credited **strictly once** (*idempotent verification*) only upon receipt of authoritative server-to-server (S2S) webhook events from Apple/Google.
3. **Mathematically Rigorous Scaling & Precedence:** Exponentiation strictly binds to level variables ($L, L_C, L_{CS}$) before multiplication by the base coefficient ($3$), guaranteeing exact baseline alignment ($3 \times 1^{1.1} = 3$).
4. **Zero-Setup Interactive Review Experience:** Complete one-click end-to-end execution available in the master Jupyter Notebook (`Mana_and_Coins_Executive_Analysis.ipynb`) and modular task notebooks, with zero database installation or cloud billing required!

---

## 2. Mathematical Precedence Statement

> ### 📌 **Formula Operator Precedence Clarification**
> In accordance with standard algebraic operator precedence (PEMDAS / BODMAS), exponentiation binds **strictly and directly to the level variables** ($L, L_C, L_{CS}$) before multiplication by the base coefficient ($3$):
>
> $$\text{Action Cost} = 3 \times L^c \equiv 3 \cdot (L^c)$$
>
> **Rationale:**  
> The prompt explicitly specifies that the initial action cost at Level 1 is **3 Mana**.  
> If the exponent were applied to the coefficient as $(3 \times L)^c$, then at Level 1 the cost would evaluate to $3^{1.1} \approx 3.35$, violating the initial baseline condition. Applying the exponent solely to $L$ guarantees that at $L=1$, $3 \times 1^{1.1} = 3.0$ exactly.
>
> The same strict precedence applies across all game formulas:
> - **Action Mana Cost ($m_a$):** $m_a = \text{round}(3 \times L^{1.1})$
> - **Charging Speed Mana/Hour:** $(3 \times L_{CS}^{1.1}) \times 1.5$
> - **Speed Upgrade Cost (Coins):** $3 \times L_{CS}^{1.1}$
> - **Mana Capacity Limit:** $(3 \times L_C^{1.1}) \times 30$
> - **Capacity Upgrade Cost (Coins):** $3 \times L_C^{2c} = 3 \times L_C^{2.2}$
> - **Coins Per Dollar (CPD):** $\text{CPD} = 4.32 \times m_a$
> - **Coins Awarded for Fiat Item:** $\text{USD Price} \times \text{CPD}$

---

## 3. Repository Directory Structure

The repository is organized into three modular release folders plus a unified master notebook in the root:

```
data_analyst_test/
├── README.md                                 <-- Original problem statement
├── REVIEWER_GUIDE.md                         <-- This executive reviewer guide
├── requirements.txt                          <-- Environment dependencies (pandas, ipykernel)
│
├── 📓 Mana_and_Coins_Executive_Analysis.ipynb <-- [RECOMMENDED] Master 1-Click End-to-End Notebook
│
├── release1_data_modeling/                   <-- MILESTONE 1 (TASK 1: DATA MODELING)
│   ├── schema_design.md                      <-- DDL Architecture, Data Dictionary & Scenario Mapping
│   ├── task1_data_modeling.ipynb             <-- Standalone Task 1 Interactive Notebook
│   ├── transactions_sample.csv               <-- Unified single-ledger sample dataset (18 rows)
│   ├── dim_shop_item.csv                     <-- Store bundles & item pricing dimension
│   ├── dim_user.csv                          <-- Player balance & progression snapshot dimension
│   └── dim_game_level.csv                    <-- Game level progression & economy lookup matrix
│
├── release2_data_validation/                 <-- MILESTONE 2 (TASK 2: DATA VALIDATION & ANTI-CHEAT)
│   ├── validation_rules.md                   <-- Threat Modeling (7 failure modes) & 10 Plain English rules
│   ├── validation_queries.sql                <-- 7 Production SQL audit queries (Window funcs & CTEs)
│   └── task2_data_validation.ipynb           <-- Standalone Task 2 In-Memory SQL Audit Notebook
│
└── release3_product_metrics/                 <-- MILESTONE 3 (TASK 3: PRODUCT & FINANCIAL ANALYTICS)
    ├── metrics_framework.md                  <-- 4-Pillar Taxonomy, Business Playbook & Stakeholder Strategy
    ├── metrics_calculation_queries.sql       <-- Analytical SQL queries for financial & economy KPIs
    └── task3_product_metrics.ipynb           <-- Standalone Task 3 Executive Scorecard Notebook
```

---

## 4. How to Review & Execute (1-Click Workflow)

Reviewers have two convenient ways to inspect and run the analysis:

### Method 1: The Unified Master Notebook (Recommended)
Open **[`Mana_and_Coins_Executive_Analysis.ipynb`](file:///c:/Users/Chairul%20Aulia/.gemini/antigravity-ide/scratch/data_analyst_test/Mana_and_Coins_Executive_Analysis.ipynb)** in VS Code or upload it to [Google Colab](https://colab.research.google.com/):
1. Click **Run All**.
2. The notebook executes Part 1 (generating curves, ledger, and CSVs), Part 2 (running all 7 in-memory SQL audits with 100% PASS), and Part 3 (rendering all financial and economic scorecards).
3. Requires zero manual file copying, downloading, or external database setup!

### Method 2: Modular Per-Task Inspection
If evaluating by milestone:
* **Task 1 Notebook:** [`release1_data_modeling/task1_data_modeling.ipynb`](file:///c:/Users/Chairul%20Aulia/.gemini/antigravity-ide/scratch/data_analyst_test/release1_data_modeling/task1_data_modeling.ipynb)
* **Task 2 Notebook:** [`release2_data_validation/task2_data_validation.ipynb`](file:///c:/Users/Chairul%20Aulia/.gemini/antigravity-ide/scratch/data_analyst_test/release2_data_validation/task2_data_validation.ipynb)
* **Task 3 Notebook:** [`release3_product_metrics/task3_product_metrics.ipynb`](file:///c:/Users/Chairul%20Aulia/.gemini/antigravity-ide/scratch/data_analyst_test/release3_product_metrics/task3_product_metrics.ipynb)

---

## 5. Milestone Highlights & Key Decisions

### Milestone 1 (Task 1: Data Modeling & Ledger Design)
* **Unified Single Table:** DDL designed with `transaction_id`, `user_id`, `timestamp` (server UTC), `currency_type` (`MANA`, `COIN`, `FIAT_USD`), `amount` (signed delta), `event_type`, `user_level`, `capacity_level`, `speed_level`, `source`, `verification_status`, `external_txn_id`, `idempotency_key`, and `metadata_json`.
* **Idempotent Triangulation:** A \$4.99 purchase emits 3 distinct records (Client callback $\to$ S2S Webhook $\to$ Cron Recon), demonstrating how duplicate credit events are prevented.

### Milestone 2 (Task 2: Data Validation & Risk Hardening)
* **Threat Modeling Matrix:** Details 7 failure modes: *Clock Spoofing*, *Ghost Purchases*, *Replay Attacks*, *Race Conditions*, *Formula Drift*, *Capacity Overflow*, and *Out-of-Order Delivery*.
* **7 Production SQL Audits:** Executed in-memory via SQLite with zero violations (100% PASS) across running balances, idempotency, mathematical formula strictness, and fake purchase isolation.

### Milestone 3 (Task 3: Product, Financial & Game Economy Analytics)
* **4-Pillar Taxonomy:** Financial Health (Gross/Net Revenue, ARPPU, Conversion Rate), Economy Balancing (Sink/Source ratio), Progression Dynamics (Friction index), and Security Integrity (Ghost claim detection).
* **Success/Failure Evaluation:** Differentiates leading indicators (Sink/Source ratio, Mana wastage) from lagging metrics (Gross Revenue, 30-day retention).
* **Actionable Playbook:** Specific corrective interventions for real-world economy anomalies.

---

## 6. Git Branching & PR Strategy

When pushing to a remote repository (e.g., GitHub or GitLab), the submission is structured to follow the requested milestone pull request workflow:

```bash
# 1. Main Branch Baseline
git checkout -b main
git add README.md REVIEWER_GUIDE.md requirements.txt .gitignore Mana_and_Coins_Executive_Analysis.ipynb
git commit -m "docs: initialize repository with executive master notebook and reviewer guide"

# 2. PR Chunk 1: Data Modeling & Ledger (Task 1)
git checkout -b release1_data_modeling
git add release1_data_modeling/
git commit -m "feat(data-modeling): implement ledger schema, task 1 notebook, and sample transactions"
# [Squash merge release1 into release2]

# 3. PR Chunk 2: Data Validation & Anti-Cheat (Task 2)
git checkout -b release2_data_validation
git add release2_data_validation/
git commit -m "feat(validation): implement threat modeling, task 2 notebook, and SQL audit suite"
# [Squash merge release2 into release3]

# 4. PR Chunk 3: Product & Financial Metrics (Task 3)
git checkout -b release3_product_metrics
git add release3_product_metrics/
git commit -m "feat(analytics): implement 4-pillar metrics framework and task 3 executive scorecard notebook"
# [Final merge release3 into main]
```

---

## 7. Conclusion

Every notebook and specification in this repository is designed to showcase the competencies of a **Senior Data Analyst**—combining technical rigor in data architecture, SQL, and Python with strategic product acumen, mathematical precision, and an intuitive review experience.

*Thank you for your time and consideration!*
