#!/usr/bin/env ruby
# frozen_string_literal: true

# Records corpus/fixtures/identity-stereo.json — the M4 tetrahedral
# tranche. Each seed runs through the gem (SMILES -> chiral molecule
# -> molfile with a centre-first wedge and 2D layout) and the IUPAC
# oracle records the identifier. Development-time only: the corpus
# ships the recorded strings, never the oracle.
#
#   (from an asciichem-ruby checkout)
#   bundle exec ruby ../inchi-tests/scripts/record-stereo-tranche.rb \
#     > ../inchi-tests/corpus/fixtures/identity-stereo.json

require 'asciichem'
require 'json'
require 'tmpdir'

# { id => [smiles, coverage class] } — enantiomer pairs plus meso
# cases; every identifier is recorded from the oracle, never authored.
SEEDS = {
  'l-alanine' => ['N[C@@H](C)C(=O)O', 'stereo-tetrahedral'],
  'd-alanine' => ['N[C@H](C)C(=O)O', 'stereo-tetrahedral'],
  's-2-butanol' => ['CC[C@H](C)O', 'stereo-tetrahedral'],
  'r-2-butanol' => ['CC[C@@H](C)O', 'stereo-tetrahedral'],
  'r-2-chlorobutane' => ['CC[C@H](C)Cl', 'stereo-tetrahedral'],
  's-2-chlorobutane' => ['CC[C@@H](C)Cl', 'stereo-tetrahedral'],
  's-3-methylhexane' => ['CC[C@H](C)CCC', 'stereo-hydrocarbon'],
  'r-3-methylhexane' => ['CC[C@@H](C)CCC', 'stereo-hydrocarbon'],
  'rr-2-3-dichlorobutane' => ['C[C@H](Cl)[C@H](C)Cl', 'stereo-dicentre'],
  'ss-2-3-dichlorobutane' => ['C[C@@H](Cl)[C@@H](C)Cl', 'stereo-dicentre'],
  'meso-2-3-dichlorobutane' => ['C[C@H](Cl)[C@@H](C)Cl', 'stereo-meso'],
  'l-threonine' => ['C[C@@H](O)[C@H](N)C(=O)O', 'stereo-dicentre'],
  'd-threonine' => ['C[C@H](O)[C@@H](N)C(=O)O', 'stereo-dicentre'],
  'l-tartaric-acid' => ['O[C@@H]([C@H](O)C(=O)O)C(=O)O', 'stereo-dicentre'],
  'd-tartaric-acid' => ['O[C@H]([C@@H](O)C(=O)O)C(=O)O', 'stereo-dicentre'],
  'meso-tartaric-acid' => ['O[C@H]([C@H](O)C(=O)O)C(=O)O', 'stereo-meso'],
  'r-lactic-acid' => ['C[C@H](O)C(=O)O', 'stereo-tetrahedral'],
  's-lactic-acid' => ['C[C@@H](O)C(=O)O', 'stereo-tetrahedral'],
  'r-limonene' => ['CC1=CC[C@@H](CC1)C(=C)C', 'stereo-ring'],
  's-limonene' => ['CC1=CC[C@H](CC1)C(=C)C', 'stereo-ring']
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
              'tags' => [], 'smiles' => smiles, 'molfile' => molfile,
              'inchi' => inchi, 'inchikey' => key }
  end
end

puts JSON.pretty_generate(rows)
