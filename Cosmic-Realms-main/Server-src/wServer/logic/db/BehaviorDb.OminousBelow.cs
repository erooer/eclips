using common.resources;
using wServer.logic.behaviors;
using wServer.logic.loot;
using wServer.logic.transitions;

namespace wServer.logic
{
    partial class BehaviorDb
    {
        // Timers are milliseconds and remain intentionally modest for the 75 ms world tick.
        private _ OminousBelow = () => Behav()
            .Init("Drowned Pilgrim", new State(new Follow(.42, 16, 1), new Shoot(8, count: 4, projectileIndex: 0, coolDown: 950)))
            .Init("Lantern Wraith", new State(new StayBack(.32, 10), new Shoot(16, predictive: 1.2, projectileIndex: 0, coolDown: 800)))
            .Init("Riverbound Hound", new State(new State("pause", new Flash(0x99ddff, 1, 1), new TimedTransition(600, "charge")), new State("charge", new Follow(.95, 18, 1), new Shoot(8, count: 4, shootAngle: 18, projectileIndex: 0, coolDown: 500), new TimedTransition(700, "recover")), new State("recover", new StayBack(.20, 7), new TimedTransition(1100, "pause"))))
            .Init("Ferryman's Attendant", new State(new Follow(.32, 15, 2), new Shoot(15, count: 3, shootAngle: 16, projectileIndex: 0, coolDown: 900)))
            .Init("Soul Collector", new State(new Follow(.36, 17, 3), new Shoot(16, count: 8, projectileIndex: 0, coolDown: 850), new Spawn("Drowned Pilgrim", 3, 0, 5000)), new Threshold(.01, new ItemLoot("Potion of Wisdom", .15)))
            .Init("Ominous Soul Lantern", new State(new ConditionalEffect(ConditionEffectIndex.Armored), new Shoot(12, count: 4, projectileIndex: 0, coolDown: 1700), new Taunt(.08, "A lantern seal has broken.")))
            .Init("Soul Barge Anchor", new State(new Shoot(12, count: 3, shootAngle: 18, projectileIndex: 0, coolDown: 850)))
            .Init("The Faceless Ferryman", new State(
                new ScaleHP2(50, 3, 15),
                new State("Toll of the Dead", new Follow(.18, 8, 2), new Shoot(11, count: 2, shootAngle: 180, projectileIndex: 0, coolDown: 450), new Shoot(11, count: 3, shootAngle: 12, projectileIndex: 1, coolDown: 1150), new Spawn("Drowned Pilgrim", 4, 0, 7000), new HpLessTransition(.75, "Crossing")),
                // Invincibility during Crossing is owned by the instance's two anchors.
                // A state-owned effect would immediately reapply after the last anchor dies.
                new State("Crossing", new Flash(0x9e7cff, 1, 2), new Spawn("Soul Barge Anchor", 2, 2, 999999), new Shoot(12, count: 8, projectileIndex: 0, coolDown: 950), new TimedTransition(9000, "The Price")),
                new State("The Price", new Shoot(12, count: 10, shootAngle: 18, projectileIndex: 0, coolDown: 550), new Shoot(12, count: 4, predictive: 1.4, projectileIndex: 1, coolDown: 900))),
                new Threshold(.01, new ItemLoot("Potion of Speed", 1), new ItemLoot("Potion of Dexterity", .5), new ItemLoot("Potion of Wisdom", .5), new ItemLoot("Mark of the Ferryman", 1), new ItemLoot("Eye Blueprint", .04), new ItemLoot("Ferryman's Toll", .008), new ItemLoot("Ominous Below Key", .002)))
            .Init("Shackled Revenant", new State(new Follow(.20, 8, 1), new Shoot(4, count: 4, projectileIndex: 0, coolDown: 1500)))
            .Init("Oathbreaker Judge", new State(new StayBack(.16, 7), new Shoot(10, count: 3, shootAngle: 20, projectileIndex: 0, coolDown: 1500)))
            .Init("Iron Gaoler", new State(new State("guard", new ConditionalEffect(ConditionEffectIndex.Armored), new TimedTransition(1800, "slam")), new State("slam", new Shoot(5, count: 8, projectileIndex: 0, coolDown: 1000), new TimedTransition(700, "guard"))))
            .Init("Condemned Oracle", new State(new StayBack(.18, 8), new Shoot(10, predictive: 1.7, projectileIndex: 0, coolDown: 1050)))
            .Init("The First Gaoler", new State(new ScaleHP2(42, 3, 15), new Follow(.22, 9, 2), new Shoot(10, count: 6, projectileIndex: 0, coolDown: 750)), new Threshold(.01, new ItemLoot("Potion of Defense", .5)))
            .Init("The Last Gaoler", new State(new ScaleHP2(42, 3, 15), new StayBack(.20, 7), new Shoot(11, count: 8, projectileIndex: 0, coolDown: 800)), new Threshold(.01, new ItemLoot("Potion of Vitality", .5)))
            .Init("Chain Anchor", new State(new Shoot(13, count: 4, shootAngle: 16, projectileIndex: 0, coolDown: 850)))
            .Init("Veyra, Warden of Chains", new State(
                new ScaleHP2(58, 3, 15),
                new State("Sentence", new StayCloseToSpawn(.18, 5), new Shoot(13, count: 5, shootAngle: 12, projectileIndex: 0, coolDown: 700), new Shoot(13, count: 6, projectileIndex: 1, coolDown: 1500), new Spawn("Shackled Revenant", 4, 0, 8000), new HpLessTransition(.8, "Four Chains")),
                // The instance owns invincibility while Chain Anchors exist. Keep
                // the Warden active here so destroying the anchors is an attack
                // phase rather than a safe pause in the encounter.
                new State("Four Chains", new Flash(0xa153d6, 1, 2), new Spawn("Chain Anchor", 4, 4, 999999), new Shoot(30, count: 12, shootAngle: 30, projectileIndex: 1, fixedAngle: 0, rotateAngle: 7, coolDown: 900), new Shoot(30, count: 5, shootAngle: 18, projectileIndex: 0, coolDown: 650), new TimedTransition(11000, "Prison Closes")),
                new State("Prison Closes", new Shoot(14, count: 12, shootAngle: 15, projectileIndex: 0, coolDown: 600), new HpLessTransition(.35, "Broken Warden")),
                new State("Broken Warden", new Shoot(13, count: 8, shootAngle: 20, projectileIndex: 0, coolDown: 480), new Shoot(13, count: 4, predictive: 1.2, projectileIndex: 1, coolDown: 800))),
                new Threshold(.01, new ItemLoot("Potion of Defense", 1), new ItemLoot("Potion of Vitality", .6), new ItemLoot("Potion of Attack", .6), new ItemLoot("Mark of the Warden", 1), new ItemLoot("Mantle Blueprint", .03), new ItemLoot("Chains of Veyra", .008), new ItemLoot("Ominous Below Key", .002)))
            .Init("Abyssal Remnant", new State(new Shoot(8, count: 6, projectileIndex: 0, coolDown: 1400)))
            .Init("Ominous Eye", new State(new State("open", new Shoot(12, predictive: 2, projectileIndex: 0, coolDown: 800), new TimedTransition(2500, "close")), new State("close", new ConditionalEffect(ConditionEffectIndex.Invulnerable), new TimedTransition(1200, "open"))))
            .Init("Hollow Devourer", new State(new State("pursue", new Follow(.35, 8, 1), new TimedTransition(1300, "retreat")), new State("retreat", new StayBack(.35, 7), new Shoot(9, count: 4, shootAngle: 16, projectileIndex: 0, coolDown: 900), new TimedTransition(1100, "pursue"))))
            .Init("Ominous Seal", new State(new Shoot(11, count: 5, projectileIndex: 0, coolDown: 1300)))
            // Ritual Pillars are spawned only for the Ominous One's stagger. They
            // are objectives, not an extra source of fire during that quiet window.
            .Init("Ritual Pillar", new State())
            .Init("The Ominous One", new State(
                new ScaleHP2(78, 3, 15),
                new State("Dreaming Beneath", new ConditionalEffect(ConditionEffectIndex.Invulnerable), new Flash(0x7d2d91, 1, 2), new Shoot(14, count: 8, projectileIndex: 0, coolDown: 1200), new TimedTransition(10000, "The Gaze")),
                new State("The Gaze", new Shoot(15, count: 12, shootAngle: 15, projectileIndex: 0, coolDown: 650), new Shoot(14, count: 4, predictive: 1.4, projectileIndex: 1, coolDown: 950), new HpLessTransition(.7, "Consume the Condemned")),
                new State("Consume the Condemned", new ConditionalEffect(ConditionEffectIndex.Invulnerable), new Taunt(.3, "The condemned will feed me."), new Spawn("Abyssal Remnant", 8, 3, 1800), new TimedTransition(8000, "World Below Pillars")),
                // The pillars are a one-time objective. Once destroyed, the fight
                // alternates only between the protected barrage and a short,
                // vulnerable stagger; it never spawns a second pillar set.
                new State("World Below Pillars", new Taunt("..."), new Spawn("Ritual Pillar", 4, 4, 999999), new EntitiesNotExistsTransition(99, "World Below Barrage", "Ritual Pillar")),
                // Every barrage is protected. The only damage window is the
                // stagger after the active pillars have all been destroyed.
                new State("World Below Barrage", new ConditionalEffect(ConditionEffectIndex.Invulnerable), new Shoot(30, count: 16, shootAngle: 22.5, projectileIndex: 2, fixedAngle: 0, rotateAngle: 8, coolDown: 560), new TimedTransition(10000, "World Below Recovery")),
                new State("World Below Recovery", new Taunt("..."), new TimedTransition(7000, "World Below Barrage"), new HpLessTransition(.35, "Crowned Strength")),
                new State("Crowned Strength", new ConditionalEffect(ConditionEffectIndex.Invulnerable), new Taunt("Thy strength befits a crown"), new TimedTransition(2500, "Crown Spiral Clockwise")),
                // Sixteen shots leave a smaller, readable gap. Eight volleys fit
                // in each three-second leg, so the counter-clockwise leg starts
                // at +24 degrees and continues the sweep rather than snapping.
                new State("Crown Spiral Clockwise", new Shoot(30, count: 16, shootAngle: 18, projectileIndex: 0, fixedAngle: 0, rotateAngle: 3, coolDown: 420), new TimedTransition(3000, "Crown Spiral Counterclockwise")),
                new State("Crown Spiral Counterclockwise", new Shoot(30, count: 16, shootAngle: 18, projectileIndex: 0, fixedAngle: 0, angleOffset: 24, rotateAngle: -3, coolDown: 420), new TimedTransition(3000, "Crown Spiral Clockwise"))),
                new Threshold(.01, new ItemLoot("Potion of Attack", 1), new ItemLoot("Potion of Defense", .7), new ItemLoot("Potion of Vitality", .7), new ItemLoot("Mark of the Ominous One", 1), new ItemLoot("Judgement Blueprint", .02), new ItemLoot("Judgement", .006), new ItemLoot("Eye of the Ominous", .006), new ItemLoot("Mantle of the Below", .006), new ItemLoot("Ominous Below Key", .002)))
            .Init("Ominous Completion Chest", new State())
            .Init("Ominous Return Portal", new State());
    }
}
