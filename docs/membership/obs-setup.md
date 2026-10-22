# 会员云文件：OBS 配置与验收

状态：已实现本地代码；桶 `qingye-4fed` 的私有权限、多版本关闭、临时前缀生命周期及专用 IAM 用户组授权已通过用户控制台截图确认。用户已将 OBS 参数保存到服务器 `/etc/legado-account.env`，尚未验证真实 OBS 或部署数据库迁移。所有销售开关默认关闭。以下命令供部署时使用，尚未执行代码切换、数据库迁移或服务重启。

## 已提供的桶信息

用户提供的地址为 `qingye-4fed.obs.cn-south-1.myhuaweicloud-custom.com`，其格式属于自定义域名绑定时的 CNAME 目标。当前 SDK 使用地域 Endpoint 并自动拼接桶名，配置如下（未写入实际运行环境）：

```dotenv
HUAWEICLOUD_OBS_BUCKET=qingye-4fed
HUAWEICLOUD_OBS_REGION=cn-south-1
HUAWEICLOUD_OBS_ENDPOINT=https://obs.cn-south-1.myhuaweicloud.com
```

`cn-south-1` 为华南-广州。专用 IAM 用户为 `qingye-obs-service`，已加入 `qingye-obs-service-group`，该组在全局服务范围绑定 `QingyeObsFileAccess`。用户已确认保存专用 AK/SK，但尚未做连接验证。密钥不要放入本文、Git、App 或聊天。默认桶访问域名为 `qingye-4fed.obs.cn-south-1.myhuaweicloud.com`；不要将包含桶名的完整地址填入当前 SDK 的 Endpoint。

依据：[OBS 访问规则及地域 Endpoint](https://support.huaweicloud.com/usermanual-obs/obs_41_0003.html)、[自定义域名与 CNAME 目标](https://support.huaweicloud.com/usermanual-obs/obs_03_0032.html)。

## 当前方案

会员中心 →「我的云文件」。超级会员可以选择系统文件，或直接选择 App 内已有的本地书籍、字体和书源。手动上传后，同账号另一设备可查看、下载并导入。暂停后从已验证分块继续；退出页面暂停传输。后台自动镜像、文件版本合并和自动删除传播不在这版中。

- **上传和下载都由 App 直连私有 OBS**；API 只处理账号鉴权、空间预留、短时签名、清单和计量。AK/SK 只保存在服务端；App 不安装 OBS SDK，也不把账号 Bearer 令牌发给 OBS。
- 每块 1 MiB，使用 HTTPS PUT/GET 原始二进制，没有 Base64 文件编码和 API 带宽中转。这是应用层分块，不是 OBS multipart。
- 上传签名有效期 120 秒，限定单个临时对象、PUT 方法、Content-Type 和 Content-MD5。App 必须原样发送这两个请求头。不能把普通 PUT 的 Content-Length 当作已签名的大小限制：完成确认还会核对 HEAD 大小及 ETag/MD5。
- App 先写入 `qingye/staging/v1/<账号 UUID>/<文件 UUID>/<块序号>`；服务端 HEAD 验证后用条件 CopyObject 复制到 `qingye/v1/...`。复制发生在 OBS 内部，文件内容不经过 API。仅服务端能写正式对象，旧 PUT 链接重放不会覆盖正式文件；上传确认重试也不会再次复制已完成块。
- MD5 用于 OBS 上传内容校验；SHA-256 由 App 计算并在下载后验证，服务端只验证声明的清单一致性，不通过下载文件来重算 SHA-256。当前确认逻辑要求普通单次 PUT 的 ETag 为内容 MD5；启用会改变 ETag 语义的加密或网关前必须另行适配和验收，不能直接跳过校验。
- 同账号相同内容、相同类型的已完成文件在上传预检时复用；保留原云端文件名。不会跨账号查询或复用。
- 上传前事务预留整个文件空间，失败保留任务以便续传；24 小时未更新的任务进入清理。书籍、字体、书源对象与普通自动同步中的书源数据共享 1 GiB，普通书架元数据不计入。临时对象和复制产生的短暂双份存储是运营开销，不是用户可额外使用的空间。
- 下载签名有效期最多 60 秒，且不超过本自然月末，每签发一块授权，事务预扣该块字节数。每个北京时间自然月 1 GiB，每月1日零点重置，不结转；达到额度停止签发新授权，不自动扣点。同一账号、同一 requestId 在有效期内复用授权，不重复计量、也不延长到期时间；新 ID 或过期后重新申请会再次计量。App 同次传输中的自动重试保留原 ID；手动重新开始或重启 App 后会生成新 ID，未完整保存的块可能再次计量。
- **这是下载授权额度，不是 OBS 实际出网流量的硬上限。** 链接在到期前可重复使用，暂停会员也不能立即撤销已签出的链接；实际流量可能高于授权计量。签名生成失败会事务回滚；已签发后不能仅凭客户端“失败”报告退额，避免拿到可用链接后反复退款。即使链接未使用或实际下载失败，已签发的额度也保留。App 同次传输的网络重试复用链接，已完整下载的块不会再次申请授权。
- 必须配置云费用预算、出网告警，并定期核对 OBS 访问日志和账单。本版未实现日志自动对账或自动扣除差额；日志核算有延迟，不能宣称严格限制云账单至每用户 1 GiB。
- API 每账号每分钟 120 次，最多同时 3 个上传确认任务；文件数据不占 API 连接或内存。DB 用户锁协调书源和文件空间，配置 DB 事务超时必须覆盖单次对象元数据请求；HEAD/Copy 与清理请求之间会刷新 DB 空闲计时。
- 删除立即停止签发新下载授权；文件物理清理分批完成。仍有上传授权时，至少等授权到期再加 5 分钟在途宽限才清理，清理成功才释放空间。已完成块的临时对象也在此时回收。必须配置临时前缀 1 天生命周期，兜底处理极迟完成的 PUT 或服务长时间停机产生的临时对象。

## 建桶

1. 按主要用户所在地区选择地域，并尽量与 API 同地域，建立**私有、标准存储桶**。记录地域、桶名和 HTTPS OBS 服务端点。
2. 不要开启匿名读写或公共网站托管。当前版本不使用 CDN、公共 URL、跨域浏览器上传。
3. 使用专用服务端 IAM 身份，权限限定到目标桶的 `qingye/v1/*` 和 `qingye/staging/v1/*` 前缀：`obs:object:PutObject`、`obs:object:GetObject`、`obs:object:DeleteObject`。HEAD 需要 GetObject 权限；同桶 CopyObject 需要源 GetObject 和目标 PutObject 权限。无需为 App 配置长期密钥或 IAM 账号。
4. 正式对象前缀 `qingye/v1/` **不设置按天删除**；临时对象前缀 `qingye/staging/` **必须设置创建 1 天后删除**的生命周期，两条规则不可混用。对象名不包含用户书名。原生 HarmonyOS HTTP 直连不需要浏览器 CORS；将来接入 Web 时再按实际 Origin 和签名头设置。
5. 本实现按无版本桶管理空间。不要直接开启桶多版本或保留锁；旧版本和删除标记会产生应用未计量的费用。若必须启用，先扩展版本删除、计量和恢复逻辑。
6. 配置用量告警及费用预算。应用月流量限额不能代替云账号账单告警。

官方资料：[预签名 URL 直传](https://support.huaweicloud.com/intl/zh-cn/bestpractice-obs/obs_05_1203.html)、[Node.js SDK](https://github.com/huaweicloud/huaweicloud-sdk-nodejs-obs)、[条件复制](https://support.huaweicloud.com/sdk-nodejs-devg-obs/obs_29_0608.html)。代码使用 `esdk-obs-nodejs`，保持 TLS 验证开启、单次超时 10 秒、SDK 自动重试关闭；业务层靠固定任务和分块恢复。

## 服务端环境变量

先在隔离测试环境执行 `server/migrations/016_memberships.sql`、`017_cloud_files.sql`、`018_cloud_direct_transfers.sql`，不要把密钥写进 Git、App 或聊天。

```dotenv
MEMBERSHIP_ENABLED=true
# 单独灰度；启用前告知旧账号，更新 App，验证超额数据保留行为
MEMBERSHIP_SOURCE_LIMITS_ENABLED=false
CLOUD_FILES_ENABLED=true
HUAWEICLOUD_OBS_ENDPOINT=https://obs.<你的地域>.myhuaweicloud.com
HUAWEICLOUD_OBS_REGION=<你的地域>
HUAWEICLOUD_OBS_BUCKET=<你的私有桶>
HUAWEICLOUD_OBS_AK=<服务端环境变量或密钥管理注入>
HUAWEICLOUD_OBS_SK=<服务端环境变量或密钥管理注入>
```

上面的尖括号内容是占位符，不能直接运行。实际端点以该桶所在地域的控制台信息为准。

缺少任一 OBS 配置或功能开关关闭时，`GET /v1/cloud-files/summary` 返回 `configured:false`，页面显示尚未启用，上传下载拒绝。超级会员销售还额外受云配置门槛控制；即使误把商品 DB 开关打开，没有完整云配置也无法创建超级会员报价。配置存在只表示可接入，不证明 AK/SK、桶权限和账单已验证。

反向代理只承载小 JSON 元数据，签名接口请求体上限 4 KiB，无需放开大文件请求体。禁止缓存云文件接口（接口和 OBS 下载响应均设置 no-store），不要记录响应中的完整签名 URL、认证头或文件内容。App 使用私有临时文件保存下载数据，不使用系统 HTTP 缓存。旧版 Base64 分块接口已移除，需配套更新 App 与服务端；旧库执行迁移 018 后，已完成对象路径不变，可以继续读取。

## 接口与恢复

| 接口 | 用途 |
| --- | --- |
| `GET /v1/cloud-files/summary` | 是否启用、空间及本月下载用量 |
| `GET /v1/cloud-files?after=<cursor>` | 按账号分页，每页 100 条 |
| `POST /v1/cloud-files/prepare` | `requestId, kind, name, bytes, manifestHash`；预留空间/复用相同内容 |
| `GET /v1/cloud-files/:id` | 状态、分块清单及校验值 |
| `POST /v1/cloud-files/:id/upload-ticket` | `index, bytes, sha256, md5`；返回 120 秒 PUT URL，md5 为 Base64 编码的 16 字节摘要 |
| `PUT <upload-ticket.url>` | App 原始二进制直传 OBS；携带 Content-Type / Content-MD5 |
| `POST /v1/cloud-files/:id/chunks/:index/confirm` | HEAD 核验并条件复制到正式位置，重复确认幂等 |
| `POST /v1/cloud-files/:id/complete` | 验证所有分块齐全，发布文件 |
| `POST /v1/cloud-files/:id/chunks/:index/download-ticket` | `requestId`；预扣下载额度，返回 60 秒 GET URL 和校验信息 |
| `GET <download-ticket.url>` | App 直连 OBS，下载后校验长度和 SHA-256 |
| `POST /v1/cloud-files/:id/delete` | 停止下载、异步清理；重复删除安全 |

`kind` 为 `BOOK/FONT/SOURCE`。单个文件不能超出总空间 1 GiB；这是总空间边界，不是额外书源套餐限额。未完成任务同时最多 10 个，避免恶意占用。上传请求 ID 绑定账号和文件参数；取消后重新上传使用新的 ID。

客户端暂存目录为 App 私有 `filesDir/cloud_transfers`，任务偏好按账号隔离。上传完成删除暂存副本；下载导入书籍/字体后删除缓存。暂停和失败保留文件以便恢复。切换账号会停止传输。

书源同步有两个入口：

- 原自动同步：非会员 50 个 / 50 KiB，普通会员 500 个 / 512 KiB；独立开关控制灰度。超额项目单独拒绝并保留本机数据，其余项目继续同步。已有超额书源可以下载、删除或缩小。
- 超级会员云文件：不设独立的书源数量、512 KiB 限额，按 1 GiB 总空间管理，支持从 App 单项上传及跨设备下载。当前为手动选择，尚未自动替换原同步协议中的大书源。

现有书源 JSON 导入器有 **25 MiB** 解析保护。超过它的云文件仍可传输和保存到系统文件，但不会强行载入内存解析；要实现超大 JSON 直接导入，应单独改为流式解析。不要将本版宣传为“任意大小书源自动同步并直接导入”。

## 开售及验收顺序

1. 本地 `cd server && npm test`、HarmonyOS `assembleHap`。
2. 隔离 PostgreSQL 上验证同时购买、续费/领取竞争、上传与普通书源同步同时抢最后空间；PGlite 单连接测试不能替代这一步。
3. 真实私有桶验证：1 字节、1 MiB、跨块、接近剩余空间文件；断网、重新进入、重复块、文件被改、同账号去重及跨账号隔离。
4. 验证月额度最后一个块、同 ID 重试只扣一次、签名失败回滚、签发后断网不退款、过期重领再次计量、北京时间自然月跨界、欠款暂停及仍可删除。确认复用 URL 的流量差异不会被误当作硬限额。
5. 验证错误 Content-MD5 被 OBS 拒绝、错误大小不能确认、条件复制拒绝被换掉的源 ETag、旧 PUT 链接重放不改变正式文件；验证删除前等待过期、在途 PUT、临时生命周期、崩溃恢复及空间最终一致。数据库恢复时应同时恢复对应文件清单和对象。
6. 双设备检查 TXT/EPUB 加入书架、字体注册、书源导入的冲突选择；检查深浅主题、字号、长文件名和离线体验。
7. 全部通过后才为已验收商品打开 `membership_products.sales_enabled`。不要用一条全表更新提前开启所有档位。

回退优先关闭销售；已经售出的权益不能因回退直接删除。关闭云开关会暂时停止文件访问，但保留 DB 和桶内容。未完成上传清理在云服务再次启用后恢复。

## 已知验证边界

- 真实桶的基本上传、校验、条件复制、下载和删除请求已验证；错误 MD5 与旧 ETag 拒绝测试通过。无 ListBucket 权限时，不存在检查得到 HEAD 403，独立确认仍未完成。延迟、费用与服务器断电后的对账未验证。生产部署状态见 [验证记录](verification.md)。
- 已完成真机单设备基础验证，以及会员 7 项、云文件 8 项、共享书源配额 6 项隔离 PostgreSQL 并发检查；这不是生产负载压测。双设备网络测试和自动流量对账仍未完成。
- OBS SDK 新增间接依赖的 `fast-xml-parser` 被 npm audit 报告 XMLBuilder 注释/CDATA 注入（中等）；当前适配器只使用 SDK XMLParser，且对象 key 由服务端生成，不调用 XMLBuilder。仓库另外已有依赖告警。正式上线前应复核依赖版本和适用性，不要以降级整个 SDK 或强制升级代替兼容性验证。
