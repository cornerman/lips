# TODO

## List aggregation (from docs/superpowers/plans/2026-07-24-list-aggregation-plan.md)

### Open questions (resolve before building)

- [ ] **Q1 — Strength mixing in an `Append` subject.** A `Law` list over a
      `Stated` list: replace the whole list, or append?
      Recommend: replace (clean override, matches scalar semantics).
- [ ] **Q2 — Order among derived contributors.** Stable total order across
      derived (`Derived ids rule`) and human (`SourceLoc`) contributors.
      Recommend: human (by file, line) before derived (by rule id, then parent).
- [ ] **Q3 — Tail-hole spelling.** `<value*>` vs `<value.tail>` vs `<value...>`.
      Recommend: `<value.tail>` (consistent with `<value.N>`).
- [ ] **Q4 — Empty tail.** `<value.tail>` matching zero tokens: error or allowed?
      Recommend: error (deduce-or-fail, never guess).
- [ ] **Q5 — `Append` for `attrsOf`-of-list.** Reachable via wildcard schema
      match; needs a conformance test before claiming Done.

### Build order

- [ ] 1. Q5 conformance test for `attrsOf`-of-list (proves the wildcard path).
- [ ] 2. Closure B — `Append` merge mode, schema-driven (gated by Q1, Q2).
- [ ] 3. Closure C — `<value.tail>` hole (gated by Q3, Q4).
- [ ] 4. Assembly step before `realize`; verify `.expect` contract behavior.
- [ ] 5. Update milestone ledger (DESIGN.md section 13): move B and C from
      Missing to Done; add "ordered list assembly by source provenance".
