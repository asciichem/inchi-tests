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

## Gate contract (current)

For every fixture, an engine emits every layer it claims and the
gate compares each emitted segment to the oracle's recording of that
layer kind, byte-for-byte — plus the native InChIKey against the
recorded key. The gate **compares every fixture and classifies the
result**; no measurement overrides exist:

- **pass** — every emitted segment matches and the key reproduces.
- **expected-failure skip** — the fixture is in `corpus/triage.json`
  with a dated, decoded reason. Triage entries are debts to retire,
  never settlements; a triaged fixture that passes again blocks CI
  (RETIREMENT) until its entry is withdrawn.
- **isotopic** — an `/i` layer (its own milestone).
- **beyond-±1** — |charge| > 1 exceeds the ±1 proton
  standardization both engines implement.

Layer rules the corpus pins (M1-era, still standing): Hill order
with the InChI twist; MDL H-count codes over the valence gap (C 4,
N 3, O 2, S 6, P 5, halogens/H 1; aromatic 1.5); ±1 proton
standardization (anion = neutral parent +1 H + `/p-1`, cation −1 H +
`/p+1`); isotopes invisible to the formula layer. Known open debt
classes live in triage.json — currently the ichitaut template
machinery over enolizable chemistry, a formula-H gap at charged
sites (the salt/charge port), and `/c` ordering ties over bridged
skeletons.

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
