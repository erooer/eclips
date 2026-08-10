using System; using System.Collections.Concurrent; using System.Collections.Generic; using System.Linq; using common;
namespace wServer.realm
{
 public sealed class Party { public string Id; public int Leader; public HashSet<int> Members=new HashSet<int>(); }
 public static class PartyService
 {
  const int Max=10; static readonly ConcurrentDictionary<string,Party> Parties=new ConcurrentDictionary<string,Party>(); static readonly ConcurrentDictionary<int,string> Pending=new ConcurrentDictionary<int,string>();
  public static string Create(DbAccount a){if(!string.IsNullOrEmpty(a.PartyState))return "Already in a party.";var p=new Party{Id=Guid.NewGuid().ToString("N"),Leader=a.AccountId};p.Members.Add(a.AccountId);Parties[p.Id]=p;a.PartyState=p.Id;a.FlushAsync().Wait();return "Party created.";}
  public static string Invite(DbAccount leader, DbAccount target){Party p;if(!Parties.TryGetValue(leader.PartyState,out p)||p.Leader!=leader.AccountId)return "Only the leader may invite.";if(p.Members.Count>=Max)return "Party is full.";if(!string.IsNullOrEmpty(target.PartyState))return "Player is already in a party.";Pending[target.AccountId]=p.Id;return "Invitation sent.";}
  public static string Accept(DbAccount a){string id;Party p;if(!Pending.TryRemove(a.AccountId,out id)||!Parties.TryGetValue(id,out p))return "No pending party invitation.";lock(p){if(p.Members.Count>=Max)return "Party is full."; if(!string.IsNullOrEmpty(a.PartyState))return "Already in a party.";p.Members.Add(a.AccountId);a.PartyState=id;a.FlushAsync().Wait();return "Joined party.";}}
  public static string Leave(DbAccount a){Party p;if(!Parties.TryGetValue(a.PartyState,out p))return "Not in a party.";lock(p){p.Members.Remove(a.AccountId);a.PartyState="";a.FlushAsync().Wait();if(p.Members.Count==0)Parties.TryRemove(p.Id,out p);else if(p.Leader==a.AccountId)p.Leader=p.Members.Min();return "Left party.";}}
  public static string Status(DbAccount a){Party p;return Parties.TryGetValue(a.PartyState,out p)?"Party "+p.Id.Substring(0,6)+": "+p.Members.Count+"/10; leader "+p.Leader:"Not in a party.";}
 }
}
