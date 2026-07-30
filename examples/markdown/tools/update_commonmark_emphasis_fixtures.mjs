#!/usr/bin/env node
// Regenerate the hermetic CommonMark emphasis HTML oracle.
//
// The checked-in CommonMark 0.31.2 JSON is the sole source of Markdown and
// expected HTML. The adjacent manifest records only explicit status overrides.

import { createHash } from 'node:crypto'
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const SECTION = 'Emphasis and strong emphasis'
const FIRST_EXAMPLE = 350
const LAST_EXAMPLE = 481
const EXPECTED_FIXTURE_COUNT = 132
const EXPECTED_SPEC_SHA256 =
  'd431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20'

function fail(message) {
  throw new Error(`CommonMark emphasis fixture validation failed: ${message}`)
}

function parseJson(source, label) {
  try {
    return JSON.parse(source)
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error)
    fail(`${label} is not valid JSON: ${detail}`)
  }
}

function validateSpec(specBytes) {
  const actualSha256 = createHash('sha256').update(specBytes).digest('hex')
  if (actualSha256 !== EXPECTED_SPEC_SHA256) {
    fail(
      `spec SHA-256 mismatch: expected ${EXPECTED_SPEC_SHA256}, got ${actualSha256}`,
    )
  }

  const spec = parseJson(specBytes.toString('utf8'), 'CommonMark spec')
  if (!Array.isArray(spec)) fail('CommonMark spec must be a JSON array')

  const sectionFixtures = spec.filter(candidate => candidate?.section === SECTION)
  if (sectionFixtures.length !== EXPECTED_FIXTURE_COUNT) {
    fail(
      `expected ${EXPECTED_FIXTURE_COUNT} fixtures in ${JSON.stringify(SECTION)}, ` +
        `got ${sectionFixtures.length}`,
    )
  }

  const rangeFixtures = spec.filter(candidate => {
    const example = candidate?.example
    return (
      Number.isInteger(example) &&
      example >= FIRST_EXAMPLE &&
      example <= LAST_EXAMPLE
    )
  })
  if (rangeFixtures.length !== EXPECTED_FIXTURE_COUNT) {
    fail(
      `expected ${EXPECTED_FIXTURE_COUNT} fixtures in example range ` +
        `${FIRST_EXAMPLE}-${LAST_EXAMPLE}, got ${rangeFixtures.length}`,
    )
  }

  const seenExamples = new Set()
  for (const [index, fixture] of sectionFixtures.entries()) {
    if (!fixture || typeof fixture !== 'object' || Array.isArray(fixture)) {
      fail(`fixture at section index ${index} must be an object`)
    }
    const expectedExample = FIRST_EXAMPLE + index
    if (fixture.example !== expectedExample) {
      fail(
        `expected continuous example ${expectedExample} at section index ${index}, ` +
          `got ${JSON.stringify(fixture.example)}`,
      )
    }
    if (seenExamples.has(fixture.example)) {
      fail(`duplicate CommonMark example ${fixture.example}`)
    }
    seenExamples.add(fixture.example)
    if (fixture.section !== SECTION) {
      fail(
        `example ${fixture.example} has section ${JSON.stringify(fixture.section)}, ` +
          `expected ${JSON.stringify(SECTION)}`,
      )
    }
    if (typeof fixture.markdown !== 'string') {
      fail(`example ${fixture.example} has non-string markdown`)
    }
    if (typeof fixture.html !== 'string') {
      fail(`example ${fixture.example} has non-string html`)
    }
  }

  for (const fixture of rangeFixtures) {
    if (fixture.section !== SECTION) {
      fail(
        `example ${fixture.example} in the selected range belongs to ` +
          `${JSON.stringify(fixture.section)}, not ${JSON.stringify(SECTION)}`,
      )
    }
  }

  return sectionFixtures.map(fixture => ({
    example: fixture.example,
    section: fixture.section,
    markdown: fixture.markdown,
    html: fixture.html,
  }))
}

function validateOverrides(manifestSource, fixtures) {
  const manifest = parseJson(manifestSource, 'override manifest')
  if (!Array.isArray(manifest)) fail('override manifest must be a JSON array')

  const fixtureIds = new Set(fixtures.map(fixture => fixture.example))
  const overrides = new Map()
  for (const [index, entry] of manifest.entries()) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      fail(`manifest entry ${index} must be an object`)
    }
    const keys = Object.keys(entry).sort()
    const expectedKeys = ['example', 'reason', 'status']
    if (keys.join(',') !== expectedKeys.join(',')) {
      fail(
        `manifest entry ${index} must contain exactly example, status, and reason`,
      )
    }
    if (!Number.isInteger(entry.example) || !fixtureIds.has(entry.example)) {
      fail(`manifest entry ${index} has unknown example ${JSON.stringify(entry.example)}`)
    }
    if (overrides.has(entry.example)) {
      fail(`manifest contains duplicate example ${entry.example}`)
    }
    if (entry.status !== 'xfail' && entry.status !== 'skip') {
      fail(
        `manifest example ${entry.example} has unsupported status ` +
          `${JSON.stringify(entry.status)}; expected "xfail" or "skip"`,
      )
    }
    if (
      typeof entry.reason !== 'string' ||
      entry.reason.length === 0 ||
      entry.reason !== entry.reason.trim()
    ) {
      fail(`manifest example ${entry.example} must have a nonempty trimmed reason`)
    }
    overrides.set(entry.example, {
      status: entry.status,
      reason: entry.reason,
    })
  }

  return overrides
}

function buildFixtureModel(specBytes, manifestSource) {
  const fixtures = validateSpec(specBytes)
  const overrides = validateOverrides(manifestSource, fixtures)
  const modeledFixtures = fixtures.map(fixture => ({
    ...fixture,
    name: `emphasis-and-strong-emphasis-${fixture.example}`,
    status: overrides.get(fixture.example) ?? { status: 'pass', reason: null },
  }))
  const counts = { pass: 0, xfail: 0, skip: 0 }
  for (const fixture of modeledFixtures) counts[fixture.status.status] += 1
  if (counts.pass !== 127 || counts.xfail !== 5 || counts.skip !== 0) {
    fail(
      `expected baseline pass=127, xfail=5, skip=0; got ` +
        `pass=${counts.pass}, xfail=${counts.xfail}, skip=${counts.skip}`,
    )
  }
  return { fixtures: modeledFixtures, counts }
}

function moonString(value) {
  return JSON.stringify(value)
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029')
}

function renderStatusLines(status) {
  switch (status.status) {
    case 'pass':
      return ['      status: CommonMarkHtmlPass,']
    case 'xfail':
      return [
        '      status: CommonMarkHtmlXfail(',
        `        ${moonString(status.reason)},`,
        '      ),',
      ]
    case 'skip':
      return [
        '      status: CommonMarkHtmlSkip(',
        `        ${moonString(status.reason)},`,
        '      ),',
      ]
    default:
      fail(`cannot render unknown status ${JSON.stringify(status.status)}`)
  }
}

function renderFixtureFile(model) {
  const lines = [
    '// Generated by examples/markdown/tools/update_commonmark_emphasis_fixtures.mjs.',
    '// Do not edit by hand. Markdown and expected HTML come only from the checked-in',
    '// CommonMark 0.31.2 spec JSON; status exceptions come from the adjacent manifest.',
    `// Spec SHA-256: ${EXPECTED_SPEC_SHA256}.`,
    `// Baseline: pass=${model.counts.pass}, xfail=${model.counts.xfail}, skip=${model.counts.skip}.`,
    '',
    '///|',
    'fn commonmark_emphasis_html_fixture_expected_status_counts() -> (Int, Int, Int) {',
    `  (${model.counts.pass}, ${model.counts.xfail}, ${model.counts.skip})`,
    '}',
    '',
    '///|',
    'fn commonmark_emphasis_html_fixture_cases() -> Array[CommonMarkHtmlFixture] {',
    '  [',
  ]

  for (const fixture of model.fixtures) {
    lines.push('    {')
    lines.push(`      example: ${fixture.example},`)
    lines.push(`      section: ${moonString(fixture.section)},`)
    lines.push(`      name: ${moonString(fixture.name)},`)
    lines.push(`      source: ${moonString(fixture.markdown)},`)
    lines.push(`      expected_html: ${moonString(fixture.html)},`)
    lines.push(...renderStatusLines(fixture.status))
    lines.push('    },')
  }

  lines.push('  ]')
  lines.push('}')
  lines.push('')
  return lines.join('\n')
}

function main() {
  const toolDirectory = dirname(fileURLToPath(import.meta.url))
  const specPath = join(toolDirectory, 'commonmark-0.31.2-spec.json')
  const manifestPath = join(toolDirectory, 'commonmark_html_fixture_overrides.json')
  const outputPath = join(
    toolDirectory,
    '..',
    'commonmark_emphasis_html_fixture_data_test.mbt',
  )

  const specBytes = readFileSync(specPath)
  const manifestSource = readFileSync(manifestPath, 'utf8')
  const output = renderFixtureFile(buildFixtureModel(specBytes, manifestSource))
  writeFileSync(outputPath, output, 'utf8')
  console.log(`Wrote ${outputPath}`)
}

try {
  main()
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error))
  process.exitCode = 1
}
