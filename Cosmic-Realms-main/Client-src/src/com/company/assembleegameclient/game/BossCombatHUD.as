package com.company.assembleegameclient.game {

import com.company.assembleegameclient.objects.GameObject;
import com.company.assembleegameclient.objects.ObjectLibrary;
import com.company.assembleegameclient.parameters.Parameters;
import com.company.ui.BaseSimpleText;

import flash.display.Sprite;
import flash.events.Event;
import flash.utils.getTimer;

/**
 * A presentation-only combat readout. DAMAGE is emitted only after the server
 * has applied damage, and its ObjectId identifies the confirmed damage source.
 */
public class BossCombatHUD extends Sprite {

    private static const MINIMUM_MAX_HP:int = 50000;
    private static const DPS_WINDOW_MS:int = 5000;
    private static const COMBAT_TIMEOUT_MS:int = 10000;
    private static const BAR_WIDTH:int = 300;
    private static const BAR_HEIGHT:int = 14;

    private var gs_:GameSprite;
    private var targetId_:int = -1;
    private var lastInteractionAt_:int = 0;
    private var samples_:Array = [];
    private var nameText_:BaseSimpleText;
    private var percentText_:BaseSimpleText;
    private var dpsText_:BaseSimpleText;

    public function BossCombatHUD(gs:GameSprite) {
        this.gs_ = gs;
        mouseEnabled = false;
        mouseChildren = false;

        this.nameText_ = makeText(18, 16777215, true);
        this.percentText_ = makeText(14, 16777215, true);
        this.dpsText_ = makeText(14, 16777215, false);
        addChild(this.nameText_);
        addChild(this.percentText_);
        addChild(this.dpsText_);
        visible = false;
        addEventListener(Event.ENTER_FRAME, this.onEnterFrame);
    }

    public function recordConfirmedDamage(targetId:int, damage:int, killed:Boolean):void {
        if (!Parameters.data_.bossHealthBarDps || damage <= 0) {
            return;
        }
        var target:GameObject = this.gs_.map.goDict_[targetId] as GameObject;
        if (!qualifies(target)) {
            return;
        }
        var now:int = getTimer();
        if (this.targetId_ != targetId) {
            this.targetId_ = targetId;
            this.samples_ = [];
        }
        this.lastInteractionAt_ = now;
        this.samples_.push({time: now, damage: damage});
        if (killed) {
            clear();
            return;
        }
        refresh(target, now);
    }

    public function clear():void {
        if (this.targetId_ < 0 && !visible && this.samples_.length == 0) {
            return;
        }
        this.targetId_ = -1;
        this.lastInteractionAt_ = 0;
        this.samples_ = [];
        visible = false;
    }

    private function onEnterFrame(event:Event):void {
        if (!Parameters.data_.bossHealthBarDps) {
            clear();
            return;
        }
        if (this.targetId_ < 0 || this.gs_.map == null || this.gs_.map.player_ == null || this.gs_.map.player_.dead_) {
            clear();
            return;
        }
        var now:int = getTimer();
        if (now - this.lastInteractionAt_ > COMBAT_TIMEOUT_MS) {
            clear();
            return;
        }
        var target:GameObject = this.gs_.map.goDict_[this.targetId_] as GameObject;
        if (!qualifies(target) || target.dead_ || target.hp_ <= 0) {
            clear();
            return;
        }
        refresh(target, now);
    }

    private function refresh(target:GameObject, now:int):void {
        trimSamples(now);
        var total:int = 0;
        for each (var sample:Object in this.samples_) {
            total += int(sample.damage);
        }
        var elapsed:int = this.samples_.length > 0 ? Math.min(DPS_WINDOW_MS, Math.max(1, now - this.samples_[0].time)) : DPS_WINDOW_MS;
        var dps:int = Math.round(total / (elapsed / 1000));
        var ratio:Number = Math.max(0, Math.min(1, target.hp_ / target.maxHP_));

        this.nameText_.text = ObjectLibrary.typeToDisplayId_[target.objectType_];
        this.nameText_.updateMetrics();
        this.nameText_.x = (BAR_WIDTH - this.nameText_.width) / 2;
        this.nameText_.y = 0;
        this.percentText_.text = Math.round(ratio * 100) + "%";
        this.percentText_.updateMetrics();
        this.percentText_.x = (BAR_WIDTH - this.percentText_.width) / 2;
        this.percentText_.y = 21;
        this.dpsText_.text = "DPS: " + formatNumber(dps);
        this.dpsText_.updateMetrics();
        this.dpsText_.x = (BAR_WIDTH - this.dpsText_.width) / 2;
        this.dpsText_.y = 40;

        graphics.clear();
        graphics.beginFill(0, 0.75);
        graphics.drawRect(-3, 18, BAR_WIDTH + 6, BAR_HEIGHT + 6);
        graphics.endFill();
        graphics.beginFill(0x4d1616);
        graphics.drawRect(0, 21, BAR_WIDTH, BAR_HEIGHT);
        graphics.endFill();
        graphics.beginFill(0xd13c3c);
        graphics.drawRect(0, 21, BAR_WIDTH * ratio, BAR_HEIGHT);
        graphics.endFill();
        visible = true;
    }

    private function trimSamples(now:int):void {
        while (this.samples_.length > 0 && now - this.samples_[0].time > DPS_WINDOW_MS) {
            this.samples_.shift();
        }
    }

    private function qualifies(target:GameObject):Boolean {
        return target != null && target.props_.isEnemy_ && target.maxHP_ >= MINIMUM_MAX_HP;
    }

    private function makeText(size:int, color:uint, bold:Boolean):BaseSimpleText {
        var text:BaseSimpleText = new BaseSimpleText(size, color, false, 0, 0);
        text.setBold(bold);
        return text;
    }

    private function formatNumber(value:int):String {
        var valueText:String = String(value);
        var result:String = "";
        while (valueText.length > 3) {
            result = "," + valueText.substr(-3) + result;
            valueText = valueText.substr(0, valueText.length - 3);
        }
        return valueText + result;
    }
}
}
