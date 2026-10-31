#!/usr/bin/env ruby
# frozen_string_literal: true

# Records the oracle AuxInfo line for every fixture record into a new
# "aux" field. Runs the official inchi-1 executable ONCE over a batch
# SDfile assembled from the fixture molfiles, then parses the
# per-structure output back onto the fixture records in place.
# Development-time tooling — the corpus ships the recorded strings.
#
#   ruby scripts/record-aux-info.rb
# (ASCIICHEM_INCHI_BIN overrides the oracle path; the recorded InChI
# lines are verified against the fixtures' existing "inchi" field.)

require 'json'
require 'tmpdir'

bin = ENV.fetch('ASCIICHEM_INCHI_BIN', 'inchi-1')
fixtures_dir = File.expand_path('../corpus/fixtures', __dir__)
files = Dir[File.join(fixtures_dir, '*.json')].sort

records = []
files.each do |path|
  JSON.parse(File.read(path)).each { |rec| records << [path, rec] }
end
puts "records: #{records.length}"

Dir.mktmpdir do |dir|
  sdf = File.join(dir, 'batch.sdf')
  File.open(sdf, 'w') do |f|
    records.each { |(_, rec)| f.write(rec['molfile'].to_s + "$$$$\n") }
  end

  out = File.join(dir, 'o.txt')
  system(bin, sdf, out, File.join(dir, 'o.log'),
         out: File::NULL, err: File::NULL)
  txt = File.read(out)

  # txt = [pre, n1, body1, n2, body2, ...]
  blocks = txt.split(/^Structure: (\d+)\n/)
  aux_by_n = {}
  inchi_by_n = {}
  blocks.drop(1).each_slice(2) do |n, body|
    break if n.nil? || body.nil?
    aux_by_n[n.to_i] = body[/^AuxInfo=\S+/]
    inchi_by_n[n.to_i] = body[/^InChI=\S+/]
  end

  mismatches = 0
  missing = 0
  records.each_with_index do |(_path, rec), i|
    aux = aux_by_n[i + 1]
    oracle_inchi = inchi_by_n[i + 1]
    if aux.nil? || oracle_inchi.nil?
      missing += 1
      warn "MISSING oracle output for #{rec['id']} (structure #{i + 1})"
      next
    end
    unless oracle_inchi == rec['inchi']
      mismatches += 1
      warn "INCHI MISMATCH for #{rec['id']}: oracle #{oracle_inchi} != recorded #{rec['inchi']}"
      next
    end
    rec['aux'] = aux
  end
  warn "missing: #{missing}, inchi mismatches: #{mismatches}"
  exit 1 if mismatches.positive? || missing.positive?
end

by_file = records.group_by(&:first)
by_file.each do |path, pairs|
  File.write(path, JSON.pretty_generate(pairs.map(&:last)) + "\n")
end
puts 'done'
