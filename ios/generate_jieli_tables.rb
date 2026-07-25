source = File.read(File.expand_path('../web/src/jl-auth.ts', __dir__), encoding: 'UTF-8')

def values(source, name)
  match = source.match(/const #{name}: number\[\] = \[(.*?)\]/m) or abort "Missing #{name}"
  match[1].scan(/0x[0-9a-f]+/i)
end

tables = {
  'keySchedule' => values(source, 'KS_TABLE'),
  'sbox' => values(source, 'SBOX'),
  'inverseSbox' => values(source, 'ISBOX'),
}

output = +"// Generated from web/src/jl-auth.ts. Do not edit by hand.\nimport Foundation\n\nenum JieliTables {\n"
tables.each do |name, bytes|
  output << "    static let #{name}: [UInt8] = [\n"
  bytes.each_slice(16) { |slice| output << "        #{slice.join(', ')},\n" }
  output << "    ]\n"
end
output << "}\n"
File.write(File.join(__dir__, 'PheonixGPMoto', 'JieliTables.generated.swift'), output)
