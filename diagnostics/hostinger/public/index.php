<?php
declare(strict_types=1);
require __DIR__ . '/common.php';

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

$installs = 0;
$active = 0;
$transferCount = 0;
$devices = [];
$transfers = [];
if ($authenticated) {
    try {
        $db = nd_db();
        nd_cleanup($db);
        $driver = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
        $installs = (int) $db->query("SELECT COUNT(DISTINCT installation_id) FROM diagnostic_events WHERE event_type = 'first_launch'")->fetchColumn();
        $activeFilter = $driver === 'sqlite'
            ? "occurred_at >= datetime('now', '-30 days')"
            : 'occurred_at >= UTC_TIMESTAMP() - INTERVAL 30 DAY';
        $activeQuery = $db->prepare("SELECT COUNT(DISTINCT installation_id) FROM diagnostic_events WHERE event_type = 'app_opened' AND " . $activeFilter);
        $activeQuery->execute();
        $active = (int) $activeQuery->fetchColumn();
        $transferCount = (int) $db->query("SELECT COUNT(*) FROM diagnostic_events WHERE event_type = 'transfer_completed'")->fetchColumn();
        $devices = $db->query(
            "SELECT e.installation_id, e.mac_name, e.app_version, e.macos_version, e.mac_model, e.occurred_at "
            . "FROM diagnostic_events e "
            . "INNER JOIN (SELECT e1.installation_id, MAX(e1.event_id) AS event_id FROM diagnostic_events e1 "
            . "WHERE e1.event_type = 'app_opened' AND e1.occurred_at = (SELECT MAX(e2.occurred_at) FROM diagnostic_events e2 WHERE e2.installation_id = e1.installation_id AND e2.event_type = 'app_opened') "
            . "GROUP BY e1.installation_id) latest ON latest.event_id = e.event_id "
            . "WHERE e.event_type = 'app_opened' ORDER BY e.occurred_at DESC LIMIT 100"
        )->fetchAll();
        $transfers = $db->query(
            "SELECT mac_name, peer_name, peer_type, transfer_direction, app_version, macos_version, occurred_at "
            . "FROM diagnostic_events WHERE event_type = 'transfer_completed' ORDER BY occurred_at DESC LIMIT 100"
        )->fetchAll();
    } catch (Throwable) {
        http_response_code(503);
        exit('Dashboard data is temporarily unavailable.');
    }
}
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>Nearby Drop Diagnostics</title>
  <style>
    :root { color-scheme: dark; font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background:#101014; color:#f3f1f7; }
    body { margin:0; padding:32px 20px 56px; }
    main { max-width:1100px; margin:auto; }
    header { display:flex; justify-content:space-between; align-items:center; gap:18px; margin-bottom:28px; }
    h1,h2,p { margin-top:0; } h1 { margin-bottom:4px; font-size:28px; } h2 { margin:30px 0 12px; font-size:18px; }
    a { color:#d75cf0; } .muted { color:#a8a3b0; }
    .cards { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:12px; }
    .card, .panel { border:1px solid #34313a; background:#19171e; border-radius:12px; padding:18px; }
    .metric { font-size:30px; font-weight:700; margin:4px 0 0; }
    .table-wrap { overflow-x:auto; border:1px solid #34313a; border-radius:10px; }
    table { border-collapse:collapse; width:100%; min-width:720px; background:#19171e; }
    th,td { text-align:left; padding:11px 13px; border-bottom:1px solid #34313a; vertical-align:top; }
    th { color:#c8c1d0; font-size:12px; text-transform:uppercase; letter-spacing:.05em; }
    tr:last-child td { border-bottom:0; }
    input,button { font:inherit; color:inherit; border:1px solid #48414f; border-radius:8px; padding:10px 12px; background:#211e27; }
    button { background:#a72ac0; border-color:#c83ae4; font-weight:650; cursor:pointer; }
    .login { max-width:420px; margin:12vh auto; } .login input { width:calc(100% - 26px); margin:8px 0 14px; }
    .error { color:#ff9797; }
    @media(max-width:600px) { body { padding:22px 14px 40px; } header { align-items:flex-start; } }
  </style>
</head>
<body>
<main>
<?php if (!$authenticated): ?>
  <section class="panel login">
    <h1>Nearby Drop Diagnostics</h1>
    <?php if ($needsSetup): ?>
      <p class="muted">Dashboard setup is ready. Open the single-use setup link provided by the site owner.</p>
    <?php else: ?>
    <p class="muted">Sign in to view install and transfer compatibility reports.</p>
    <?php if ($loginError !== ''): ?><p class="error"><?= nd_h($loginError) ?></p><?php endif; ?>
    <form method="post" action="/">
      <input type="hidden" name="csrf" value="<?= nd_h($_SESSION['nd_csrf']) ?>">
      <label for="username">Dashboard username</label>
      <input id="username" name="username" type="text" autocomplete="username" required>
      <label for="password">Dashboard password</label>
      <input id="password" name="password" type="password" autocomplete="current-password" required>
      <button type="submit">Sign in</button>
    </form>
    <?php endif; ?>
  </section>
<?php else: ?>
  <header>
    <div><h1>Nearby Drop diagnostics</h1><p class="muted">Installation activity and completed transfer compatibility.</p></div>
    <a href="/?logout=1">Sign out</a>
  </header>
  <section class="cards" aria-label="Summary">
    <article class="card"><span class="muted">Reported installs</span><p class="metric"><?= $installs ?></p></article>
    <article class="card"><span class="muted">Active installs, 30 days</span><p class="metric"><?= $active ?></p></article>
    <article class="card"><span class="muted">Completed wireless transfers</span><p class="metric"><?= $transferCount ?></p></article>
  </section>
  <p class="muted" style="margin-top:14px">Last 90 days. Counts represent app installations, not named accounts; reinstalling can create a new ID. Mac and peer names are advertised device labels and can identify people. Event times are rounded to the hour, UTC.</p>
  <h2>Recent Macs</h2>
  <div class="table-wrap"><table>
    <thead><tr><th>Mac name</th><th>Mac model</th><th>App version</th><th>macOS</th><th>Last opened</th></tr></thead>
    <tbody>
      <?php foreach ($devices as $device): ?><tr>
        <td><?= nd_h($device['mac_name']) ?></td><td><?= nd_h($device['mac_model']) ?></td><td><?= nd_h($device['app_version']) ?></td>
        <td><?= nd_h($device['macos_version']) ?></td><td><?= nd_h($device['occurred_at']) ?> UTC</td>
      </tr><?php endforeach; ?>
      <?php if ($devices === []): ?><tr><td colspan="5" class="muted">No launch reports yet.</td></tr><?php endif; ?>
    </tbody>
  </table></div>
  <h2>Recent completed transfers</h2>
  <div class="table-wrap"><table>
    <thead><tr><th>Mac</th><th>Phone/device name</th><th>Type</th><th>Direction</th><th>App / macOS</th><th>Time</th></tr></thead>
    <tbody>
      <?php foreach ($transfers as $transfer): ?><tr>
        <td><?= nd_h($transfer['mac_name']) ?></td><td><?= nd_h($transfer['peer_name']) ?></td>
        <td><?= nd_h($transfer['peer_type']) ?></td><td><?= nd_h($transfer['transfer_direction']) ?></td>
        <td><?= nd_h($transfer['app_version']) ?> / <?= nd_h($transfer['macos_version']) ?></td>
        <td><?= nd_h($transfer['occurred_at']) ?> UTC</td>
      </tr><?php endforeach; ?>
      <?php if ($transfers === []): ?><tr><td colspan="6" class="muted">No completed transfers reported yet.</td></tr><?php endif; ?>
    </tbody>
  </table></div>
<?php endif; ?>
</main>
</body>
</html>
