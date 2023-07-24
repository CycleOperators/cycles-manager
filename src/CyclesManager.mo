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
import Internal "Internal";

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
    durationInSeconds: Nat;
  };

  /// Quota types for individual canisters 
  public type CanisterQuota = {
    // Canister will always be topped up with this amount, ignores cyclesUsed  
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
    quota: CanisterQuota;
  };

  /// Aggregate settings that applies to the cumulative cycles usage of all canisters
  public type AggregateCyclesSettings = {
    // A cycles quota setting for the aggregate cycles usage of all canisters
    quota: AggregateQuota;
  };

  /// Single Canister specific cycles settings
  /// These overwrite the default child canister cycles settings
  public type CanisterCyclesSettings = {
    // The number of cycles that can be used by the canister in this period.
    // overwrites the default quota setting if set
    quota: ?CanisterQuota;
  };

  /// Max # of cycles that can be requested by a canister per topup request
  /// A mapping of canister principals to their cycles settings
  public type ChildCanisterMap = BTree.BTree<Principal, Internal.InternalCanisterCyclesSettings>;

  /// A type representing cycles management where the Index/Factory cansiter is responsible for
  /// fielding requests from canisters and determining whether or not to top them up
  ///
  /// Cycles Quota Priority
  ///
  /// 1. Aggregate Quota Cycles Setting - if a rate aggregate quota exists and it has been hit, then no more cycles will be funded from
  ///                                     this cycles manager for the rest of the period
  /// 2. Individual canister Cycles Quota Setting 
  /// 3. Default Cycles Quota Settings - If a canister exists in the childCanisterMap, but no quota setting is provided for that canister,
  ///                                   use the default (default) cycles quota setting
  /// 
  /// If no individual or default quota is provided, the request for cycles is denied.
  /// Also, if the individual canister does not exist in the childCanisterMap, it's request for cycles will be denied (access control)
  public type CyclesManager = {
    defaultSettings: Internal.InternalDefaultChildCanisterCyclesSettings;
    aggregateSettings: Internal.InternalAggregateCyclesSettings;    
    childCanisterMap: ChildCanisterMap;
    var minCyclesPerTopup: ?Nat; // recommended to set at least 50 billion
  };

  /// Initializes a CyclesManager
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
      childCanisterMap = BTree.init<Principal, Internal.InternalCanisterCyclesSettings>(null);
      var minCyclesPerTopup = minCyclesPerTopup;
    }
  };

  /// Adds a child canister to the CyclesManager
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

  /// Removes a child canister from the CyclesManager
  public func removeChildCanister(cyclesManager: CyclesManager, canister: Principal): () {
    ignore BTree.delete(cyclesManager.childCanisterMap, Principal.compare, canister);
  };

  /// Sets the minimum number of cycles that a canister can request per topup
  public func setMinCyclesPerTopup(cyclesManager: CyclesManager, minCyclesPerTopup: Nat): () {
    cyclesManager.minCyclesPerTopup := ?minCyclesPerTopup;
  };

  /// Sets the default canister cycles quota
  public func setDefaultCanisterCyclesQuota(cyclesManager: CyclesManager, quota: CanisterQuota): () {
    cyclesManager.defaultSettings.quota := intitializeCanisterQuota(quota);
  };

  /// Sets the aggregate canister cycles quota
  public func setAggregateCyclesQuota(cyclesManager: CyclesManager, quota: AggregateQuota): () {
    cyclesManager.aggregateSettings.quota := initializeAggregateCanisterQuota(quota);
  };

  /// Attempts to transfers cycles to a canister principal
  public func transferCycles({
    cyclesManager: CyclesManager;
    canister: Principal;
    cyclesRequested: Nat;
  }): async* TransferCyclesResult {
    await* internal_DO_NOT_USE_TransferCycles({
      cyclesManager;
      canister;
      cyclesRequested;
      sendCycles = SendCycles.sendCycles;
    });
  };

  public func toText(cyclesManager: CyclesManager): Text {
    let { defaultSettings; aggregateSettings; childCanisterMap } = cyclesManager;
    let defaultSettingsText = "{ quota = " # debug_show(defaultSettings.quota) # "}";
    let aggregateSettingsText = "{ quota = " # debug_show(aggregateSettings.quota) # ", cyclesUsed = " # debug_show(aggregateSettings.cyclesUsed) # " }";
    let childCanisterMapText = BTree.toText<Principal, Internal.InternalCanisterCyclesSettings>(
      childCanisterMap,
      Principal.toText,
      func(cyclesSettings: Internal.InternalCanisterCyclesSettings): Text {
        "{ quota = " # debug_show(cyclesSettings.quota) # ", cyclesUsed = " # debug_show(cyclesSettings.cyclesUsed) # " }"
      },
    );
    "CyclesManager { defaultSettings = " # defaultSettingsText # ", aggregateSettings = " # aggregateSettingsText # ", childCanisterMap = " # childCanisterMapText # ", minCyclesPerTopup = " # debug_show(cyclesManager.minCyclesPerTopup) # " }";
  };

  /* INTERNAL FUNCTIONS, exposed for testing purposes only */

  /// @deprecated - this is an internal function whose only purpose is to allow async unit testing. Do not use directly!
  public func internal_DO_NOT_USE_TransferCycles({
    cyclesManager: CyclesManager;
    canister: Principal;
    cyclesRequested: Nat;
    sendCycles: (Nat, Principal) -> async SendCycles.SendCyclesResult;
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

    // Before the commit point, update the cycles used for the canister and the aggregate cycles used so that
    // any requests that come in within the same round will be able to see the updated cycles used
    canisterSettings.cyclesUsed += grantableCycles;
    aggregateSettings.cyclesUsed += grantableCycles;
    // send the cycles to the canister
    switch(await sendCycles(grantableCycles, canister)) {
      // If sending the cycles was successful, return the amount of cycles sent 
      case (#ok(cyclesSent)) #ok(cyclesSent);
      // If sending the cycles failed for any reason, decrement the cycles used for the canister (release the grantableCycles)
      // Covers all SendCyclesError cases
      case (#err(errorCases)) { 
        canisterSettings.cyclesUsed -= grantableCycles;
        aggregateSettings.cyclesUsed -= grantableCycles;
        #err(errorCases) 
      };
    };
  };

  func intitializeCanisterQuota(quota: CanisterQuota): Internal.InternalCanisterQuota {
    switch(quota) {
      case (#fixedAmount(amt)) #fixedAmount(amt);
      case (#maxAmount(amt)) #maxAmount(amt); 
      case (#rate({ durationInSeconds; maxAmount })) { 
        #rate({
          maxAmount;
          durationInSeconds;
          var quotaPeriodExpiryTimestamp = abs(now()) + durationInSeconds * 1_000_000_000;
        })
      };
      case (#unlimited) #unlimited;
    };
  };

  func initializeAggregateCanisterQuota(quota: AggregateQuota): Internal.InternalAggregateQuota {
    switch(quota) {
      case (#rate({ durationInSeconds; maxAmount })) { 
        #rate({
          maxAmount;
          durationInSeconds;
          var quotaPeriodExpiryTimestamp = abs(now()) + durationInSeconds * 1_000_000_000;
        })
      };
      case (#unlimited) #unlimited;
    };
  };

  type CanisterQuotaAndSettings = {
    // The canister cycles settings
    canisterSettings: Internal.InternalCanisterCyclesSettings;
    // The quota to use for the canister
    quota: Internal.InternalCanisterQuota;
  };

  // Gets a canister's quota and cycles settings. This will use the canister specific cycles settings if exists,
  // or will use the default cycles settings otherwise.
  //
  // This function will trap if the canister does not exist in the child canister map
  func getCanisterQuotaAndSettings(
    defaultSettings: Internal.InternalDefaultChildCanisterCyclesSettings,
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

  func getAggregateCyclesRemaining(aggregateSettings: Internal.InternalAggregateCyclesSettings, cyclesRequested: Nat): Nat = switch(aggregateSettings.quota) {
    // In this case, null means no aggregate cycles quota exists on the battery canister
    case (#unlimited) { cyclesRequested };
    // The developer has set an aggregate quota
    case (#rate(rateQuota)) {
      // Get the current time
      let currentTime = abs(now());
      // If the quota period has expired, reset the cycles used and the quota period expiry time
      if (currentTime >= rateQuota.quotaPeriodExpiryTimestamp) {
        aggregateSettings.cyclesUsed := 0;
        rateQuota.quotaPeriodExpiryTimestamp := currentTime + rateQuota.durationInSeconds * 1_000_000_000; 
      };

      let cyclesRemaining = getDifferenceOrZero(rateQuota.maxAmount, aggregateSettings.cyclesUsed);
      cyclesRemaining;
    };
  };

  func getCanisterCyclesRemaining(
    canisterSettings: Internal.InternalCanisterCyclesSettings,
    quota: Internal.InternalCanisterQuota,
    cyclesRequested: Nat
  ): Nat = switch(quota) {
    case (#fixedAmount(amt)) { amt };
    case (#maxAmount(amt)) { getDifferenceOrZero(amt, canisterSettings.cyclesUsed) };
    case (#rate(rateQuota)) {
      // Get the current time
      let currentTime = abs(now());
      // If the quota period has expired, reset the cycles used and the quota period expiry time
      if (currentTime >= rateQuota.quotaPeriodExpiryTimestamp) {
        canisterSettings.cyclesUsed := 0;
        rateQuota.quotaPeriodExpiryTimestamp := currentTime + rateQuota.durationInSeconds * 1_000_000_000;
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