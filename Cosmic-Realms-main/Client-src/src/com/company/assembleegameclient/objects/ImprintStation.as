package com.company.assembleegameclient.objects
{
    import ToolForge.ToolForgePanel;
    import com.company.assembleegameclient.game.GameSprite;
    import com.company.assembleegameclient.ui.panels.Panel;

    public class ImprintStation extends GameObject implements IInteractiveObject
    {
        public function ImprintStation(xml:XML)
        {
            super(xml);
            isInteractive_ = true;
        }

        public function getPanel(gameSprite:GameSprite):Panel
        {
            return new ToolForgePanel(gameSprite, "imprint");
        }
    }
}
