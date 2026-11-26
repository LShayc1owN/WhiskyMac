export const field = {
  order: 'Patreon 订单号',
  visibility: '公开方式',
  name: '展示昵称',
  username: 'GitHub 用户名',
  approval: '审核状态',
  registeredOrder: '已登记订单号',
  githubId: 'GitHub 数字 ID',
  githubLogin: '已检查登录名',
  sync: '同步结果',
};

export const approval = { approved: '已通过', revoked: '已撤销' };
export const githubUsername = /^(?=.{1,39}$)[a-z\d]+(?:-[a-z\d]+)*$/i;

function setting(env, key) {
  const value = env[key]?.trim();
  if (!value) throw new Error(`配置缺失（${key}）`);
  return value;
}

async function request(label, url, options = {}) {
  try {
    return await fetch(url, {
      ...options,
      // Workers supports manual redirects. Keep credentials on the configured origin.
      redirect: 'manual',
      signal: AbortSignal.timeout(12_000),
    });
  } catch {
    throw new Error(`${label}网络请求失败`);
  }
}

async function json(label, response) {
  if (!response.ok) throw new Error(`${label}失败（HTTP ${response.status}）`);
  try {
    return await response.json();
  } catch {
    throw new Error(`${label}返回了无效数据`);
  }
}

async function feishuRequest(label, url, options) {
  const body = await json(label, await request(label, url, options));
  if (body?.code !== 0) {
    const code = Number.isInteger(body?.code) ? body.code : '未知';
    throw new Error(`${label}失败（飞书错误码 ${code}）`);
  }
  return body;
}

export async function connectFeishu(env) {
  const origin = 'https://open.feishu.cn';
  const app = encodeURIComponent(setting(env, 'FEISHU_BASE_TOKEN'));
  const table = encodeURIComponent(setting(env, 'FEISHU_TABLE_ID'));
  const endpoints = `${origin}/open-apis/bitable/v1/apps/${app}/tables/${table}/records`;
  const token = await feishuRequest(
    '飞书应用认证',
    `${origin}/open-apis/auth/v3/tenant_access_token/internal`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        app_id: setting(env, 'FEISHU_APP_ID'),
        app_secret: setting(env, 'FEISHU_APP_SECRET'),
      }),
    },
  );
  if (!token.tenant_access_token) throw new Error('飞书应用认证缺少令牌');
  const headers = {
    Authorization: `Bearer ${token.tenant_access_token}`,
    'Content-Type': 'application/json',
  };

  return {
    async list() {
      const records = [];
      const seenPages = new Set();
      let pageToken;
      do {
        const params = new URLSearchParams({ page_size: '500' });
        if (pageToken) params.set('page_token', pageToken);
        const { data } = await feishuRequest('读取飞书审批', `${endpoints}/search?${params}`, {
          method: 'POST',
          headers,
          body: JSON.stringify({
            field_names: Object.values(field),
            filter: {
              conjunction: 'or',
              conditions: Object.values(approval).map((value) => ({
                field_name: field.approval, operator: 'is', value: [value],
              })),
            },
          }),
        });
        const items = data?.items ?? (data?.total === 0 ? [] : null);
        if (typeof data?.has_more !== 'boolean' || !Array.isArray(items)
          || items.some((row) => !row?.record_id || !row.fields)) {
          throw new Error('飞书审批记录格式无效');
        }
        records.push(...items);
        pageToken = data.has_more ? data.page_token : undefined;
        if (data.has_more && (!pageToken || seenPages.has(pageToken))) {
          throw new Error('飞书审批记录分页失败');
        }
        if (pageToken) seenPages.add(pageToken);
      } while (pageToken);
      if (new Set(records.map((row) => row.record_id)).size !== records.length) {
        throw new Error('读取飞书时记录发生变动，请重试');
      }
      return records;
    },

    async update(records) {
      for (let index = 0; index < records.length; index += 500) {
        const batch = records.slice(index, index + 500);
        await feishuRequest('写入飞书同步结果', `${endpoints}/batch_update`, {
          method: 'POST',
          headers,
          body: JSON.stringify({ records: batch }),
        });
      }
    },
  };
}

function base64(bytes) {
  let binary = '';
  for (let index = 0; index < bytes.length; index += 8192) {
    binary += String.fromCharCode(...bytes.subarray(index, index + 8192));
  }
  return btoa(binary);
}

const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });

function base64url(bytes) {
  return base64(bytes).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

async function appJWT(env) {
  const clientId = setting(env, 'GITHUB_APP_CLIENT_ID');
  const pem = setting(env, 'GITHUB_APP_PRIVATE_KEY');
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(encoder.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: clientId, iat: now - 60, exp: now + 540 })));
  const unsigned = `${header}.${claims}`;
  try {
    const raw = pem.replace('-----BEGIN PRIVATE KEY-----', '')
      .replace('-----END PRIVATE KEY-----', '').replace(/\s/g, '');
    const algorithm = { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' };
    const key = await crypto.subtle.importKey('pkcs8', Uint8Array.fromBase64(raw), algorithm, false, ['sign']);
    const signature = await crypto.subtle.sign(algorithm.name, key, encoder.encode(unsigned));
    return `${unsigned}.${base64url(new Uint8Array(signature))}`;
  } catch {
    throw new Error('GitHub App 私钥无效，需要 PKCS#8 PEM');
  }
}

export async function connectGitHub(env) {
  const origin = 'https://api.github.com';
  const owner = encodeURIComponent(setting(env, 'GITHUB_OWNER'));
  const repo = setting(env, 'GITHUB_REPO');
  const branch = setting(env, 'GITHUB_BRANCH');
  const installation = encodeURIComponent(setting(env, 'GITHUB_INSTALLATION_ID'));
  const baseHeaders = {
    Accept: 'application/vnd.github+json',
    'Content-Type': 'application/json',
    'User-Agent': 'WhiskyMac-Supporters',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  const tokenURL = `${origin}/app/installations/${installation}/access_tokens`;
  const { token } = await json('GitHub App 安装认证', await request('GitHub App 安装认证', tokenURL, {
    method: 'POST',
    headers: { ...baseHeaders, Authorization: `Bearer ${await appJWT(env)}` },
    body: JSON.stringify({ repositories: [repo], permissions: { contents: 'write' } }),
  }));
  if (!token) throw new Error('GitHub App 安装认证缺少令牌');
  const headers = { ...baseHeaders, Authorization: `Bearer ${token}` };
  const readme = `${origin}/repos/${owner}/${encodeURIComponent(repo)}/contents/README.md`;

  return {
    async loadReadme() {
      const result = await json('读取 GitHub 名单', await request(
        '读取 GitHub 名单', `${readme}?ref=${encodeURIComponent(branch)}`, { headers },
      ));
      if (result.type !== 'file' || result.encoding !== 'base64' || !result.sha) {
        throw new Error('GitHub 名单文件格式无效');
      }
      return { sha: result.sha, content: decoder.decode(Uint8Array.fromBase64(result.content)) };
    },

    async account(username) {
      const response = await request('核验 GitHub 账号', `${origin}/users/${encodeURIComponent(username)}`, { headers });
      if (response.status === 404) return null;
      const { id, login, type } = await json('核验 GitHub 账号', response);
      if (!Number.isSafeInteger(id) || id <= 0 || typeof login !== 'string' || !githubUsername.test(login)) {
        throw new Error('GitHub 账号数据无效');
      }
      return type === 'User' ? { id: String(id), login } : null;
    },

    async publish(sha, content) {
      await json('更新 GitHub 名单', await request('更新 GitHub 名单', readme, {
        method: 'PUT',
        headers,
        body: JSON.stringify({
          message: 'Update WhiskyMac supporters', branch, sha, content: base64(encoder.encode(content)),
        }),
      }));
    },
  };
}
