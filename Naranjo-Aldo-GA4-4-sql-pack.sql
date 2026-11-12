-- =========================================================
-- IBM 6500 | GA4-4 Milestone 4: SQL Pack (Individual)
-- Author: Aldo Naranjo
-- Dataset: bigquery-public-data.ga4_obfuscated_sample_ecommerce
-- =========================================================


-- ---------------------------------------------------------
-- Q1) Daily funnel event counts for one week
-- Skills: filtering and scoping (A), grouping and aggregation (B)
-- ---------------------------------------------------------
SELECT
  event_date,
  COUNTIF(event_name = 'session_start')  AS session_starts,
  COUNTIF(event_name = 'view_item')      AS view_item_events,
  COUNTIF(event_name = 'add_to_cart')    AS add_to_cart_events,
  COUNTIF(event_name = 'begin_checkout') AS begin_checkout_events,
  COUNTIF(event_name = 'purchase')       AS purchase_events
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201207'   -- one week only
  AND event_name IN ('session_start', 'view_item', 'add_to_cart',
                     'begin_checkout', 'purchase')
GROUP BY event_date
ORDER BY event_date;


-- ---------------------------------------------------------
-- Q2) Highest value mobile purchases from the US, week before Christmas
-- Skills: filtering and scoping (A) on nested RECORD fields
-- ---------------------------------------------------------
SELECT
  event_date,
  user_pseudo_id,
  ecommerce.transaction_id,
  ecommerce.total_item_quantity,
  ecommerce.purchase_revenue_in_usd AS revenue_usd
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201214' AND '20201220'
  AND event_name = 'purchase'
  AND device.category = 'mobile'
  AND geo.country = 'United States'
  AND ecommerce.purchase_revenue_in_usd > 0
ORDER BY revenue_usd DESC
LIMIT 15;


-- ---------------------------------------------------------
-- Q3) Users, events, and revenue by first user medium, December 2020
-- Skills: grouping and aggregation (B)
-- ---------------------------------------------------------
SELECT
  traffic_source.medium                          AS first_user_medium,
  COUNT(DISTINCT user_pseudo_id)                 AS users,
  COUNT(*)                                       AS events,
  COUNTIF(event_name = 'purchase')               AS purchase_events,
  ROUND(SUM(ecommerce.purchase_revenue_in_usd), 2) AS revenue_usd
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY first_user_medium
ORDER BY users DESC;


-- ---------------------------------------------------------
-- Q4) Purchaser rate by device and operating system, December 2020
-- Skills: grouping and aggregation (B) with a HAVING filter
-- ---------------------------------------------------------
SELECT
  device.category         AS device_category,
  device.operating_system AS operating_system,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)) AS purchasers,
  ROUND(100 * SAFE_DIVIDE(
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)),
    COUNT(DISTINCT user_pseudo_id)), 2) AS purchaser_rate_pct
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY device_category, operating_system
HAVING COUNT(DISTINCT user_pseudo_id) >= 500   -- drop tiny groups
ORDER BY users DESC;


-- ---------------------------------------------------------
-- Q5) Top pages by page views (page_location, a STRING parameter)
-- Skills: UNNEST(event_params) with string_value (C)
-- ---------------------------------------------------------
SELECT
  REGEXP_REPLACE(
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
    r'\?.*$', '')                AS page_url,     -- strip query strings
  COUNT(*)                       AS page_views,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  AND event_name = 'page_view'
GROUP BY page_url
ORDER BY page_views DESC
LIMIT 15;


-- ---------------------------------------------------------
-- Q6) Engaged time by page (engagement_time_msec, an INT parameter)
-- Skills: UNNEST(event_params) with string_value AND int_value (C)
-- ---------------------------------------------------------
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title') AS page_title,
  COUNT(*) AS engagement_events,
  ROUND(SUM((SELECT value.int_value FROM UNNEST(event_params)
             WHERE key = 'engagement_time_msec')) / 1000 / 60, 1) AS total_engaged_minutes,
  ROUND(AVG((SELECT value.int_value FROM UNNEST(event_params)
             WHERE key = 'engagement_time_msec')) / 1000, 1)      AS avg_engaged_seconds
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201207'
  AND event_name = 'user_engagement'
GROUP BY page_title
HAVING COUNT(*) >= 200
ORDER BY total_engaged_minutes DESC
LIMIT 15;


-- ---------------------------------------------------------
-- Q7) Session level shopping funnel, December 2020
-- Skills: CTE / modular structure (D), multi-step combining (E), UNNEST int (C)
-- ---------------------------------------------------------
WITH funnel_events AS (
  -- Base event set: one row per funnel event with its session id
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    event_name
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
    AND event_name IN ('session_start', 'view_item', 'add_to_cart',
                       'begin_checkout', 'purchase')
),
sessions AS (
  -- One row per session with a 1/0 flag for each step reached
  SELECT
    user_pseudo_id,
    session_id,
    MAX(IF(event_name = 'view_item', 1, 0))      AS viewed_item,
    MAX(IF(event_name = 'add_to_cart', 1, 0))    AS added_to_cart,
    MAX(IF(event_name = 'begin_checkout', 1, 0)) AS began_checkout,
    MAX(IF(event_name = 'purchase', 1, 0))       AS purchased
  FROM funnel_events
  WHERE session_id IS NOT NULL
  GROUP BY user_pseudo_id, session_id
)
SELECT
  COUNT(*)            AS sessions,
  SUM(viewed_item)    AS sessions_view_item,
  SUM(added_to_cart)  AS sessions_add_to_cart,
  SUM(began_checkout) AS sessions_begin_checkout,
  SUM(purchased)      AS sessions_purchase,
  ROUND(100 * SAFE_DIVIDE(SUM(viewed_item), COUNT(*)), 1)              AS pct_view_item,
  ROUND(100 * SAFE_DIVIDE(SUM(added_to_cart), SUM(viewed_item)), 1)    AS pct_view_to_cart,
  ROUND(100 * SAFE_DIVIDE(SUM(began_checkout), SUM(added_to_cart)), 1) AS pct_cart_to_checkout,
  ROUND(100 * SAFE_DIVIDE(SUM(purchased), SUM(began_checkout)), 1)     AS pct_checkout_to_purchase,
  ROUND(100 * SAFE_DIVIDE(SUM(purchased), COUNT(*)), 2)                AS session_conversion_pct
FROM sessions;


-- ---------------------------------------------------------
-- Q8) Daily sessions joined to daily revenue, December 2020
-- Skills: multiple CTEs (D), LEFT JOIN (E), UNNEST int (C)
-- ---------------------------------------------------------
WITH daily_sessions AS (
  SELECT
    event_date,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(
      (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING))) AS sessions
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  GROUP BY event_date
),
daily_revenue AS (
  SELECT
    event_date,
    COUNT(*)                                          AS purchase_events,
    ROUND(SUM(ecommerce.purchase_revenue_in_usd), 2)  AS revenue_usd
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
    AND event_name = 'purchase'
  GROUP BY event_date
)
SELECT
  s.event_date,
  s.sessions,
  IFNULL(r.purchase_events, 0) AS purchase_events,
  IFNULL(r.revenue_usd, 0)     AS revenue_usd,
  ROUND(100 * SAFE_DIVIDE(IFNULL(r.purchase_events, 0), s.sessions), 2) AS purchases_per_100_sessions,
  ROUND(SAFE_DIVIDE(IFNULL(r.revenue_usd, 0), s.sessions), 2)           AS revenue_per_session_usd
FROM daily_sessions AS s
LEFT JOIN daily_revenue AS r
  USING (event_date)
ORDER BY s.event_date;
