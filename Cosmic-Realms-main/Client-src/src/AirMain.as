package {
import eclipse.ClientBuildInfo;

import flash.display.Sprite;
import flash.events.Event;
import flash.events.UncaughtErrorEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.text.TextField;
import flash.text.TextFormat;
import flash.utils.getTimer;

[SWF(frameRate="60", backgroundColor="#000000", width="800", height="600")]
public class AirMain extends Sprite {
    private var logFile:File;

    public function AirMain() {
        if (stage) initialize();
        else addEventListener(Event.ADDED_TO_STAGE, onAdded);
    }

    private function onAdded(event:Event):void {
        removeEventListener(Event.ADDED_TO_STAGE, onAdded);
        initialize();
    }

    private function initialize():void {
        loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
        stage.addEventListener(Event.DEACTIVATE, onDeactivate);

        var config:Object = loadConfig();
        stage.nativeWindow.title = "Cosmic Realms - " + ClientBuildInfo.SHORT_SOURCE;
        WebMain.configureDesktopEnvironment(String(config.accountHost), int(config.accountPort), String(config.environment));
        log("[ECLIPSE_CLIENT_BUILD] " + ClientBuildInfo.LABEL + " AIR window title=" + stage.nativeWindow.title);
        log("AIR startup account=" + config.accountHost + ":" + config.accountPort);

        addChild(new WebMain());
        if (WebMain.BOOTSTRAP_READY) log("[AIR_BOOTSTRAP_READY] assets and application context initialized");
        else showStartupFailure("The client could not start. See air-client.log for details.");
    }

    private function loadConfig():Object {
        var defaults:Object = {accountHost:"108.181.154.220", accountPort:80, worldHost:"108.181.154.220", worldPort:2050, environment:"production"};
        try {
            var file:File = File.applicationDirectory.resolvePath("client.json");
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.READ);
            var parsed:Object = JSON.parse(stream.readUTFBytes(stream.bytesAvailable));
            stream.close();
            for (var key:String in defaults) if (parsed[key] == null || parsed[key] === "") parsed[key] = defaults[key];
            if (parsed.accountPort < 1 || parsed.accountPort > 65535) throw new Error("accountPort must be 1-65535");
            if (parsed.logDirectory) logFile = File.applicationDirectory.resolvePath(String(parsed.logDirectory)).resolvePath("air-client.log");
            return parsed;
        } catch (error:Error) {
            log("Configuration fallback: " + error.message);
            return defaults;
        }
        return defaults;
    }

    private function onDeactivate(event:Event):void {
        log("Application deactivated");
        stage.focus = null;
    }

    private function onUncaughtError(event:UncaughtErrorEvent):void {
        var error:Error = event.error as Error;
        var detail:String = String(event.error) + (error && error.getStackTrace() ? "\n" + error.getStackTrace() : "");
        log("[FATAL_UNCAUGHT] " + detail);
        // Runtime exceptions remain visible to developers in air-client.log,
        // but must not replace gameplay with a diagnostic overlay or dialog.
        event.preventDefault();
    }

    private function showStartupFailure(message:String):void {
        if (!stage || getChildByName("airStartupFailure")) return;
        var field:TextField = new TextField();
        field.name = "airStartupFailure";
        field.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF);
        field.background = true;
        field.backgroundColor = 0x242424;
        field.wordWrap = true;
        field.multiline = false;
        field.selectable = false;
        field.width = Math.min(520, Math.max(320, stage.stageWidth - 32));
        field.height = 42;
        field.x = Math.max(16, (stage.stageWidth - field.width) / 2);
        field.y = Math.max(16, (stage.stageHeight - field.height) / 2);
        field.text = message;
        addChild(field);
    }

    private function log(message:String):void {
        try {
            if (!logFile) logFile = File.applicationStorageDirectory.resolvePath("logs/air-client.log");
            logFile.parent.createDirectory();
            var stream:FileStream = new FileStream();
            stream.open(logFile, FileMode.APPEND);
            stream.writeUTFBytes("[" + getTimer() + "] " + message + "\n");
            stream.close();
        } catch (ignored:Error) {
            trace("[AIR_LOG_FAILURE] " + ignored.message + " original=" + message);
        }
    }
}
}
