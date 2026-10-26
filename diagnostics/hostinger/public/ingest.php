<?php
declare(strict_types=1);
require __DIR__ . '/common.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    nd_json(405, ['ok' => false, 'error' => 'method_not_allowed']);
}

nd_rate_limit('ingest-ip', (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown'), 300);

$length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
if ($length > 8192) {
    nd_json(413, ['ok' => false, 'error' => 'payload_too_large']);
}

$raw = file_get_contents('php://input', false, null, 0, 8193);
if ($raw === false || strlen($raw) > 8192) {
    nd_json(413, ['ok' => false, 'error' => 'payload_too_large']);
}
$event = json_decode($raw, true);
if (!is_array($event)) {
    nd_json(400, ['ok' => false, 'error' => 'invalid_json']);
}

$eventID = nd_text($event['event_id'] ?? null, 36);
$installationID = nd_text($event['installation_id'] ?? null, 36);
$eventType = nd_text($event['event'] ?? null, 32);
$appName = nd_text($event['app_name'] ?? null, 80);
$appVersion = nd_text($event['app_version'] ?? null, 80);
$macOSVersion = nd_text($event['macos_version'] ?? null, 32);
$macModel = nd_text($event['mac_model'] ?? 'unknown', 80);
$macName = nd_text($event['mac_name'] ?? null, 255);
$occurredAtRaw = nd_text($event['occurred_at'] ?? null, 64);

$uuidPattern = '/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i';
$eventTypes = ['first_launch', 'app_opened', 'transfer_completed'];
if ($eventID === null || !preg_match($uuidPattern, $eventID)
    || $installationID === null || !preg_match($uuidPattern, $installationID)
    || $eventType === null || !in_array($eventType, $eventTypes, true)
    || $appName !== 'Nearby Drop'
    || $appVersion === null || $macOSVersion === null || $macName === null || $macModel === null
    || $occurredAtRaw === null) {
    nd_json(422, ['ok' => false, 'error' => 'invalid_event']);
}

try {
    $occurredAt = new DateTimeImmutable($occurredAtRaw);
} catch (Throwable) {
    nd_json(422, ['ok' => false, 'error' => 'invalid_timestamp']);
}

if ($occurredAt->getTimestamp() < time() - 90 * 86400 || $occurredAt->getTimestamp() > time() + 3600) {
    nd_json(422, ['ok' => false, 'error' => 'timestamp_out_of_range']);
}
nd_rate_limit('installation', $installationID, 120);

$direction = null;
$peerName = null;
$peerType = null;
if ($eventType === 'transfer_completed') {
    $direction = nd_text($event['transfer_direction'] ?? null, 16);
    $peerName = nd_text($event['peer_name'] ?? null, 255);
    $peerType = nd_text($event['peer_type'] ?? null, 16);
    if (!in_array($direction, ['incoming', 'outgoing'], true)
        || $peerName === null
        || !in_array($peerType, ['phone', 'tablet', 'computer', 'unknown'], true)) {
        nd_json(422, ['ok' => false, 'error' => 'invalid_transfer_event']);
    }
}

try {
    $db = nd_db();
    nd_cleanup($db);
    $insertVerb = $db->getAttribute(PDO::ATTR_DRIVER_NAME) === 'sqlite' ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
    $statement = $db->prepare(
        $insertVerb . ' INTO diagnostic_events '
        . '(event_id, installation_id, event_type, occurred_at, app_name, app_version, macos_version, mac_name, mac_model, transfer_direction, peer_name, peer_type) '
        . 'VALUES (:event_id, :installation_id, :event_type, :occurred_at, :app_name, :app_version, :macos_version, :mac_name, :mac_model, :direction, :peer_name, :peer_type)'
    );
    $statement->execute([
        ':event_id' => $eventID,
        ':installation_id' => $installationID,
        ':event_type' => $eventType,
        ':occurred_at' => $occurredAt->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s.v'),
        ':app_name' => $appName,
        ':app_version' => $appVersion,
        ':macos_version' => $macOSVersion,
        ':mac_name' => $macName,
        ':mac_model' => $macModel,
        ':direction' => $direction,
        ':peer_name' => $peerName,
        ':peer_type' => $peerType,
    ]);
    nd_json(202, ['ok' => true]);
} catch (Throwable) {
    // Keep database details and submitted names out of public error responses.
    nd_json(503, ['ok' => false, 'error' => 'temporarily_unavailable']);
}
