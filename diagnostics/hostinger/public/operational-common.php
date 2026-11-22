<?php
declare(strict_types=1);

function nd_operational_health(PDO $db, string $metric): void {
    $driver = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
    $sql = $driver === 'sqlite'
        ? 'INSERT INTO operational_collector_health(day,metric,value) VALUES(?,?,1) ON CONFLICT(day,metric) DO UPDATE SET value=value+1'
        : 'INSERT INTO operational_collector_health(day,metric,value) VALUES(?,?,1) ON DUPLICATE KEY UPDATE value=value+1';
    $db->prepare($sql)->execute([gmdate('Y-m-d'), $metric]);
    $db->prepare('DELETE FROM operational_collector_health WHERE day < ?')->execute([gmdate('Y-m-d', time()-90*86400)]);
}

function nd_operational_timestamp(mixed $value, int $now): string {
    if (!is_string($value) || !preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/D', $value)) {
        throw new InvalidArgumentException('invalid_timestamp');
    }
    try { $date = new DateTimeImmutable($value); }
    catch (Throwable) { throw new InvalidArgumentException('invalid_timestamp'); }
    $errors = DateTimeImmutable::getLastErrors();
    if (($errors !== false && ($errors['warning_count'] || $errors['error_count']))
        || $date->getTimestamp() < $now - 90 * 86400 || $date->getTimestamp() > $now + 3600) {
        throw new InvalidArgumentException('timestamp_out_of_range');
    }
    return $date->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');
}

function nd_validate_operational(array $event, int $now): array {
    $allowed = ['schema_version','event_id','installation_id','event','occurred_at','app_version','macos_version','device_category',
        'job_id','attempt_id','attempt_number','job_started_at','method','direction','outcome','size_bucket','count_bucket',
        'duration_bucket','error_category','queue_bucket','stage','connection_duration_bucket','approval_duration_bucket'];
    if (array_diff(array_keys($event), $allowed) || ($event['schema_version'] ?? null) !== 2
        || ($event['device_category'] ?? null) !== 'computer') throw new InvalidArgumentException('invalid_schema');
    $uuid = '/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iD';
    foreach (['event_id','installation_id'] as $key) {
        if (!is_string($event[$key] ?? null) || !preg_match($uuid, $event[$key])) throw new InvalidArgumentException('invalid_identifier');
    }
    $outcomes = [
        'transfer_started'=>['pending'], 'transfer_completed'=>['completed'], 'transfer_failed'=>['failed'],
        'transfer_cancelled'=>['cancelled'], 'transfer_declined'=>['declined'], 'usb_operation_started'=>['pending'],
        'usb_operation_finished'=>['completed','failed','cancelled'], 'troubleshooting_used'=>['none'],
        'onboarding_completed'=>['none'], 'client_health'=>['none'],
    ];
    $kind = $event['event'] ?? null;
    if (!is_string($kind) || !isset($outcomes[$kind]) || !in_array($event['outcome'] ?? null, $outcomes[$kind], true)) {
        throw new InvalidArgumentException('invalid_outcome');
    }
    $duration = ['unknown','lt1s','1to5s','5to30s','30to120s','120to600s','600plus'];
    $enums = [
        'method'=>['wifi','qr','usb','none'], 'direction'=>['incoming','outgoing','none'],
        'size_bucket'=>['unknown','zero','lt1mb','1to10mb','10to100mb','100mbto1gb','1gbplus'],
        'count_bucket'=>['unknown','zero','one','2to10','11to50','51to128','129plus'],
        'duration_bucket'=>$duration, 'connection_duration_bucket'=>$duration, 'approval_duration_bucket'=>$duration,
        'error_category'=>['none','network','file_access','source_changed','connection','cancelled','declined','other'],
        'queue_bucket'=>['zero','1to10','11to50','51plus'], 'stage'=>['preparing','connecting','approval','transferring','none'],
    ];
    foreach ($enums as $key=>$values) {
        if (!in_array($event[$key] ?? null, $values, true)) throw new InvalidArgumentException('invalid_category');
    }
    if (!is_string($event['app_version'] ?? null) || !preg_match('/^[0-9A-Za-z.+-]{1,80}$/D', $event['app_version'])
        || !is_string($event['macos_version'] ?? null) || !preg_match('/^[0-9]{1,2}\.[0-9]{1,2}$/D', $event['macos_version'])) {
        throw new InvalidArgumentException('invalid_version');
    }
    $isJob = str_starts_with($kind, 'transfer_') || str_starts_with($kind, 'usb_operation_');
    $startedAt = null;
    if ($isJob) {
        foreach (['job_id','attempt_id'] as $key) {
            if (!is_string($event[$key] ?? null) || !preg_match($uuid, $event[$key])) throw new InvalidArgumentException('invalid_job');
        }
        if (!is_int($event['attempt_number'] ?? null) || $event['attempt_number'] < 1 || $event['attempt_number'] > 100
            || $event['method'] === 'none' || $event['direction'] === 'none' || $event['stage'] === 'none') throw new InvalidArgumentException('invalid_attempt');
        if ((str_starts_with($kind, 'usb_') && $event['method'] !== 'usb')
            || (str_starts_with($kind, 'transfer_') && !in_array($event['method'], ['wifi','qr'], true))) throw new InvalidArgumentException('invalid_method');
        $startedAt = nd_operational_timestamp($event['job_started_at'] ?? null, $now);
    } elseif (($event['job_id'] ?? null) !== null || ($event['attempt_id'] ?? null) !== null
        || ($event['attempt_number'] ?? null) !== 0 || ($event['job_started_at'] ?? null) !== null
        || $event['method'] !== 'none' || $event['direction'] !== 'none' || $event['stage'] !== 'none') {
        throw new InvalidArgumentException('unexpected_job');
    }
    $occurredAt = nd_operational_timestamp($event['occurred_at'] ?? null, $now);
    if ($startedAt !== null && $startedAt > $occurredAt) throw new InvalidArgumentException('invalid_job_time');
    $event['event_type'] = $kind; unset($event['event'], $event['device_category']);
    $event['occurred_at'] = $occurredAt; $event['job_started_at'] = $startedAt;
    $event['received_at'] = gmdate('Y-m-d H:i:s', $now);
    $event['job_id'] = $event['job_id'] ?? null; $event['attempt_id'] = $event['attempt_id'] ?? null;
    // UUID casing is semantically irrelevant, including on SQLite test databases.
    foreach (['event_id','installation_id','job_id','attempt_id'] as $key) {
        if ($event[$key] !== null) $event[$key] = strtolower($event[$key]);
    }
    return $event;
}

function nd_operational_summary(array $events, int $now): array {
    $jobs = []; $attempts = []; $installs = []; $activation = []; $histograms = [];
    foreach ($events as $event) {
        $install = $event['installation_id']; $installs[$install] = true;
        $activation[$install][$event['event_type']] = true;
        foreach (['method','direction','duration_bucket','connection_duration_bucket','approval_duration_bucket','size_bucket','count_bucket','error_category','stage','queue_bucket','app_version','macos_version','schema_version'] as $field) {
            $value = (string)$event[$field]; $histograms[$field][$value] = ($histograms[$field][$value] ?? 0) + 1;
        }
        if ($event['job_id'] === null) continue;
        // Scope correlation to an installation; public client identifiers are not authentication.
        $key = $install . ':' . $event['job_id'];
        $attemptKey = $key . ':' . $event['attempt_id']; $attempts[$attemptKey] = true;
        $started = in_array($event['event_type'], ['transfer_started','usb_operation_started'], true);
        $job = $jobs[$key] ?? ['started'=>false, 'number'=>0, 'terminal'=>false, 'outcome'=>'pending', 'time'=>$event['job_started_at']];
        $job['started'] = $job['started'] || $started;
        $number = (int)$event['attempt_number']; $terminal = $event['outcome'] !== 'pending';
        if ($number > $job['number'] || ($number === $job['number'] && $terminal && !$job['terminal'])) {
            $job['number'] = $number; $job['terminal'] = $terminal; $job['outcome'] = $event['outcome'];
        }
        // Conflicting terminals for the same attempt are indeterminate, never optimistically successful.
        elseif ($number === $job['number'] && $terminal && $job['terminal'] && $event['outcome'] !== $job['outcome']) {
            $job['outcome'] = 'unknown';
        }
        $jobs[$key] = $job;
    }
    $counts = array_fill_keys(['attempted','completed','failed','cancelled','declined','pending','unknown','missing_start'], 0);
    foreach ($jobs as $job) {
        if (!$job['started']) { $counts['missing_start']++; continue; }
        $counts['attempted']++;
        $outcome = $job['outcome'];
        if ($outcome === 'pending' && strtotime($job['time'] . ' UTC') < $now - 86400) $outcome = 'unknown';
        $counts[$outcome]++;
    }
    return ['counts'=>$counts, 'attempts'=>count($attempts), 'installations'=>count($installs), 'histograms'=>$histograms, 'activation'=>$activation];
}
