import Array "mo:base/Array";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Time "mo:base/Time";

actor Token {
  
  type TransferError = {
    #InsufficientFunds;
    #InvalidRecipient;
    #Unauthorized;
  };

  private stable var balancesEntries : [(Principal, Nat)] = [];
  private var balances = HashMap.fromIter<Principal, Nat>(balancesEntries.vals(), balancesEntries.size(), Principal.equal, Principal.hash);
  
  private stable var totalSupply : Nat = 1000000000000000;
  private stable var tokenName : Text = "Dollar For Watching";
  private stable var tokenSymbol : Text = "DFW";
  private stable var decimals : Nat = 8;
  private stable var owner : Principal = Principal.fromText("2vxsx-fae");

  system func preupgrade() {
    balancesEntries := Iter.toArray(balances.entries());
  };

  system func postupgrade() {
    balancesEntries := [];
  };

  public shared(msg) func init() : async () {
    owner := msg.caller;
    balances.put(owner, totalSupply);
  };

  public shared(msg) func transfer(to : Principal, amount : Nat) : async Result.Result<(), TransferError> {
    let from = msg.caller;
    let fromBalance = balances.get(from);
    
    switch (fromBalance) {
      case null { #err(#InsufficientFunds) };
      case (?balance) {
        if (balance < amount) {
          #err(#InsufficientFunds)
        } else {
          let newFromBalance = balance - amount;
          let toBalance = balances.get(to);
          let newToBalance = switch (toBalance) {
            case null { amount };
            case (?existingBalance) { existingBalance + amount };
          };
          
          balances.put(from, newFromBalance);
          balances.put(to, newToBalance);
          #ok(());
        };
      };
    };
  };

  public query func balanceOf(account : Principal) : async Nat {
    switch (balances.get(account)) {
      case null { 0 };
      case (?balance) { balance };
    };
  };

  public query func name() : async Text {
    tokenName;
  };

  public query func symbol() : async Text {
    tokenSymbol;
  };

  public query func totalSupply() : async Nat {
    totalSupply;
  };

  public query func decimals() : async Nat {
    decimals;
  };

  public shared(msg) func mint(to : Principal, amount : Nat) : async Result.Result<(), Text> {
    if (msg.caller != owner) {
      #err("Only owner can mint")
    } else {
      let currentBalance = balances.get(to);
      let newBalance = switch (currentBalance) {
        case null { amount };
        case (?balance) { balance + amount };
      };
      balances.put(to, newBalance);
      #ok(());
    };
  };
}
