#!/usr/bin/env bash
set -euo pipefail

# Populates the countries table from data/countries/country-codes.csv.
# The data/ directory is mounted read-only at /data inside the DB container
# (see docker-compose.yml), so COPY FROM uses the /data container path.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

HOST_CSV="${DATA_DIR}/countries/country-codes.csv"
CONTAINER_CSV="/data/countries/country-codes.csv"

require_file "${HOST_CSV}"

echo "Populating countries..."

docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << SQL
-- Re-run safe: CASCADE drops dependent FK rows so we start clean.
TRUNCATE TABLE countries CASCADE;

-- Temporary table mirroring every column in the source CSV (subset used below).
CREATE TEMP TABLE tmp_countries (
    FIFA                                    TEXT,
    Dial                                    TEXT,
    ISO3166_1_Alpha_3                       TEXT,
    MARC                                    TEXT,
    is_independent                          TEXT,
    ISO3166_1_numeric                       TEXT,
    GAUL                                    TEXT,
    FIPS                                    TEXT,
    WMO                                     TEXT,
    ISO3166_1_Alpha_2                       TEXT,
    ITU                                     TEXT,
    IOC                                     TEXT,
    DS                                      TEXT,
    UNTERM_Spanish_Formal                   TEXT,
    Global_Code                             TEXT,
    Intermediate_Region_Code                TEXT,
    official_name_fr                        TEXT,
    UNTERM_French_Short                     TEXT,
    ISO4217_currency_name                   TEXT,
    UNTERM_Russian_Formal                   TEXT,
    UNTERM_English_Short                    TEXT,
    ISO4217_currency_alphabetic_code        TEXT,
    Small_Island_Developing_States_SIDS     TEXT,
    UNTERM_Spanish_Short                    TEXT,
    ISO4217_currency_numeric_code           TEXT,
    UNTERM_Chinese_Formal                   TEXT,
    UNTERM_French_Formal                    TEXT,
    UNTERM_Russian_Short                    TEXT,
    M49                                     TEXT,
    Sub_region_Code                         TEXT,
    Region_Code                             TEXT,
    official_name_ar                        TEXT,
    ISO4217_currency_minor_unit             TEXT,
    UNTERM_Arabic_Formal                    TEXT,
    UNTERM_Chinese_Short                    TEXT,
    Land_Locked_Developing_Countries_LLDC   TEXT,
    Intermediate_Region_Name                TEXT,
    official_name_es                        TEXT,
    UNTERM_English_Formal                   TEXT,
    official_name_cn                        TEXT,
    official_name_en                        TEXT,
    ISO4217_currency_country_name           TEXT,
    Least_Developed_Countries_LDC           TEXT,
    Region_Name                             TEXT,
    UNTERM_Arabic_Short                     TEXT,
    Sub_region_Name                         TEXT,
    official_name_ru                        TEXT,
    Global_Name                             TEXT,
    Capital                                 TEXT,
    Continent                               TEXT,
    TLD                                     TEXT,
    Languages                               TEXT,
    Geoname_ID                              TEXT,
    CLDR_display_name                       TEXT,
    EDGAR                                   TEXT,
    wikidata_id                             TEXT
);

COPY tmp_countries
FROM '${CONTAINER_CSV}'
DELIMITER ','
CSV HEADER;

INSERT INTO countries (iso2, iso3, name, m49_code, region, sub_region, capital, tld, continent)
SELECT
    NULLIF(ISO3166_1_Alpha_2, '')           AS iso2,
    NULLIF(ISO3166_1_Alpha_3, '')           AS iso3,
    NULLIF(official_name_en,  '')           AS name,
    NULLIF(M49, '')::INTEGER                AS m49_code,
    NULLIF(Region_Name,       '')           AS region,
    NULLIF(Sub_region_Name,   '')           AS sub_region,
    NULLIF(Capital,           '')           AS capital,
    NULLIF(TLD,               '')           AS tld,
    NULLIF(Continent,         '')           AS continent
FROM tmp_countries
WHERE ISO3166_1_Alpha_2 IS NOT NULL
  AND ISO3166_1_Alpha_2 <> '';

DROP TABLE tmp_countries;

SELECT COUNT(*) AS total_countries FROM countries;
SQL

echo "countries table populated."
