<?php
declare(strict_types=1);
require __DIR__ . '/common.php';
require __DIR__ . '/operational-common.php';
nd_require_authentication();
header('Cache-Control: no-store');
header("Content-Security-Policy: default-src 'none'; style-src 'self' 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");
function nd_date_filter(string $value): string {
    $date = DateTimeImmutable::createFromFormat('!Y-m-d', $value, new DateTimeZone('UTC'));
    if (!$date || $date->format('Y-m-d') !== $value) { http_response_code(400); exit('Choose valid dates.'); }
    return $value;
}
$from = nd_date_filter((string)($_GET['from'] ?? gmdate('Y-m-d', time()-29*86400)));
$to = nd_date_filter((string)($_GET['to'] ?? gmdate('Y-m-d')));
$method = (string)($_GET['method'] ?? 'all'); $version = (string)($_GET['version'] ?? '');
if ($from > $to || strtotime($from . ' UTC') < time()-91*86400 || strtotime($to . ' UTC') > time()+86400
    || !in_array($method, ['all','wifi','qr','usb','none'], true)
    || ($version !== '' && !preg_match('/^[0-9A-Za-z.+-]{1,80}$/D', $version))) {
    http_response_code(400); exit('Choose a valid retained date range, method and version.');
}
$error = ''; $events = []; $health = []; $truncated = false; $legacy = ['installs'=>0,'opens'=>0,'transfers'=>0];
try {
    $db = nd_db();
    $where = '((job_id IS NOT NULL AND job_started_at >= ? AND job_started_at <= ?) OR (job_id IS NULL AND occurred_at >= ? AND occurred_at <= ?))';
    $parameters = [$from.' 00:00:00',$to.' 23:59:59',$from.' 00:00:00',$to.' 23:59:59'];
    if ($method !== 'all') { $where .= ' AND method = ?'; $parameters[] = $method; }
    if ($version !== '') { $where .= ' AND app_version = ?'; $parameters[] = $version; }
    $query = $db->prepare('SELECT * FROM operational_events WHERE '.$where.' ORDER BY occurred_at,event_id LIMIT 50001');
    $query->execute($parameters); $events = $query->fetchAll();
    if (count($events)>50000) { array_pop($events); $truncated = true; }
    $query = $db->prepare('SELECT metric,SUM(value) AS total FROM operational_collector_health WHERE day >= ? AND day <= ? GROUP BY metric');
    $query->execute([$from,$to]); foreach ($query as $row) $health[$row['metric']] = (int)$row['total'];
    $query = $db->prepare("SELECT COUNT(DISTINCT installation_id) AS installs, SUM(CASE WHEN event_type='app_opened' THEN 1 ELSE 0 END) AS opens, SUM(CASE WHEN event_type='transfer_completed' THEN 1 ELSE 0 END) AS transfers FROM diagnostic_events WHERE occurred_at>=? AND occurred_at<=?");
    $query->execute([$from.' 00:00:00',$to.' 23:59:59']); $legacy = $query->fetch() ?: $legacy;
} catch (Throwable) { $error = 'Operational tables are not available. Prepare migration 004 in staging before an authorized rollout. Legacy reporting remains separate.'; }
$summary = nd_operational_summary($events, time()); $counts = $summary['counts'];
$denominator = $counts['completed']+$counts['failed'];
$successRate = $denominator > 0 ? round(100*$counts['completed']/$denominator,1).'%' : 'No eligible outcomes';
$firstAttempts = []; $firstSuccesses = []; $activeDays = []; $usbSuccess = 0; $troubleshooting = 0; $onboarded = [];
foreach ($events as $event) {
    $id = $event['installation_id']; $activeDays[$id][substr($event['occurred_at'],0,10)] = true;
    if (in_array($event['event_type'], ['transfer_started','usb_operation_started'], true)) $firstAttempts[$id] = true;
    if ($event['outcome'] === 'completed') $firstSuccesses[$id] = true;
    if ($event['event_type'] === 'usb_operation_finished' && $event['outcome'] === 'completed') $usbSuccess++;
    if ($event['event_type'] === 'troubleshooting_used') $troubleshooting++;
    if ($event['event_type'] === 'onboarding_completed') $onboarded[$id] = true;
}
$returning = count(array_filter($activeDays, fn($days)=>count($days)>1));
function nd_kpi(string $title, string|int $value): void {
    echo '<article class="card"><span>'.nd_h($title).'</span><strong>'.nd_h((string)$value).'</strong></article>';
}
function nd_distribution(string $title, array $values): void {
    echo '<section class="panel"><h3>'.nd_h($title).'</h3>';
    $max = max(array_merge([1], array_values($values))); arsort($values);
    if (!$values) echo '<p class="muted">No events in this cohort.</p>';
    foreach ($values as $label=>$count) echo '<div class="bar"><span>'.nd_h((string)$label).'</span><meter min="0" max="'.$max.'" value="'.(int)$count.'">'.(int)$count.'</meter><b>'.(int)$count.'</b></div>';
    echo '</section>';
}
?>
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Nearby Drop — Operational Diagnostics</title>
<style>
:root{color-scheme:dark;font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#10141e;color:#f3f6fc}body{margin:0;padding:28px}main{max-width:1200px;margin:auto}header{display:flex;justify-content:space-between;align-items:center;gap:20px}h1{font-size:28px;margin:0}h2{margin:30px 0 12px}h3{margin:0 0 14px;font-size:16px}a{color:#70dadd}.muted,.card span{color:#b6cbda}.cards,.charts{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px}.charts{grid-template-columns:repeat(auto-fit,minmax(300px,1fr))}.card,.panel{background:#162838;border:1px solid #456b80;border-radius:12px;padding:16px}.card strong{display:block;font-size:28px;margin-top:6px}.filters{display:flex;flex-wrap:wrap;gap:12px;margin:24px 0}.filters label{display:flex;flex-direction:column;gap:5px}input,select,button{font:inherit;color:inherit;background:#0b1724;border:1px solid #456b80;border-radius:6px;padding:9px}button{cursor:pointer;color:#70dadd}.bar{display:grid;grid-template-columns:130px 1fr 45px;gap:10px;align-items:center;margin:8px 0}.bar span{overflow-wrap:anywhere}meter{width:100%;accent-color:#70dadd}.notice{border-left:3px solid #f5a66f;padding:12px;background:#201e24}p{max-width:100ch}@media(max-width:600px){body{padding:16px}header{display:block}.charts{grid-template-columns:1fr}.bar{grid-template-columns:100px 1fr 35px}}
</style></head><body><main>
<header><div><h1>Operational diagnostics</h1><p class="muted">Schema 2 · explicit outcomes · installation IDs, not verified people</p></div><nav><a href="/">Legacy overview</a> · <a href="/?logout=1">Sign out</a></nav></header>
<form class="filters" method="get"><label>From, UTC<input type="date" name="from" value="<?=nd_h($from)?>" required></label><label>Through, UTC<input type="date" name="to" value="<?=nd_h($to)?>" required></label><label>Method<select name="method"><?php foreach(['all','wifi','qr','usb','none'] as $option):?><option value="<?=$option?>" <?=$method===$option?'selected':''?>><?=$option?></option><?php endforeach;?></select></label><label>App version<input name="version" value="<?=nd_h($version)?>" placeholder="All versions" maxlength="80"></label><button type="submit">Apply filters</button></form>
<?php if($error):?><p class="notice"><?=nd_h($error)?></p><?php endif;?>
<?php if($truncated):?><p class="notice">Results exceed 50,000 events. These metrics cover a truncated sample; narrow the filters before drawing conclusions.</p><?php endif;?>
<?php if ((nd_config()['preview_fixture'] ?? false) === true): ?><p class="notice">LOCAL FIXTURE DATA — not production activity.</p><?php endif; ?>
<h2>Reporting coverage</h2><section class="cards"><?php nd_kpi('Operational reporting installations',$summary['installations']); nd_kpi('Operational events',count($events)); nd_kpi('Successful USB outcome events',$usbSuccess); nd_kpi('Jobs missing every start event',$counts['missing_start']);?></section>
<p class="muted">Only schema 2 clients that opted into the approved rollout contribute operational data. Missing events from older clients are not failures. Identifiers are client-generated, unauthenticated reporting hints; counts are not fraud-proof user measurements.</p>
<h2>Transfer reliability</h2><section class="cards"><?php nd_kpi('Started jobs',$counts['attempted']);nd_kpi('Observed attempt IDs',$summary['attempts']);foreach(['completed','failed','cancelled','declined','pending','unknown'] as $key)nd_kpi(ucfirst($key).' jobs',$counts[$key]);nd_kpi('Observed final-outcome success',$successRate);?></section>
<p class="muted">Jobs are grouped by installation + job ID; the latest numbered attempt wins, regardless of delivery order. A terminal event overrides its start. Conflicting terminal events are unknown. Missing terminal outcomes stay pending for 24 hours, then unknown—not failed. The success percentage is completed ÷ (completed + failed), excluding cancelled, declined, pending, unknown, and jobs without a start event. Cohorts use job start time; late events can revise earlier cohorts.</p>
<h2>Activation and repeat reporting</h2><section class="cards"><?php nd_kpi('Onboarding completion installations',count($onboarded));nd_kpi('Installations with a transfer start',count($firstAttempts));nd_kpi('Installations with an explicit success',count($firstSuccesses));nd_kpi('Reporting on two or more UTC days',$returning);nd_kpi('Sampled troubleshooting events',$troubleshooting);?></section>
<p class="muted">These are milestones observed within the selected range, not lifetime first-ever conversions. We cannot attribute a later success to troubleshooting from these events alone. UI/health events are sampled at most once per installation per day.</p>
<h2>Performance, troubleshooting and coverage</h2><div class="charts"><?php foreach(['method'=>'Event mix by method','duration_bucket'=>'Events by duration category','stage'=>'Events by observed stage','error_category'=>'Events by error category','app_version'=>'Events by app version','queue_bucket'=>'Reported queue-depth event categories'] as $field=>$title)nd_distribution($title,$summary['histograms'][$field]??[]);?></div>
<p class="muted">Distributions count events, not people or distinct jobs. Start events can have short durations; this chart is not a throughput benchmark. Sizes, counts, durations and stage timings are coarse categories, not payload metadata.</p>
<h2>Collector health</h2><section class="cards"><?php foreach(['accepted'=>'New events accepted','duplicates'=>'Duplicate deliveries','rejected'=>'Invalid events rejected','delayed_over_hour'=>'Deliveries delayed over one hour','server_errors'=>'Database-visible server errors'] as $key=>$label)nd_kpi($label,$health[$key]??0);?></section>
<p class="muted">Health uses receipt-day totals for the selected dates, across all methods and versions. Event cohorts use occurrence/job-start dates. A database outage can prevent its own error counters from being written. Queue depth covers reporting clients only; no events does not prove a service outage. Events and health counters retain 90 days.</p>
<h2>Legacy coverage, kept separate</h2><section class="cards"><?php nd_kpi('Legacy reporting installations',(int)$legacy['installs']);nd_kpi('Legacy app-open events',(int)$legacy['opens']);nd_kpi('Legacy successful wireless events',(int)$legacy['transfers']);?></section><p class="muted">Legacy figures use the selected event dates only; method/version filters above apply to schema 2. The two systems overlap and must not be added together. Legacy events contain no attempted-job denominator.</p>
</main></body></html>
