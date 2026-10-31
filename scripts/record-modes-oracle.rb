#!/usr/bin/env ruby
# frozen_string_literal: true

# Records the oracle's non-standard mode outputs for every fixture
# record: "fixedh" (-FixedH), "recmet" (-RecMet), "snon" (-SNon). Each
# mode is one batch SDF run of the CLEAN inchi-1 executable (the
# instrumented witnessing build segfaults on -FixedH — use
# ASCIICHEM_INCHI_BIN to point at a clean binary); each fixture gains
# "<mode>" => { "inchi" => String|Array, "aux" => String }.
# Development-time tooling — the corpus ships the recorded strings.
#
#   ruby scripts/record-modes-oracle.rb
# The recorded STANDARD inchi lines are verified against the fixtures'
# existing "inchi" field each run (RecMet emits two lines per
# structure — disconnected then /r — stored as an array).

require 'json'
require 'tmpdir'

MODES = {
  'fixedh' => ['-FixedH'],
  'recmet' => ['-RecMet'],
  'snon' => ['-SNon']
}.freeze

bin = ENV.fetch('ASCIICHEM_INCHI_BIN')
fixtures_dir = File.expand_path('../corpus/fixtures', __dir__)
files = Dir[File.join(fixtures_dir, '*.json')].sort

records = []
files.each do |path|
  JSON.parse(File.read(path)).each { |rec| records << [path, rec] }
end
puts "records: #{records.length}"

def parse_blocks(txt)
  out = {}
  blocks = txt.split(/^Structure: (\d+)\n/)
  blocks.drop(1).each_slice(2) do |n, body|
    break if n.nil? || body.nil?

    inchis = body.scan(/^InChI=\S+/).map(&:strip)
    aux = body[/^AuxInfo=\S+/]
    out[n.to_i] = { 'inchi' => inchis.length == 1 ? inchis.first : inchis, 'aux' => aux }
  end
  out
end

Dir.mktmpdir do |dir|
  sdf = File.join(dir, 'batch.sdf')
  File.open(sdf, 'w') do |f|
    records.each { |(_, rec)| f.write(rec['molfile'].to_s + "$$$$\n") }
  end

  MODES.each do |mode, flags|
    out = File.join(dir, "o-#{mode}.txt")
    system(bin, sdf, out, File.join(dir, "o-#{mode}.log"),
           '-Key', *flags, out: File::NULL, err: File::NULL)
    parsed = parse_blocks(File.read(out))

    missing = 0
    mismatches = 0
    records.each_with_index do |(_path, rec), i|
      block = parsed[i + 1]
      if block.nil? || block['aux'].nil? || block['inchi'].nil? ||
         (block['inchi'].is_a?(String) && block['inchi'].empty?)
        missing += 1
        warn "MISSING #{mode} output for #{rec['id']}"
        next
      end
      standard = block['inchi'].is_a?(Array) ? block['inchi'].first : block['inchi']
      # Consistency check per mode, versions normalized (SNon keeps
      # the `1S` letter — it is standard-legal): FixedH and RecMet
      # EXTEND the standard layers (an /f block, resp. a /r block on
      # the same line); an SNon line TRUNCATES at the stereo boundary
      # (everything from /b onward is gone).
      line = standard.sub(/\AInChI=1(S?)/, '')
      base = rec['inchi'].delete_prefix('InChI=1S')
      ok = case mode
           when 'fixedh', 'recmet' then line.start_with?(base)
           else base.start_with?(line)
           end
      unless ok
        mismatches += 1
        warn "STANDARD MISMATCH (#{mode}) #{rec['id']}: #{standard} != #{rec['inchi']}"
        next
      end
      rec[mode] = { 'inchi' => block['inchi'], 'aux' => block['aux'] }
    end
    warn "#{mode}: missing #{missing}, standard mismatches #{mismatches}"
    exit 1 if missing.positive? || mismatches.positive?
  end
end

records.group_by(&:first).each do |path, pairs|
  File.write(path, JSON.pretty_generate(pairs.map(&:last)) + "\n")
end
puts 'done'
