using common;
using wServer.logic.behaviors;
using wServer.logic.loot;
using wServer.logic.transitions;

namespace wServer.logic
{
    partial class BehaviorDb
    {
        private _ EclipseCitadel = () => Behav()
            .Init("Lightless Court Guard", new State(new Follow(.32, 14, 1), new Shoot(13, count: 5, shootAngle: 18, coolDown: 760)))
            .Init("The Hollow Regent", new State(new ScaleHP2(70, 3, 15),
                new State("Throne Guard", new Shoot(18, count: 10, shootAngle: 18, projectileIndex: 0, coolDown: 700), new Spawn("Lightless Court Guard", 3, 0, 7000), new HpLessTransition(.65, "Hollow Decree")),
                new State("Hollow Decree", new Shoot(22, count: 8, shootAngle: 22.5, projectileIndex: 1, fixedAngle: 0, rotateAngle: 4, coolDown: 620), new Shoot(15, predictive: 1.2, projectileIndex: 0, coolDown: 900))),
                new Threshold(.01, new ItemLoot("Potion of Defense", .8), new ItemLoot("Potion of Attack", .6)))
            .Init("Zenith Astralist", new State(new StayBack(.25, 10), new Shoot(16, count: 4, predictive: 1.2, coolDown: 720)))
            .Init("The Zenith Warden", new State(new ScaleHP2(74, 3, 15),
                new State("Rotating Lanes", new Shoot(28, count: 12, shootAngle: 30, projectileIndex: 0, fixedAngle: 0, rotateAngle: 5, coolDown: 720), new TimedTransition(7000, "Celestial Strike")),
                new State("Celestial Strike", new Flash(0xaad8ff, .5, 2), new Shoot(20, count: 5, predictive: 1.5, projectileIndex: 1, coolDown: 520), new TimedTransition(6000, "Rotating Lanes"))),
                new Threshold(.01, new ItemLoot("Potion of Wisdom", .7), new ItemLoot("Potion of Vitality", .7)))
            .Init("Umbra Engine Node", new State(new Shoot(14, count: 6, shootAngle: 20, projectileIndex: 0, coolDown: 900)))
            .Init("The Umbra Enginekeeper", new State(new ScaleHP2(78, 3, 15),
                new State("Armored Engine", new Shoot(20, count: 8, shootAngle: 20, projectileIndex: 0, coolDown: 700), new TimedTransition(8000, "Exposed Engine")),
                new State("Exposed Engine", new Shoot(18, count: 4, predictive: 1.2, projectileIndex: 1, coolDown: 500), new TimedTransition(6500, "Armored Engine"))),
                new Threshold(.01, new ItemLoot("Potion of Attack", .8), new ItemLoot("Potion of Defense", .8)))
            .Init("Crown Shadow", new State())
            .Init("The Crowned Eclipse", new State(new ScaleHP2(105, 3, 15),
                new State("Crown Ascendant", new Shoot(24, count: 8, shootAngle: 18, projectileIndex: 0, coolDown: 620), new Shoot(24, count: 8, shootAngle: 18, projectileIndex: 1, fixedAngle: 180, rotateAngle: -3, coolDown: 880), new HpLessTransition(.72, "Eclipse Guard")),
                new State("Eclipse Guard", new Spawn("Crown Shadow", 5, 4, 999999), new Shoot(22, count: 10, shootAngle: 18, projectileIndex: 0, coolDown: 720), new EntitiesNotExistsTransition(99, "Light and Umbra", "Crown Shadow")),
                new State("Light and Umbra", new Shoot(30, count: 12, shootAngle: 20, projectileIndex: 1, fixedAngle: 0, rotateAngle: 4, coolDown: 600), new TimedTransition(6000, "Umbra and Light")),
                new State("Umbra and Light", new Shoot(30, count: 12, shootAngle: 20, projectileIndex: 2, fixedAngle: 180, rotateAngle: -4, coolDown: 600), new TimedTransition(6000, "Light and Umbra"), new HpLessTransition(.32, "Broken Crown")),
                new State("Broken Crown", new Shoot(26, count: 10, shootAngle: 16, projectileIndex: 2, coolDown: 430), new Shoot(18, count: 4, predictive: 1.3, projectileIndex: 1, coolDown: 650))),
                new Threshold(.01, new ItemLoot("Potion of Attack", 1), new ItemLoot("Potion of Defense", 1), new ItemLoot("Potion of Vitality", .8), new ItemLoot("Citadel Mark", 1), new ItemLoot("Crownrender", .012), new ItemLoot("Eclipse Aegis", .012), new ItemLoot("Zenithal Ring", .016)))
            .Init("Citadel Completion Chest", new State())
            .Init("Citadel Return Portal", new State());
    }
}
