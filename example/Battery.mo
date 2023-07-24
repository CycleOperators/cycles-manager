import { logand } "mo:base/Bool";
import { trap } "mo:base/Debug";
import Principal "mo:base/Principal";
import { endsWith; size } "mo:base/Text";
import CyclesManager "mo:cycles-manager/CyclesManager";

// A simple battery canister actor example that implements the cycles_manager_transferCycles API of the CyclesManager.Interface 

actor Battery {
  // Initializes a cycles manager
  stable let cyclesManager = CyclesManager.init({
    // By default, with each transfer request 500 billion cycles will be transferred
    // to the requesting canister, provided they are permitted to request cycles
    //
    // This means that if a canister is added with no quota, it will default to the quota of #fixedAmount(500)
    defaultCyclesSettings = {
      quota = #fixedAmount(500_000_000_000);
    };
    // Allow an aggregate of 10 trillion cycles to be transferred every 24 hours 
    aggregateSettings = {
      quota = #rate({
        maxAmount = 10_000_000_000_000;
        durationInSeconds = 24 * 60 * 60;
      });
    };
    // 50 billion is a good default minimum for most low use canisters
    minCyclesPerTopup = ?50_000_000_000;
  });

  // @required - IMPORTANT!!!
  // Allows canisters to request cycles from this "battery canister" that implements
  // the cycles manager
  public shared ({ caller }) func cycles_manager_transferCycles(
    cyclesRequested: Nat
  ): async CyclesManager.TransferCyclesResult {
    if (not isCanister(caller)) trap("Calling principal must be a canister");
    
    let result = await* CyclesManager.transferCycles({
      cyclesManager;
      canister = caller;
      cyclesRequested;
    });
    result;
  };

  // A very basic example of adding a canister to the cycles manager
  // This adds a canister with a 1 trillion cycles allowed per 24 hours cycles quota
  //
  // IMPORTANT: Add authoriation for production implementation so that not just any canister
  // can add themself
  public shared func addCanisterWith1TrillionPer24HoursLimit(canisterId: Principal) {
    CyclesManager.addChildCanister(cyclesManager, canisterId, {
      // This topup rule all1 Trillion every 24 hours
      quota = ?(#rate({
        maxAmount = 1_000_000_000_000;
        durationInSeconds = 24 * 60 * 60;
      }));
    })
  };

  // **DO NOT USE IN PRODUCTION** - for developer debugging and testing purposes only
  public func toText() : async Text {
    let result = CyclesManager.toText(cyclesManager);
    result;
  };

  func isCanister(p : Principal) : Bool {
    let principal_text = Principal.toText(p);
    // Canister principals have 27 characters
    size(principal_text) == 27
    and
    // Canister principals end with "-cai"
    endsWith(principal_text, #text "-cai");
  };
}