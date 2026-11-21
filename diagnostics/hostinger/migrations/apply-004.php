<?php
declare(strict_types=1);
// Explicit config path prevents accidentally discovering a production database.
if (PHP_SAPI !== 'cli' || $argc !== 2 || !is_file($argv[1])) { fwrite(STDERR, "Usage: php apply-004.php /absolute/path/to/staging-config.php\n"); exit(2); }
$config = require $argv[1];
$db = new PDO($config['dsn'], $config['db_user'] ?? '', $config['db_password'] ?? '', [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$db->exec((string)file_get_contents(__DIR__.'/004-operational.sql'));
foreach (['operational_event_time'=>['operational_events','occurred_at'], 'operational_job_time'=>['operational_events','job_started_at'], 'operational_job_lookup'=>['operational_events','installation_id,job_id,attempt_number']] as $name=>[$table,$columns]) {
    if ($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='sqlite') {
        $existing = $db->query("PRAGMA index_list($table)")->fetchAll(PDO::FETCH_ASSOC);
        $names = array_column($existing, 'name');
    } else {
        $existing = $db->query("SHOW INDEX FROM $table")->fetchAll(PDO::FETCH_ASSOC);
        $names = array_column($existing, 'Key_name');
    }
    if (!in_array($name, $names, true)) $db->exec("CREATE INDEX $name ON $table ($columns)");
}
echo "Schema 2 tables and indexes prepared; collection enablement unchanged.\n";
