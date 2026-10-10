import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const spec = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
const migration = await readFile(new URL('../../migrations/0109_branch_country.sql', import.meta.url), 'utf8');
const dto = await readFile(new URL('../../src/branches/branch-onboarding.dto.ts', import.meta.url), 'utf8');
const metricsController = await readFile(new URL('../../src/metrics/metrics.controller.ts', import.meta.url), 'utf8');

test('migration 0109 adds branches.country_code with ISO alpha-2 check, SV default and org/country/status index', () => {
  assert.match(migration, /ALTER TABLE branches ADD COLUMN IF NOT EXISTS country_code text NOT NULL DEFAULT 'SV'/);
  assert.match(migration, /CHECK \(country_code ~ '\^\[A-Z\]\{2\}\$'\)/);
  assert.match(migration, /ON branches \(organization_id, country_code, status\)/);
  assert.match(migration, /^BEGIN;[\s\S]*COMMIT;\s*$/);
});

test('OpenAPI exposes branch countryCode on create, list filter and onboarding identity', () => {
  const country = spec.components.schemas.CountryCode;
  assert.equal(country.pattern, '^[A-Z]{2}$');
  const create = spec.components.schemas.BranchDraftRequest;
  assert.ok(create.properties.countryCode);
  assert.equal(create.properties.countryCode.default, 'SV');
  assert.ok(!create.required.includes('countryCode'), 'countryCode es opcional al crear');
  assert.match(spec.components.schemas.OnboardingStepRequest.properties.data.description, /countryCode/);
  const filter = spec.paths['/branches'].get.parameters.find(parameter => parameter.name === 'countryCode');
  assert.equal(filter?.in, 'query');
  assert.equal(filter.required, false);
  assert.match(dto, /countryCode\?: string/);
  assert.match(dto, /@Matches\(\/\^\[A-Z\]\{2\}\$\/\)/);
});

test('OpenAPI network dashboard documents countryCode filter, countries summary and per-branch countryCode', () => {
  const operation = spec.paths['/metrics/network/dashboard'].get;
  const parameter = operation.parameters.find(item => item.name === 'countryCode');
  assert.equal(parameter?.in, 'query');
  assert.notEqual(parameter.required, true);
  const data = operation.responses['200'].content['application/json'].schema.properties.data;
  assert.equal(data.properties.countries.items.$ref, '#/components/schemas/NetworkCountrySummary');
  assert.deepEqual(spec.components.schemas.NetworkCountrySummary.required, ['countryCode', 'branchCount']);
  assert.ok(data.properties.branches.items.properties.countryCode);
  assert.ok(data.properties.scopeCountryCode);
  const branchDashboard = spec.paths['/metrics/branches/{branchId}/dashboard'].get.responses['200'].content['application/json'].schema.properties.data;
  assert.ok(branchDashboard.properties.branch.properties.countryCode);
  assert.match(metricsController, /@Query\('countryCode'\)/);
});
