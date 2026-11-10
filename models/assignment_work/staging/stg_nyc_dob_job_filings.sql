
-- Clean and standardize NYC DOB NOW job filings
-- Grain: one row per job filing

WITH source AS (
    SELECT *
    FROM {{ source('raw', 'source_nyc_dob_job_apps') }}
),

cleaned AS (
    SELECT
        * REPLACE (

            -- Clean filing identifier
            TRIM(job_filing_number) AS job_filing_number,

            -- Standardize borough names
            CASE
                WHEN UPPER(TRIM(borough)) IN
                    ('MANHATTAN', 'NEW YORK')
                    THEN 'Manhattan'
                WHEN UPPER(TRIM(borough)) IN
                    ('BRONX', 'THE BRONX')
                    THEN 'Bronx'
                WHEN UPPER(TRIM(borough)) IN
                    ('BROOKLYN', 'KINGS')
                    THEN 'Brooklyn'
                WHEN UPPER(TRIM(borough)) = 'QUEENS'
                    THEN 'Queens'
                WHEN UPPER(TRIM(borough)) IN
                    ('STATEN ISLAND', 'RICHMOND')
                    THEN 'Staten Island'
                ELSE 'UNKNOWN or CITYWIDE'
            END AS borough,

            -- Standardize location fields
            NULLIF(TRIM(council_district), '')
                AS council_district,

            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(zip),
                    r'^\d{5}(-\d{4})?$'
                ) THEN TRIM(zip)
                WHEN REGEXP_CONTAINS(
                    TRIM(zip),
                    r'^\d{9}$'
                ) THEN TRIM(zip)
                ELSE NULL
            END AS zip,

            -- Convert string dates into DATE types
            COALESCE(
                SAFE_CAST(filing_date AS DATE),
                DATE(SAFE_CAST(filing_date AS TIMESTAMP)),
                SAFE.PARSE_DATE('%m/%d/%Y', filing_date)
            ) AS filing_date,

            COALESCE(
                SAFE_CAST(current_status_date AS DATE),
                DATE(SAFE_CAST(current_status_date AS TIMESTAMP)),
                SAFE.PARSE_DATE('%m/%d/%Y', current_status_date)
            ) AS current_status_date,

            COALESCE(
                SAFE_CAST(first_permit_date AS DATE),
                DATE(SAFE_CAST(first_permit_date AS TIMESTAMP)),
                SAFE.PARSE_DATE('%m/%d/%Y', first_permit_date)
            ) AS first_permit_date,

            COALESCE(
                SAFE_CAST(approved_date AS DATE),
                DATE(SAFE_CAST(approved_date AS TIMESTAMP)),
                SAFE.PARSE_DATE('%m/%d/%Y', approved_date)
            ) AS approved_date,

            COALESCE(
                SAFE_CAST(signoff_date AS DATE),
                DATE(SAFE_CAST(signoff_date AS TIMESTAMP)),
                SAFE.PARSE_DATE('%m/%d/%Y', signoff_date)
            ) AS signoff_date

        )
    FROM source
    WHERE job_filing_number IS NOT NULL
      AND TRIM(job_filing_number) != ''
),

-- Keep the most recent record per filing number
deduplicated AS (
    SELECT *
    FROM cleaned
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY job_filing_number
        ORDER BY
            current_status_date DESC NULLS LAST,
            filing_date DESC NULLS LAST
    ) = 1
)

SELECT
    *,
    CURRENT_TIMESTAMP() AS _stg_loaded_at
FROM deduplicated
