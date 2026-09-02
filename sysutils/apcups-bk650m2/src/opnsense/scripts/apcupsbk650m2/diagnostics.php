#!/usr/local/bin/php
<?php

function run_command($label, $command)
{
    exec('stdbuf -o0 ' . $command . ' 2>&1', $lines, $returnCode);
    return [
        'label' => $label,
        'command' => $command,
        'exit_code' => $returnCode,
        'output' => trim(implode("\n", $lines)),
    ];
}

$target = $argv[1] ?? 'BK650M2@localhost';
if (!preg_match('/^[0-9A-Za-z._:-]+(@[0-9A-Za-z._:-]+)?$/', $target)) {
    echo json_encode([
        'ok' => false,
        'message' => 'Invalid UPS target',
    ]);
    exit(1);
}

$checks = [];
$checks[] = run_command('通过 upsc 查看 UPS 状态', '/usr/local/bin/upsc ' . escapeshellarg($target));
$checks[] = run_command('NUT 服务状态', '/usr/sbin/service nut status');
$checks[] = run_command('NUT upsmon 状态', '/usr/sbin/service nut_upsmon status');
$checks[] = run_command('USB 设备', '/usr/sbin/usbconfig');
$checks[] = run_command('NUT 配置文件列表', '/bin/ls -l /usr/local/etc/nut');
$checks[] = run_command('ups.conf', '/bin/cat /usr/local/etc/nut/ups.conf');
$checks[] = run_command('upsmon.conf 中的 MONITOR 行', '/usr/bin/grep -n "^[[:space:]]*MONITOR" /usr/local/etc/nut/upsmon.conf');
$checks[] = run_command('最近的 UPS/NUT 日志', '/bin/sh -c "/usr/sbin/clog /var/log/system/latest.log 2>/dev/null | /usr/bin/grep -Ei \"nut|ups|apcups|BK650M2|unavailable\" | /usr/bin/tail -n 80"');

echo json_encode([
    'ok' => true,
    'target' => $target,
    'checks' => $checks,
], JSON_UNESCAPED_SLASHES);
