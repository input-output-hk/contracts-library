
pub type SettingsDatum {
  current: Data,
  next: Option<Data>,
  next_apply: Option<Int>,
}

pub type SpendRedeemer {
  Propose { out_ix: Int }
  Apply { out_ix: Int }
  Close
}

pub type MintRedeemer {
  Mint { out_ix: Int }
  Burn
}
