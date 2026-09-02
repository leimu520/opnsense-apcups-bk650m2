#!/usr/local/bin/php
<?php

$target = $argv[1] ?? 'BK650M2@localhost';
if (!preg_match('/^[0-9A-Za-z._:-]+(@[0-9A-Za-z._:-]+)?$/', $target)) {
    echo json_encode([
        'connected' => false,
        'message' => 'Invalid UPS target',
    ]);
    exit(1);
}

function query_ups($target) {
    $command = 'stdbuf -o0 /usr/local/bin/upsc ' . escapeshellarg($target) . ' 2>&1';
    exec($command, $lines, $returnCode);

    $vars = [];
    foreach ($lines as $line) {
        $parts = explode(':', $line, 2);
        if (count($parts) === 2) {
            $vars[trim($parts[0])] = trim($parts[1]);
        }
    }

    return [$returnCode, $vars, $lines];
}

$returnCode = 1;
$vars = [];
$lines = [];

// Retry a few times to tolerate transient upsc failures/segfaults.
for ($attempt = 1; $attempt <= 3; $attempt++) {
    [$returnCode, $vars, $lines] = query_ups($target);
    if ($returnCode === 0 || isset($vars['ups.status']) || isset($vars['battery.charge'])) {
        break;
    }
    if ($attempt < 3) {
        usleep(500000);
    }
}

if ($returnCode !== 0 && !isset($vars['ups.status']) && !isset($vars['battery.charge'])) {
    echo json_encode([
        'connected' => false,
        'target' => $target,
        'message' => trim(implode("\n", $lines)),
    ]);
    exit(0);
}

$status = $vars['ups.status'] ?? '';
$statusText = '未知';
if (strpos($status, 'OL') !== false) {
    $statusText = '在线';
} elseif (strpos($status, 'OB') !== false) {
    $statusText = '电池供电';
}
if (strpos($status, 'LB') !== false) {
    $statusText .= ' / 低电量';
}

$runtimeSeconds = isset($vars['battery.runtime']) ? (int)$vars['battery.runtime'] : null;
$runtimeText = null;
if ($runtimeSeconds !== null) {
    $runtimeText = sprintf('%02d:%02d:%02d', intdiv($runtimeSeconds, 3600), intdiv($runtimeSeconds % 3600, 60), $runtimeSeconds % 60);
}

echo json_encode([
    'connected' => true,
    'target' => $target,
    'raw_status' => $status,
    'status_text' => $statusText,
    'charge' => $vars['battery.charge'] ?? null,
    'runtime_seconds' => $runtimeSeconds,
    'runtime_text' => $runtimeText,
    'load' => $vars['ups.load'] ?? null,
    'input_voltage' => $vars['input.voltage'] ?? null,
    'output_voltage' => $vars['output.voltage'] ?? null,
    'battery_voltage' => $vars['battery.voltage'] ?? null,
    'model' => $vars['device.model'] ?? ($vars['ups.model'] ?? null),
    'manufacturer' => $vars['device.mfr'] ?? null,
    'serial' => $vars['device.serial'] ?? null,
    'message' => $returnCode === 0 ? 'OK' : 'UPS 数据已读取，upsc 退出码：' . $returnCode,
], JSON_UNESCAPED_SLASHES);
