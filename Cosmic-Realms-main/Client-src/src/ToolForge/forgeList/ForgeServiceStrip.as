package ToolForge.forgeList {
import com.company.assembleegameclient.game.GameSprite;
import com.company.assembleegameclient.ui.DeprecatedClickableText;
import flash.display.Sprite;
import flash.events.MouseEvent;
import kabam.rotmg.messaging.impl.incoming.ForgeListResult;
import kabam.rotmg.text.view.TextFieldDisplayConcrete;
import kabam.rotmg.text.view.stringBuilder.StaticStringBuilder;

public class ForgeServiceStrip extends Sprite {
    private var gs:GameSprite;
    private var command:String;

    public function ForgeServiceStrip(gameSprite:GameSprite, row:ForgeListResult) {
        this.gs = gameSprite;
        this.command = row.Command;

        var heading:TextFieldDisplayConcrete = new TextFieldDisplayConcrete()
            .setColor(0xFFFFFF).setSize(16).setBold(true)
            .setStringBuilder(new StaticStringBuilder(row.Result));
        addChild(heading);

        var details:TextFieldDisplayConcrete = new TextFieldDisplayConcrete()
            .setColor(row.Craftable ? 0xB3FFB3 : 0xFFB3B3).setSize(13)
            .setStringBuilder(new StaticStringBuilder(row.Details));
        details.y = 23;
        addChild(details);

        var button:DeprecatedClickableText = new DeprecatedClickableText(16, true, row.ActionLabel);
        button.x = 400;
        button.y = 12;
        button.mouseEnabled = row.Craftable && this.command != null && this.command.length > 0;
        button.alpha = button.mouseEnabled ? 1 : .45;
        if (button.mouseEnabled)
            button.addEventListener(MouseEvent.CLICK, onAction);
        addChild(button);

        graphics.beginFill(0x252525, .7);
        graphics.drawRect(0, 0, 500, 52);
        graphics.endFill();
    }

    private function onAction(event:MouseEvent):void {
        this.gs.gsc_.playerText(this.command);
    }
}
}
