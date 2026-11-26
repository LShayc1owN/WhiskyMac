import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { test } from 'node:test';
import { approval, field } from './services.mjs';
import worker, { synchronize } from './worker.mjs';

function record(id, order, fields = {}) {
  return {
    record_id: id,
    fields: {
      [field.order]: [{ text: order, type: 'text' }],
      [field.approval]: approval.approved,
      [field.visibility]: '公开',
      [field.name]: id,
      ...fields,
    },
  };
}

test('scheduled sync paginates, signs a scoped installation request, and keeps buyer data out of GitHub', async (t) => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const env = {
    FEISHU_APP_ID: 'test-app', FEISHU_APP_SECRET: 'test-secret',
    FEISHU_BASE_TOKEN: 'test-base', FEISHU_TABLE_ID: 'test-table',
    GITHUB_OWNER: 'test-owner', GITHUB_REPO: 'test-repo', GITHUB_BRANCH: 'test-branch',
    GITHUB_APP_CLIENT_ID: 'test-client', GITHUB_INSTALLATION_ID: '123',
    GITHUB_APP_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }),
  };
  const approved = [record('rec-public', 'PRIVATE-ORDER-A', {
    [field.name]: '海盐 [x](https://example.test) @test', [field.username]: 'octocat',
  }), record('rec-nickname', 'PRIVATE-ORDER-B', { [field.name]: '小栗子' })];
  const anonymous = record('rec-anonymous', 'PRIVATE-ORDER-C', {
    [field.visibility]: '匿名', [field.name]: '隐藏昵称', [field.username]: 'hidden-account',
  });
  const updates = [];
  let published;
  t.mock.method(globalThis, 'fetch', async (address, options) => {
    assert.equal(options.redirect, 'manual');
    const url = new URL(address);
    const body = options.body && JSON.parse(options.body);
    if (url.pathname.endsWith('/tenant_access_token/internal')) {
      assert.deepEqual(body, { app_id: 'test-app', app_secret: 'test-secret' });
      return Response.json({ code: 0, tenant_access_token: 'test-tenant' });
    }
    if (url.pathname === '/app/installations/123/access_tokens') {
      const jwt = options.headers.Authorization.replace('Bearer ', '').split('.');
      const claims = JSON.parse(Buffer.from(jwt[1], 'base64url'));
      assert.equal(claims.iss, env.GITHUB_APP_CLIENT_ID);
      assert.equal(verify('RSA-SHA256', Buffer.from(jwt.slice(0, 2).join('.')), publicKey, Buffer.from(jwt[2], 'base64url')), true);
      assert.deepEqual(body, { repositories: ['test-repo'], permissions: { contents: 'write' } });
      return Response.json({ token: 'test-install-token' });
    }
    if (url.pathname.endsWith('/records/search')) {
      assert.equal(options.headers.Authorization, 'Bearer test-tenant');
      assert.ok(!body.field_names.includes('核对码'));
      assert.ok(!body.field_names.includes(field.afdianOrder));
      assert.deepEqual(body.filter.conditions.map((condition) => condition.value[0]), ['已通过', '已撤销']);
      const secondPage = url.searchParams.get('page_token') === 'second';
      return Response.json({ code: 0, data: secondPage
        ? { items: [anonymous], has_more: false }
        : { items: approved, has_more: true, page_token: 'second' } });
    }
    if (url.pathname.endsWith('/records/batch_update')) {
      updates.push(...body.records);
      return Response.json({ code: 0 });
    }
    if (url.pathname.startsWith('/users/')) {
      const login = url.pathname.split('/').at(-1);
      return Response.json({ login, id: login === 'octocat' ? 123 : 456, type: 'User' });
    }
    assert.equal(url.pathname, '/repos/test-owner/test-repo/contents/README.md');
    if (options.method === 'PUT') {
      assert.equal(body.sha, 'old-sha');
      assert.equal(body.branch, 'test-branch');
      published = Buffer.from(body.content, 'base64').toString('utf8');
      return Response.json({});
    }
    assert.equal(url.searchParams.get('ref'), 'test-branch');
    return Response.json({ type: 'file', encoding: 'base64', sha: 'old-sha', content: 'T2xk\n' });
  });

  await worker.scheduled({}, env);
  assert.match(published, /海盐.*\]\(https:\/\/github\.com\/octocat\)/);
  assert.match(published, /- 小栗子/);
  assert.match(published, /匿名赞助者 × 1/);
  assert.doesNotMatch(published, /隐藏昵称|hidden-account|PRIVATE-ORDER|456|@test|https:\/\/example/);
  assert.equal(updates.find((row) => row.record_id === 'rec-anonymous').fields[field.githubId], '456');
});

test('keeps the registered order, blocks ambiguous duplicates, and reconciles a revocation', async () => {
  const original = record('Original', 'A');
  const other = record('Other', 'B');
  const rows = [original, other];
  let content = '';
  let publishCount = 0;
  const feishu = {
    list: async () => rows,
    update: async (patches) => {
      for (const patch of patches) Object.assign(rows.find((row) => row.record_id === patch.record_id).fields, patch.fields);
    },
  };
  const github = {
    loadReadme: async () => ({ sha: 'sha', content }),
    publish: async (_, next) => { content = next; publishCount++; },
  };
  const sync = () => synchronize(feishu, async () => github);
  await sync();
  rows.push(record('Duplicate', ' a '), record('AmbiguousOne', 'C'), record('AmbiguousTwo', 'c'));
  await sync();
  assert.match(content, /- Original/);
  assert.doesNotMatch(content, /Duplicate|Ambiguous/);
  assert.equal(publishCount, 1);

  original.fields[field.approval] = approval.revoked;
  await sync();
  assert.match(content, /- Other/);
  assert.doesNotMatch(content, /Original|Duplicate|Ambiguous/);
  assert.match(rows[2].fields[field.sync], /订单已撤销/);
  assert.match(rows[3].fields[field.sync], /订单重复/);
  assert.equal(publishCount, 2);
});

test('preserves the published snapshot on a failed write and recovers on the next run', async () => {
  const row = record('NewSupporter', 'A');
  const feishu = {
    list: async () => [row],
    update: async (patches) => Object.assign(row.fields, patches[0].fields),
  };
  let content = 'Existing supporters';
  let fail = true;
  const openGitHub = async () => ({
    loadReadme: async () => ({ sha: 'sha', content }),
    publish: async (_, next) => {
      if (fail) throw new Error('GitHub unavailable');
      content = next;
    },
  });
  await assert.rejects(synchronize(feishu, openGitHub), /GitHub unavailable/);
  assert.equal(content, 'Existing supporters');
  assert.match(row.fields[field.sync], /待重试/);
  fail = false;
  await synchronize(feishu, openGitHub);
  assert.match(content, /NewSupporter/);
  assert.equal(row.fields[field.sync], '已同步');
});

test('treats a Patreon order and an Afdian order with the same number independently', async () => {
  const patreon = record('PatreonSupporter', 'SHARED', { [field.registeredOrder]: 'shared' });
  const afdian = record('AfdianSupporter', '', { [field.afdianOrder]: 'SHARED' });
  const rows = [patreon, afdian];
  let content = '';
  const feishu = {
    list: async () => rows,
    update: async (patches) => {
      for (const { record_id, fields } of patches) {
        Object.assign(rows.find((row) => row.record_id === record_id).fields, fields);
      }
    },
  };
  const github = {
    loadReadme: async () => ({ sha: 'sha', content }),
    publish: async (_, next) => { content = next; },
  };
  const sync = () => synchronize(feishu, async () => github);

  await sync();
  assert.match(content, /- PatreonSupporter/);
  assert.match(content, /- AfdianSupporter/);
  assert.equal(patreon.fields[field.registeredOrder], 'shared');
  assert.equal(afdian.fields[field.registeredOrder], 'afdian:shared');

  const duplicate = record('DuplicateAfdian', '', { [field.afdianOrder]: ' shared ' });
  const both = record('BothChannels', 'ambiguous', { [field.afdianOrder]: 'ambiguous' });
  rows.push(duplicate, both);
  await sync();
  assert.match(duplicate.fields[field.sync], /订单重复/);
  assert.match(both.fields[field.sync], /只能填写一个渠道/);
  assert.doesNotMatch(content, /DuplicateAfdian|BothChannels/);

  afdian.fields[field.approval] = approval.revoked;
  await sync();
  assert.match(content, /- PatreonSupporter/);
  assert.doesNotMatch(content, /AfdianSupporter|DuplicateAfdian/);
  assert.match(duplicate.fields[field.sync], /订单已撤销/);
});
