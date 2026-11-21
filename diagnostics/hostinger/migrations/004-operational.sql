-- Apply once to a backed-up staging database first. This does not enable collection.
CREATE TABLE IF NOT EXISTS operational_events (
    event_id CHAR(36) NOT NULL PRIMARY KEY,
    installation_id CHAR(36) NOT NULL,
    schema_version INTEGER NOT NULL,
    event_type VARCHAR(40) NOT NULL,
    occurred_at DATETIME NOT NULL,
    received_at DATETIME NOT NULL,
    app_version VARCHAR(80) NOT NULL,
    macos_version VARCHAR(16) NOT NULL,
    job_id CHAR(36) NULL,
    attempt_id CHAR(36) NULL,
    attempt_number INTEGER NOT NULL,
    job_started_at DATETIME NULL,
    method VARCHAR(8) NOT NULL,
    direction VARCHAR(8) NOT NULL,
    outcome VARCHAR(12) NOT NULL,
    size_bucket VARCHAR(16) NOT NULL,
    count_bucket VARCHAR(16) NOT NULL,
    duration_bucket VARCHAR(16) NOT NULL,
    error_category VARCHAR(24) NOT NULL,
    queue_bucket VARCHAR(16) NOT NULL,
    stage VARCHAR(16) NOT NULL,
    connection_duration_bucket VARCHAR(16) NOT NULL,
    approval_duration_bucket VARCHAR(16) NOT NULL
);
CREATE TABLE IF NOT EXISTS operational_collector_health (
    day VARCHAR(10) NOT NULL,
    metric VARCHAR(32) NOT NULL,
    value INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(day, metric)
);
