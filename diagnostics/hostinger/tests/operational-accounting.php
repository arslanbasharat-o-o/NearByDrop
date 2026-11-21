<?php
declare(strict_types=1);
require __DIR__.'/../public/common.php';
require __DIR__.'/../public/operational-common.php';
function check(bool $condition, string $message): void { if (!$condition) throw new RuntimeException($message); }
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
$fail = $start; $fail['event_type']='transfer_failed'; $fail['outcome']='failed';
$retry = $start; $retry['attempt_id']='30000000-0000-4000-8000-000000000002'; $retry['attempt_number']=2;
$complete = $retry; $complete['event_type']='transfer_completed'; $complete['outcome']='completed';
for($i=0;$i<40;$i++) {
 $events=[$start,$fail,$retry,$complete]; shuffle($events); $s=nd_operational_summary($events,$now);
 check($s['counts']['attempted']===1 && $s['attempts']===2 && $s['counts']['completed']===1 && $s['counts']['failed']===0,'Retries/order inflated jobs');
}
$old=$start; $old['job_started_at']=gmdate('Y-m-d H:i:s',$now-90001);
$s=nd_operational_summary([$old],$now);check($s['counts']['unknown']===1 && $s['counts']['failed']===0,'Missing terminal became failed');
$s=nd_operational_summary([$complete],$now);check($s['counts']['missing_start']===1 && $s['counts']['attempted']===0,'Missing start silently entered denominator');
$conflict=$complete; $conflict['outcome']='failed'; $conflict['event_type']='transfer_failed';
$s=nd_operational_summary([$retry,$complete,$conflict],$now);check($s['counts']['unknown']===1,'Conflicting terminals became success');
$other=$start;$other['installation_id']='10000000-0000-4000-8000-000000000002';
check(nd_operational_summary([$start,$other],$now)['counts']['attempted']===2,'Cross-installation ID collision');
foreach (['mac_name'=>'Personal Mac','file_name'=>'private.txt','peer_name'=>'Phone','content'=>'secret','schema_version'=>1,'outcome'=>'completed','occurred_at'=>'tomorrow','method'=>'usb'] as $key=>$value) {
 $bad=$base;$bad[$key]=$value;$rejected=false;
 try { nd_validate_operational($bad,$now); } catch(Throwable) { $rejected=true; }
 check($rejected,'Unsafe/invalid field accepted: '.$key);
}
$db=new PDO('sqlite::memory:');$db->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
$db->exec((string)file_get_contents(__DIR__.'/../migrations/004-operational.sql'));
nd_operational_health($db,'accepted');nd_operational_health($db,'accepted');
check((int)$db->query("SELECT value FROM operational_collector_health WHERE metric='accepted'")->fetchColumn()===2,'Health counter did not increment');
$db->exec('CREATE TABLE diagnostic_events(event_id TEXT PRIMARY KEY,installation_id TEXT,event_type TEXT,occurred_at TEXT,mac_name TEXT,peer_name TEXT,transfer_direction TEXT)');
$date=gmdate('Y-m-d H:00:00',$now);
$stmt=$db->prepare('INSERT INTO diagnostic_events VALUES(?,?,?,?,?,?,?)');
foreach(['a','b'] as $id)$stmt->execute([$id,'install','transfer_completed',$date,'same name','same phone','outgoing']);
nd_cleanup($db);check((int)$db->query('SELECT COUNT(*) FROM diagnostic_events')->fetchColumn()===2,'Cleanup deleted distinct same-hour transfers');
echo "Operational accounting passed: retries, ordering, unknown/pending, conflicts, coverage, privacy, health and retention.\n";
