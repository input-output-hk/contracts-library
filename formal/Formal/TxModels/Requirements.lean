namespace Formal.TxModels

/-- Encodings of every datum and redeemer produced by a transaction model. -/
inductive DataShape where
  | bytes
  | constr (index : Nat) (fields : List DataShape)
  deriving BEq, Repr

structure SpendingInputs where
  datum : DataShape
  redeemer : DataShape
  deriving BEq, Repr

end Formal.TxModels
