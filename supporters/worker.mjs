import {
  afdianReview, approval, connectAfdian, connectFeishu, connectGitHub, field, githubUsername,
  pendingAfdianStatuses,
} from './services.mjs';

const afdianCheckCron = '5,20,35,50 * * * *';

const listHeader = [
  '# WhiskyMac Supporters · 赞助者',
  '',
  'Thank you for supporting the independent development of [WhiskyMac](https://github.com/LShayc1owN/WhiskyMac).',
  '感谢你支持 WhiskyMac 的独立开发。',
  '',
];

function value(row, key) {
  const cell = row.fields[key];
  if (Array.isArray(cell)) return cell.map((part) => part?.text ?? '').join('').trim();
  return typeof cell === 'string' ? cell.trim() : '';
}

function orderKey(order) {
  return order.normalize('NFKC').toLowerCase();
}

function plainMarkdown(text) {
  return text.replace(/[\x21-\x2f\x3a-\x40\x5b-\x60\x7b-\x7e]/g, (character) => `&#${character.charCodeAt(0)};`);
}

export function renderSupporters(entries) {
  const named = entries.filter((entry) => entry !== null);
  named.sort((a, b) => a.name.localeCompare(b.name, 'en') || (a.login ?? '').localeCompare(b.login ?? '', 'en'));
  const lines = named.map(({ name, login }) => {
    const text = plainMarkdown(name);
    return login ? `- [${text}](https://github.com/${login})` : `- ${text}`;
  });
  const anonymous = entries.length - named.length;
  if (anonymous) lines.push(`- Anonymous supporters · 匿名赞助者 × ${anonymous}`);
  if (!lines.length) lines.push('The supporter list will appear here after the first approval.');
  return [...listHeader, ...lines, ''].join('\n');
}

function change(updates, row, fields) {
  const changed = Object.entries(fields).filter(([key, next]) => value(row, key) !== (next ?? ''));
  if (!changed.length) return;
  const previous = updates.get(row.record_id) ?? {};
  updates.set(row.record_id, { ...previous, ...Object.fromEntries(changed) });
}

async function save(feishu, updates) {
  if (updates.size) {
    await feishu.update(Array.from(updates, ([record_id, fields]) => ({ record_id, fields })));
  }
}

const afdianOrderId = /^[A-Za-z0-9_-]{1,64}$/;
const claimCode = /^[A-Za-z0-9]{8}$/;
const afdianRemark = /^(.+?)\s*[/／]\s*([A-Za-z0-9]{8})$/u;
const afdianMatch = '已付款，留言项目名和核对码一致';

function afdianResult(order, code, project) {
  if (!order) return '待人工核对，未查到订单';
  const amount = order.total_amount;
  if (order.status !== 2 || typeof amount !== 'string'
    || !/^\d+(?:\.\d+)?$/.test(amount) || !(Number(amount) > 0)) {
    return '待人工核对，订单未确认实付';
  }
  const remark = typeof order.remark === 'string' ? order.remark.trim() : '';
  if (!remark) return '已付款，缺少订单留言，请核对私信';
  if (claimCode.test(remark)) return '已付款，留言缺少项目名，请核对私信';
  const match = remark.match(afdianRemark);
  if (!match) return '已付款，留言格式无法识别，请核对私信';
  if (orderKey(match[1].trim()) !== project) return '已付款，留言项目名不符，请核对私信';
  if (match[2] !== code) return '已付款，留言核对码不一致，请核对私信';
  return afdianMatch;
}

async function verifyAfdianClaims(feishu, openAfdian, project) {
  const claims = [];
  const updates = new Map();
  const ids = new Set();
  for (const row of await feishu.listPendingAfdian()) {
    if (!pendingAfdianStatuses.includes(value(row, field.approval))) continue;
    const id = value(row, field.afdianOrder);
    if (!id) {
      change(updates, row, { [afdianReview.result]: null });
      continue;
    }
    const code = value(row, afdianReview.code);
    if (value(row, field.order) || !afdianOrderId.test(id) || !claimCode.test(code)) {
      change(updates, row, { [afdianReview.result]: '待人工核对，请检查订单号和核对码' });
      continue;
    }
    claims.push({ row, id, code });
    ids.add(id);
  }

  const orders = ids.size ? await openAfdian().orders([...ids]) : new Map();
  const matched = new Map();
  for (const { row, id, code } of claims) {
    const result = afdianResult(orders.get(id), code, project);
    if (result !== afdianMatch) {
      change(updates, row, { [afdianReview.result]: result });
      continue;
    }
    const group = matched.get(id) ?? [];
    group.push(row);
    matched.set(id, group);
  }
  for (const group of matched.values()) {
    const result = group.length === 1 ? afdianMatch : '待人工核对，同一订单有多条匹配申请';
    for (const row of group) change(updates, row, { [afdianReview.result]: result });
  }
  await save(feishu, updates);
}

function selectOrders(rows, statuses) {
  const orders = new Map();
  for (const row of rows) {
    const patreon = orderKey(value(row, field.order));
    const afdian = orderKey(value(row, field.afdianOrder));
    if (!patreon && !afdian) {
      change(statuses, row, { [field.sync]: '待更正：缺少订单号' });
      continue;
    }
    if (patreon && afdian) {
      change(statuses, row, { [field.sync]: '待更正：同一申请只能填写一个渠道的订单号' });
      continue;
    }
    const key = patreon ? `patreon:${patreon}` : `afdian:${afdian}`;
    const group = orders.get(key) ?? { order: patreon || key, rows: [] };
    group.rows.push(row);
    orders.set(key, group);
  }

  const selected = [];
  for (const { order, rows: group } of orders.values()) {
    const approved = group.filter((row) => value(row, field.approval) === approval.approved);
    const revoked = group.filter((row) => value(row, field.approval) === approval.revoked);
    for (const row of revoked) change(statuses, row, { [field.sync]: '已撤销' });
    const registered = approved.filter((row) => value(row, field.registeredOrder) === order);
    let winner;
    if (!revoked.length) {
      if (registered.length === 1) winner = registered[0];
      else if (approved.length === 1) winner = approved[0];
    }
    for (const row of approved) {
      if (row === winner) continue;
      const reason = revoked.length ? '订单已撤销' : '订单重复，请核查原记录';
      change(statuses, row, { [field.sync]: `待更正：${reason}` });
    }
    if (winner) selected.push({ row: winner, order });
  }
  return selected;
}

function validate(row) {
  const visibility = value(row, field.visibility);
  const name = value(row, field.name);
  const username = value(row, field.username);
  if (visibility !== '公开' && visibility !== '匿名') return { error: '请选择公开或匿名' };
  if (visibility === '公开' && (!name || [...name].length > 80 || /[\p{Cc}\p{Bidi_Control}\u2028\u2029]/u.test(name))) {
    return { error: '展示昵称需为 1 至 80 个字符的单行文本' };
  }
  if (username && !githubUsername.test(username)) return { error: '请只填写有效的 GitHub 用户名' };
  return { visibility, name, username };
}

export async function synchronize(feishu, openGitHub) {
  const bindings = new Map();
  const statuses = new Map();
  const ready = [];
  let rows;
  try {
    // Capture the GitHub SHA before reading approvals so a concurrent publish can't overwrite newer content.
    const github = await openGitHub();
    const current = await github.loadReadme();
    rows = await feishu.list();
    const accounts = new Map();
    const entries = [];
    for (const { row, order } of selectOrders(rows, statuses)) {
      const { visibility, name, username, error } = validate(row);
      if (error) {
        change(statuses, row, { [field.sync]: `待更正：${error}` });
        continue;
      }

      let id = value(row, field.githubId);
      let login = value(row, field.githubLogin);
      if (!username) {
        id = '';
        login = '';
      } else if (login.toLowerCase() !== username.toLowerCase()) {
        const key = username.toLowerCase();
        if (!accounts.has(key)) {
          // Leave room for record pagination and writes within the Workers Free subrequest limit.
          if (accounts.size >= 15) {
            change(statuses, row, { [field.sync]: '等待 GitHub 核验' });
            continue;
          }
          accounts.set(key, await github.account(username));
        }
        const account = accounts.get(key);
        id = account?.id ?? '';
        login = account?.login ?? username;
      }

      if (username && !/^[1-9]\d*$/.test(id)) {
        change(bindings, row, { [field.githubId]: null, [field.githubLogin]: login });
        change(statuses, row, { [field.sync]: '待更正：未找到 GitHub 个人账号' });
        continue;
      }

      change(bindings, row, {
        [field.registeredOrder]: order,
        [field.githubId]: id || null,
        [field.githubLogin]: login || null,
      });
      entries.push(visibility === '匿名' ? null : { name, login });
      ready.push(row);
    }

    await save(feishu, bindings);
    const next = renderSupporters(entries);
    if (next !== current.content) await github.publish(current.sha, next);
    for (const row of ready) change(statuses, row, { [field.sync]: '已同步' });
  } catch (error) {
    try {
      rows ??= await feishu.list();
      for (const row of rows) {
        if (!statuses.has(row.record_id)) {
          change(statuses, row, { [field.sync]: '待重试：名单同步失败，请查看 Worker 日志' });
        }
      }
      await save(feishu, statuses);
    } catch {
      console.error('飞书同步结果未能写入');
    }
    throw error;
  }
  await save(feishu, statuses);
}

export default {
  async scheduled(event, env) {
    const checkAfdian = event.cron === afdianCheckCron;
    if (checkAfdian && env.FEISHU_AFDIAN_ORDER_CHECK_ENABLED !== 'true') return;
    try {
      const feishu = await connectFeishu(env);
      if (checkAfdian) {
        const project = orderKey(env.AFDIAN_PROJECT_NAME?.trim() || 'WhiskyMac');
        await verifyAfdianClaims(feishu, () => connectAfdian(env), project);
      } else {
        await synchronize(feishu, () => connectGitHub(env));
      }
    } catch (error) {
      if (error instanceof Error && /^[\p{Script=Han}A-Za-z]/u.test(error.message)) {
        console.error(error.message);
      }
      // Mark the scheduled invocation as failed without including provider payloads in logs.
      throw new Error(checkAfdian ? 'WhiskyMac Afdian order check failed' : 'WhiskyMac supporter sync failed');
    }
  },
};
