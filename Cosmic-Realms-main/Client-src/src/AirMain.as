package {
import flash.filesystem.File; import flash.filesystem.FileMode; import flash.filesystem.FileStream;
import flash.display.Sprite; import flash.events.Event; import flash.events.UncaughtErrorEvent; import flash.utils.getTimer;
[SWF(frameRate="60", backgroundColor="#000000", width="800", height="600")]
public class AirMain extends Sprite {
    private var logFile:File;
    public function AirMain() { if (stage) initialize(); else addEventListener(Event.ADDED_TO_STAGE, onAdded); }
    private function onAdded(event:Event):void { removeEventListener(Event.ADDED_TO_STAGE, onAdded); initialize(); }
    private function initialize():void { var config:Object=loadConfig(); WebMain.configureDesktopEnvironment(String(config.accountHost),int(config.accountPort),String(config.environment)); log("AIR startup account="+config.accountHost+":"+config.accountPort); loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,onUncaughtError); stage.addEventListener(Event.DEACTIVATE,onDeactivate); addChild(new WebMain()); }
    private function loadConfig():Object { var defaults:Object={accountHost:"108.181.154.220",accountPort:80,worldHost:"108.181.154.220",worldPort:2050,environment:"production"}; try { var file:File=File.applicationDirectory.resolvePath("client.json"); var stream:FileStream=new FileStream(); stream.open(file,FileMode.READ); var parsed:Object=JSON.parse(stream.readUTFBytes(stream.bytesAvailable)); stream.close(); for(var key:String in defaults) if(parsed[key]==null||parsed[key]==="") parsed[key]=defaults[key]; if(parsed.accountPort<1||parsed.accountPort>65535) throw new Error("accountPort must be 1-65535"); if(parsed.logDirectory) logFile=new File(String(parsed.logDirectory)).resolvePath("air-client.log"); return parsed; } catch(error:Error) { log("Configuration fallback: "+error.message); return defaults; } return defaults; }
    private function onDeactivate(event:Event):void { log("Application deactivated"); stage.focus=null; }
    private function onUncaughtError(event:UncaughtErrorEvent):void { var error:Error=event.error as Error; log("Uncaught exception: "+event.error+(error ? "\n"+error.getStackTrace() : "")); }
    private function log(message:String):void { try { if(!logFile) logFile=File.applicationStorageDirectory.resolvePath("logs/air-client.log"); logFile.parent.createDirectory(); var stream:FileStream=new FileStream(); stream.open(logFile,FileMode.APPEND); stream.writeUTFBytes("["+getTimer()+"] "+message+"\n"); stream.close(); } catch(ignored:Error) {} }
}}
