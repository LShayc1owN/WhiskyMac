# WhiskyMac 赞助运营

`worker.mjs` 由 Cloudflare 每 15 分钟运行，从飞书发布 GitHub 赞助者名单。运行 `node --test supporters/*.test.mjs` 验证同步逻辑。

## 飞书

创建私有多维表格 `WhiskyMac 赞助申请`。字段名称和选项需与 Worker 一致。

| 字段 | 类型 | 表单设置 |
| --- | --- | --- |
| Patreon 订单号 | 文本 | 必填。填写 Patreon 收据上的编号 |
| 核对码 | 文本 | 必填。自定 8 位字母或数字，在 Patreon 私信中使用同一个码 |
| 公开方式 | 单选，`公开` 或 `匿名` | 必填。匿名仅计入 GitHub 名单人数 |
| 展示昵称 | 文本 | `公开` 时显示并必填，限单行 80 字符 |
| 匿名备注昵称 | 文本 | `匿名` 时显示，选填，仅供核对 |
| GitHub 用户名 | 文本 | 选填。题目说明 `github.com/`，只填写用户名 |
| 审核状态 | 单选，`待审核`、`待补充`、`已通过`、`未通过`、`已撤销` | 仅后台 |
| 已登记订单号 | 文本 | 仅后台，Worker 写入 |
| GitHub 数字 ID | 文本 | 仅后台，Worker 写入 |
| 已检查登录名 | 文本 | 仅后台，Worker 写入 |
| 同步结果 | 文本 | 仅后台，Worker 写入 |

表单标题用 `WhiskyMac 赞助登记 · Supporter registration`。顶部说明可直接使用以下内容。

> 请填写 Patreon 收据上的订单号和一个自定的 8 位核对码。提交后，请从购买账号发 Patreon 私信，带上相同的订单号和核对码。订单信息仅用于审核。选择公开时，你的昵称及选填的 GitHub 主页会出现在赞助者名单中，且可能保留在 GitHub 提交历史里。选择匿名时，公开名单只增加匿名赞助者人数。
>
> Enter the order ID on your Patreon receipt and an 8-character code you choose. After submitting, message the creator from your purchasing Patreon account with the same order ID and code. We use your order details to verify the request. If you choose public recognition, your display name and optional GitHub profile appear on the supporter list and may remain in GitHub history. If you choose anonymous recognition, we only increase the anonymous supporter count.

只对外分享表单视图，选择「互联网上获得链接的人可填写」。用无痕窗口验证访客能填写，且表格和审批视图只有维护者能打开。复制表单的分享链接供 Patreon 商品交付使用。

建一个「待审核」视图，筛选审核状态为空或为 `待审核` 的记录。建一个「同步问题」视图，筛选同步结果以 `待更正` 或 `待重试` 开头的记录。创建定时工作流，每天北京时间 20:00 查找待审核视图对应的记录。数量大于 0 时，由多维表格助手单聊维护者一条消息，插入查找到的记录条数，并添加指向私有待审视图的「打开待审核」按钮。可先临时设一个近时的触发点查看推送，验收后设回 20:00。

审核时，在 Patreon `Audience → Sales` 核对订单、商品和已完成的支付状态，再核对私信来自该购买账号，且订单号、核对码均与表单一致。确认后把原记录改为 `已通过`。待补充材料用 `待补充`，拒绝用 `未通过`，退款或撤回用 `已撤销`。若买家通过购买账号提交更正，在核对后修改原记录。GitHub 账号从未找到变为可用且用户名没变时，清空 `已检查登录名` 以便下轮重新核验。

## GitHub 和 Cloudflare

1. 创建公开的 `LShayc1owN/WhiskyMac-supporters` 仓库，用 `main` 和一个初始 `README.md` 初始化。Worker 负责此 README 的内容。先让名单实际显示，再合入主仓库的 README 链接。
2. 创建只安装给本人使用的 GitHub App，仓库权限只设 `Contents: Read and write`，关闭 webhook，安装范围只选择名单仓库。记录 Client ID 和安装 ID。生成私钥并转换成 `BEGIN PRIVATE KEY` 格式的 PKCS#8 PEM。私钥通过 Cloudflare Worker Secret 保存。

   ```sh
   openssl pkcs8 -topk8 -nocrypt -in downloaded-app-key.pem -out worker-app-key.pem
   ```

3. 在飞书开放平台创建企业自建应用，开通多维表格查询和记录编辑所需权限，发布应用后把它加入该多维表格，授权到这一份表。获取应用 ID、应用 Secret、Base token 和赞助申请数据表 ID。
4. 用 Wrangler 部署 `supporters/wrangler.jsonc` 指定的 Worker。在 `supporters/` 中登录 Wrangler 并运行 `npx wrangler deploy`。在 Worker 的 Variables and Secrets 中配置以下项目。两项密钥的类型设为 Secret。

   | 项目 | 值 |
   | --- | --- |
   | `FEISHU_APP_ID` | 飞书自建应用 ID |
   | `FEISHU_APP_SECRET` | 飞书自建应用 Secret |
   | `FEISHU_BASE_TOKEN` | 私有多维表格 Base token |
   | `FEISHU_TABLE_ID` | 赞助申请数据表 ID |
   | `GITHUB_APP_CLIENT_ID` | GitHub App Client ID |
   | `GITHUB_INSTALLATION_ID` | GitHub App 安装 ID |
   | `GITHUB_APP_PRIVATE_KEY` | PKCS#8 PEM 全文 |

   后续用 `npx wrangler deploy --keep-vars` 保留后台设置的变量。同步按完整的获批记录重新生成名单，重复订单保留已登记且未撤销的原记录。若未经登记的订单重复获批，两条都留待人工处理。外部服务出错时，下次 Cron 会重试。飞书连接故障可从 Cloudflare Logs 查到，恢复后再写入飞书同步结果。

## Patreon 商品草稿

商品名 `Support WhiskyMac · 支持 WhiskyMac`，一次性 `US$3`。公开说明可用以下文案。

> Support the independent development of WhiskyMac with a one-time purchase. You’ll receive a thank-you note and an optional link to register for the supporter list.
>
> 一次性支持 WhiskyMac 的独立开发。购买后，你会收到感谢说明，也可以自愿申请加入赞助者名单。

将以下正文放在购买后可见区。将 `{{FEISHU_FORM_URL}}` 换成已经过访客测试的固定表单分享地址。

> Thank you for supporting WhiskyMac!
>
> 1. Find your order ID on the receipt under Purchases. Choose an 8-character code using letters or numbers.
> 2. Submit the [supporter registration form]({{FEISHU_FORM_URL}}) with the order ID and your code.
> 3. Open this purchase in Patreon, choose **Message creator**, and send the same order ID and code from your purchasing account. We’ll review your request before updating the supporter list.
>
> 感谢你支持 WhiskyMac！
>
> 1. 在 Patreon「购买记录」的收据中找到订单号，自定一个 8 位字母或数字核对码。
> 2. 用订单号和核对码提交[赞助登记表]({{FEISHU_FORM_URL}})。
> 3. 从购买账号打开这件商品，选择「给创作者发消息」，发送相同的订单号和核对码。审核通过后会更新赞助者名单。

先用独立测试表和测试分支验证访客提交、机器人私聊、公开昵称、匿名人数、重复订单、撤销和更新失败后的重试。然后确认正式商品发布与测试付款，用一笔真实 US$3 订单验证大陆无代理网络下的结账、购买后打开表单、Patreon 私信和名单更新。
