-- 00_load.sql
-- Load the Synthea CSVs from all 10 runs (seeds 42-51) into DuckDB tables.
-- The * in each path reads every run's file and stacks them into one table.
-- read_csv_auto guesses each column's type (dates, numbers), so no manual schema is needed.
-- Patient-level tables differ in every run, so they are simply stacked.
-- Hospitals and insurers are the same list in every run, so SELECT DISTINCT keeps one copy
-- (only the descriptive columns, because the yearly revenue columns differ by run).

CREATE OR REPLACE TABLE patients AS
SELECT * FROM read_csv_auto('output/seed_*/csv/patients.csv', union_by_name = true);

CREATE OR REPLACE TABLE encounters AS
SELECT * FROM read_csv_auto('output/seed_*/csv/encounters.csv', union_by_name = true);

CREATE OR REPLACE TABLE conditions AS
SELECT * FROM read_csv_auto('output/seed_*/csv/conditions.csv', union_by_name = true);

CREATE OR REPLACE TABLE observations AS
SELECT * FROM read_csv_auto('output/seed_*/csv/observations.csv', union_by_name = true);

CREATE OR REPLACE TABLE procedures AS
SELECT * FROM read_csv_auto('output/seed_*/csv/procedures.csv', union_by_name = true);

CREATE OR REPLACE TABLE medications AS
SELECT * FROM read_csv_auto('output/seed_*/csv/medications.csv', union_by_name = true);

CREATE OR REPLACE TABLE careplans AS
SELECT * FROM read_csv_auto('output/seed_*/csv/careplans.csv', union_by_name = true);

CREATE OR REPLACE TABLE organizations AS
SELECT DISTINCT
    Id,
    NAME,
    ADDRESS,
    CITY,
    STATE,
    ZIP
FROM read_csv_auto('output/seed_*/csv/organizations.csv', union_by_name = true);

CREATE OR REPLACE TABLE payers AS
SELECT DISTINCT
    Id,
    NAME,
    OWNERSHIP
FROM read_csv_auto('output/seed_*/csv/payers.csv', union_by_name = true);

-- Real CMS file: every ACO's 2024 results. all_varchar keeps CMS's "-" placeholders
-- from breaking the load; numbers are converted with TRY_CAST where they are used.
CREATE OR REPLACE TABLE aco_results AS
SELECT * FROM read_csv_auto('external/aco_py2024_results.csv', all_varchar = true);
