<?php
declare(strict_types=1);
require __DIR__ . '/common.php';

nd_start_session();
$directory = dirname(__DIR__);
$configPath = getenv('NEARBYDROP_DIAGNOSTICS_CONFIG') ?: $directory . '/nearbydrop-diagnostics-config.php';
$tokenPath = $directory . '/nearbydrop-dashboard-setup.token';
$setupError = '';

header('Cache-Control: no-store');
header('Referrer-Policy: no-referrer');
header("Content-Security-Policy: default-src 'none'; style-src 'self' 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");

$setupRecord = [];
if (is_file($tokenPath)) {
    $decoded = json_decode((string) file_get_contents($tokenPath), true);
    if (is_array($decoded)) {
        $setupRecord = $decoded;
    }
}
$storedHash = (string) ($setupRecord['token_hash'] ?? '');
$expiresAt = (int) ($setupRecord['expires_at'] ?? 0);
$tokenIsValid = $storedHash !== '' && $expiresAt > time();

// A fresh link must replace stale setup state in the current browser session.
$providedToken = (string) ($_GET['token'] ?? '');
if ($providedToken !== '') {
    if (!$tokenIsValid || !hash_equals($storedHash, hash('sha256', $providedToken))) {
        http_response_code(404);
        exit('Setup link is invalid or has already been used.');
    }
    session_regenerate_id(true);
    $_SESSION = [
        'nd_setup_authorized' => true,
        'nd_setup_token_hash' => $storedHash,
        'nd_setup_csrf' => bin2hex(random_bytes(32)),
    ];
    header('Location: /setup.php');
    exit;
}
if (empty($_SESSION['nd_setup_authorized'])) {
    http_response_code(404);
    exit('Setup link is invalid or has already been used.');
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $csrf = (string) ($_POST['csrf'] ?? '');
    $expectedCsrf = (string) ($_SESSION['nd_setup_csrf'] ?? '');
    $username = trim((string) ($_POST['username'] ?? ''));
    $databasePassword = (string) ($_POST['database_password'] ?? '');
    $password = (string) ($_POST['password'] ?? '');
    $confirmation = (string) ($_POST['password_confirmation'] ?? '');

    if ($expectedCsrf === '' || !hash_equals($expectedCsrf, $csrf)) {
        $setupError = 'This form expired. Reopen the setup link.';
    } elseif ($username === '' || strlen($username) > 80 || preg_match('/[\x00-\x1F\x7F]/', $username)) {
        $setupError = 'Enter a valid username.';
    } elseif ($databasePassword === '' || strlen($databasePassword) > 256) {
        $setupError = 'Enter a valid database password.';
    } elseif (strlen($password) < 16 || strlen($password) > 256) {
        $setupError = 'Choose a password with at least 16 characters.';
    } elseif (!hash_equals($password, $confirmation)) {
        $setupError = 'The passwords do not match.';
    } elseif (!$tokenIsValid || !hash_equals((string) ($_SESSION['nd_setup_token_hash'] ?? ''), $storedHash)) {
        $setupError = 'This setup link has expired.';
    } else {
        try {
            $config = require $configPath;
            if (!is_array($config)) {
                throw new RuntimeException('Invalid diagnostics configuration.');
            }
            $database = new PDO(
                (string) ($config['dsn'] ?? ''),
                (string) ($config['db_user'] ?? ''),
                $databasePassword,
                [
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                    PDO::ATTR_EMULATE_PREPARES => false,
                ]
            );
            $database->query('SELECT 1 FROM diagnostic_events LIMIT 0');
            $config['db_password'] = $databasePassword;
            $config['admin_username'] = $username;
            $config['admin_password_hash'] = password_hash($password, PASSWORD_DEFAULT);
            $temporaryPath = $configPath . '.tmp-' . bin2hex(random_bytes(8));
            $previousMask = umask(0077);
            try {
                $written = file_put_contents($temporaryPath, "<?php\nreturn " . var_export($config, true) . ";\n", LOCK_EX);
            } finally {
                umask($previousMask);
            }
            if ($written === false || !chmod($temporaryPath, 0600) || !rename($temporaryPath, $configPath)) {
                @unlink($temporaryPath);
                throw new RuntimeException('Could not save dashboard credentials.');
            }
            @unlink($tokenPath);
            session_regenerate_id(true);
            $_SESSION = ['nd_authenticated' => true];
            header('Location: /');
            exit;
        } catch (Throwable) {
            $setupError = 'Could not verify the database connection or save dashboard access. Check the database password and try again.';
        }
    }
}

if (empty($_SESSION['nd_setup_csrf'])) {
    $_SESSION['nd_setup_csrf'] = bin2hex(random_bytes(32));
}
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>Set up Nearby Drop Diagnostics</title>
  <style>
    :root { color-scheme: dark; font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background:#101014; color:#f3f1f7; }
    body { margin:0; padding:32px 20px 56px; }
    main { max-width:460px; margin:12vh auto; }
    .panel { border:1px solid #34313a; background:#19171e; border-radius:12px; padding:24px; }
    h1 { margin:0 0 8px; font-size:26px; }
    p { color:#a8a3b0; margin-top:0; }
    label { display:block; margin:14px 0 6px; }
    input,button { width:100%; box-sizing:border-box; font:inherit; color:inherit; border:1px solid #48414f; border-radius:8px; padding:11px 12px; background:#211e27; }
    button { margin-top:20px; background:#a72ac0; border-color:#c83ae4; font-weight:650; cursor:pointer; }
    .error { color:#ff9797; }
  </style>
</head>
<body>
<main>
  <section class="panel">
    <h1>Set up dashboard access</h1>
    <p>Choose a username and a new password for your diagnostics dashboard.</p>
    <?php if ($setupError !== ''): ?><p class="error"><?= nd_h($setupError) ?></p><?php endif; ?>
    <form method="post" action="/setup.php">
      <input type="hidden" name="csrf" value="<?= nd_h($_SESSION['nd_setup_csrf']) ?>">
      <label for="username">Dashboard username</label>
      <input id="username" name="username" type="text" value="Arsalan Basharat" maxlength="80" autocomplete="username" required>
      <label for="database_password">MySQL database password</label>
      <input id="database_password" name="database_password" type="password" maxlength="256" autocomplete="current-password" required>
      <label for="password">New dashboard password</label>
      <input id="password" name="password" type="password" minlength="16" maxlength="256" autocomplete="new-password" required>
      <label for="password_confirmation">Confirm new password</label>
      <input id="password_confirmation" name="password_confirmation" type="password" minlength="16" maxlength="256" autocomplete="new-password" required>
      <button type="submit">Save dashboard access</button>
    </form>
  </section>
</main>
</body>
</html>
