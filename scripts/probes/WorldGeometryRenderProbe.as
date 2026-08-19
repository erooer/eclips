package {
import com.company.assembleegameclient.engine3d.Face3D;
import com.company.assembleegameclient.map.Camera;

import flash.display.BitmapData;
import flash.display.Graphics;
import flash.display.IGraphicsData;
import flash.display.Sprite;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.geom.Matrix;
import flash.geom.Rectangle;

public final class WorldGeometryRenderProbe extends Sprite {
    private static const UVT:Vector.<Number> = new <Number>[0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0];

    public function WorldGeometryRenderProbe() {
        stage.scaleMode = StageScaleMode.NO_SCALE;
        stage.align = StageAlign.TOP_LEFT;
        try {
            // Exercise authored coordinates, but position the camera close enough that
            // each object belongs in the current draw viewport. World synchronization
            // is covered separately; this probe owns the creation -> Face3D -> pixels
            // boundary and must not mistake a legitimately off-screen object for a
            // renderer failure.
            runCase("Vault Wood Panel Wall 0x01e4 @ 52,60", 52.5, 65.5, 52, 60);
            runCase("Vault Wood Fence 0x193c @ 56,56", 56.5, 61.5, 56, 56);
            runCase("Nexus Guild Board 0x01e7 @ 86,170", 86.5, 175.5, 86, 170);
            // The standalone debug projector does not reliably flush trace() before
            // fscommand("quit") on Windows. An intentional terminal exception is
            // captured by flashlog synchronously and gives the harness an observable
            // result after every real drawing assertion above has passed.
            throw new Error("WORLD_GEOMETRY_RENDER_PROBE PASS viewport=800x600 mapClip=600x600 " +
                "Vault Wood Panel Wall 0x01e4 @ 52,60; Vault Wood Fence 0x193c @ 56,56; " +
                "Nexus Guild Board 0x01e7 @ 86,170");
        } catch (error:Error) {
            if (error.message.indexOf("WORLD_GEOMETRY_RENDER_PROBE PASS") == 0) throw error;
            throw new Error("WORLD_GEOMETRY_RENDER_PROBE FAIL " + error.message);
        }
    }

    private static function runCase(label:String, cameraX:Number, cameraY:Number, objectX:int, objectY:int):void {
        var camera:Camera = new Camera();
        var clip:Rectangle = new Rectangle(-300, -450, 600, 600);
        camera.configure(cameraX, cameraY, 12, 0, clip);
        var texture:BitmapData = new BitmapData(16, 16, false, 0xE2B66F);
        var vertices:Vector.<Number> = new <Number>[
            objectX, objectY, 1, objectX + 1, objectY, 1,
            objectX + 1, objectY + 1, 1, objectX, objectY + 1, 1
        ];
        var face:Face3D = new Face3D(texture, vertices, UVT, false, true);
        var data:Vector.<IGraphicsData> = new Vector.<IGraphicsData>();
        if (!face.draw(data, camera) || data.length != 3)
            throw new Error(label + " was rejected before software-renderer submission.");
        var surface:Sprite = new Sprite();
        var graphics:Graphics = surface.graphics;
        graphics.drawGraphicsData(data);
        var bounds:Rectangle = surface.getBounds(surface);
        if (bounds.isEmpty()) throw new Error(label + " produced empty final draw bounds.");
        var pixels:BitmapData = new BitmapData(600, 600, true, 0);
        pixels.draw(surface, new Matrix(1, 0, 0, 1, -clip.x, -clip.y));
        var visibleBounds:Rectangle = pixels.getColorBoundsRect(0xFF000000, 0, false);
        if (visibleBounds.isEmpty()) throw new Error(label + " produced no visible software-renderer pixels.");
        trace("WORLD_GEOMETRY " + label + " drawBounds=" + bounds + " visiblePixels=" + visibleBounds);
        pixels.dispose();
        face.dispose();
        texture.dispose();
    }
}
}
