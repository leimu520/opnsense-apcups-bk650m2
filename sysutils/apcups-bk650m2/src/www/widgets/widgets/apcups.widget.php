<?php

/*
 * APC BK650M2 UPS dashboard widget for OPNsense
 */

?>

<div class="apcups-widget-content" style="padding: 10px;">
    <div style="font-size: 16px; margin-bottom: 8px;">
        UPS状态：<span id="apcups-widget-status" style="font-weight: bold;">-</span>
    </div>
    <div style="font-size: 16px;">
        电量：<span id="apcups-widget-charge" style="font-weight: bold;">-</span>
    </div>
</div>

<script>
$(document).ready(function() {
    function updateApcUpsWidget() {
        $.ajax({
            url: '/api/apcups/service/status',
            type: 'POST',
            dataType: 'json',
            data: {},
            success: function(data) {
                if (data && data.connected !== undefined) {
                    $('#apcups-widget-status').text(data.connected ? '在线' : '离线');
                    $('#apcups-widget-charge').text(data.charge !== null && data.charge !== undefined ? data.charge + '%' : '-');
                } else {
                    $('#apcups-widget-status').text('读取失败');
                    $('#apcups-widget-charge').text('-');
                }
            },
            error: function() {
                $('#apcups-widget-status').text('读取失败');
                $('#apcups-widget-charge').text('-');
            }
        });
    }

    updateApcUpsWidget();
    setInterval(updateApcUpsWidget, 10000);
});
</script>
