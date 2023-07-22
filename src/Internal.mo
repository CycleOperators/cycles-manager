/// DO NOT USE - these are internal types that may change and are not meant to be used by the developer 

import SendCycles "SendCycles";
import Result "mo:base/Result";

module {
  /** 
  * INTERNAL TYPES
  */

  public type InternalRateQuota = {
    // The number of cycles that can be used by the canister during the quota duration period.
    maxAmount: Nat;
    // The duration of the quota period in seconds.
    durationInSeconds: Nat;
    // The timestamp after which the cyclesUsed field will reset
    var quotaPeriodExpiryTimestamp: Nat;
  };

  public type InternalAggregateQuota = {
    #rate: InternalRateQuota;
    #unlimited;
  };

  // Quota types for individual canisters 
  public type InternalCanisterQuota = {
    // Canister will always be topped up with this amount, ignores cyclesUsed 
    #fixedAmount: Nat;
    // The maximum number of cycles to top up the canister with
    #maxAmount: Nat;
    // Defines a rate at which the canister can request more cycles 
    #rate: InternalRateQuota; 
    // A canister can use as many cycles as it wants
    #unlimited;
  };

  // Default canister cycles settings that by default apply to all "child" canisters in the canisterToCyclesSettingsMap 
  // these are overwritten by a canister specific cycles settings
  public type InternalDefaultChildCanisterCyclesSettings = {
    // A default cycles quota setting for all canisters
    var quota: InternalCanisterQuota;
  };

  // Aggregate settings that applies to the cumulative cycles usage of all canisters
  public type InternalAggregateCyclesSettings = {
    // A cycles quota setting for the aggregate cycles usage of all canisters
    var quota: InternalAggregateQuota;
    // Tracks the total cycles used by all canisters
    var cyclesUsed: Nat;
  };

  // Single Canister specific cycles settings
  public type InternalCanisterCyclesSettings = {
    // The number of cycles that can be used by the canister in this period.
    // overwrites the default quota setting if set
    var quota: ?InternalCanisterQuota;
    // The number of cycles that have been used by the canister during the current period.
    var cyclesUsed: Nat;
  };
}