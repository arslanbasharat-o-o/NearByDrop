CREATE TABLE IF NOT EXISTS diagnostic_events (
    event_id CHAR(36) NOT NULL PRIMARY KEY,
    installation_id CHAR(36) NOT NULL,
    event_type VARCHAR(32) NOT NULL,
    occurred_at DATETIME(3) NOT NULL,
    app_name VARCHAR(80) NOT NULL,
    app_version VARCHAR(80) NOT NULL,
    macos_version VARCHAR(32) NOT NULL,
    mac_name VARCHAR(255) NOT NULL,
    mac_model VARCHAR(80) NOT NULL DEFAULT 'unknown',
    transfer_direction VARCHAR(16) NULL,
    peer_name VARCHAR(255) NULL,
    peer_type VARCHAR(16) NULL,
    INDEX diagnostic_events_time (occurred_at),
    INDEX diagnostic_events_install_time (installation_id, occurred_at),
    INDEX diagnostic_events_type_time (event_type, occurred_at),
    INDEX diagnostic_events_peer_type (peer_type, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
