<script type="text/javascript">
$(document).ready(function() {
    function valueOrDash(value, suffix) {
        if (value === undefined || value === null || value === "") {
            return "-";
        }
        return suffix ? value + suffix : value;
    }

    function setStatus(data) {
        $("#upsConnection").text(data.connected ? "已连接" : "已断开");
        $("#upsStatus").text(valueOrDash(data.status_text));
        $("#upsCharge").text(valueOrDash(data.charge, "%"));
        $("#upsRuntime").text(valueOrDash(data.runtime_text));
        $("#upsLoad").text(valueOrDash(data.load, "%"));
        $("#upsInput").text(valueOrDash(data.input_voltage, " V"));
        $("#upsModel").text(valueOrDash(data.model));
        $("#upsSerial").text(valueOrDash(data.serial));
        $("#upsMessage").text(valueOrDash(data.message));
    }

    function refreshStatus(done) {
        ajaxCall(url="/api/apcups/service/status", sendData={}, callback=function(data,status) {
            setStatus(data);
            if (typeof done === "function") { done(status); }
        });
    }

    function refreshDiagnostics(done) {
        ajaxCall(url="/api/apcups/service/diagnostics", sendData={}, callback=function(data,status) {
            var html = "";
            if (data.checks !== undefined) {
                data.checks.forEach(function(check) {
                    html += "<h4>" + check.label + "</h4>";
                    html += "<pre>命令: " + check.command + "\n退出码: " + check.exit_code + "\n\n" + (check.output || "-") + "</pre>";
                });
            } else {
                html = "<pre>" + (data.message || "未返回诊断数据") + "</pre>";
            }
            $("#diagnosticsOutput").html(html);
            if (typeof done === "function") { done(status); }
        });
    }

    // Mirror core SimpleActionButton feedback: a .reload_progress icon slot
    // inside the button shows a pulsing spinner while the action runs and a
    // check mark for a few seconds once it succeeded.
    function actionFeedback($btn) {
        var $icon = $btn.find(".reload_progress");
        if (!$icon.length) {
            $icon = $('<i class="reload_progress" style="display:inline-block;"></i>');
            $btn.append(document.createTextNode(" "), $icon);
        }
        // The hide timer lives on the shared icon node so a re-click during the
        // check-mark window cannot be clobbered by a stale timeout.
        function setIcon(add) {
            var prev = $icon.data("apcHideTimer");
            if (prev) { clearTimeout(prev); $icon.data("apcHideTimer", null); }
            $icon.removeClass("fa fa-check fa-spinner fa-pulse");
            if (add) {
                $icon.addClass("fa " + add);
                $icon.css("width", "1em");
                if (add === "fa-check") {
                    $icon.data("apcHideTimer", setTimeout(function () { setIcon(""); }, 4000));
                }
            } else {
                $icon.css("width", "");
            }
        }
        return {
            busy: function () {
                $btn.prop("disabled", true);
                setIcon("fa-spinner fa-pulse");
            },
            success: function () {
                $btn.prop("disabled", false);
                setIcon("fa-check");
            },
            fail: function () {
                $btn.prop("disabled", false);
                setIcon("");
            }
        };
    }

    function updateActionBar() {
        var active = $(".nav-tabs li.active a").attr("href");
        if (active === "#settings" || active === "#notifications") {
            $("#bottomActionBar").show();
        } else {
            $("#bottomActionBar").hide();
        }
        // 测试通知按钮只在“通知”标签页显示
        if (active === "#notifications") {
            $("#testNotifyAct").show();
        } else {
            $("#testNotifyAct").hide();
        }
    }

    function friendlyChannelLabel(channel) {
        var labels = {
            email: "邮件通知",
            wechat_bot: "企业微信机器人",
            wechat_app: "企业微信应用消息",
            sms: "短信通知"
        };
        return labels[channel] || channel;
    }

    function friendlyChannelError(channel, output) {
        if (channel === "email") {
            return "发件邮箱信息不对或网络异常，请检查 SMTP 服务器、端口、账号、密码及收件人地址。";
        }
        if (channel === "wechat_bot") {
            return "企业微信机器人配置失败，请检查 Webhook 地址。";
        }
        if (channel === "wechat_app") {
            return "企业微信应用配置失败，请检查 CorpID、CorpSecret、AgentId 及接收用户。";
        }
        if (channel === "sms") {
            return "短信配置失败，请检查服务商、API 地址/密钥、手机号及模板/签名。";
        }
        return "配置失败，请检查网络或渠道配置。";
    }

    function showTestNotifyResult(data) {
        var html = "";
        var okCount = 0;
        var failCount = 0;
        var channels = data.channels || {};
        Object.keys(channels).forEach(function(channel) {
            var result = channels[channel];
            var label = friendlyChannelLabel(channel);
            if (result.status === "ok") {
                okCount++;
                html += '<div class="alert alert-success" style="margin-bottom: 8px;">' +
                    '<strong>' + label + '</strong>：配置成功，测试消息已发送。' +
                    '</div>';
            } else {
                failCount++;
                html += '<div class="alert alert-danger" style="margin-bottom: 8px;">' +
                    '<strong>' + label + '</strong>：' + friendlyChannelError(channel, result.output);
                if (result.output) {
                    html += '<pre style="margin-top: 8px; margin-bottom: 0;">' +
                        $('<div/>').text(result.output).html() +
                        '</pre>';
                }
                html += '</div>';
            }
        });

        if (Object.keys(channels).length === 0) {
            html = '<div class="alert alert-warning">没有启用任何通知渠道，请先在“通知”标签页勾选需要启用的渠道并保存。</div>';
        }

        BootstrapDialog.show({
            title: "通知测试结果",
            message: html,
            type: failCount > 0 ? BootstrapDialog.TYPE_DANGER : BootstrapDialog.TYPE_SUCCESS,
            size: BootstrapDialog.SIZE_WIDE,
            buttons: [{
                label: '关闭',
                action: function(dialogRef) {
                    dialogRef.close();
                }
            }]
        });
    }

    $("a[data-toggle='tab']").on("shown.bs.tab", function() {
        updateActionBar();
    });

    mapDataToFormUI({
        'frm_Settings': "/api/apcups/settings/get",
        'frm_NotificationSettings': "/api/apcups/settings/get"
    }).done(function() {
        updateActionBar();
    });

    $("#saveAct").click(function(){
        var fb = actionFeedback($(this));
        fb.busy();
        var failed = function () {
            fb.fail();
        };
        saveFormToEndpoint("/api/apcups/settings/set", "frm_Settings", function(){
            saveFormToEndpoint("/api/apcups/settings/set", "frm_NotificationSettings", function(){
                ajaxCall(url="/api/apcups/service/reload", sendData={}, callback=function(data,status) {
                    if (status === "success") {
                        fb.success();
                        refreshStatus();
                    } else {
                        failed();
                        BootstrapDialog.show({
                            title: "重载失败",
                            message: "配置已保存，但服务重载失败，请到诊断页检查 NUT 服务状态。",
                            type: BootstrapDialog.TYPE_DANGER,
                            buttons: [{
                                label: '关闭',
                                action: function(dialogRef) {
                                    dialogRef.close();
                                }
                            }]
                        });
                    }
                });
            }, false, failed);
        }, false, failed);
    });

    $("#testNotifyAct").click(function(){
        var fb = actionFeedback($(this));
        fb.busy();
        ajaxCall(
            url="/api/apcups/service/testNotify",
            sendData={channel: "all"},
            callback=function(data, status) {
                if (status === "success") {
                    fb.success();
                    showTestNotifyResult(data);
                } else {
                    fb.fail();
                    BootstrapDialog.show({
                        title: "测试失败",
                        message: "请求失败，请检查网络或后端日志。",
                        type: BootstrapDialog.TYPE_DANGER,
                        buttons: [{
                            label: '关闭',
                            action: function(dialogRef) {
                                dialogRef.close();
                            }
                        }]
                    });
                }
            }
        );
    });

    $("#restartAct").SimpleActionButton({
        onAction: function(data) {
            refreshStatus();
        }
    });

    $("#refreshAct").click(function(){
        var fb = actionFeedback($(this));
        fb.busy();
        refreshStatus(function(status){
            if (status === "success") { fb.success(); } else { fb.fail(); }
        });
    });

    $("#diagnosticsAct").click(function(){
        var fb = actionFeedback($(this));
        fb.busy();
        refreshDiagnostics(function(status){
            if (status === "success") { fb.success(); } else { fb.fail(); }
        });
    });

    refreshStatus();
    // Skip polling while the tab is hidden: every poll runs upsc on the box.
    window.setInterval(function () {
        if (!document.hidden) { refreshStatus(); }
    }, 10000);
});
</script>

<ul class="nav nav-tabs" role="tablist">
    <li class="active"><a data-toggle="tab" href="#status">状态</a></li>
    <li><a data-toggle="tab" href="#diagnostics">诊断</a></li>
    <li><a data-toggle="tab" href="#settings">设置</a></li>
    <li><a data-toggle="tab" href="#notifications">通知</a></li>
</ul>

<div class="tab-content content-box">
    <div id="status" class="tab-pane fade in active">
        <div class="table-responsive">
            <table class="table table-striped">
                <tbody>
                    <tr><th>连接状态</th><td id="upsConnection">-</td></tr>
                    <tr><th>UPS 状态</th><td id="upsStatus">-</td></tr>
                    <tr><th>电池电量</th><td id="upsCharge">-</td></tr>
                    <tr><th>剩余续航</th><td id="upsRuntime">-</td></tr>
                    <tr><th>负载</th><td id="upsLoad">-</td></tr>
                    <tr><th>输入电压</th><td id="upsInput">-</td></tr>
                    <tr><th>型号</th><td id="upsModel">-</td></tr>
                    <tr><th>序列号</th><td id="upsSerial">-</td></tr>
                    <tr><th>消息</th><td id="upsMessage">-</td></tr>
                </tbody>
            </table>
        </div>
        <div style="margin-top: 10px;">
            <button class="btn btn-primary" id="refreshAct" type="button"><b>刷新</b> <i class="reload_progress" style="display:inline-block;"></i></button>
            <button class="btn btn-default" id="restartAct" data-endpoint="/api/apcups/service/restart" data-label="重启 NUT"></button>
        </div>
    </div>
    <div id="diagnostics" class="tab-pane fade">
        <div style="padding: 20px 0 15px 20px;">
            <button class="btn btn-primary" id="diagnosticsAct" type="button"><b>运行诊断</b> <i class="reload_progress" style="display:inline-block;"></i></button>
        </div>
        <div id="diagnosticsOutput" style="margin-top: 15px; padding: 0 20px 15px 20px;"></div>
    </div>
    <div id="settings" class="tab-pane fade">
        {{ partial("layout_partials/base_form",['fields':settingsForm,'id':'frm_Settings']) }}
    </div>
    <div id="notifications" class="tab-pane fade">
        <div class="alert alert-info">
            <i class="fa fa-info-circle"></i>
            请先填写上方邮件 SMTP 发件信息，再在下方勾选需要启用的通知渠道。点击底部“测试通知”可一次性验证所有已启用渠道。
        </div>
        {{ partial("layout_partials/base_form",['fields':notificationForm,'id':'frm_NotificationSettings']) }}
    </div>
    <div id="bottomActionBar" class="col-md-12" style="display:none; margin-top: 15px; padding-bottom: 20px;">
        <button class="btn btn-primary" id="saveAct" type="button"><b>保存</b> <i class="reload_progress" style="display:inline-block;"></i></button>
        <button class="btn btn-default" id="testNotifyAct" type="button"><b><i class="fa fa-paper-plane"></i> 测试通知</b> <i class="reload_progress" style="display:inline-block;"></i></button>
    </div>
</div>
