import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const read = path => readFileSync(`${root}/${path}`);
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const manifest = JSON.parse(read('formal/tests/UP002/artifacts.json'));

for (const [path, expected] of Object.entries(manifest.sourceSha256)) {
  assert.equal(sha256(read(path)), expected, `Source identity changed: ${path}`);
}

for (const entry of manifest.validators) {
  const source = read(entry.lean).toString();
  const embedded = source.match(/singleCborEncodedScriptFromHexM "([0-9a-f]+)"/)[1];
  const blueprint = JSON.parse(read(entry.blueprint));
  const validator = blueprint.validators.find(item => item.title === entry.title);
  assert.equal(validator.compiledCode, embedded, `${entry.name}: embedded program differs`);
  const bytes = Buffer.from(embedded, 'hex');
  assert.equal(bytes.length, entry.compiledCodeBytes, `${entry.name}: CBOR length differs`);
  assert.equal(sha256(bytes), entry.compiledCodeSha256, `${entry.name}: CBOR digest differs`);
  assert.equal(validator.hash, entry.scriptHashHex, `${entry.name}: blueprint hash differs`);
  assert.equal(source.match(/def ownHashHex : String := "([0-9a-f]+)"/)[1], entry.scriptHashHex);
  const own = source.match(/def own : ByteString := ⟨⟨\[([^\]]+)\]\.map Char\.ofNat⟩⟩/)[1];
  const decoded = own.split(',').map(item => Number(item.trim()));
  assert.equal(decoded.length, 28, `${entry.name}: own must contain 28 decoded bytes`);
  assert(decoded.every(byte => Number.isInteger(byte) && byte >= 0 && byte <= 255));
  assert.equal(Buffer.from(decoded).toString('hex'), entry.scriptHashHex);
  // The shell wrapper independently hashes these raw bytes with GNU b2sum.
  process.stdout.write(`${entry.name}\t${entry.scriptHashHex}\t03${embedded}\n`);
}
