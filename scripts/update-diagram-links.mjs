import assert from 'node:assert/strict'
import { readFile, writeFile } from 'node:fs/promises'

const root = new URL('../', import.meta.url)
const names = ['how-it-works', 'deployment-self-hosted', 'deployment-managed']
const check = process.argv.includes('--check')
assert(process.argv.slice(2).every(arg => arg === '--check'), 'Usage: node scripts/update-diagram-links.mjs [--check]')

const links = []
for (const name of names) {
  const diagram = JSON.parse(await readFile(new URL(`assets/diagrams/${name}.json`, root), 'utf8'))
  assert(Array.isArray(diagram.groups) && Array.isArray(diagram.nodes) && Array.isArray(diagram.connections), `${name}: missing diagram arrays`)
  const ids = new Set()
  for (const node of diagram.nodes) {
    assert(typeof node.id === 'string' && node.id && !ids.has(node.id), `${name}: invalid or duplicate node id`)
    ids.add(node.id)
  }
  for (const item of [...diagram.groups, ...diagram.nodes]) {
    assert([item.x, item.y, item.w, item.h].every(Number.isFinite) && item.w > 0 && item.h > 0, `${name}: invalid bounds`)
  }
  for (const connection of diagram.connections) {
    assert(ids.has(connection.from) && ids.has(connection.to), `${name}: dangling connection`)
    for (const side of [connection.fromSide, connection.toSide]) {
      assert(['left', 'right', 'top', 'bottom'].includes(side), `${name}: invalid connection side`)
    }
  }
  const preview = await readFile(new URL(`assets/images/${name}.svg`, root), 'utf8')
  assert(preview.startsWith('<svg') && !/<(?:script|foreignObject)\b/i.test(preview), `${name}: expected a GitHub-safe SVG export`)
  const payload = Buffer.from(JSON.stringify(diagram), 'utf8').toString('base64')
  links.push(`[draw-${name}]: https://draw.uug.ai/#diagram=${payload}`)
}

const file = new URL('README.md', root)
const readme = await readFile(file, 'utf8')
const start = '<!-- BEGIN GENERATED DRAW LINKS -->'
const end = '<!-- END GENERATED DRAW LINKS -->'
assert(readme.split(start).length === 2 && readme.split(end).length === 2, 'Expected one Draw links section in README.md')
const section = `${start}\n${links.join('\n')}\n${end}`
const updated = readme.replace(/<!-- BEGIN GENERATED DRAW LINKS -->[\s\S]*?<!-- END GENERATED DRAW LINKS -->/, section)
if (check) {
  assert.equal(updated, readme, 'Draw links are stale. Run node scripts/update-diagram-links.mjs')
} else if (updated !== readme) {
  await writeFile(file, updated)
}
console.log(`${check ? 'Verified' : 'Updated'} ${names.length} editable Draw links and checked their sources/previews.`)
