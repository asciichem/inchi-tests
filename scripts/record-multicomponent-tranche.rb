#!/usr/bin/env ruby
# frozen_string_literal: true

# Records the multi-component tranche (salts, hydrates, double salts)
# from the IUPAC oracle. Same contract as record-identity-oracle.rb:
# the oracle is a development-time test oracle — the corpus ships only
# the recorded strings. Every structure here is a DISCONNECTED
# multi-component input, the coverage the RecMet and multi-component
# layer work needs.
#
# The gem's molfile writer is single-fragment, so each dot component
# is written separately and the V2000 blocks are merged here (atom and
# bond counts summed, bond partners and charge/isotope indices
# offset).
#
#   cd asciichem-ruby && bundle exec ruby \
#     ../inchi-tests/scripts/record-multicomponent-tranche.rb \
#     > ../inchi-tests/corpus/fixtures/identity-multicomponent.json

require 'asciichem'
require 'json'
require 'tmpdir'

# { id => [smiles, coverage class] }
SEEDS = {
  'nacl' => ['[Na+].[Cl-]', 'salt'],
  'kcl' => ['[K+].[Cl-]', 'salt'],
  'sodium-hydroxide' => ['[Na+].[OH-]', 'salt'],
  'potassium-hydroxide' => ['[K+].[OH-]', 'salt'],
  'sodium-acetate' => ['[Na+].CC(=O)[O-]', 'salt-organic'],
  'sodium-phenoxide' => ['[Na+].[O-]c1ccccc1', 'salt-organic'],
  'sodium-benzoate' => ['[Na+].[O-]C(=O)c1ccccc1', 'salt-organic'],
  'potassium-benzoate' => ['[K+].[O-]C(=O)c1ccccc1', 'salt-organic'],
  'ammonium-chloride' => ['[NH4+].[Cl-]', 'salt'],
  'ammonium-benzoate' => ['[NH4+].[O-]C(=O)c1ccccc1', 'salt-organic'],
  'sodium-bicarbonate' => ['[Na+].OC(=O)[O-]', 'salt-acid'],
  'sodium-hydrogen-sulfate' => ['[Na+].OS(=O)(=O)[O-]', 'salt-acid'],
  'sodium-carbonate' => ['[Na+].[Na+].[O-]C(=O)[O-]', 'salt-stoichiometric'],
  'magnesium-sulfate' => ['[Mg+2].[O-]S(=O)(=O)[O-]', 'salt-stoichiometric'],
  'calcium-sulfate' => ['[Ca+2].[O-]S(=O)(=O)[O-]', 'salt-stoichiometric'],
  'copper-sulfate' => ['[Cu+2].[O-]S(=O)(=O)[O-]', 'salt-transition-metal'],
  'iron-trichloride' => ['[Fe+3].[Cl-].[Cl-].[Cl-]', 'salt-stoichiometric'],
  'lead-diiodide' => ['[Pb+2].[I-].[I-]', 'salt-heavy'],
  'silver-nitrate' => ['[Ag+].[O-][N+](=O)O', 'salt-transition-metal'],
  'zinc-oxide' => ['[Zn+2].[O-2]', 'salt-lattice'],
  'sodium-thiosulfate' => ['[Na+].[Na+].[O-]S(=O)(=O)[S-]', 'salt-stoichiometric'],
  'potassium-permanganate' => ['[K+].[O-][Mn](=O)(=O)=O', 'salt-transition-metal'],
  'lithium-hexafluorophosphate' => ['[Li+].F[P-](F)(F)(F)(F)F', 'salt-fluorine'],
  'tetrabutylammonium-bromide' => ['[Br-].CCCC[N+](CCCC)(CCCC)CCCC', 'salt-organic'],
  'sodium-dodecyl-sulfate' => ['[Na+].CCCCCCCCCCCCOS(=O)(=O)[O-]', 'salt-organic'],
  'ammonium-sulfate' => ['[NH4+].[NH4+].[O-]S(=O)(=O)[O-]', 'salt-stoichiometric'],
  'sodium-citrate' => ['[Na+].[Na+].[Na+].[O-]C(=O)CC([C@@H](O)(C(=O)[O-])C(=O)[O-])C(=O)[O-]', 'salt-organic'],
  'magnesium-sulfate-heptahydrate' => ['[Mg+2].[O-]S(=O)(=O)[O-].O.O.O.O.O.O.O', 'hydrate'],
  'copper-sulfate-pentahydrate' => ['[Cu+2].[O-]S(=O)(=O)[O-].O.O.O.O.O', 'hydrate'],
  'sodium-carbonate-decahydrate' => ['[Na+].[Na+].[O-]C(=O)[O-].O.O.O.O.O.O.O.O.O.O', 'hydrate'],
  'alum-dodecahydrate' => ['[K+].[Al+3].[O-]S(=O)(=O)[O-].[O-]S(=O)(=O)[O-].O.O.O.O.O.O.O.O.O.O.O.O', 'hydrate-double-salt'],
  'barium-chloride-dihydrate' => ['[Ba+2].[Cl-].[Cl-].O.O', 'hydrate'],
  'sodium-sulfate-decahydrate' => ['[Na+].[Na+].[O-]S(=O)(=O)[O-].O.O.O.O.O.O.O.O.O.O', 'hydrate']
}.freeze

# Merges single-fragment V2000 molfiles into one multi-component
# structure: counts summed, atom references offset per part.
def merge_molfiles(parts)
  atoms = []
  bonds = []
  mlines = []
  parts.each do |txt|
    lines = txt.split("\n")
    na = lines[3][0, 3].to_i
    nb = lines[3][3, 3].to_i
    base = atoms.length
    atoms.concat(lines[4, na])
    nb.times do |i|
      b = lines[4 + na + i]
      bonds << format('%3d%3d%3s', b[0, 3].to_i + base, b[3, 3].to_i + base, b[6, 3])
    end
    lines[(4 + na + nb)..].each do |l|
      next unless l&.start_with?('M  CHG')

      n = l[6, 3].to_i
      # The gem emits each entry as %4d atom + %4d charge (8-char
      # stride) — wider than the CTfile spec's %3d charge; re-emit the
      # same shape, atom indices offset.
      entries = (0...n).map do |j|
        raw = l[9 + 8 * j, 8]
        [raw[0, 4].to_i + base, raw[4, 4]]
      end
      mlines << 'M  CHG' + format('%3d', n) +
               entries.map { |(a, c)| format('%4d', a) + c }.join
    end
  end

  out = +"merged\n  AsciiChem\n\n"
  out << format("%3d%3d  0  0  0  0  0  0  0  0999 V2000\n", atoms.length, bonds.length)
  out << atoms.join("\n") << "\n"
  out << bonds.join("\n") << "\n" unless bonds.empty?
  out << mlines.join("\n") << "\n" unless mlines.empty?
  out << 'M  END' << "\n"
  out
end

bin = ENV.fetch('ASCIICHEM_INCHI_BIN', 'inchi-1')
rows = []
SEEDS.each do |name, (smiles, klass)|
  parsed = AsciiChem.parse_smiles(smiles)
  parts = parsed.nodes.map { |node| AsciiChem::Molfile.write(node) }
  raise "#{name}: no components" if parts.empty?

  molfile = parts.length == 1 ? parts.first : merge_molfiles(parts)
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, 's.mol'), molfile)
    system(bin, File.join(dir, 's.mol'), File.join(dir, 'o.txt'),
           '-Key', out: File::NULL, err: File::NULL)
    txt = File.read(File.join(dir, 'o.txt'))
    inchi = txt[/^InChI=\S+/]
    key = txt[/^InChIKey=(\S+)/, 1]
    aux = txt[/^AuxInfo=\S+/]
    raise "oracle produced no InChI for #{name}:\n#{txt}" unless inchi && key && aux
    raise "#{name} did not read as multi-component:\n#{inchi}" unless inchi.include?(';')

    rows << { 'id' => "identity/multi-#{name}", 'structureClass' => klass,
              'tags' => ['multicomponent'], 'smiles' => smiles, 'molfile' => molfile,
              'inchi' => inchi, 'inchikey' => key, 'aux' => aux }
  end
end
puts JSON.pretty_generate(rows)
