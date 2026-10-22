# 同步限额提示修复与部署记录

## 修复

旧客户端使用同一同步接口。服务端原先先按 960 KiB 统一检查书源大小，再判断会员资格，导致非超级会员上传超过 960 KiB 的书源时，也收到 960KB 提示。

现在先解析并验证请求结构，再在同步事务中确定账号额度，随后校验书源大小。非超级会员保持 512 KiB，生效中的永久超级会员为 960 KiB，其他同步实体保持 64 KiB；不修改会员分档配额和整批超限拒绝行为。

## 验证

- 服务端 TypeScript 构建通过。
- `node --test dist/sync.test.js scripts/source-quota.test.mjs`：12 项测试通过，事务测试含 8 个场景。
- 覆盖旧客户端协议、各会员档位、512/960 KiB 边界、关闭会员系统、整批拒绝与非书源数据校验。
- 更新包补丁已与此前交付的 `qingye-server-20261022.zip` 中的 `sync.js` 验证兼容，结果与编译产物一致。
- 已检查重复应用、不兼容版本拒绝、保留无关代码、脚本语法及包内校验和；回归校验可识别修复前的错误行为。

## 更新包

包名：`qingye-sync-limit-fix-20261022.zip`。

SHA256：`d2c6038c666c3203bae0e918bed42c7a1b6da2e6a1fbf5de2b5f6f3cf4d56f7c`。

源码与部署说明位于 `server/scripts/sync-limit-update/`。仅修改运行目录中的 `sync.js`，包含备份、候选校验、健康检查及回滚，不修改数据库或配置。

## 用户回传的部署结果

根据用户提供的终端截图，更新包校验、候选额度校验及部署健康检查均通过，输出 `PASS: sync limit message fixed`。

- 备份目录：`/root/qingye-sync-limit-backup.EH7P1A`
- 服务状态：`ActiveState=active`、`SubState=running`
- `MainPID=684207`、`NRestarts=0`

此记录依据用户回传日志；尚无修复后旧客户端实际同步截图。
