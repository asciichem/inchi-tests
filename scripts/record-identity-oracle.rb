#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates corpus/fixtures/identity.json from the IUPAC oracle
# (TODO.v2/16 M0). Requires: the asciichem gem (molfile emission) and
# the official `inchi-1` binary on PATH or ASCIICHEM_INCHI_BIN. The
# oracle is a development-time test oracle — the corpus ships only
# the recorded identifier strings.
#
#   ruby scripts/record-identity-oracle.rb > corpus/fixtures/identity.json
# (run with the asciichem gem on the load path — e.g. from an
# asciichem-ruby checkout: bundle exec ruby ../asciichem-tests/...)

require 'asciichem'
require 'json'
require 'tmpdir'

# { id => [smiles, coverage class] } — the seed battery. Extend with
# the same coverage classes the gates need; every entry is recorded
# from the oracle, never authored.
SEEDS = {
  'water' => ['O', 'simple'],
  'methane' => ['C', 'simple'],
  'ammonia' => ['N', 'simple'],
  'ethanol' => ['CCO', 'simple'],
  'benzene' => ['c1ccccc1', 'ring'],
  'cyclohexane' => ['C1CCCCC1', 'ring'],
  'naphthalene' => ['c1ccc2ccccc2c1', 'ring-fused'],
  'pyridine' => ['c1ccncc1', 'heteroaromatic'],
  'furan' => ['c1ccoc1', 'heteroaromatic'],
  'ammonium' => ['[NH4+]', 'charge'],
  'acetate' => ['CC(=O)[O-]', 'charge'],
  'hydroxide' => ['[OH-]', 'charge'],
  'd2o' => ['[2H]O[2H]', 'isotope'],
  'c13-methane' => ['[13CH4]', 'isotope'],
  'l-alanine' => ['N[C@@H](C)C(=O)O', 'stereo-tetrahedral'],
  'd-alanine' => ['N[C@H](C)C(=O)O', 'stereo-tetrahedral'],
  'e-2-butene' => ['C/C=C/C', 'stereo-ez-molfile-loss'],
  'z-2-butene' => ['C/C=C\\C', 'stereo-ez-molfile-loss'],
  'aspirin' => ['CC(=O)OC1=CC=CC=C1C(=O)O', 'drug'],
  'ibuprofen' => ['CC(C)Cc1ccc(cc1)C(C)C(=O)O', 'drug-stereo'],
  'paracetamol' => ['CC(=O)Nc1ccc(O)cc1', 'drug'],
  'caffeine' => ['Cn1cnc2c1c(=O)n(C)c(=O)n2C', 'drug'],
  'glycine' => ['NCC(=O)O', 'amino-acid'],
  'urea' => ['NC(=O)N', 'simple'],
  'sulfuric-acid' => ['OS(=O)(=O)O', 'heteroatom'],
  'phosphoric-acid' => ['OP(=O)(O)O', 'heteroatom']
}.freeze

bin = ENV.fetch('ASCIICHEM_INCHI_BIN', 'inchi-1')
rows = []
SEEDS.each do |name, (smiles, klass)|
  molecule = AsciiChem.parse_smiles(smiles).nodes.first
  molfile = AsciiChem::Molfile.write(molecule)
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, 's.mol'), molfile)
    system(bin, File.join(dir, 's.mol'), File.join(dir, 'o.txt'),
           '-AuxNone', '-NoLabels', '-Key', out: File::NULL, err: File::NULL)
    txt = File.read(File.join(dir, 'o.txt'))
    inchi = txt[/^InChI=\S+/]
    key = txt[/^InChIKey=(\S+)/, 1]
    raise "oracle produced no InChI for #{name}:\n#{txt}" unless inchi && key

    rows << { 'id' => "identity/#{name}", 'structureClass' => klass,
              'smiles' => smiles, 'molfile' => molfile,
              'inchi' => inchi, 'inchikey' => key }
  end
end
puts JSON.pretty_generate(rows)
