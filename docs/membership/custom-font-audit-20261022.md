# 自定义字体检查（2026-10-22）

## 本轮发现并修复

1. 云空间手动上传 FONT 后只清除传输暂存文件，没有加入本机字体库。现在完成上传后从暂存文件导入，已有相同文件指纹的本机字体复用原路径，避免重复导入；不自动切换用户正在使用的字体。导入失败保留上传任务供重试。
2. FontSettings 首次选择或从 A 切换到 B 时，注册函数只在字体已经是当前选择时才更新生效状态。现在选择成功后明确更新 active family 与 registered 状态，避免应用继续沿用旧字体。
3. FontSettings 和 Settings 在注册前写入 custom 模式，注册失败仍改变模式。现在成功后才改变模式。
4. CustomFontManager 注册失败返回系统字体名称，调用处把非空字符串当作成功。现在失败返回空字符串。
5. ReaderFontSettings 的正文、标题和规则字体选择在注册失败时仍保存原 family。现在提示失败并阻止保存；列表过滤已不存在的字体文件。

## 已检查的现有流程

- 本机导入支持 TTF、OTF、TTC；文件进入应用字体目录，以稳定路径生成字体 family。
- 云端下载会保存原始名称、登记本机字体记录；历史内部文件名可通过字体 name 表恢复。下载不会直接覆盖用户的当前选择。
- 本机字体可在普通账户使用；自动文件同步要求有效终身超级会员，并遵守自定义字体同步开关。
- 自动同步通过文件指纹匹配本机与云端副本；删除字体产生 REMOVED 标记，其他设备据此移除；仅删除云端副本的 DETACHED 标记保留本机文件。
- 全局字体选择保持为设备本地设置，字体规则的同步走独立保存路径。

## 验证及范围

命令：`node --test scripts/custom-font-lifecycle-check.mjs scripts/cloud-auto-sync-check.mjs scripts/cloud-font-import-check.mjs scripts/reader-font-weight-check.mjs scripts/cloud-transfer-check.mjs`。

28 项测试通过；编译后的云空间 UI 更新检查通过；签名 HAP 构建通过。测试执行实际业务方法，文件系统、账户、网络与字体注册接口使用替身，未验证每一种字体在实际设备上的 ArkUI/graphics.text 渲染效果。

本轮仅修改客户端，无需新的服务端或数据库变更。
