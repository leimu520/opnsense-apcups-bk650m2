<?php

namespace OPNsense\ApcUps\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class SettingsController extends ApiMutableModelControllerBase
{
    protected static $internalModelClass = 'OPNsense\ApcUps\ApcUps';
    protected static $internalModelName = 'apcups';
}
