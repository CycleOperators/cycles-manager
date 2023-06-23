/// A library meant to allow a single canister to act as a cycles battery for receiving requests from and topping up child canisters 

import { trap } "mo:base/Debug";
import Buffer "mo:base/Buffer";
import { message } "mo:base/Error";
import { abs } "mo:base/Int";
import { min; toText } "mo:base/Nat";
import { now } "mo:base/Time";
import Principal "mo:base/Principal";
import Result "mo:base/Result";

import BTree "mo:btree/BTree";
import InterfaceSpec "InterfaceSpec";
import SendCycles "SendCycles";

module {
  /*
   * PUBLIC TYPES
   */

  public type TransferCyclesResult = Result.Result<Nat, TransferCyclesError>;
  public type TransferCyclesError = {
    // The sending canister does not have enough cycles to send.
    #insufficient_cycles_available;
    // The requesting canister has asked for too few cycles.
    #too_few_cycles_requested;
    // The cycles manager has reached its aggregate quota.
    #aggregate_quota_reached;
    // The canister has reached its quota.
    #canister_quota_reached;
    // Some other error.
    #other : Text;
  };

  /// Interface that must be implemented by the "battery" canister in order for this library to work
  public type Interface = actor {
    // prefixed so that it won't conflict with any existing APIs on the implementing canister
    cycles_manager_transferCycles: shared (Nat) -> async TransferCyclesResult;
  };

  /// A quota for the maximum amount of cycles that can be spent during the specified duration
  public type RateQuota = {
    // The number of cycles that can be used by the canister during the quota duration period.
    maxAmount: Nat;
    // The duration of the quota period in seconds.
    duration_in_seconds: Nat;
  };

  /// Quota types for individual canisters 
  public type CanisterQuota = {
    // Canister will always be topped up with this amount 
    #fixedAmount: Nat;
    // The maximum number of cycles to top up the canister with
    #maxAmount: Nat;
    // Defines a rate at which the canister can request more cycles 
    #rate: RateQuota; 
    // A canister can use as many cycles as it wants
    #unlimited;
  };

  /// Quota types specified by the "Battery Canister" in which the Cycles Manager resides
  public type AggregateQuota = {
    #rate: RateQuota;
    #unlimited;
  };

  /// Default canister cycles settings that by default apply to all "child" canisters in the canisterToCyclesSettingsMap 
  /// These are overwritten by a canister specific cycles settings
  public type DefaultChildCanisterCyclesSettings = {
    // A default cycles quota setting for all canisters
    var quota: CanisterQuota;
  };

  /// Aggregate settings that applies to the cumulative cycles usage of all canisters
  public type AggregateCyclesSettings = {
    // A cycles quota setting for the aggregate cycles usage of all canisters
    var quota: AggregateQuota;
  };

  /// Single Canister specific cycles settings
  /// These overwrite the default child canister cycles settings
  public type CanisterCyclesSettings = {
    // The number of cycles that can be used by the canister in this period.
    // overwrites the default quota setting if set
    var quota: ?CanisterQuota;
  };

  /** 
   * INTERNAL TYPES
   */

  type InternalRateQuota = RateQuota and {
    // The timestamp after which the cyclesUsed field will reset
    var quotaPeriodExpiryTimestamp: Nat;
  };

  type InternalAggregateQuota = {
    #rate: InternalRateQuota;
    #unlimited;
  };

  // Quota types for individual canisters 
  type InternalCanisterQuota = {
    // Canister will always be topped up with this amount 
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
  type InternalDefaultChildCanisterCyclesSettings = {
    // A default cycles quota setting for all canisters
    var quota: InternalCanisterQuota;
  };

  // Aggregate settings that applies to the cumulative cycles usage of all canisters
  type InternalAggregateCyclesSettings = {
    // A cycles quota setting for the aggregate cycles usage of all canisters
    var quota: InternalAggregateQuota;
    // Tracks the total cycles used by all canisters
    var cyclesUsed: Nat;
  };

  // Single Canister specific cycles settings
  type InternalCanisterCyclesSettings = {
    // The number of cycles that can be used by the canister in this period.
    // overwrites the default quota setting if set
    var quota: ?InternalCanisterQuota;
    // The number of cycles that have been used by the canister during the current period.
    var cyclesUsed: Nat;
  };

  // Max # of cycles that can be requested by a canister per topup request
  // A mapping of canister principals to their cycles settings
  type ChildCanisterMap = BTree.BTree<Principal, InternalCanisterCyclesSettings>;

  // A type representing cycles management where the Index/Factory cansiter is responsible for
  // fielding requests from canisters and determining whether or not to top them up
  /**
  * Cycles Quota Priority
  *
  * 1. Aggregate Quota Cycles Setting - if a rate aggregate quota exists and it has been hit, then no more cycles will be funded from
  *                                     this cycles manager for the rest of the period
  * 2. Individual canister Cycles Quota Setting 
  * 3. Default Cycles Quota Settings - If a canister exists in the childCanisterMap, but no quota setting is provided for that canister,
  *                                   use the default (default) cycles quota setting
  *
  * If no individual or default quota is provided, the request for cycles is denied.
  * Also, if the individual canister does not exist in the childCanisterMap, it's request for cycles will be denied (access control)
  */
  type CyclesManager = {
    defaultSettings: InternalDefaultChildCanisterCyclesSettings;
    aggregateSettings: InternalAggregateCyclesSettings;    
    childCanisterMap: ChildCanisterMap;
    var minCyclesPerTopup: ?Nat; // recommended to set at least 50 billion
  };

  public func init({
    defaultCyclesSettings: DefaultChildCanisterCyclesSettings;
    aggregateSettings: AggregateCyclesSettings;
    minCyclesPerTopup: ?Nat;
  }): CyclesManager {
    {
      defaultSettings = {
        var quota = intitializeCanisterQuota(defaultCyclesSettings.quota)
      };
      aggregateSettings = {
        var quota = initializeAggregateCanisterQuota(aggregateSettings.quota);
        var cyclesUsed = 0;
      };
      childCanisterMap = BTree.init<Principal, InternalCanisterCyclesSettings>(null);
      var minCyclesPerTopup = minCyclesPerTopup;
    }
  };

  public func addChildCanister(cyclesManager: CyclesManager, canister: Principal, cyclesSettings: CanisterCyclesSettings): () {
    let internalCanisterCyclesSettings = {
      var quota = switch(cyclesSettings.quota) {
        case null { null };
        case (?q) { ?intitializeCanisterQuota(q) };
      };
      var cyclesUsed = 0;
    };
    ignore BTree.insert(cyclesManager.childCanisterMap, Principal.compare, canister, internalCanisterCyclesSettings);
  };

  public func removeChildCanister(cyclesManager: CyclesManager, canister: Principal): () {
    ignore BTree.delete(cyclesManager.childCanisterMap, Principal.compare, canister);
  };

  public func setMinCyclesPerTopup(cyclesManager: CyclesManager, minCyclesPerTopup: Nat): () {
    cyclesManager.minCyclesPerTopup := ?minCyclesPerTopup;
  };

  public func setDefaultCanisterCyclesQuota(cyclesManager: CyclesManager, quota: CanisterQuota): () {
    cyclesManager.defaultSettings.quota := intitializeCanisterQuota(quota);
  };

  public func setAggregateCyclesQuota(cyclesManager: CyclesManager, quota: AggregateQuota): () {
    cyclesManager.aggregateSettings.quota := initializeAggregateCanisterQuota(quota);
  };

  public func transferCycles({
    cyclesManager: CyclesManager;
    canister: Principal;
    cyclesRequested: Nat;
  }): async* TransferCyclesResult {
    let { defaultSettings; aggregateSettings; childCanisterMap } = cyclesManager;
    // Get the quota and cycles used for the canister
    // Will throw an error if the canister is not permitted (not present in the childCanisterMap)
    let { canisterSettings; quota } = getCanisterQuotaAndSettings(defaultSettings, childCanisterMap, canister);

    // If a minCyclesPerTopup is set, check that the canister is requesting at least that amount
    switch(cyclesManager.minCyclesPerTopup) {
      case null {};
      case (?minAmount) { 
        if (cyclesRequested < minAmount) return #err(#too_few_cycles_requested);
      }
    };

    // Check the aggregate cycles remaining for the cycles manager "battery" canister
    let aggregateCyclesRemaining = getAggregateCyclesRemaining(aggregateSettings, cyclesRequested); 
    if (aggregateCyclesRemaining == 0) return #err(#aggregate_quota_reached);

    // Check the max cycles that the canister is allowed to request
    let remainingCyclesForCanister = getCanisterCyclesRemaining(canisterSettings, quota, cyclesRequested); 
    if (remainingCyclesForCanister == 0) return #err(#canister_quota_reached);

    // The available cycles is the lesser of the aggregate cycles remaining and the remaining cycles for the canister
    let availableCycles = min(aggregateCyclesRemaining, remainingCyclesForCanister );
    // Grant the canister the lesser of the availableCycles and the cyclesRequested
    let grantableCycles = min(availableCycles, cyclesRequested);

    // send the cycles to the canister
    switch(await SendCycles.sendCycles(grantableCycles, canister)) {
      // If sending the cycles was successful, increment the cycles used for the canister 
      case (#ok(_)) { 
        canisterSettings.cyclesUsed += grantableCycles;
        aggregateSettings.cyclesUsed += grantableCycles;
        #ok(grantableCycles) 
      };
      // Covers all SendCyclesError cases
      case errorCases { errorCases }; 
    };
  };

  func intitializeCanisterQuota(quota: CanisterQuota): InternalCanisterQuota {
    switch(quota) {
      case (#fixedAmount(amt)) #fixedAmount(amt);
      case (#maxAmount(amt)) #maxAmount(amt); 
      case (#rate({ duration_in_seconds; maxAmount })) { 
        #rate({
          maxAmount;
          duration_in_seconds;
          var quotaPeriodExpiryTimestamp = abs(now()) + duration_in_seconds * 1_000_000_000;
        })
      };
      case (#unlimited) #unlimited;
    };
  };

  func initializeAggregateCanisterQuota(quota: AggregateQuota): InternalAggregateQuota {
    switch(quota) {
      case (#rate({ duration_in_seconds; maxAmount })) { 
        #rate({
          maxAmount;
          duration_in_seconds;
          var quotaPeriodExpiryTimestamp = abs(now()) + duration_in_seconds * 1_000_000_000;
        })
      };
      case (#unlimited) #unlimited;
    };
  };

  type CanisterQuotaAndSettings = {
    // The canister cycles settings
    canisterSettings: InternalCanisterCyclesSettings;
    // The quota to use for the canister
    quota: InternalCanisterQuota;
  };

  // Gets a canister's quota and cycles settings. This will use the canister specific cycles settings if exists,
  // or will use the default cycles settings otherwise.
  //
  // This function will trap if the canister does not exist in the child canister map
  func getCanisterQuotaAndSettings(
    defaultSettings: InternalDefaultChildCanisterCyclesSettings,
    childCanisterMap: ChildCanisterMap,
    canister: Principal
  ): CanisterQuotaAndSettings {
    let canisterSettings = switch (BTree.get(childCanisterMap, Principal.compare, canister)) {
      // If the canister is not in the map, use the default quota setting
      case null { trap("Canister is not permitted to request cycles") };
      case (?canisterSettings) canisterSettings;
    };

    switch (canisterSettings.quota) {
      // If the canister is present in the map, but has no specific quota setting, use the default quota setting
      case (null) ({ quota = defaultSettings.quota; canisterSettings });
      // If a canister-specific quota setting exists, use that
      case (?canisterQuota) ({ quota = canisterQuota; canisterSettings });
    };
  };

  func getAggregateCyclesRemaining(aggregateSettings: InternalAggregateCyclesSettings, cyclesRequested: Nat): Nat = switch(aggregateSettings.quota) {
    // In this case, null means no aggregate cycles quota exists on the battery canister
    case (#unlimited) { cyclesRequested };
    // The developer has set an aggregate quota
    case (#rate(rateQuota)) {
      // Get the current time in seconds
      let currentTime = abs(now()) / 1_000_000_000;
      // If the quota period has expired, reset the cycles used and the quota period expiry time
      if (currentTime >= rateQuota.quotaPeriodExpiryTimestamp) {
        aggregateSettings.cyclesUsed := 0;
        rateQuota.quotaPeriodExpiryTimestamp := currentTime + rateQuota.duration_in_seconds * 1_000_000_000; 
      };

      let cyclesRemaining = getDifferenceOrZero(rateQuota.maxAmount, aggregateSettings.cyclesUsed);
      cyclesRemaining;
    };
  };

  func getCanisterCyclesRemaining(
    canisterSettings: InternalCanisterCyclesSettings,
    quota: InternalCanisterQuota,
    cyclesRequested: Nat
  ): Nat = switch(quota) {
    case (#fixedAmount(amt)) { amt };
    case (#maxAmount(amt)) { getDifferenceOrZero(amt, canisterSettings.cyclesUsed) };
    case (#rate(rateQuota)) {
      // Get the current time in seconds
      let currentTime = abs(now()) / 1_000_000_000;
      // If the quota period has expired, reset the cycles used and the quota period expiry time
      if (currentTime >= rateQuota.quotaPeriodExpiryTimestamp) {
        canisterSettings.cyclesUsed := 0;
        rateQuota.quotaPeriodExpiryTimestamp := currentTime + rateQuota.duration_in_seconds * 1_000_000_000;
      };

      let cyclesRemaining = getDifferenceOrZero(rateQuota.maxAmount, canisterSettings.cyclesUsed);
      cyclesRemaining;
    };
    // If unlimited, then the canister can definitely used the cycles requested
    case (#unlimited) { cyclesRequested };
  };

  // If a > b return their difference, otherwise return 0
  func getDifferenceOrZero(a: Nat, b: Nat): Nat {
    if (a > b) { a - b } else { 0 }
  };
}