package alifestancedots.viewpoint;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import me.zed_0xff.zombie_buddy.Exposer;

/*
 * Lets Lua place a marker in Viewpoint's 3D view. Viewpoint keeps the camera
 * it projects over-head text with in viewpoint.game.WorldText.screen (a
 * package-private WorldToScreen, refreshed every 3D frame); this reuses it,
 * as ViewpointUI does.
 *
 * Exposed as a Lua class (like Viewpoint.View): ZombieBuddy registers those
 * when the mod loads, while global @LuaMethod functions only appeared after
 * a Lua reload.
 *
 * Lua: ALifeStanceDotsViewpoint.pixel(x, y, z, metres) -> in front of camera,
 *      then .pixelX() / .pixelY() for the UI position.
 *
 * ponytail: reflection into Viewpoint internals (checked against 0.1.6.1).
 * If Viewpoint renames them, pixel returns false and the markers hide in 3D;
 * ask the Viewpoint authors for a public world-to-screen call if that keeps
 * happening.
 */
@Exposer.LuaClass(name = "ALifeStanceDotsViewpoint")
public final class Bridge {
    private static final float[] pixel = new float[2];
    private static Object screen;
    private static Method project;
    private static boolean broken;

    private static boolean ready() {
        if (project != null) return true;
        if (broken) return false;
        try {
            Field field = Class.forName("viewpoint.game.WorldText").getDeclaredField("screen");
            field.setAccessible(true);
            screen = field.get(null);
            project = screen.getClass().getDeclaredMethod("pixel",
                float.class, float.class, float.class, float.class, float[].class);
            project.setAccessible(true);
            return true;
        } catch (ReflectiveOperationException | RuntimeException e) {
            broken = true;
            System.out.println("[ALifeStanceDots] Viewpoint camera not found, no markers in 3D: " + e);
            return false;
        }
    }

    // x, y, z in tiles / levels; rise in metres above z. True when in front of the camera.
    public static synchronized boolean pixel(double x, double y, double z, double rise) {
        if (!ready()) return false;
        try {
            return (Boolean) project.invoke(screen, (float) x, (float) y, (float) z, (float) rise, pixel);
        } catch (ReflectiveOperationException | RuntimeException e) {
            return false;
        }
    }

    public static synchronized double pixelX() {
        return pixel[0];
    }

    public static synchronized double pixelY() {
        return pixel[1];
    }

    private Bridge() {
    }
}
