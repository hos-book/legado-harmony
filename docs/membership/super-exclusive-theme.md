# 永久超级会员专属主题：曜金藏书

主题 ID：`obsidian-archive`。沿用永久超级会员的曜黑、香槟金与无限书页意象。浅色模式以暖象牙为正文底色，深色模式以曜黑为底；金色集中在导航、描边、强调和操作区域。

## 视觉资源

- 即梦 CLI 生成启动封面、藏书分组图和桌面图标；书封第二版重绘为 6 幅：流金书页、山河长卷、月下航帆、银杏书签、星海鲸游、远山飞鸟。原两幅封面已替换，去掉拱门与碑形构图。
- 原画以默认 5.0 模型、2K 分辨率生成；生成成功后只做居中裁切、尺寸适配与压缩。
- 配套 SVG 为代码绘制：导航第二版使用开卷书架、折页罗盘、寻书镜和读者藏书印；「曜金藏签」强调气泡采用折角书签端饰、非对称圆角与墨底香槟字。保留 `gilded-orbit` 样式 ID，兼容已保存规则与专属主题权限。
- 文件夹第二版采用即梦重绘的横叠藏书、织带书签和银杏叶，生成记录见 [文件夹重绘记录](../obsidian-theme-folder-refresh.json)。通过 `scripts/prepare-obsidian-folder-refresh.mjs` 处理为 450×660 的生产素材。
- 阅读背景第二版改为暖象牙纸 `#F5EFE3` 与暖墨纸 `#1C1C1B`，搭配银杏扉页角饰及山河书页页脚。角饰为透明 SVG，沿用按页面短边缩放的布局，正文中央保持纯色；无整页图片拉伸、噪点纹理或动画。
- 主题标志、透明书框及朗读面板沿用第一版。
- 生成任务、提示词及文件 SHA-256 见 [首版历史记录](../obsidian-theme-generation.json) 和 [第二版书封记录](../obsidian-theme-cover-refresh.json)。第二版记录取代首版中的两幅书封记录；记录不包含认证令牌或签名下载链接。
- `scripts/prepare-obsidian-theme.mjs` 从本地原画清单生成生产位图；`scripts/generate-obsidian-theme-vectors.mjs` 生成配套矢量资源。
- 第二版封面处理：`scripts/prepare-obsidian-cover-refresh.mjs`；预览：`scripts/preview-obsidian-refresh.mjs`，产物 `output/obsidian-archive-v2/theme-refresh-preview.png`。该图由真实主题素材与配色合成，是设计示意，不是真机截图。
- 文件夹与阅读页预览：`scripts/preview-obsidian-reader-refresh.mjs`，产物 `output/obsidian-archive-v2/folder-reader-preview.png`；使用实际阅读配色、角饰和原有等比布局参数合成。
- 本次视觉更新只涉及客户端，无需数据库迁移或重新领取主题。

## 领取与使用规则

1. 仅有效的 `SUPER_LIFETIME` 账号可手动领取。不自动赠送，不进入普通会员主题库，不提供试用，不能通过点数兑换。
2. 每次领取从服务端当前时间起有效一个北京时间日历年。2 月 29 日的周年日期截到次年 2 月末。
3. 有效期内显示已领取，重复点击、不同请求 ID、网络重试均不延长有效期。到期后以新的手动请求领取下一年。
4. 已完成请求的迟到重放返回原来的到期时间，不因过期自动产生续领。
5. 主题权限同时要求永久超级会员身份和未到期的领取记录。退款欠款暂停、退出账号或授权到期后，前台权限检查撤回专属整套主题、自定义方案内引用的专属部件和专属桌面图标；保留自定义方案内容供再次领取后使用。
6. 会员中心新增「专属主题」权益行，从「领取会员权益」进入领取页查看专属主题卡片；主题页也提供领取、有效期与应用入口。领取与应用是两个独立动作。

客户端使用已有账户快照支持离线校验；恢复前台时沿用会员状态刷新策略。年限判断使用最近服务端时间加本地已流逝时长，并拒绝时钟倒退到校验时刻之前的授权。

## 服务端

新增迁移：`server/migrations/023_super_exclusive_theme.sql`。

- `theme_catalog.acquisition` 区分 `POINTS` 与 `SUPER_CLAIM`。
- 专属主题目录项为 `price_points=0`、`member_included=false`。零价格是领取目录元数据，不是免费点数商品；点数兑换服务按 ID 与获取方式双重拒绝。
- `membership_theme_claims` 保存用户、主题、请求 ID、领取时刻和原始到期时刻；用户与请求 ID 唯一。
- 新接口：`POST /v1/membership/themes/obsidian-archive/claim`，认证方式与其他会员接口相同；请求体为 `{ "requestId": "客户端生成且持久化的唯一 ID" }`。
- 响应：`{ claim: { themeId, expiresAt, duplicate }, account }`。
- 权限由服务端账户身份决定，忽略客户端伪造的用户或会员档位。领取、到期续领和快照读取在同一事务内完成；使用会员账户事务锁串行化，并沿用会员接口限流。
- 不创建点数流水，不更改点数余额。

## 上线顺序与验证

2026-10-22：用户在生产服务器执行 v3 更新包完成部署。截图确认 023 迁移提交、原目录归属及权限保留、内外网健康检查与领取接口鉴权通过，服务正常运行；部署脚本未代用户领取主题。用户随后确认功能正常。

1. 确认服务器此前迁移已执行至 022，备份数据库和当前应用代码。
2. 暂停服务更新窗口；线上 theme_catalog 属于 postgres 时，以 postgres 管理员执行 023 和新领取记录表 SELECT、INSERT 授权，保留目录表归属及 ACL；新代码查询依赖 `acquisition` 字段，因此必须先完成数据库迁移再切换服务端代码。
3. 构建并部署对应版本服务端，包括新编译产物 `superThemeService.js` 及修改后的 `themeCatalog.js`、`membershipRoutes.js`、`index.js`。不要只替换新模块。
4. 重启并检查健康接口和主题目录，确认 `obsidian-archive` 为 `SUPER_CLAIM`、0 点且不包含在普通会员主题库。
5. 发布新版客户端后，用永久超级会员验收手动领取、重复领取有效期不变、应用主题和会员中心入口；用免费及普通会员验证拒绝领取和点数兑换。

本地验证命令：

```powershell
npm test --prefix server
node scripts/membership-theme-check.mjs
node scripts/app-icon-check.mjs
node scripts/theme-framework-check.mjs
node scripts/obsidian-reader-bubbles-check.mjs
```

2026-10-22 阅读气泡修正：`ThemeRuntime` 的气泡样式白名单补齐 `gilded-orbit`，修复应用主题时被替换为普通气泡的问题；同时将主题继承的强调文字颜色改为香槟色，避免覆盖墨底气泡预设。段评和「本章说」统一使用原生绘制的折角藏书签、细金边与小书签尾，浅色为墨底金字，深色为香槟底墨字。书源显式设置的段评颜色和圆角仍优先。

新增验证从主题应用开始，经过实际阅读页上下文和原生文字样式转换，覆盖浅深色、书签资源、段评与本章说绘制、书源覆盖和授权回退。`scripts/preview-obsidian-bubbles.mjs` 使用同一运行时与实际绘制路径生成评审图；评审图的文字由 SVG 排版，不代替设备截图。

服务端自动化覆盖普通会员拒绝、周年与闰日、过期续领、旧请求重放、欠款暂停、目录下架、点数不变、迁移重跑及 HTTP 认证绑定。客户端脚本覆盖授权、到期/退出后的整套与自定义部件撤回、图标权限和有效授权保留。鸿蒙 HAP 编译验证语法和资源；真机冷启动、折叠屏、字体与翻页效果仍需设备验收。
