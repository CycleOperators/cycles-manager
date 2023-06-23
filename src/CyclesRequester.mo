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

  public type CyclesRequester = {
    batteryCanisterPrincipal: Principal;
    var topupRule: TopupRule;
  };

  public func init({
    batteryCanisterPrincipal: Principal;
    topupRule: TopupRule;
  }): CyclesRequester = {
    batteryCanisterPrincipal;
    var topupRule = topupRule;
  };

  public func setTopupRule(cyclesRequester: CyclesRequester, topupRule: TopupRule) {
    cyclesRequester.topupRule := topupRule;
  };

  public func isBelowCyclesThreshold(cyclesRequester: CyclesRequester): async Bool {
    balance() < cyclesRequester.topupRule.threshold;
  };

  public func initiateTopup(cyclesRequester: CyclesRequester): async CyclesManager.TransferCyclesResult {
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
  }
}