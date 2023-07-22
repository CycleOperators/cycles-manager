/// The CyclesRequester module is meant to be used by canisters that need to request cycles from a battery canister that implements the CyclesManager interface.

import { toText } "mo:base/Principal";
import { message } "mo:base/Error";
import { balance } "mo:base/ExperimentalCycles";
import SendCycles "SendCycles";
import CyclesManager "CyclesManager";

module {
  public type Cycles = Nat;

  /// For resources on choosing a good topup rule, check out https://www.notion.so/cycleops/Best-Practices-for-Top-up-Rules-e3e9458ec96f46129533f58016f66f6e
  public type TopupRule = {
    // Top-up when <= this cycle threshold.
    threshold : Cycles;

    // Method of determining amount of cycles to top-up with.
    method : {

      // Top-up with enough cycles to restore the specified balance.
      // i.e. `threshold`      = 10 | 10 | 10
      //      `toBalance`      = 20 | 20 | 20
      //      `balance`        = 8  | 10 | 12
      //      `cyclesToSend`   = 12 | 10 | 0
      #to_balance : Cycles;

      // Top-up to with a fixed amount of cycles.
      // i.e. `threshold`    = 10 | 10 | 10
      //      `topUpAmount`  = 5  | 5  | 5
      //      `balance`      = 8  | 10 | 12
      //      `cyclesToSend` = 5  | 5  | 0
      #by_amount : Cycles;
    };
  };

  /// The cycles requester type, containing the principal of the "battery canister", or the canister
  /// From which cycles are requested, and a topup rule.
  public type CyclesRequester = {
    batteryCanisterPrincipal: Principal;
    var topupRule: TopupRule;
  };

  /// Initialize a cycles requester.
  public func init({
    batteryCanisterPrincipal: Principal;
    topupRule: TopupRule;
  }): CyclesRequester = {
    batteryCanisterPrincipal;
    var topupRule = topupRule;
  };

  /// Sets the topup rule for a cycles requester.
  public func setTopupRule(cyclesRequester: CyclesRequester, topupRule: TopupRule) {
    cyclesRequester.topupRule := topupRule;
  };

  /// Returns a boolean representing if the canister is below its set cycles threshold.
  public func isBelowCyclesThreshold(cyclesRequester: CyclesRequester): Bool {
    balance() < cyclesRequester.topupRule.threshold;
  };

  /// Requests a topup according to the set topup rule if the canister is below its cycles threshold.
  public func requestTopupIfBelowThreshold(cyclesRequester: CyclesRequester): async* CyclesManager.TransferCyclesResult {
    if (isBelowCyclesThreshold(cyclesRequester)) {
      try {
        return await requestTopup(cyclesRequester);
      } catch(error) {
        return #err(#other(message(error)));
      }
    } else {
      return #ok(0);
    }
  };

  /// Requests a specific amount of cycles from the battery canister.
  public func requestCyclesAmount(cyclesRequester: CyclesRequester, amount: Nat): async CyclesManager.TransferCyclesResult {
    let battery: CyclesManager.Interface = actor (toText(cyclesRequester.batteryCanisterPrincipal));
    try {
      let result = await battery.cycles_manager_transferCycles(amount);
      return result;
    } catch(error) {
      return #err(#other(message(error)));
    }
  };

  func requestTopup(cyclesRequester: CyclesRequester): async CyclesManager.TransferCyclesResult {
    let battery: CyclesManager.Interface = actor (toText(cyclesRequester.batteryCanisterPrincipal));
    let currentBalance = balance();
    let amountToRequest = switch(cyclesRequester.topupRule.method) {
      case (#to_balance(toBalance)) {
        if (currentBalance >= toBalance) return #ok(0);
        toBalance - currentBalance : Nat;
      };
      case (#by_amount(topUpAmount)) topUpAmount;
    };
    try {
      let result = await battery.cycles_manager_transferCycles(amountToRequest);
      return result;
    } catch(error) {
      return #err(#other(message(error)));
    }
  };
}