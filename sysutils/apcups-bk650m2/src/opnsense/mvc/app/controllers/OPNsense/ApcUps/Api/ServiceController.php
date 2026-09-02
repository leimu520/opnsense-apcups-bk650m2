<?php

namespace OPNsense\ApcUps\Api;

use OPNsense\ApcUps\ApcUps;
use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiControllerBase
{
    private function getUpsTarget()
    {
        $model = new ApcUps();
        $upsName = (string)$model->general->upsName;
        if (!preg_match('/^[0-9a-zA-Z._-]{1,64}$/', $upsName)) {
            $upsName = 'BK650M2';
        }
        return $upsName . '@localhost';
    }

    public function statusAction()
    {
        if ($this->request->isPost()) {
            $response = trim((new Backend())->configdRun('apcupsbk650m2 status ' . $this->getUpsTarget()));
            $decoded = json_decode($response, true);
            if (is_array($decoded)) {
                return $decoded;
            }
            return ["connected" => false, "message" => $response];
        }
        return ["connected" => false, "message" => "POST required"];
    }

    public function reloadAction()
    {
        if ($this->request->isPost()) {
            $backend = new Backend();
            $templateStatus = strtolower(trim($backend->configdRun('template reload OPNsense/ApcUps')));
            $serviceStatus = strtolower(trim($backend->configdRun('apcupsbk650m2 restart')));
            return ["template" => $templateStatus, "service" => $serviceStatus];
        }
        return ["template" => "failed", "service" => "failed"];
    }

    public function restartAction()
    {
        if ($this->request->isPost()) {
            $status = strtolower(trim((new Backend())->configdRun('apcupsbk650m2 restart')));
            return ["status" => $status];
        }
        return ["status" => "failed"];
    }

    public function diagnosticsAction()
    {
        if ($this->request->isPost()) {
            $response = trim((new Backend())->configdRun('apcupsbk650m2 diagnostics ' . $this->getUpsTarget()));
            $decoded = json_decode($response, true);
            if (is_array($decoded)) {
                return $decoded;
            }
            return ["ok" => false, "message" => $response];
        }
        return ["ok" => false, "message" => "POST required"];
    }

    public function testNotifyAction()
    {
        if (!$this->request->isPost()) {
            return ["status" => "failed", "message" => "POST required"];
        }

        $channel = $this->request->getPost('channel', 'string', '');
        $allowed = ['email', 'wechat_bot', 'wechat_app', 'sms'];
        if ($channel !== 'all' && !in_array($channel, $allowed, true)) {
            return ["status" => "failed", "message" => "invalid channel"];
        }

        $model = new ApcUps();
        $baseCfg = [
            'enabled' => true,
            'shutdown_mode' => (string)$model->shutdown->mode,
            'battery_shutdown_threshold' => (int)(string)$model->shutdown->batteryShutdownThreshold,
            'email_enabled' => (string)$model->notifications->emailEnabled === '1',
            'email_smtp_host' => (string)$model->notifications->emailSmtpHost,
            'email_smtp_port' => (int)(string)$model->notifications->emailSmtpPort,
            'email_smtp_username' => (string)$model->notifications->emailSmtpUsername,
            'email_smtp_password' => (string)$model->notifications->emailSmtpPassword,
            'email_from' => (string)$model->notifications->emailFrom,
            'email_to' => (string)$model->notifications->emailTo,
            'email_use_tls' => (string)$model->notifications->emailUseTls === '1',
            'wechat_bot_enabled' => (string)$model->notifications->wechatBotEnabled === '1',
            'wechat_bot_webhook' => (string)$model->notifications->wechatBotWebhook,
            'wechat_app_enabled' => (string)$model->notifications->wechatAppEnabled === '1',
            'wechat_app_corp_id' => (string)$model->notifications->wechatAppCorpId,
            'wechat_app_corp_secret' => (string)$model->notifications->wechatAppCorpSecret,
            'wechat_app_agent_id' => (string)$model->notifications->wechatAppAgentId,
            'wechat_app_to_user' => (string)$model->notifications->wechatAppToUser,
            'sms_enabled' => (string)$model->notifications->smsEnabled === '1',
            'sms_provider' => (string)$model->notifications->smsProvider,
            'sms_api_url' => (string)$model->notifications->smsApiUrl,
            'sms_api_key' => (string)$model->notifications->smsApiKey,
            'sms_api_secret' => (string)$model->notifications->smsApiSecret,
            'sms_phone_number' => (string)$model->notifications->smsPhoneNumber,
            'sms_template_code' => (string)$model->notifications->smsTemplateCode,
            'sms_sign_name' => (string)$model->notifications->smsSignName,
            'battery_alert_enabled' => (string)$model->notifications->batteryAlertEnabled === '1',
            'battery_alert_threshold' => (int)(string)$model->notifications->batteryAlertThreshold,
        ];

        $channelsToTest = $channel === 'all' ? $allowed : [$channel];
        $results = [];
        $hostname = gethostname() ?: 'OPNsense';
        $subject = $hostname . '-UPS告警通知';
        $body = '[' . $hostname . ']上的UPS已进入电池供电模式，预计续航30分钟，请及时检查市电情况或关闭其他设备';

        foreach ($channelsToTest as $ch) {
            // Skip channels that are not enabled when testing all enabled channels.
            if ($channel === 'all' && !$baseCfg[$ch . '_enabled']) {
                continue;
            }

            $cfg = $baseCfg;
            // Force only the current channel on for the test run.
            foreach ($allowed as $a) {
                $cfg[$a . '_enabled'] = ($a === $ch);
            }

            $tmpFile = '/tmp/apcups_notify_test_' . $ch . '.conf';
            $written = file_put_contents($tmpFile, json_encode($cfg, JSON_UNESCAPED_UNICODE));
            if ($written === false) {
                $results[$ch] = ['status' => 'failed', 'output' => 'failed to write temporary config'];
                continue;
            }

            $cmd = '/usr/local/bin/python3 /usr/local/opnsense/scripts/apcupsbk650m2/notify.py '
                 . '--config ' . escapeshellarg($tmpFile) . ' '
                 . '--channel ' . escapeshellarg($ch) . ' '
                 . escapeshellarg($subject) . ' ' . escapeshellarg($body) . ' 2>&1';
            exec($cmd, $output, $returnCode);
            @unlink($tmpFile);

            $results[$ch] = [
                'status' => $returnCode === 0 ? 'ok' : 'failed',
                'output' => implode("\n", $output),
            ];
        }

        $overall = 'ok';
        foreach ($results as $res) {
            if ($res['status'] !== 'ok') {
                $overall = count($results) > 0 ? 'partial' : 'failed';
                break;
            }
        }
        if (empty($results)) {
            $overall = 'failed';
        }

        return [
            'status' => $overall,
            'channels' => $results,
        ];
    }
}
