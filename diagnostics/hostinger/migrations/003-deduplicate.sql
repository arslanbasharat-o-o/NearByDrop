-- Deduplicate diagnostic events in MySQL / MariaDB on Hostinger
-- Run these in phpMyAdmin (or MySQL CLI) on Hostinger database

-- 1. Remove exact duplicate events (same installation, type, and timestamp)
DELETE d1 FROM diagnostic_events d1
INNER JOIN diagnostic_events d2
  ON d1.installation_id = d2.installation_id
  AND d1.event_type = d2.event_type
  AND d1.occurred_at = d2.occurred_at
  AND d1.event_id > d2.event_id;

-- 2. Remove duplicate completed transfer records (same devices, direction, and timestamp)
DELETE t1 FROM diagnostic_events t1
INNER JOIN diagnostic_events t2
  ON t1.mac_name = t2.mac_name
  AND ((t1.peer_name = t2.peer_name) OR (t1.peer_name IS NULL AND t2.peer_name IS NULL))
  AND t1.event_type = t2.event_type
  AND ((t1.transfer_direction = t2.transfer_direction) OR (t1.transfer_direction IS NULL AND t2.transfer_direction IS NULL))
  AND t1.occurred_at = t2.occurred_at
  AND t1.event_id > t2.event_id;

-- 3. Remove duplicate app_opened events for the same Mac within the same timestamp
DELETE a1 FROM diagnostic_events a1
INNER JOIN diagnostic_events a2
  ON a1.mac_name = a2.mac_name
  AND a1.mac_model = a2.mac_model
  AND a1.event_type = 'app_opened'
  AND a2.event_type = 'app_opened'
  AND a1.occurred_at = a2.occurred_at
  AND a1.event_id > a2.event_id;

-- 4. Clean up any redundant test installations for the same physical Mac,
-- keeping only events from the newest installation_id for that Mac:
DELETE d1 FROM diagnostic_events d1
INNER JOIN (
    SELECT mac_name, mac_model, installation_id, occurred_at,
           ROW_NUMBER() OVER (PARTITION BY mac_name, mac_model ORDER BY occurred_at DESC, event_id DESC) AS rn
    FROM diagnostic_events
    WHERE event_type = 'app_opened'
) latest ON d1.mac_name = latest.mac_name AND d1.mac_model = latest.mac_model
WHERE latest.rn = 1
  AND d1.installation_id <> latest.installation_id;
