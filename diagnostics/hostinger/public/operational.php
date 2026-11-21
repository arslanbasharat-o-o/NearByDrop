<?php
declare(strict_types=1);
require __DIR__ . '/common.php';
require __DIR__ . '/operational-common.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { header('Allow: POST'); nd_json(405, ['ok'=>false,'error'=>'method_not_allowed']); }
if ((nd_config()['operational_enabled'] ?? false) !== true) nd_json(503, ['ok'=>false,'error'=>'rollout_disabled']);
nd_rate_limit('operational-ip', (string)($_SERVER['REMOTE_ADDR'] ?? 'unknown'), 300);
$db = null;
try {
    $db = nd_db();
    $raw = file_get_contents('php://input', false, null, 0, 8193);
    if ($raw === false || strlen($raw) > 8192) throw new InvalidArgumentException('invalid_payload');
    $decoded = json_decode($raw, true, 16, JSON_THROW_ON_ERROR);
    if (!is_array($decoded)) throw new InvalidArgumentException('invalid_payload');
    $event = nd_validate_operational($decoded, time());
    nd_rate_limit('operational-install', $event['installation_id'], 120);
    $verb = $db->getAttribute(PDO::ATTR_DRIVER_NAME) === 'sqlite' ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
    $columns = array_keys($event);
    $sql = $verb . ' INTO operational_events (' . implode(',', $columns) . ') VALUES (' . implode(',', array_fill(0, count($columns), '?')) . ')';
    $statement = $db->prepare($sql); $statement->execute(array_values($event));
    nd_operational_health($db, $statement->rowCount() > 0 ? 'accepted' : 'duplicates');
    if (strtotime($event['received_at'] . ' UTC') - strtotime($event['occurred_at'] . ' UTC') > 3600) nd_operational_health($db, 'delayed_over_hour');
    $cutoff = gmdate('Y-m-d H:i:s', time() - 90 * 86400);
    $db->prepare('DELETE FROM operational_events WHERE occurred_at < ?')->execute([$cutoff]);
    $db->prepare('DELETE FROM operational_collector_health WHERE day < ?')->execute([substr($cutoff, 0, 10)]);
    nd_json(202, ['ok'=>true]);
} catch (InvalidArgumentException|JsonException $error) {
    if ($db) { try { nd_operational_health($db, 'rejected'); } catch (Throwable) {} }
    nd_json(422, ['ok'=>false,'error'=>'invalid_operational_event']);
} catch (Throwable $error) {
    if ($db) { try { nd_operational_health($db, 'server_errors'); } catch (Throwable) {} }
    nd_json(503, ['ok'=>false,'error'=>'temporarily_unavailable']);
}
