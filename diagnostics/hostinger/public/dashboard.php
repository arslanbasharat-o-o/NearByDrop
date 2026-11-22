<?php
declare(strict_types=1);
require_once __DIR__.'/common.php';
require_once __DIR__.'/operational-common.php';
nd_require_authentication();
header('Cache-Control: no-store');
header("Content-Security-Policy: default-src 'none'; style-src 'self' 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");
function nd_dashboard_date(string $value): string {
 $d=DateTimeImmutable::createFromFormat('!Y-m-d',$value,new DateTimeZone('UTC'));
 if(!$d||$d->format('Y-m-d')!==$value){http_response_code(400);exit('Choose valid dates.');}
 return $value;
}
function nd_label(string $value): string {
 return ['wifi'=>'Wi-Fi','qr'=>'QR','usb'=>'USB','none'=>'—','incoming'=>'Receive','outgoing'=>'Send','pending'=>'In progress','completed'=>'Completed','failed'=>'Failed','cancelled'=>'Cancelled','declined'=>'Declined','unknown'=>'Unknown','preparing'=>'Preparing','connecting'=>'Connecting','approval'=>'Waiting for approval','transferring'=>'Transferring','file_access'=>'File access','source_changed'=>'Source changed','connection'=>'Connection','network'=>'Network','other'=>'Other','lt1s'=>'Under 1 s','1to5s'=>'1–5 s','5to30s'=>'5–30 s','30to120s'=>'30 s–2 min','120to600s'=>'2–10 min','600plus'=>'Over 10 min','client_health'=>'App health','transfer_started'=>'Transfer started','transfer_completed'=>'Transfer completed','transfer_failed'=>'Transfer failed','transfer_cancelled'=>'Transfer cancelled','transfer_declined'=>'Transfer declined','usb_operation_started'=>'USB started','usb_operation_finished'=>'USB finished','onboarding_completed'=>'Setup completed','troubleshooting_used'=>'Connection Doctor opened','zero'=>'0','one'=>'1','2to10'=>'2–10','11to50'=>'11–50','51to128'=>'51–128','129plus'=>'129+','lt1mb'=>'Under 1 MB','1to10mb'=>'1–10 MB','10to100mb'=>'10–100 MB','100mbto1gb'=>'100 MB–1 GB','1gbplus'=>'Over 1 GB','1to10'=>'1–10','51plus'=>'51+'][$value]??$value;
}
function nd_stat(string $label,int|string $value,string $note): void {
 echo '<article class="stat"><span>'.nd_h($label).'</span><strong>'.nd_h(is_int($value)?number_format($value):$value).'</strong><small>'.nd_h($note).'</small></article>';
}
function nd_bars(string $title,array $values): void {
 echo '<article class="panel"><h3>'.nd_h($title).'</h3>';
 arsort($values);$max=max(array_merge([1],array_values($values)));
 if(!$values)echo '<p class="empty">No reports for this selection.</p>';
 foreach(array_slice($values,0,10,true) as $label=>$count)echo '<div class="bar"><span>'.nd_h(nd_label((string)$label)).'</span><meter min="0" max="'.$max.'" value="'.(int)$count.'">'.(int)$count.'</meter><b>'.number_format((int)$count).'</b></div>';
 if(count($values)>10)echo '<p class="muted">Top 10 shown.</p>';
 echo '</article>';
}
function nd_pager(string $key,int $page,int $total,string $anchor): void {
 $pages=max(1,(int)ceil($total/50));
 echo '<nav class="pager" aria-label="'.nd_h($anchor).' pages"><span>'.number_format($total).' records · Page '.$page.' of '.$pages.'</span><div>';
 foreach(['Previous'=>$page-1,'Next'=>$page+1] as $label=>$target)if($target>=1&&$target<=$pages){$q=$_GET;$q[$key]=$target;echo '<a class="button subtle" href="/?'.nd_h(http_build_query($q)).'#'.nd_h($anchor).'">'.$label.'</a>';}
 echo '</div></nav>';
}
$from=nd_dashboard_date((string)($_GET['from']??gmdate('Y-m-d',time()-29*86400)));
$to=nd_dashboard_date((string)($_GET['to']??gmdate('Y-m-d')));
$method=(string)($_GET['method']??'all');$version=trim((string)($_GET['version']??''));
$page=filter_var($_GET['page']??1,FILTER_VALIDATE_INT,['options'=>['min_range'=>1,'max_range'=>1000000]]);
$eventPage=filter_var($_GET['event_page']??1,FILTER_VALIDATE_INT,['options'=>['min_range'=>1,'max_range'=>1000000]]);
if($from>$to||!in_array($method,['all','wifi','qr','usb','none'],true)||($version!==''&&!preg_match('/^[0-9A-Za-z.+-]{1,80}$/D',$version))||$page===false||$eventPage===false){http_response_code(400);exit('Choose a valid date range, method and app version.');}
$dates=[$from.' 00:00:00',$to.' 23:59:59'];$base='occurred_at>=? AND occurred_at<=?';$args=$dates;
if($version!==''){$base.=' AND app_version=?';$args[]=$version;}
$error='';$opError='';$events=[];$health=[];$devices=[];$transfers=[];$recent=[];$versions=[];$daily=[];$installations=[];$basic=['opens'=>0,'transfers'=>0];$opTotal=0;$historyTotal=0;$truncated=false;$lastReceived=null;
try {
 $db=nd_db();
 // Dashboard requests never run cleanup or write to the reporting database.
 $query=function(string $sql,array $parameters=[])use($db):PDOStatement{$s=$db->prepare($sql);$s->execute($parameters);return $s;};
 $basic=$query("SELECT SUM(CASE WHEN event_type='app_opened' THEN 1 ELSE 0 END) AS opens,SUM(CASE WHEN event_type='transfer_completed' THEN 1 ELSE 0 END) AS transfers FROM diagnostic_events WHERE $base",$args)->fetch()?:$basic;
 foreach($query("SELECT DISTINCT installation_id FROM diagnostic_events WHERE $base",$args) as $row)$installations[strtolower($row['installation_id'])]=true;
 $devices=$query("SELECT * FROM (SELECT installation_id,mac_name,mac_model,app_version,macos_version,occurred_at,ROW_NUMBER() OVER(PARTITION BY installation_id ORDER BY occurred_at DESC,event_id DESC) AS rn FROM diagnostic_events WHERE $base AND event_type='app_opened') latest WHERE rn=1 ORDER BY occurred_at DESC LIMIT 100",$args)->fetchAll();
 $historyTotal=(int)$query("SELECT COUNT(*) FROM diagnostic_events WHERE $base AND event_type='transfer_completed'",$args)->fetchColumn();
 $page=min($page,max(1,(int)ceil($historyTotal/50)));
 $offset=($page-1)*50;
 $transfers=$query("SELECT * FROM diagnostic_events WHERE $base AND event_type='transfer_completed' ORDER BY occurred_at DESC,event_id DESC LIMIT 50 OFFSET $offset",$args)->fetchAll();
 $daily=$query("SELECT SUBSTR(occurred_at,1,10) AS day,COUNT(*) AS total FROM diagnostic_events WHERE $base AND event_type='app_opened' GROUP BY SUBSTR(occurred_at,1,10) ORDER BY day DESC LIMIT 31",$args)->fetchAll();
 $versions=$query('SELECT DISTINCT app_version FROM diagnostic_events ORDER BY app_version DESC')->fetchAll(PDO::FETCH_COLUMN);
 try {
  $where='((job_id IS NOT NULL AND job_started_at>=? AND job_started_at<=?) OR (job_id IS NULL AND occurred_at>=? AND occurred_at<=?))';$params=array_merge($dates,$dates);
  if($method!=='all'){$where.=' AND method=?';$params[]=$method;}
  if($version!==''){$where.=' AND app_version=?';$params[]=$version;}
  $events=$query("SELECT * FROM operational_events WHERE $where ORDER BY occurred_at,event_id LIMIT 50001",$params)->fetchAll();
  if(count($events)>50000){array_pop($events);$truncated=true;}
  foreach($query("SELECT DISTINCT installation_id FROM operational_events WHERE $base",$args) as $row)$installations[strtolower($row['installation_id'])]=true;
  $opTotal=(int)$query("SELECT COUNT(*) FROM operational_events WHERE $where",$params)->fetchColumn();
  $eventPage=min($eventPage,max(1,(int)ceil($opTotal/50)));
  $offset=($eventPage-1)*50;
  $recent=$query("SELECT * FROM operational_events WHERE $where ORDER BY occurred_at DESC,event_id DESC LIMIT 50 OFFSET $offset",$params)->fetchAll();
  foreach($query('SELECT metric,SUM(value) AS total FROM operational_collector_health WHERE day>=? AND day<=? GROUP BY metric',[$from,$to]) as $row)$health[$row['metric']]=(int)$row['total'];
  $lastReceived=$query('SELECT MAX(received_at) FROM operational_events')->fetchColumn()?:null;
  $versions=array_unique(array_merge($versions,$query('SELECT DISTINCT app_version FROM operational_events ORDER BY app_version DESC')->fetchAll(PDO::FETCH_COLUMN)));
 }catch(Throwable){$opError='Detailed reports are unavailable right now. Existing app activity and transfer records are still shown.';}
}catch(Throwable){http_response_code(503);$error='Reports could not be loaded. Please try again shortly.';}
$summary=nd_operational_summary($events,time());$counts=$summary['counts'];$finished=$counts['completed']+$counts['failed'];$rate=$finished?round(100*$counts['completed']/$finished,1).'%':'—';
$transferHist=nd_operational_summary(array_filter($events,fn($r)=>$r['job_id']!==null),time())['histograms'];
$macVersions=array_count_values(array_column($devices,'app_version'));
?>
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Nearby Drop Diagnostics</title><link rel="stylesheet" href="/dashboard.css"></head><body>
<a class="skip" href="#overview">Skip to reports</a>
<aside class="sidebar"><a class="brand" href="/">Nearby Drop<span>Diagnostics</span></a><nav aria-label="Sections"><a href="#overview">Overview</a><a href="#reliability">Transfers</a><a href="#reports">Recent reports</a><a href="#devices">Macs &amp; history</a><a href="#collector">Collector</a></nav><div class="sidebar-bottom"><span class="status-dot"></span> Private dashboard<br><a href="/?logout=1">Sign out ↗</a></div></aside>
<main class="workspace"><header class="page-header"><div><p class="eyebrow">NEARBY DROP / REPORTS</p><h1>Diagnostics</h1><p class="muted">App activity, transfer results and connection issues.</p></div><a class="button subtle" href="/?<?=nd_h(http_build_query($_GET))?>">Refresh reports ↻</a></header>
<form class="filters" method="get" action="/"><label>From<input type="date" name="from" value="<?=nd_h($from)?>" required></label><label>To<input type="date" name="to" value="<?=nd_h($to)?>" required></label><label>App version<select name="version"><option value="">All versions</option><?php if($version!==''&&!in_array($version,$versions,true))$versions[]=$version;foreach($versions as $v):?><option value="<?=nd_h($v)?>" <?=$version===$v?'selected':''?>><?=nd_h($v)?></option><?php endforeach;?></select></label><label>Transfer method<select name="method"><?php foreach(['all'=>'All methods','wifi'=>'Wi-Fi','qr'=>'QR','usb'=>'USB','none'=>'App events'] as $v=>$label):?><option value="<?=$v?>" <?=$method===$v?'selected':''?>><?=$label?></option><?php endforeach;?></select></label><button type="submit">Apply</button><a href="/">Reset</a><p class="filter-note">Dates use UTC. Method filters apply to detailed reports.</p></form>
<?php if($error):?><p class="notice error" role="alert"><?=nd_h($error)?></p><?php endif;?><?php if($opError):?><p class="notice" role="status"><?=nd_h($opError)?></p><?php endif;?><?php if($truncated):?><p class="notice">Charts use the first 50,000 detailed reports. Narrow the dates for complete charts; report pages still include every matching record.</p><?php endif;?><?php if((nd_config()['preview_fixture']??false)===true):?><p class="notice">LOCAL FIXTURE DATA — not production activity.</p><?php endif;?>
<section id="overview"><div class="section-heading"><h2>Overview</h2><span><?=nd_h($from)?> — <?=nd_h($to)?></span></div><div class="stats"><?php nd_stat('Reporting Macs',count($installations),'Distinct installation IDs');nd_stat('App opens',(int)$basic['opens'],'Recorded app launches');nd_stat('Completed wireless transfers',(int)$basic['transfers'],'Basic transfer reports');nd_stat('Transfer success',$rate,$finished?'Based on completed and failed jobs':'Awaiting detailed transfer results');?></div><div class="overview-grid"><?php nd_bars('App opens by day',array_column($daily,'total','day'));nd_bars('Recent Mac versions',$macVersions);?></div></section>
<section id="reliability"><div class="section-heading"><div><h2>Transfer results</h2><p>Detailed reports from newer app builds.</p></div><span><?=number_format($opTotal)?> reports</span></div><div class="result-strip"><?php foreach(['attempted'=>'Started jobs','completed'=>'Completed jobs','failed'=>'Failed jobs','cancelled'=>'Cancelled','declined'=>'Declined','pending'=>'In progress','unknown'=>'Unknown jobs'] as $k=>$label):?><div><span class="result-label"><?=nd_h($label)?></span><strong class="<?=in_array($k,['completed','failed'],true)?$k:''?>"><?=number_format($counts[$k])?></strong></div><?php endforeach;?></div><div class="chart-grid"><?php nd_bars('Error categories',array_filter($transferHist['error_category']??[],fn($k)=>$k!=='none',ARRAY_FILTER_USE_KEY));nd_bars('Transfer method',$transferHist['method']??[]);nd_bars('Connection time',$transferHist['connection_duration_bucket']??[]);nd_bars('Approval wait',$transferHist['approval_duration_bucket']??[]);?></div><details class="definitions"><summary>How transfer results are counted</summary><p>Retries belong to one job. The latest attempt decides the result. A missing result is in progress for 24 hours, then unknown. Cancelled, declined and unknown jobs do not enter the success rate. <?=$counts['missing_start']?> jobs lack a start report and are excluded. Basic reports contain successful transfers only and are kept separate to avoid double-counting. Reporting IDs identify app installations, not verified people.</p><p>Charts count reports, not transfer speeds or unique users. Health counters use receipt dates across all methods and versions.</p></details></section>
<section id="reports"><div class="section-heading"><h2>Recent reports</h2><span>Newest first · UTC</span></div><div class="table-wrap"><table><caption class="sr-only">Detailed app and transfer reports</caption><thead><tr><th>Time</th><th>Event</th><th>Method</th><th>Stage</th><th>Result</th><th>Error</th><th>App / macOS</th></tr></thead><tbody><?php foreach($recent as $r):?><tr><td class="date"><?=nd_h(substr($r['occurred_at'],0,19))?></td><td><?=nd_h(nd_label($r['event_type']))?><small><?=nd_h(nd_label($r['direction']))?></small></td><td><?=nd_h(nd_label($r['method']))?></td><td><?=nd_h(nd_label($r['stage']))?></td><td><span class="badge <?=nd_h($r['outcome'])?>"><?=nd_h(nd_label($r['outcome']))?></span></td><td><?=nd_h(nd_label($r['error_category']))?></td><td><?=nd_h($r['app_version'])?> / <?=nd_h($r['macos_version'])?></td></tr><?php endforeach;?><?php if(!$recent):?><tr><td colspan="7" class="empty">No detailed reports for this selection. Older app builds only send basic activity and successful transfers.</td></tr><?php endif;?></tbody></table></div><?php nd_pager('event_page',$eventPage,$opTotal,'reports');?></section>
<section id="devices"><div class="section-heading"><h2>Reporting Macs</h2><span>Latest app-open report · up to 100 installations</span></div><div class="table-wrap"><table><thead><tr><th>Mac</th><th>Model</th><th>App</th><th>macOS</th><th>Last opened, UTC</th></tr></thead><tbody><?php foreach($devices as $r):?><tr><td class="device-name"><?=nd_h($r['mac_name'])?></td><td><?=nd_h($r['mac_model'])?></td><td><?=nd_h($r['app_version'])?></td><td><?=nd_h($r['macos_version'])?></td><td class="date"><?=nd_h(substr($r['occurred_at'],0,19))?></td></tr><?php endforeach;?><?php if(!$devices):?><tr><td colspan="5" class="empty">No app-open reports for this selection.</td></tr><?php endif;?></tbody></table></div><div class="section-heading subheading"><h2>Wireless transfer history</h2><span>Basic reports · successful transfers only</span></div><div class="table-wrap"><table><thead><tr><th>Time, UTC</th><th>Mac</th><th>Other device</th><th>Direction</th><th>App / macOS</th></tr></thead><tbody><?php foreach($transfers as $r):?><tr><td class="date"><?=nd_h(substr($r['occurred_at'],0,19))?></td><td class="device-name"><?=nd_h($r['mac_name'])?></td><td><?=nd_h($r['peer_name']??'—')?><small><?=nd_h($r['peer_type']??'')?></small></td><td><?=nd_h(nd_label($r['transfer_direction']??'none'))?></td><td><?=nd_h($r['app_version'])?> / <?=nd_h($r['macos_version'])?></td></tr><?php endforeach;?><?php if(!$transfers):?><tr><td colspan="5" class="empty">No completed transfers for this selection.</td></tr><?php endif;?></tbody></table></div><?php nd_pager('page',$page,$historyTotal,'devices');?></section>
<section id="collector"><div class="section-heading"><div><h2>Collector health</h2><p>Last detailed report received: <?=nd_h($lastReceived?substr($lastReceived,0,19).' UTC':'No reports yet')?></p></div><span class="badge <?= (nd_config()['operational_enabled']??false)?'completed':'unknown'?>"><?= (nd_config()['operational_enabled']??false)?'Collection enabled':'Collection paused'?></span></div><div class="health-strip"><?php foreach(['accepted'=>'Accepted','duplicates'=>'Duplicate deliveries','rejected'=>'Rejected','delayed_over_hour'=>'Delayed over 1 hour','server_errors'=>'Server errors'] as $k=>$label):?><div><strong><?=number_format($health[$k]??0)?></strong><span><?=$label?></span></div><?php endforeach;?></div><details class="definitions"><summary>Report details</summary><div class="chart-grid"><?php foreach(['macos_version'=>'macOS versions','size_bucket'=>'Payload sizes','count_bucket'=>'Files per transfer','duration_bucket'=>'Attempt duration','queue_bucket'=>'Client queue depth'] as $field=>$title)nd_bars($title,$summary['histograms'][$field]??[]);?></div><p>Viewing reports never changes or deletes records. Device names are supplied by the reporting apps. Detailed reports do not include filenames or file contents.</p></details></section>
<footer>Nearby Drop Diagnostics <span>Updated <?=gmdate('H:i')?> UTC · <a href="#overview">Back to top ↑</a></span></footer></main></body></html>
