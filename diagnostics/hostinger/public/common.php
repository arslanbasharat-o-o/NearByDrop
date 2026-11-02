<?php
declare(strict_types=1);

function nd_config(): array
{
    static $config;
    if (is_array($config ?? null)) {
        return $config;
    }

    $configuredPath = getenv('NEARBYDROP_DIAGNOSTICS_CONFIG');
    $path = $configuredPath ?: dirname(__DIR__) . '/nearbydrop-diagnostics-config.php';
    if (!is_file($path)) {
        throw new RuntimeException('Diagnostics configuration is missing.');
    }
    $loaded = require $path;
    if (!is_array($loaded)) {
        throw new RuntimeException('Diagnostics configuration is invalid.');
    }
    $config = $loaded;
    return $config;
}

function nd_db(): PDO
{
    static $pdo;
    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $config = nd_config();
    $pdo = new PDO(
        (string) ($config['dsn'] ?? ''),
        (string) ($config['db_user'] ?? ''),
        (string) ($config['db_password'] ?? ''),
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
    if ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql') {
        $pdo->exec("SET time_zone = '+00:00'");
    }
    return $pdo;
}

function nd_json(int $status, array $body): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($body, JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
}

function nd_text(mixed $value, int $maxLength): ?string
{
    if (!is_string($value)) {
        return null;
    }
    $value = trim($value);
    if ($value === '' || strlen($value) > $maxLength) {
        return null;
    }
    return $value;
}

function nd_h(mixed $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function nd_start_session(): void
{
    if (session_status() === PHP_SESSION_ACTIVE) {
        return;
    }
    session_set_cookie_params([
        'httponly' => true,
        'secure' => true,
        'samesite' => 'Strict',
        'path' => '/',
    ]);
    session_start();
}

function nd_is_authenticated(): bool
{
    nd_start_session();
    return ($_SESSION['nd_authenticated'] ?? false) === true;
}

function nd_require_authentication(): void
{
    if (!nd_is_authenticated()) {
        http_response_code(401);
        exit('Sign in to view this dashboard.');
    }
}

// Fixed-size, private disk buckets avoid storing raw addresses or unbounded files.
function nd_rate_limit(string $scope, string $identity, int $limit, int $window = 60): void
{
    $configuredPath = getenv('NEARBYDROP_DIAGNOSTICS_CONFIG');
    $parent = $configuredPath ? dirname($configuredPath) : dirname(__DIR__);
    $directory = $parent . '/nearbydrop-rate-limits';
    if (!is_dir($directory) && !@mkdir($directory, 0700, true) && !is_dir($directory)) {
        nd_json(503, ['ok' => false, 'error' => 'temporarily_unavailable']);
    }
    $hash = hash('sha256', $scope . ':' . $identity);
    $file = @fopen($directory . '/' . substr($hash, 0, 3), 'c+');
    if (!$file || !flock($file, LOCK_EX)) {
        nd_json(503, ['ok' => false, 'error' => 'temporarily_unavailable']);
    }
    @chmod($directory . '/' . substr($hash, 0, 3), 0600);
    $bucket = json_decode(stream_get_contents($file), true) ?: [];
    $now = time();
    if (($bucket['until'] ?? 0) <= $now) { $bucket = ['until' => $now + $window, 'count' => 0]; }
    $bucket['count']++;
    rewind($file);
    ftruncate($file, 0);
    fwrite($file, json_encode($bucket));
    fflush($file);
    flock($file, LOCK_UN);
    fclose($file);
    if ($bucket['count'] > $limit) {
        header('Retry-After: ' . max(1, $bucket['until'] - $now));
        nd_json(429, ['ok' => false, 'error' => 'rate_limited']);
    }
}

function nd_cleanup(PDO $db): void
{
    $cutoff = gmdate('Y-m-d H:i:s', time() - 90 * 86400);
    $statement = $db->prepare('DELETE FROM diagnostic_events WHERE occurred_at < ?');
    $statement->execute([$cutoff]);

    $driver = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
    if ($driver === 'sqlite') {
        $db->exec("DELETE FROM diagnostic_events WHERE rowid NOT IN (
            SELECT MIN(rowid) FROM diagnostic_events GROUP BY installation_id, event_type, occurred_at
        )");
        $db->exec("DELETE FROM diagnostic_events WHERE rowid NOT IN (
            SELECT MIN(rowid) FROM diagnostic_events GROUP BY mac_name, COALESCE(peer_name, ''), event_type, COALESCE(transfer_direction, ''), occurred_at
        )");
    } else {
        $db->exec("DELETE d1 FROM diagnostic_events d1
            INNER JOIN diagnostic_events d2
            ON d1.installation_id = d2.installation_id
            AND d1.event_type = d2.event_type
            AND d1.occurred_at = d2.occurred_at
            AND d1.event_id > d2.event_id");
        $db->exec("DELETE t1 FROM diagnostic_events t1
            INNER JOIN diagnostic_events t2
            ON t1.mac_name = t2.mac_name
            AND ((t1.peer_name = t2.peer_name) OR (t1.peer_name IS NULL AND t2.peer_name IS NULL))
            AND t1.event_type = t2.event_type
            AND ((t1.transfer_direction = t2.transfer_direction) OR (t1.transfer_direction IS NULL AND t2.transfer_direction IS NULL))
            AND t1.occurred_at = t2.occurred_at
            AND t1.event_id > t2.event_id");
    }
}
