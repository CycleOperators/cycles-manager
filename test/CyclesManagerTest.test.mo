import BTree "mo:btree/BTree";
import Principal "mo:base/Principal";
import { describe; it; its; Suite } = "mo:testing/Suite";
import { assertAllTrue } = "mo:testing/Assert";
import CM "../src/CyclesManager";
import Internal "../src/Internal";
import SendCycles "../src/SendCycles";

func internalRateQuotasEqual(
  r1: Internal.InternalRateQuota,
  r2: Internal.InternalRateQuota,
): Bool {
  (r1.quotaPeriodExpiryTimestamp == r2.quotaPeriodExpiryTimestamp)
  and
  (r1.maxAmount == r2.maxAmount)
  and
  (r1.durationInSeconds == r2.durationInSeconds);
};

func internalCanisterQuotasEqual(
  quota1: Internal.InternalCanisterQuota,
  quota2: Internal.InternalCanisterQuota
): Bool {
  switch(quota1, quota2) {
    case (#fixedAmount(q1), #fixedAmount(q2)) q1 == q2;
    case (#maxAmount(q1), #maxAmount(q2)) q1 == q2;
    case (#rate(r1), #rate(r2)) internalRateQuotasEqual(r1, r2);
    case (#unlimited, #unlimited) true;
    case _ return false;
  };
};

func internalCanisterCyclesSettingsEqual(s1: Internal.InternalCanisterCyclesSettings, s2: Internal.InternalCanisterCyclesSettings): Bool {
  if (s1.cyclesUsed != s2.cyclesUsed) return false;

  switch(s1.quota, s2.quota) {
    case (?q1, ?q2) internalCanisterQuotasEqual(q1, q2);
    case (null, null) true;
    case _ false;
  };
};

func defaultSettingsEqual(
  s1: Internal.InternalDefaultChildCanisterCyclesSettings,
  s2: Internal.InternalDefaultChildCanisterCyclesSettings
): Bool {
  internalCanisterQuotasEqual(s1.quota, s2.quota); 
};

func aggregateSettingsEqual(
  s1: Internal.InternalAggregateCyclesSettings,
  s2: Internal.InternalAggregateCyclesSettings
): Bool {
  if (s1.cyclesUsed != s2.cyclesUsed) return false;
  switch(s1.quota, s2.quota) {
    case (#rate(r1), #rate(r2)) internalRateQuotasEqual(r1, r2);
    case (#unlimited, #unlimited) true;
    case _ return false;
  };
};

func childCanisterMapsEqual(
  m1: CM.ChildCanisterMap,
  m2: CM.ChildCanisterMap,
): Bool {
  BTree.equals<Principal, Internal.InternalCanisterCyclesSettings>(
    m1,
    m2,
    Principal.equal,
    internalCanisterCyclesSettingsEqual
  );
};

func cyclesManagersEqual(c1: CM.CyclesManager, c2: CM.CyclesManager): Bool {
  // default settings equal
  if (not defaultSettingsEqual(c1.defaultSettings, c2.defaultSettings)) return false; 
  
  // aggregate settings equal
  if (not aggregateSettingsEqual(c1.aggregateSettings, c2.aggregateSettings)) return false;

  // child canister maps equal
  if (not childCanisterMapsEqual(c1.childCanisterMap, c2.childCanisterMap)) return false;

  c1.minCyclesPerTopup == c2.minCyclesPerTopup;
};


type State = {};

let s = Suite();

let initSuite = describe("init", [
  it(
    "initializes a cycles manager with the expected defaults",
    func(): Bool {
      cyclesManagersEqual(
        CM.init({
          defaultCyclesSettings = {
            quota = #rate({
              maxAmount = 1_000_000_000_000;
              durationInSeconds = 60 * 60 * 24;
            })
          };
          aggregateSettings = {
            quota = #unlimited;
          };
          minCyclesPerTopup = ?50_000_000_000;
        }),
        {
          defaultSettings = {
            var quota = #rate({
              maxAmount = 1_000_000_000_000;
              durationInSeconds = 60 * 60 * 24;
              var quotaPeriodExpiryTimestamp = 86_400_000_000_042;
            });
          };
          aggregateSettings = {
            var quota = #unlimited;
            var cyclesUsed = 0;
          };
          childCanisterMap = BTree.init<Principal, Internal.InternalCanisterCyclesSettings>(null);
          var minCyclesPerTopup = ?50_000_000_000;
        }
      )
    }
  )
]);

let addChildCanisterSuite = describe("addChildCanister", [
  it(
    "if a quota is non-null, adds a child canister to the child canister map of the cycles manager with that quota setting",
    func(): Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 1_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          })
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#fixedAmount(500_000_000_000);
        }
      );

      cyclesManagersEqual(
        cyclesManager,
        {
          defaultSettings = {
            var quota = #rate({
              maxAmount = 1_000_000_000_000;
              durationInSeconds = 60 * 60 * 24;
              var quotaPeriodExpiryTimestamp = 86_400_000_000_042;
            });
          };
          aggregateSettings = {
            var quota = #unlimited;
            var cyclesUsed = 0;
          };
          childCanisterMap = BTree.fromArray<Principal, Internal.InternalCanisterCyclesSettings>(
            32,
            Principal.compare,
            [
              (
                Principal.fromText("aaaaa-aa"),
                {
                  var quota = ?#fixedAmount(500_000_000_000);
                  var cyclesUsed = 0;
                }
              )
            ]
          );
          var minCyclesPerTopup = ?50_000_000_000;
        }
      )
    }
  ),
  it(
    "if a quota is null, adds a child canister to the child canister map of the cycles manager with a null quota setting",
    func(): Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 1_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          })
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = null;
        } 
      );

      cyclesManagersEqual(
        cyclesManager,
        {
          defaultSettings = {
            var quota = #rate({
              maxAmount = 1_000_000_000_000;
              durationInSeconds = 60 * 60 * 24;
              var quotaPeriodExpiryTimestamp = 86_400_000_000_042;
            });
          };
          aggregateSettings = {
            var quota = #unlimited;
            var cyclesUsed = 0;
          };
          childCanisterMap = BTree.fromArray<Principal, Internal.InternalCanisterCyclesSettings>(
            32,
            Principal.compare,
            [
              (
                Principal.fromText("aaaaa-aa"),
                {
                  var quota = null;
                  var cyclesUsed = 0;
                }
              )
            ]
          );
          var minCyclesPerTopup = ?50_000_000_000;
        }
      )
    }
  )
]);

let removeChildCanisterSuite = describe("removeChildCanister", [
  it(
    "if the child canister is in the child canister map of the cycles manager, removes it",
    func(): Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 1_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          })
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#fixedAmount(500_000_000_000);
        }
      );
      CM.removeChildCanister(cyclesManager, Principal.fromText("aaaaa-aa"));

      cyclesManagersEqual(
        cyclesManager,
        {
          defaultSettings = {
            var quota = #rate({
              maxAmount = 1_000_000_000_000;
              durationInSeconds = 60 * 60 * 24;
              var quotaPeriodExpiryTimestamp = 86_400_000_000_042;
            });
          };
          aggregateSettings = {
            var quota = #unlimited;
            var cyclesUsed = 0;
          };
          childCanisterMap = BTree.init<Principal, Internal.InternalCanisterCyclesSettings>(null);
          var minCyclesPerTopup = ?50_000_000_000;
        }
      )
    }
  ),
  it(
    "if there is more than one child canister in the child canister map of the cycles manager, removes only the specified child canister",
    func(): Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 1_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          })
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#fixedAmount(500_000_000_000);
        }
      );
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("rdmx6-jaaaa-aaaaa-aaadq-cai"),
        {
          quota = ?#fixedAmount(500_000_000_000);
        }
      );
      CM.removeChildCanister(cyclesManager, Principal.fromText("aaaaa-aa"));

      cyclesManagersEqual(
        cyclesManager,
        {
          defaultSettings = {
            var quota = #rate({
              maxAmount = 1_000_000_000_000;
              durationInSeconds = 60 * 60 * 24;
              var quotaPeriodExpiryTimestamp = 86_400_000_000_042;
            });
          };
          aggregateSettings = {
            var quota = #unlimited;
            var cyclesUsed = 0;
          };
          childCanisterMap = BTree.fromArray<Principal, Internal.InternalCanisterCyclesSettings>(
            32,
            Principal.compare,
            [
              (
                Principal.fromText("rdmx6-jaaaa-aaaaa-aaadq-cai"),
                {
                  var quota = ?#fixedAmount(500_000_000_000);
                  var cyclesUsed = 0;
                }
              )
            ]
          );
          var minCyclesPerTopup = ?50_000_000_000;
        }
      )
    }
  )
]);

let setMinCyclesPerTopupSuite = describe("setMinCyclesPerTopup", [
  it(
    "sets the minCyclePerTopup field of the cycles manager to the specified value",
    func(): Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 1_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          })
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.setMinCyclesPerTopup(cyclesManager, 100_000_000_000);

      cyclesManagersEqual(
        cyclesManager,
        {
          defaultSettings = {
            var quota = #rate({
              maxAmount = 1_000_000_000_000;
              durationInSeconds = 60 * 60 * 24;
              var quotaPeriodExpiryTimestamp = 86_400_000_000_042;
            });
          };
          aggregateSettings = {
            var quota = #unlimited;
            var cyclesUsed = 0;
          };
          childCanisterMap = BTree.init<Principal, Internal.InternalCanisterCyclesSettings>(null);
          var minCyclesPerTopup = ?100_000_000_000;
        }
      )
    }
  )
]);

let setDefaultCanisterCyclesQuotaSuite = describe("setDefaultCanisterCyclesQuota", [
  it(
    "sets the defaultCyclesSettings.quota field of the cycles manager to the specified value",
    func(): Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 1_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          })
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.setDefaultCanisterCyclesQuota(
        cyclesManager,
        #rate({
          maxAmount = 2_000_000_000_000;
          durationInSeconds = 60 * 60 * 24;
        })
      );

      cyclesManagersEqual(
        cyclesManager,
        {
          defaultSettings = {
            var quota = #rate({
              maxAmount = 2_000_000_000_000;
              durationInSeconds = 60 * 60 * 24;
              var quotaPeriodExpiryTimestamp = 86_400_000_000_042;
            });
          };
          aggregateSettings = {
            var quota = #unlimited;
            var cyclesUsed = 0;
          };
          childCanisterMap = BTree.init<Principal, Internal.InternalCanisterCyclesSettings>(null);
          var minCyclesPerTopup = ?50_000_000_000;
        }
      )
    }
  )
]);

let setAggregateCyclesQuotaSuite = describe("setAggregateCyclesQuota", [
  it(
    "sets the aggregateSettings.quota field of the cycles manager to the specified value",
    func(): Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 1_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          })
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.setAggregateCyclesQuota(
        cyclesManager,
        #rate({
          maxAmount = 2_000_000_000_000;
          durationInSeconds = 60 * 60 * 24;
        })
      );

      cyclesManagersEqual(
        cyclesManager,
        {
          defaultSettings = {
            var quota = #rate({
              maxAmount = 1_000_000_000_000;
              durationInSeconds = 60 * 60 * 24;
              var quotaPeriodExpiryTimestamp = 86_400_000_000_042;
            });
          };
          aggregateSettings = {
            var quota = #rate({
              maxAmount = 2_000_000_000_000;
              durationInSeconds = 60 * 60 * 24;
              var quotaPeriodExpiryTimestamp = 86_400_000_000_042;
            });
            var cyclesUsed = 0;
          };
          childCanisterMap = BTree.init<Principal, Internal.InternalCanisterCyclesSettings>(null);
          var minCyclesPerTopup = ?50_000_000_000;
        }
      )
    }
  )
]);

let mockSendCyclesResultOk = func(amount : Nat, canisterId : Principal): async SendCycles.SendCyclesResult { #ok(amount) };
let mockSendCyclesResultErr = func(amount : Nat, canisterId : Principal): async SendCycles.SendCyclesResult { #err(#other("mock error")) };
let internal_DO_NOT_USE_TransferCyclesSuite = describe("internal_DO_NOT_USE_TransferCycles", [
  /* These tests should trap if uncommented, blocking requests to transfer cycles from the cycles manager
  // Should trap with execution error, explicit trap: Canister is not permitted to request cycles
  its(
    "if the cycles requested are less than the minCyclesPerTopup, returns the #too_few_cycles_requested error variant",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #unlimited;
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      let result = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 100_000_000_000;
        sendCycles = mockSendCyclesResultOk;
      });
      // The test should trap before getting here
      false;
    }
  ),
  */
  its(
    "if the cycles requested are less than the minCyclesPerTopup, returns the #too_few_cycles_requested error variant",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #unlimited;
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#fixedAmount(500_000_000_000);
        }
      );
      let result = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 49_999_999_999;
        sendCycles = mockSendCyclesResultOk;
      });
      switch(result) {
        case (#err(#too_few_cycles_requested)) true;
        case _ false;
      };
    }
  ),
  its(
    "if the aggregate cycles quota is not unlimited and the aggregate cycles used are equal to the aggregate cycles quota, returns the #aggregate_quota_reached error variant",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #unlimited;
        };
        aggregateSettings = {
          quota = #rate({
            maxAmount = 1_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#fixedAmount(500_000_000_000);
        }
      );
      cyclesManager.aggregateSettings.cyclesUsed := 1_000_000_000_000;
      let result = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 100_000_000_000;
        sendCycles = mockSendCyclesResultOk;
      });
      switch(result) {
        case (#err(#aggregate_quota_reached)) true;
        case _ false;
      };
    }
  ),
  its(
    "if the canister cycles quota is not unlimited or fixed and the canister cycles used are equal to the canister cycles quota, returns the #canister_quota_reached error variant",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #unlimited;
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#maxAmount(500_000_000_000);
        }
      );
      switch(BTree.get<Principal, Internal.InternalCanisterCyclesSettings>(cyclesManager.childCanisterMap, Principal.compare, Principal.fromText("aaaaa-aa"))) {
        case (?settings) settings.cyclesUsed := 500_000_000_000;
        case _ return false;
      };
      let result = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 100_000_000_000;
        sendCycles = mockSendCyclesResultOk;
      });
      switch(result) {
        case (#err(#canister_quota_reached)) true;
        case _ false;
      };
    }
  ),
  its("if sendCycles returns an error, returns that error", func(): async* Bool {
    let cyclesManager = CM.init({
      defaultCyclesSettings = {
        quota = #unlimited;
      };
      aggregateSettings = {
        quota = #unlimited;
      };
      minCyclesPerTopup = ?50_000_000_000;
    });
    CM.addChildCanister(
      cyclesManager,
      Principal.fromText("aaaaa-aa"),
      {
        quota = ?#fixedAmount(500_000_000_000);
      }
    );
    let result = await* CM.internal_DO_NOT_USE_TransferCycles({
      cyclesManager;
      canister = Principal.fromText("aaaaa-aa");
      cyclesRequested = 100_000_000_000;
      sendCycles = mockSendCyclesResultErr;
    });
    switch(result) {
      case (#err(#other "mock error")) true;
      case _ false;
    };
  }),
  its(
    "if sendCycles returns an error, resets the cyclesUsed settings on both the requesting canister and the aggregate settings to what they were before the request was made",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #unlimited;
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#fixedAmount(500_000_000_000);
        }
      );
      switch(BTree.get<Principal, Internal.InternalCanisterCyclesSettings>(cyclesManager.childCanisterMap, Principal.compare, Principal.fromText("aaaaa-aa"))) {
        case (?settings) settings.cyclesUsed := 100_000_000_000;
        case _ return false;
      };
      cyclesManager.aggregateSettings.cyclesUsed := 400_000_000_000;
      let result = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 100_000_000_000;
        sendCycles = mockSendCyclesResultErr;
      });
      switch(BTree.get<Principal, Internal.InternalCanisterCyclesSettings>(cyclesManager.childCanisterMap, Principal.compare, Principal.fromText("aaaaa-aa"))) {
        case (?settings) if (settings.cyclesUsed != 100_000_000_000) return false;
        case _ return false;
      };
      cyclesManager.aggregateSettings.cyclesUsed == 400_000_000_000;
    }
  ),
  its(
    "if sendCycles returns ok, returns the #ok variant with the amount of cycles requested",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #unlimited;
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#rate({
            maxAmount = 500_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        }
      );
      let result = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 100_000_000_000;
        sendCycles = mockSendCyclesResultOk;
      });
      switch(result) {
        case (#ok(100_000_000_000)) true;
        case _ false;
      };
    }
  ),
  its(
    "if sendCycles returns ok, updates the child canister cycles used amount and aggregate cycles used amount",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #unlimited;
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#rate({
            maxAmount = 500_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        }
      );
      let result = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 100_000_000_000;
        sendCycles = mockSendCyclesResultOk;
      });
      switch(BTree.get<Principal, Internal.InternalCanisterCyclesSettings>(cyclesManager.childCanisterMap, Principal.compare, Principal.fromText("aaaaa-aa"))) {
        case (?settings) if (settings.cyclesUsed != 100_000_000_000) return false;
        case _ return false;
      };
      cyclesManager.aggregateSettings.cyclesUsed == 100_000_000_000;
    }
  ),
  its(
    "if the canister is present in the child canister map but has no specific quota settings, uses the default quota setting",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 500_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = null;
        }
      );
      let result = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 100_000_000_000;
        sendCycles = mockSendCyclesResultOk;
      });
      switch(result) {
        case (#ok(100_000_000_000)) true;
        case _ return false;
      };
    }
  ),
  its(
    "if the quota period has expired for a single canister, resets that canister's cycles used to 0",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 500_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#rate({
            maxAmount = 500_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        }
      );
      let intermediateResult = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 100_000_000_000;
        sendCycles = mockSendCyclesResultOk;
      });
      switch(BTree.get<Principal, Internal.InternalCanisterCyclesSettings>(cyclesManager.childCanisterMap, Principal.compare, Principal.fromText("aaaaa-aa"))) {
        case (?settings) {
          switch(settings.quota) {
            case (?#rate(r)) r.quotaPeriodExpiryTimestamp := 0;
            case _ return false;
          };
        };
        case _ return false;
      };
      let resetResult = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 100_000_000_000;
        sendCycles = mockSendCyclesResultOk;
      });
      switch(BTree.get<Principal, Internal.InternalCanisterCyclesSettings>(cyclesManager.childCanisterMap, Principal.compare, Principal.fromText("aaaaa-aa"))) {
        case (?settings) settings.cyclesUsed == 100_000_000_000;
        case _ return false;
      };
    }
  ),
  its(
    "if a canister can still request more than 0 cycles, but is requesting more than its quota, sends the amount of allowed cycles remaining",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 500_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        };
        aggregateSettings = {
          quota = #unlimited;
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#rate({
            maxAmount = 500_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        }
      );
      let result = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 600_000_000_000;
        sendCycles = mockSendCyclesResultOk;
      });
      switch(result) {
        case (#ok(500_000_000_000)) true;
        case _ return false;
      };
    }
  ),
  its(
    "if a canister has more cycles remaining in its quota, but is requesting more than the aggregate rate limit, sends the amount of allowed cycles remaining in the aggregate limit",
    func(): async* Bool {
      let cyclesManager = CM.init({
        defaultCyclesSettings = {
          quota = #rate({
            maxAmount = 1_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        };
        aggregateSettings = {
          quota = #rate({
            maxAmount = 2_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        };
        minCyclesPerTopup = ?50_000_000_000;
      });
      CM.addChildCanister(
        cyclesManager,
        Principal.fromText("aaaaa-aa"),
        {
          quota = ?#rate({
            maxAmount = 1_000_000_000_000;
            durationInSeconds = 60 * 60 * 24;
          });
        }
      );
      cyclesManager.aggregateSettings.cyclesUsed := 1_500_000_000_000;
      // canister requests 600_000_000_000, but only 500_000_000_000 are available in the aggregate limit
      let result = await* CM.internal_DO_NOT_USE_TransferCycles({
        cyclesManager;
        canister = Principal.fromText("aaaaa-aa");
        cyclesRequested = 600_000_000_000;
        sendCycles = mockSendCyclesResultOk;
      });
      switch(result) {
        case (#ok(500_000_000_000)) {};
        case _ return false;
      };
      cyclesManager.aggregateSettings.cyclesUsed == 2_000_000_000_000;
    }
  )
]);

await* s.run([
  initSuite,
  addChildCanisterSuite,
  removeChildCanisterSuite,
  setMinCyclesPerTopupSuite,
  setDefaultCanisterCyclesQuotaSuite,
  setAggregateCyclesQuotaSuite,
  internal_DO_NOT_USE_TransferCyclesSuite,
]);