#!/usr/bin/env ruby
# frozen_string_literal: true

# M0b breadth tranche (TODO.v2/16): sample the PubChem CID space,
# ingest each structure through the gem (SMILES -> molfile), verify
# the IUPAC oracle agrees with PubChem's recorded InChI, and emit the
# agreeing cases as breadth fixtures. Disagreements are written to a
# triage file — they are writer/parser bugs or standardization gaps,
# never silently dropped.
#
#   ruby scripts/import-pubchem-breadth.rb START STEP CANDIDATES LIMIT OUT.json [TRIAGE.log]
#   ruby scripts/import-pubchem-breadth.rb 1 11 30000 1200 identity-breadth.json

require 'net/http'
require 'json'
require 'tmpdir'
require 'asciichem'

start_cid = ARGV[0].to_i
step = ARGV[1].to_i
candidates = ARGV[2].to_i
limit = ARGV[3].to_i
out_path = ARGV[4] or abort "usage: import-pubchem-breadth.rb START STEP CANDIDATES LIMIT OUT.json [TRIAGE.log]"
triage_path = ARGV[5]

cids = (0...candidates).map { |i| start_cid + i * step }
base = 'https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid'
organic = /\A(C|H|B|N|O|F|Si|P|S|Cl|Br|I)+\z/

require 'uri'

def fetch(url)
  uri = URI(url)
  response = Net::HTTP.get_response(uri)
  raise "PubChem #{response.code}: #{response.body[0, 200]}" unless response.is_a?(Net::HTTPOK)

  response.body
end

# Multi-property output requires JSON (TXT is single-property).
def fetch_triples(batch, base)
  body = fetch("#{base}/#{batch.join(',')}/property/IsomericSMILES,InChI,InChIKey/JSON")
  properties = JSON.parse(body).dig('PropertyTable', 'Properties') || []
  properties.filter_map do |row|
    # PubChem answers with the SMILES key when a compound carries no
    # stereo; accept both spellings.
    smiles = row['IsomericSMILES'] || row['SMILES']
    next nil unless smiles && row['InChI'] && row['InChIKey']

    [row['CID'].to_s, smiles, row['InChI'], row['InChIKey']]
  end
rescue JSON::ParserError => e
  warn "batch parse failed: #{e.message}"
  []
end

triples = {}
cids.each_slice(100).with_index do |batch, batch_index|
  fetch_triples(batch, base).each do |cid, smiles, inchi, key|
    triples[cid] = [smiles, inchi, key]
  end
  warn "batch #{batch_index}: #{triples.length} structures so far"
  sleep 0.35
end
warn "candidate structures: #{triples.length}"

rows = []
disagreements = []
skips = { parse: 0, elements: 0, oracle_error: 0 }
triples.each_value do |smiles, pubchem_inchi, pubchem_key|
  break if rows.length >= limit

  molecule = begin
    AsciiChem.parse_smiles(smiles).nodes.first
  rescue AsciiChem::Error
    skips[:parse] += 1
    next
  end
  elements = AsciiChem::Structure::Graph.build!(molecule).first.map(&:element).uniq.join
  unless organic.match?(elements)
    skips[:elements] += 1
    next
  end

  molfile = AsciiChem::Molfile.write(molecule, layout: false)
  # S/P chemistry restructures under the oracle's mobile-H rules —
  # M3 scope, tagged out of the M1 gates.
  tags = AsciiChem::Structure::Graph.build!(molecule).first.any? { |a| %w[S P].include?(a.element) } ? ['m3'] : []
  oracle_inchi, oracle_key = Dir.mktmpdir do |dir|
    File.write(File.join(dir, 's.mol'), molfile)
    system('inchi-1', File.join(dir, 's.mol'), File.join(dir, 'o.txt'),
           '-AuxNone', '-NoLabels', '-Key', out: File::NULL, err: File::NULL)
    txt = File.exist?(File.join(dir, 'o.txt')) ? File.read(File.join(dir, 'o.txt')) : ''
    [txt[/^InChI=\S+/], txt[/^InChIKey=(\S+)/, 1]]
  end
  if oracle_inchi.nil? || oracle_key.nil?
    skips[:oracle_error] += 1
    next
  end
  if oracle_inchi != pubchem_inchi || oracle_key != pubchem_key
    disagreements << { smiles: smiles, pubchem: pubchem_inchi, oracle: oracle_inchi }
    next
  end

  rows << { 'id' => "identity/breadth-#{rows.length + 1}", 'structureClass' => 'breadth',
            'tags' => tags, 'smiles' => smiles, 'molfile' => molfile,
            'inchi' => oracle_inchi, 'inchikey' => oracle_key }
end

File.write(out_path, JSON.pretty_generate(rows) + "\n")
File.write(triage_path, disagreements.map(&:inspect).join("\n") + "\n") if triage_path
warn "recorded #{rows.length}; disagreements #{disagreements.length}; skips #{skips.inspect}"
