using common; using wServer.logic.behaviors;
using wServer.logic.loot;
using wServer.logic.transitions;
namespace wServer.logic { partial class BehaviorDb { private _ SunkenReliquary = () => Behav()
 .Init("Pearlbound Sentinel", new State(new Follow(.32, 10, 1), new Shoot(10, count: 4, shootAngle: 18, coolDown: 950)))
 .Init("Tideglass Oracle", new State(new StayBack(.25, 8), new Shoot(12, predictive: 1.2, coolDown: 900)))
 .Init("Reliquary Custodian", new State(new ScaleHP2(34,3,12), new Shoot(12,count:8,shootAngle:18,coolDown:700)), new Threshold(.01,new ItemLoot("Potion of Wisdom",.7)))
 .Init("Nacre Shield Pearl", new State(new Shoot(10,count:4,shootAngle:20,coolDown:950)))
 .Init("Nacre Warden", new State(new ScaleHP2(45,3,12), new State("Shielded",new Spawn("Nacre Shield Pearl",3,4,999999),new Shoot(14,count:5,shootAngle:18,projectileIndex:0,coolDown:750),new EntitiesNotExistsTransition(99,"Exposed","Nacre Shield Pearl")),new State("Exposed",new Shoot(16,count:3,predictive:1.2,projectileIndex:1,coolDown:500),new TimedTransition(9000,"Shielded"))),new Threshold(.01,new ItemLoot("Potion of Wisdom",1),new ItemLoot("Potion of Vitality",.8),new ItemLoot("Reliquary Mark",1),new ItemLoot("Nacre Talisman",.01)))
 ; } }
