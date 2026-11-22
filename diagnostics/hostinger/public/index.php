<?php
declare(strict_types=1);
require_once __DIR__ . '/common.php';

try {
    $config = nd_config();
} catch (Throwable) {
    http_response_code(503);
    exit('Dashboard setup is incomplete.');
}

nd_start_session();
if (isset($_GET['logout'])) {
    $_SESSION = [];
    session_destroy();
    header('Location: /');
    exit;
}

$loginError = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && !nd_is_authenticated()) {
    nd_rate_limit('login', (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown'), 10, 900);
    $csrf = (string) ($_POST['csrf'] ?? '');
    $token = (string) ($_SESSION['nd_csrf'] ?? '');
    $username = trim((string) ($_POST['username'] ?? ''));
    $password = (string) ($_POST['password'] ?? '');
    $expectedUsername = (string) ($config['admin_username'] ?? '');
    if ($token !== '' && hash_equals($token, $csrf)
        && $expectedUsername !== '' && hash_equals($expectedUsername, $username)
        && password_verify($password, (string) ($config['admin_password_hash'] ?? ''))) {
        session_regenerate_id(true);
        $_SESSION['nd_authenticated'] = true;
        unset($_SESSION['nd_csrf']);
        header('Location: /');
        exit;
    }
    $loginError = 'The username or password was not accepted.';
}

header('Cache-Control: no-store');
header("Content-Security-Policy: default-src 'none'; style-src 'self' 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");

$authenticated = nd_is_authenticated();
$needsSetup = trim((string) ($config['admin_username'] ?? '')) === ''
    || trim((string) ($config['admin_password_hash'] ?? '')) === '';
if (!$authenticated && empty($_SESSION['nd_csrf'])) {
    $_SESSION['nd_csrf'] = bin2hex(random_bytes(32));
}

if ($authenticated) { require __DIR__.'/dashboard.php'; exit; }
?>
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Nearby Drop Diagnostics</title><link rel="stylesheet" href="/dashboard.css"></head><body class="login-page"><main class="login-panel"><a class="brand" href="/">Nearby Drop <span>Diagnostics</span></a><h1>Welcome back</h1><p class="muted">Sign in to view app activity and transfer reports.</p>
<?php if ($needsSetup): ?><p class="notice">Open the setup link provided by the site owner to finish setup.</p><?php else: ?>
<?php if ($loginError !== ''): ?><p class="notice error" role="alert"><?=nd_h($loginError)?></p><?php endif; ?>
<form method="post" action="/"><input type="hidden" name="csrf" value="<?=nd_h($_SESSION['nd_csrf'])?>"><label for="username">Username</label><input id="username" name="username" autocomplete="username" required><label for="password">Password</label><input id="password" name="password" type="password" autocomplete="current-password" required><button type="submit">Sign in</button></form>
<?php endif; ?></main></body></html>
