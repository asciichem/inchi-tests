# The InChI suite

The conformance suite for InChI layer emission: an oracle corpus
recorded from the IUPAC reference implementation (`inchi-1`), the
fixture schema, the recording harness, and the gate contract every
engine must pass.

Single-contract rule, applied to InChI itself: **every engine — the
Ruby reference, the Rust port, any future language — passes the same
corpus, byte-for-byte, or it does not claim the layer.** The oracle
binary is a development-time test oracle only; this repo ships
identifier strings, never code from the InChI Trust.

## Corpus

`corpus/fixtures/` — one JSON array of fixtures per tranche
(`identity.json` seeds, `identity-breadth.json` the M0b breadth
sample, `identity-breadth2.json` the scaling tranche, the stereo and
E/Z tranches). One fixture per structure:

| Field | Meaning |
|---|---|
| `molfile` | Verbatim V2000 as fed to the oracle — the input engines derive from |
| `inchi` | The oracle's standard InChI (the ground truth) |
| `inchikey` | The oracle's standard InChIKey |
| `structureClass` | The coverage class the case exists for |

## Gate contract (M1 — the formula layer)

For every fixture, an engine must emit the formula layer — the
segment after `InChI=1S/` — byte-identically:

- Hill order with the InChI twist: carbon first (when present), then
  hydrogen, then the rest alphabetically; counts omitted when 1.
- Implicit hydrogens: the MDL H-count code wins (`n` → n−1 H); with
  code 0 the valence gap fills in (C 4, N 3, O 2, S 6, P 5,
  halogens/H 1; aromatic bonds count 1.5) — the oracle does the same
  for code-0 atoms.
- Charged species are **standardized**: the formula layer is the
  neutral parent — an anion gains one hydrogen and emits `/p-1`, a
  cation loses one and emits `/p+1` (ammonium is `H3N` + `/p+1`,
  hydroxide is `H2O` + `/p-1`).
- Isotopes do not appear in the formula layer (D counts as H;
  ¹³C as C) — they belong to the `/i` layer, a later milestone.

A gate run reports per-fixture pass/fail and must be 100% — a
failing case is either a bug or a corpus gap, never silently
skipped.

## Milestones (TODO.v2/16)

M1 formula layer → M2 `/c` connection layer → M3 `/h`, `/q`, `/p` →
M4 stereo → M5 InChIKey → bindings. The corpus grows with each
milestone: 1559 fixtures through the stereo/E/Z tranches (v0.2.5),
3559 with the breadth2 scaling tranche (v0.3.0) — the ≥100k target
continues in further batches of the same harness.

## Recording

`scripts/record-identity-oracle.rb` regenerates the corpus from the
gem (molfile emission) + the oracle. Run it from an asciichem-ruby
checkout:

```sh
bundle exec ruby ../inchi-tests/scripts/record-identity-oracle.rb > ../inchi-tests/corpus/fixtures/identity.json
```

New coverage classes ride a corpus review, never a silent edit —
fixtures are never weakened to make an engine pass.

`scripts/record-stereo-tranche.rb` records the tetrahedral tranche
(gem-written wedges); `scripts/record-ez-tranche.rb` the E/Z tranche
(hand-laid layouts, /b presence asserted). The breadth importer
records only gem→oracle agreements; disagreements count in the run
log and surface as triage entries or bug fixes through the engines'
gates.
