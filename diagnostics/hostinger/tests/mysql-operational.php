<?php
declare(strict_types=1);
// Uses only connection-local temporary tables, which shadow production names.
if (PHP_SAPI !== 'cli' || $argc !== 2 || !is_file($argv[1])) {
    fwrite(STDERR, "Usage: php mysql-operational.php /private/config.php\n"); exit(2);
}
require __DIR__.'/../public/common.php';
require __DIR__.'/../public/operational-common.php';
$config = require $argv[1];
$db = new PDO($config['dsn'], $config['db_user'], $config['db_password'], [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES=>false]);
if ($db->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'mysql') throw new RuntimeException('MySQL required');
$db->exec("SET time_zone = '+00:00'");
$sql = str_replace('CREATE TABLE IF NOT EXISTS', 'CREATE TEMPORARY TABLE IF NOT EXISTS', (string)file_get_contents(__DIR__.'/../migrations/004-operational.sql'));
$db->exec($sql); $db->exec($sql);
foreach (['operational_event_time'=>'occurred_at', 'operational_job_time'=>'job_started_at', 'operational_job_lookup'=>'installation_id,job_id,attempt_number'] as $name=>$columns) {
    $db->exec("CREATE INDEX $name ON operational_events ($columns)");
}
function verify(bool $condition, string $label): void { if (!$condition) throw new RuntimeException($label); }
$now = time();
$base = [
 'schema_version'=>2,'event_id'=>'00000000-0000-4000-8000-000000000001','installation_id'=>'10000000-0000-4000-8000-000000000001',
 'event'=>'transfer_started','occurred_at'=>gmdate('Y-m-d\TH:i:s.000\Z',$now), 'app_version'=>'2.5.0','macos_version'=>'26.0','device_category'=>'computer',
 'job_id'=>'20000000-0000-4000-8000-000000000001','attempt_id'=>'30000000-0000-4000-8000-000000000001','attempt_number'=>1,
 'job_started_at'=>gmdate('Y-m-d\TH:i:s.000\Z',$now-120), 'method'=>'wifi','direction'=>'outgoing','outcome'=>'pending',
 'size_bucket'=>'lt1mb','count_bucket'=>'one','duration_bucket'=>'1to5s','error_category'=>'none','queue_bucket'=>'zero',
 'stage'=>'connecting','connection_duration_bucket'=>'1to5s','approval_duration_bucket'=>'unknown',
];
$start = nd_validate_operational($base,$now);
$fail = $start; $fail['event_id']='00000000-0000-4000-8000-000000000002'; $fail['event_type']='transfer_failed'; $fail['outcome']='failed'; $fail['error_category']='connection';
$retry = $start; $retry['event_id']='00000000-0000-4000-8000-000000000003'; $retry['attempt_id']='30000000-0000-4000-8000-000000000002'; $retry['attempt_number']=2;
$done = $retry; $done['event_id']='00000000-0000-4000-8000-000000000004'; $done['event_type']='transfer_completed'; $done['outcome']='completed';
$columns = array_keys($start);
$insert = $db->prepare('INSERT IGNORE INTO operational_events ('.implode(',',$columns).') VALUES ('.implode(',',array_fill(0,count($columns),'?')).')');
foreach ([$done,$fail,$retry,$start,$start] as $event) $insert->execute(array_values($event));
verify((int)$db->query('SELECT COUNT(*) FROM operational_events')->fetchColumn()===4, 'UUID dedup');
$rows=$db->query('SELECT * FROM operational_events ORDER BY occurred_at,event_id')->fetchAll(PDO::FETCH_ASSOC);
$summary=nd_operational_summary($rows,$now);
verify($summary['counts']['attempted']===1 && $summary['counts']['completed']===1 && $summary['attempts']===2, 'Retry accounting');
verify($summary['histograms']['macos_version']['26.0']===4, 'OS breakdown');
nd_operational_health($db,'accepted'); nd_operational_health($db,'accepted');
verify((int)$db->query("SELECT value FROM operational_collector_health WHERE metric='accepted'")->fetchColumn()===2, 'MySQL health upsert');
$filter=$db->prepare('SELECT COUNT(*) FROM operational_events WHERE job_started_at >= ? AND method=? AND app_version=?');
$filter->execute([gmdate('Y-m-d 00:00:00',$now),'wifi','2.5.0']);
verify((int)$filter->fetchColumn()===4, 'Dashboard filters');
$db->prepare('DELETE FROM operational_events WHERE occurred_at < ?')->execute([gmdate('Y-m-d H:i:s',$now-90*86400)]);
verify((int)$db->query('SELECT COUNT(*) FROM operational_events')->fetchColumn()===4, 'Retention');
echo "MySQL temporary-table checks passed: additive DDL replay, indexes, insertion, UUID dedup, retry accounting, filters, health and retention. No persistent tables or rows changed.\n";
