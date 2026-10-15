-- 01_deidentify.sql
-- A de-identified view of patients. Every later query uses this view, never the raw table.
-- Dropped: SSN, DRIVERS, PASSPORT, names (PREFIX/FIRST/MIDDLE/LAST/SUFFIX/MAIDEN),
-- ADDRESS, ZIP, LAT/LON, BIRTHPLACE, INCOME. Kept only what the analysis needs.

CREATE OR REPLACE VIEW patients_deid AS
SELECT
    Id,
    BIRTHDATE,
    DEATHDATE,
    GENDER,
    RACE,
    ETHNICITY,
    COUNTY
FROM patients;
