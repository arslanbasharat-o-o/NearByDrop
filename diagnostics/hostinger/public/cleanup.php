<?php
declare(strict_types=1);
// CLI only: the web endpoint must not allow unauthenticated cleanup requests.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require __DIR__ . '/common.php';
nd_cleanup(nd_db());
echo "Expired diagnostics removed.\n";
