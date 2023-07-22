/// Subset of the Interface Spec used for sending cycles

/// For the full Interface Spec, see https://github.com/dfinity/interface-spec/blob/master/spec/ic.did
module {
  public let IC : Interface = actor ("aaaaa-aa");

  public type Interface = actor {
    deposit_cycles : shared ({ canister_id : Principal }) -> async ();
  };
};