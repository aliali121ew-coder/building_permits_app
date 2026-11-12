import fs from 'node:fs';

const SUPABASE_URL = 'https://diorwiyawahunnozeoqc.supabase.co';
const SUPABASE_KEY = 'sb_publishable_pPj5yUCAAIYnubgxty7X0Q_wywAV5K2';

function sqlStr(val) {
  if (val === null || val === undefined) return 'NULL';
  return "'" + String(val).replace(/'/g, "''") + "'";
}

function sqlNum(val) {
  if (val === null || val === undefined || val === '') return 'NULL';
  const n = Number(val);
  return Number.isFinite(n) ? String(n) : 'NULL';
}

async function fetchAllPermits() {
  const all = [];
  const step = 1000;
  let offset = 0;

  while (true) {
    const url = `${SUPABASE_URL}/rest/v1/permits?select=*&order=permit_year.asc,permit_number.asc&limit=${step}&offset=${offset}`;
    console.log(`Fetching offset ${offset}...`);
    const res = await fetch(url, {
      headers: {
        'apikey': SUPABASE_KEY,
        'Authorization': `Bearer ${SUPABASE_KEY}`,
      },
    });
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    }
    const batch = await res.json();
    all.push(...batch);
    console.log(`Fetched ${batch.length} rows (total: ${all.length})`);
    if (batch.length < step) break;
    offset += step;
  }
  return all;
}

async function main() {
  const permits = await fetchAllPermits();
  console.log(`Total permits fetched: ${permits.length}`);

  const lines = [];
  const chunkSize = 100;

  for (let i = 0; i < permits.length; i += chunkSize) {
    const chunk = permits.slice(i, i + chunkSize);
    const values = chunk.map(p => {
      const attachments = JSON.stringify(Array.isArray(p.attachment_urls) ? p.attachment_urls : []);
      const isDeleted = p.is_deleted ? 1 : 0;
      const dupFlag = p.duplicate_flag ? 1 : 0;

      return `(${[
        sqlStr(p.id),
        sqlNum(p.permit_number),
        sqlNum(p.permit_year),
        sqlStr(p.full_name ?? ''),
        sqlStr(p.plot_number ?? ''),
        sqlStr(p.permit_date ?? '1980-01-01'),
        sqlStr(p.notes),
        sqlStr(p.permit_type),
        sqlStr(p.name_change_notes),
        sqlNum(p.plot_area),
        sqlNum(p.building_area),
        sqlStr(p.name_per_new_registry),
        sqlStr(attachments),
        isDeleted,
        dupFlag,
        'NULL',
        sqlStr(p.created_at ?? new Date().toISOString()),
        'NULL',
        sqlStr(p.updated_at ?? new Date().toISOString()),
      ].join(',')})`;
    });

    lines.push(
      `INSERT OR IGNORE INTO permits (id, permit_number, permit_year, full_name, plot_number, permit_date, notes, permit_type, name_change_notes, plot_area, building_area, name_per_new_registry, attachment_urls, is_deleted, duplicate_flag, created_by, created_at, updated_by, updated_at) VALUES\n${values.join(',\n')};`
    );
  }

  fs.writeFileSync('migrated_permits.sql', lines.join('\n\n'), 'utf8');
  console.log('Saved migrated_permits.sql successfully!');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

