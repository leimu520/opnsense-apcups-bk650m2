/*
 * Copyright (C) 2026 APC BK650M2 UPS Plugin
 * All rights reserved.
 *
 * Dashboard widget for Lobby showing UPS status and battery charge.
 */

export default class ApcUps extends BaseTableWidget {

    constructor(config) {
        super(config);
    }

    getGridOptions() {
        return {
            sizeToContent: 220
        };
    }

    getMarkup() {
        return `
            <div class="apcups-widget" style="padding: 5px;">
                <div style="font-size: 16px; margin-bottom: 8px;">
                    <i class="fa fa-battery-half fa-fw text-primary" style="margin-right: 5px;"></i>
                    UPS状态：<span id="apcups-widget-status" style="font-weight: bold;">-</span>
                </div>
                <div style="font-size: 16px;">
                    <i class="fa fa-bolt fa-fw text-warning" style="margin-right: 5px;"></i>
                    电量：<span id="apcups-widget-charge" style="font-weight: bold;">-</span>
                </div>
            </div>
        `;
    }

    async onWidgetTick() {
        try {
            const data = await this.ajaxCall('/api/apcups/service/status', {}, 'POST');
            if (data && data.connected !== undefined) {
                $('#apcups-widget-status').text(data.connected ? (data.status_text || '在线') : '离线');
                $('#apcups-widget-charge').text(
                    data.charge !== null && data.charge !== undefined ? data.charge + '%' : '-'
                );
            } else {
                $('#apcups-widget-status').text('读取失败');
                $('#apcups-widget-charge').text('-');
            }
        } catch (e) {
            $('#apcups-widget-status').text('读取失败');
            $('#apcups-widget-charge').text('-');
        }
    }

}
