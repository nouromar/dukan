// Per-base-unit compatibility filter for the Custom packaging dropdown
// in AddPackagingSheet and AddNewItemSheet.
//
// The data model lets you attach any unit as a packaging of any base —
// the constraint here is pure UX: when the base is kg, "bottle" or
// "litre" don't make sense to offer as packagings. The server stays
// permissive in case future edge cases need them.
//
// Source of truth for unit codes: 0002_reference_data.sql.
// Keep this map in sync if new units land.

const _allowed = <String, Set<String>>{
  // Mass bases: containers + smaller mass units.
  'kg':     {'bag', 'sack', 'carton', 'box', 'packet'},
  'gram':   {'bag', 'sack', 'carton', 'box', 'packet'},

  // Volume bases: bottles + bag/sack containers that liquids ship in.
  'litre':  {'bottle', 'carton', 'bag', 'sack'},
  'ml':     {'bottle', 'carton', 'bag', 'sack'},

  // Count bases: any grouping container.
  'piece':  {'packet', 'box', 'carton', 'bag', 'dozen'},
  'packet': {'box', 'carton', 'bag'},
  'bottle': {'carton', 'box', 'sack'},
  'dozen':  {'box', 'carton'},

  // Rarely-used-as-base container codes: same-level or larger only.
  'bag':    {'carton', 'box'},
  'sack':   {'carton', 'box'},
  'carton': {'box'},
  'box':    {'carton'},
};

/// Filters a list of unit options down to those that are valid
/// packagings for [baseCode]. The base unit itself is always excluded
/// (conversion=1 IS the base by definition). When the base code is
/// unknown to this map the filter is a no-op so future units don't
/// silently disappear from pickers.
List<T> filterPackagingsForBase<T>(
  String baseCode,
  List<T> all,
  String Function(T) getCode,
) {
  final allowed = _allowed[baseCode];
  return [
    for (final u in all)
      if (getCode(u) != baseCode &&
          (allowed == null || allowed.contains(getCode(u))))
        u,
  ];
}
