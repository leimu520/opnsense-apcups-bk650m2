<?php

namespace OPNsense\ApcUps;

class IndexController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->view->settingsForm = $this->getForm("settings");
        $this->view->notificationForm = $this->getForm("notification");
        $this->view->pick('OPNsense/ApcUps/index');
    }
}
