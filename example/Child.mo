import CyclesRequester "../src/CyclesRequester";
import CyclesManager "../src/CyclesManager";

import { print } "mo:base/Debug";

actor Child {
  
  // Stable variable holding the cycles requester
  stable var cyclesRequester: ?CyclesRequester.CyclesRequester = null;

  // Initialize the cycles requester
  // As an alternative, you can also initialize the cycles requester in the constructor
  public func initializeCyclesRequester(
    batteryCanisterPrincipal: Principal,
    topupRule: CyclesRequester.TopupRule,
  ) {
    cyclesRequester := ?CyclesRequester.init({
      batteryCanisterPrincipal;
      topupRule
    });
  };

  // An example of adding cycles request functionality to an arbitrary update function
  public func justAnotherUpdateFunction(): async () {
    // before doing something, check if we need to request cycles
    let result = await* requestTopupIfLow();
    print(debug_show(result));

    // do something in the rest of the function;
  };

  // Local helper function you can use in your actor if the cyclesRequester could possibly be null
  func requestTopupIfLow(): async* CyclesManager.TransferCyclesResult {
    switch(cyclesRequester) {
      case null #err(#other("CyclesRequester not initialized"));
      case (?requester) await* CyclesRequester.requestTopupIfBelowThreshold(requester);
    }
  }; 
}