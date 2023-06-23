import Result "mo:base/Result";
import { add } "mo:base/ExperimentalCycles";
import { IC } "./InterfaceSpec";

module {
  public type SendCyclesResult = Result.Result<Nat, SendCyclesError>;
  public type SendCyclesError = {
    // The sending canister does not have enough cycles to send.
    #insufficient_cycles_available;
    // Some other error.
    #other : Text;
  };

  /// Sends cycles to a canister. Is a wrapper around deposit_cycles
  public func sendCycles(
    amount : Nat,
    canisterId : Principal,
  ) : async SendCyclesResult {
    try {
      add(amount);
      await IC.deposit_cycles({ canister_id = canisterId });
      #ok(amount);
    } catch (_) {
      #err(#other "Error sending cycles.");
    }
  };

}