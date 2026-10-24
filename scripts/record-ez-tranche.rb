#!/usr/bin/env ruby
# frozen_string_literal: true

# Records corpus/fixtures/identity-ez.json — the M4 slice-2 tranche
# for double-bond stereo (/b). The gem's molfile writer does not yet
# carry E/Z through its layout (the stereo-ez-molfile-loss class
# documents that), so these seeds use explicit hand-laid coordinates
# — the layouts the oracle reads E/Z from — and the IUPAC oracle
# records the identifier. Development-time only: the corpus ships the
# recorded strings, never the oracle.
#
#   ASCIICHEM_INCHI_BIN=inchi-1 ruby scripts/record-ez-tranche.rb \
#     > corpus/fixtures/identity-ez.json

require 'json'
require 'tmpdir'

# { id => [class, atoms, bonds] } — atoms [element, x, y]; bonds
# [a, b, order] (0-based). Each layout puts the substituents at
# drawn positions whose sides carry the E/Z information.
SEEDS = {
  'e-2-butene' => ['stereo-ez', [%w[C 12 85], %w[C 60 50], %w[C 120 50], %w[C 168 15]],
                  [[0, 1, 1], [1, 2, 2], [2, 3, 1]]],
  'z-2-butene' => ['stereo-ez', [%w[C 12 15], %w[C 60 50], %w[C 120 50], %w[C 168 15]],
                  [[0, 1, 1], [1, 2, 2], [2, 3, 1]]],
  'e-2-pentene' => ['stereo-ez', [%w[C 12 85], %w[C 60 50], %w[C 120 50], %w[C 168 15], %w[C 204 51]],
                    [[0, 1, 1], [1, 2, 2], [2, 3, 1], [3, 4, 1]]],
  'z-2-pentene' => ['stereo-ez', [%w[C 12 15], %w[C 60 50], %w[C 120 50], %w[C 168 15], %w[C 204 51]],
                    [[0, 1, 1], [1, 2, 2], [2, 3, 1], [3, 4, 1]]],
  'e-1-2-dichloroethene' => ['stereo-ez-hetero', [%w[Cl 12 85], %w[C 60 50], %w[C 120 50], %w[Cl 168 15]],
                             [[0, 1, 1], [1, 2, 2], [2, 3, 1]]],
  'z-1-2-dichloroethene' => ['stereo-ez-hetero', [%w[Cl 12 15], %w[C 60 50], %w[C 120 50], %w[Cl 168 15]],
                             [[0, 1, 1], [1, 2, 2], [2, 3, 1]]],
  'e-3-methyl-2-pentene' => ['stereo-ez-tri', [%w[C 24 86], %w[C 60 50], %w[C 120 50], %w[C 168 14], %w[C 168 86], %w[C 204 50]],
                             [[0, 1, 1], [1, 2, 2], [2, 3, 1], [3, 5, 1], [2, 4, 1]]],
  'z-3-methyl-2-pentene' => ['stereo-ez-tri', [%w[C 24 86], %w[C 60 50], %w[C 120 50], %w[C 168 86], %w[C 168 14], %w[C 204 50]],
                             [[0, 1, 1], [1, 2, 2], [2, 3, 1], [3, 5, 1], [2, 4, 1]]],
  'e-2-hexene' => ['stereo-ez', [%w[C 12 85], %w[C 60 50], %w[C 120 50], %w[C 168 15], %w[C 204 51], %w[C 240 15]],
                   [[0, 1, 1], [1, 2, 2], [2, 3, 1], [3, 4, 1], [4, 5, 1]]],
  'z-2-hexene' => ['stereo-ez', [%w[C 12 15], %w[C 60 50], %w[C 120 50], %w[C 168 15], %w[C 204 51], %w[C 240 15]],
                   [[0, 1, 1], [1, 2, 2], [2, 3, 1], [3, 4, 1], [4, 5, 1]]]
}.freeze

bin = ENV.fetch('ASCIICHEM_INCHI_BIN', 'inchi-1')
rows = []
SEEDS.each do |name, (klass, atoms, bonds)|
  molfile = +"#{name}\n  AsciiChem\n\n"
  molfile += format("%3d%3d  0  0  0  0  0  0  0  0999 V2000\n", atoms.length, bonds.length)
  atoms.each do |(element, x, y)|
    molfile += format("%10.4f%10.4f%10.4f %-3s 0  0  0  0  0  0  0  0  0  0  0  0  0\n",
                      x.to_f, y.to_f, 0.0, element)
  end
  bonds.each do |(a, b, order)|
    molfile += format("%3d%3d%3d%3d  0  0  0  0\n", a + 1, b + 1, order, 0)
  end
  molfile << "M  END\n"

  Dir.mktmpdir do |dir|
    File.write(File.join(dir, 's.mol'), molfile)
    system(bin, File.join(dir, 's.mol'), File.join(dir, 'o.txt'),
           '-AuxNone', '-NoLabels', '-Key', out: File::NULL, err: File::NULL)
    txt = File.read(File.join(dir, 'o.txt'))
    inchi = txt[/^InChI=\S+/]
    key = txt[/^InChIKey=(\S+)/, 1]
    raise "oracle produced no InChI for #{name}:\n#{txt}" unless inchi && key
    raise "oracle recorded no /b for #{name}: #{inchi}" unless inchi.include?('/b')

    rows << { 'id' => "identity/#{name}", 'structureClass' => klass,
              'tags' => [], 'molfile' => molfile,
              'inchi' => inchi, 'inchikey' => key }
  end
end

puts JSON.pretty_generate(rows)
