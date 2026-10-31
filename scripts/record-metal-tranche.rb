#!/usr/bin/env ruby
# frozen_string_literal: true

# Records the metal/organometallic tranche from the IUPAC oracle:
# coordination complexes, organometallics and metal salts drawn BONDED
# — the coverage the standard-path metal disconnection and the RecMet
# reconnection units need. Standard inchi/key/aux only; the fixedh,
# recmet and snon mode recordings come from re-running
# scripts/record-modes-oracle.rb over the corpus afterwards.
#
#   cd asciichem-ruby && ASCIICHEM_INCHI_BIN=<clean inchi-1> \
#     bundle exec ruby ../inchi-tests/scripts/record-metal-tranche.rb \
#     > ../inchi-tests/corpus/fixtures/identity-metal.json

require 'asciichem'
require 'json'
require 'tmpdir'

# { id => [smiles, coverage class] } — metal bonds drawn explicitly.
SEEDS = {
  'cisplatin' => ['N[Pt](Cl)(Cl)N', 'coordination'],
  'palladium-dichloride' => ['Cl[Pd](Cl)', 'coordination'],
  'gold-trichloride' => ['Cl[Au](Cl)Cl', 'coordination'],
  'tin-tetrachloride' => ['Cl[Sn](Cl)(Cl)Cl', 'coordination'],
  'sodium-phenoxide-bonded' => ['[Na]Oc1ccccc1', 'metal-bonded'],
  'sodium-acetate-bonded' => ['CC(=O)O[Na]', 'metal-bonded'],
  'silver-nitrate-bonded' => ['[O-][N+](=O)O[Ag]', 'metal-bonded'],
  'methyl-lithium' => ['C[Li]', 'organometallic'],
  'n-butyl-lithium' => ['CCCC[Li]', 'organometallic'],
  'ethyl-magnesium-bromide' => ['CC[Mg]Br', 'grignard'],
  'dimethyl-zinc' => ['C[Zn]C', 'organometallic'],
  'trimethyl-aluminium' => ['C[Al](C)C', 'organometallic'],
  'sodium-diethylamide' => ['CC[Na]N(CC)CC', 'metal-bonded'],
  'methyl-copper' => ['C[Cu]', 'organometallic']
}.freeze

bin = ENV.fetch('ASCIICHEM_INCHI_BIN', 'inchi-1')
rows = []
SEEDS.each do |name, (smiles, klass)|
  molecule = AsciiChem.parse_smiles(smiles).nodes.first
  molfile = AsciiChem::Molfile.write(molecule)
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, 's.mol'), molfile)
    system(bin, File.join(dir, 's.mol'), File.join(dir, 'o.txt'),
           '-Key', out: File::NULL, err: File::NULL)
    txt = File.read(File.join(dir, 'o.txt'))
    inchi = txt[/^InChI=\S+/]
    key = txt[/^InChIKey=(\S+)/, 1]
    aux = txt[/^AuxInfo=\S+/]
    raise "oracle produced no InChI for #{name}:\n#{txt}" unless inchi && key && aux

    rows << { 'id' => "identity/metal-#{name}", 'structureClass' => klass,
              'tags' => ['metal'], 'smiles' => smiles, 'molfile' => molfile,
              'inchi' => inchi, 'inchikey' => key, 'aux' => aux }
  end
end
puts JSON.pretty_generate(rows)
