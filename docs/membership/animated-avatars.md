# 动态头像

终身会员（LIFETIME）和终身超级会员（SUPER_LIFETIME）支持 GIF / WebP 动态头像。免费、月度、年度会员继续使用静态头像。权限由账号快照的 `membership.benefits.animatedAvatar` 提供；服务端检查有效期、开始时间和退款欠款，客户端不能通过提交档位绕过校验。

用户仍在「会员与账号 → 编辑资料 → 选择头像」拖动和缩放裁剪。静态图片沿用原有 JPEG 流程；动画上传原文件与裁剪区域，由服务端对所有帧使用相同裁剪区域，输出 256×256 GIF，保留帧间隔与循环次数。编辑预览直接显示裁剪后的动画。

- 原始动画不超过 2 MiB、120 帧，单帧不超过 1024×1024，累计解码像素不超过 32 Mi 像素。
- 处理后的 GIF 不超过 1 MiB；静态头像仍不超过 256 KiB。
- 编码限定 10 秒，并沿用账号敏感操作频率限制。
- 入库前再次检查权益。权益失效或出现退款欠款时，头像读取接口仅返回 JPEG 首帧；数据库中保留动画，权益恢复后可继续显示。
- 账号头像 URL 包含权益状态标记，账号刷新时可切换缓存键；已经加载到屏幕上的动画需要重新加载后才会切换。

## 存储和发布

继续使用现有 `app_users.avatar_data BYTEA`、`avatar_mime TEXT`，无需为本功能迁移数据库。MIME 根据实际输出保存为 `image/jpeg` 或 `image/gif`。

客户端与服务端需要一起更新；建议先发布服务端再更新客户端。部署完整的新服务端构建，包含新增的 `profileRoutes.js` 及更新后的 `imageSecurity.js`、`membershipPolicy.js` 和 `index.js`，不能只替换入口文件。反向代理需要允许 `/v1/me/profile` 至少 3 MiB 请求体；该路由已单独放宽限制以容纳 Base64，其他接口的默认请求上限保持原值。

本功能不会修改生产环境或自动部署。

### 旧服务端导致终身会员被误提示无权限

旧服务端/缓存没有 `animatedAvatar` 字段。客户端现已将终身会员身份和服务可用性分开判断：选择动图、保存动图前主动刷新账号；有效终身会员遇到字段缺失或关闭时，提示“动态头像服务暂未就绪”，不会误报会员档位不足。更新服务端后，在 App 刷新账号即可使用；已安装首版动态头像 App 的用户也可通过刷新取得新字段。

针对已确认部署的 `server-deploy-20261022` 版本，独立补丁位于 `output/animated-avatar-server/`，部署入口为 `server/scripts/deploy-animated-avatar.sh`。补丁只包含 index、membershipPolicy、imageSecurity、profileRoutes 四个模块，保留旧版本会员价格策略；不包含工作区内其他未发布的会员活动或云同步改动。部署前校验旧文件哈希，遇到不同版本即停止，不强行覆盖。

## 验证

用户提供的部署终端截图确认：四个文件校验通过，模块导入、会员规则、服务器 GIF 编码与内外网健康检查均通过；`MainPID=631103`、`NRestarts=0`、`active/running`。备份目录为 `/root/qingye-avatar-backup.FTEwtV`。这确认服务端部署成功，不替代下列真机交互验收。

- `cd server && npm test`：动画逐帧裁剪、GIF/WebP 时序及循环保留、大小和像素限制；HTTP 权限矩阵、伪造档位、入库前失权、GIF 返回类型、静态首帧回退、静态上传、改名和删除兼容。
- `node scripts/animated-avatar-check.mjs`：客户端保留原始动画字节、短读补齐、裁剪参数、提交、权益和资源清理。
- `assembleHap`：完整 ArkTS 编译与 HAP 打包。
- 真机待验：相册选择、圆形裁剪、编辑预览、「我的」和「会员与账号」中的动画播放，以及退款欠款后的重新加载回退。

动画处理使用 Sharp 的[多帧读取](https://sharp.pixelplumbing.com/api-constructor/)和[裁剪](https://sharp.pixelplumbing.com/api-resize/)能力，并通过解码输出帧验证实际结果。
