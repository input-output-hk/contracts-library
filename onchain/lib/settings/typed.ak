//// Admissible-value predicate for the `settings_typed` validator: setting
//// values must be `Constr(0, [_])` — a single-field constructor whose field may
//// be any `Data` (spec §3.d, §6.d R7). `un_constr_data` halts on non-constructor
//// `Data`, so an out-of-shape value rejects the transaction.

use aiken/builtin.{un_constr_data}

/// Admissible values are exactly `Constr(0, [_])` — a single-field
/// constructor whose field may be any `Data`.
pub fn validate_datum(data: Data) -> Bool {
  let constr = un_constr_data(data)
  constr.1st == 0 && when constr.2nd is {
    [_field] -> True
    _ -> False
  }
}
