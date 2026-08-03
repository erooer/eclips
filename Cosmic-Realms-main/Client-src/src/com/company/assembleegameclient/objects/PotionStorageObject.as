package com.company.assembleegameclient.objects {
import com.company.assembleegameclient.game.GameSprite;
import com.company.assembleegameclient.ui.panels.Panel;
import kabam.rotmg.potionStorage.PotionStoragePanel;

public class PotionStorageObject extends GameObject implements IInteractiveObject {
    public function PotionStorageObject(xml:XML) { super(xml); }
    public function getPanel(gs:GameSprite) : Panel { return new PotionStoragePanel(gs); }
}
}
