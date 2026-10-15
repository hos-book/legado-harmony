# @legado/sourceengine

开源轻页的书源解析内核，以 HAR 形式供应用模块依赖。它包含：

- 兼容书源（阅读格式）的规则解析：`AnalyzeUrl`、`AnalyzeRule`、`JsonPathEvaluator`、`JavaRegexCompat` 与 JS 兼容层。
- 请求层：`HttpClient`、`CookieStore`、`TlsTrustStore`、`HttpAuth`、限流与网页验证支持。
- 原生书源：`NativeSourceSpec`、`NativeExpr`、`NativeSourceRunner`、`NativeSourceService`。
- 脚本运行时：QuickJS 运行、迁移与诊断，以及需要 ArkWeb 的阶段脚本运行时 `BookSourceStageWebRuntime` 和网页抓取 `WebBookFetchRuntime`。
- 数据模型：`model/data/Book.ts` 里的 `Book`、`BookChapter`、`BookSource` 等。

搜索、发现以及详情/目录/正文的调度（`SearchCoordinator`、`ExploreCoordinator`、`WebBookService`）仍在 `entry` 模块里。

## 引入

```json5
// 应用模块的 oh-package.json5
"dependencies": {
  "@legado/sourceengine": "file:../sourceengine"
}
```

`build-profile.json5` 的 `modules` 里还要注册 `sourceengine`。

`Index.ts` 是主入口，只导出 `.ts` 文件，`.ts` 和 `.ets` 都可以从这里导入。`QuickJsDiagnostics` 和 `QuickJsShadowExecutor` 用到了 `@Concurrent`，必须是 `.ets` 文件，所以单独从子入口导入：

```ts
import { QuickJsDiagnostics } from '@legado/sourceengine/Diagnostics';
```

新增公开类型时，把它追加到 `Index.ts`（或 `Diagnostics.ets`）对应的文件分组里。

## 宿主应用需要接入的部分

内核不访问应用数据库，也不包含界面。下面这些由宿主提供：

| 接入点 | 做法 |
| --- | --- |
| 书源运行时状态持久化 | 实现 `BookSourceRuntimePersistence`（读取书源、写回 `variable` / `loginHeader` / `loginInfo`），在启动时调用 `BookSourceRuntimeStore.install(...)`。不安装时读到 `null`，写入被跳过。 |
| ArkWeb 宿主 | `BookSourceStageWebRuntime.get().attach(controller)`、`WebBookFetchRuntime` 需要页面里挂一个 `Web` 组件提供控制器；参考 `entry/src/main/ets/components/BookSourceStageRuntimeHost.ets`、`WebBookFetchRuntimeHost.ets`。 |
| Context | `TlsTrustStore.load(context)`、`QuickJsDiagnostics.initialize(context)` 等 Preferences 存储需要传入应用上下文。 |
| 网页验证 | 遇到验证页时 `VerificationSupport` 写入 AppStorage：`pendingVerificationUrl`、`pendingVerificationTitle`、`pendingVerificationTime`、`pendingVerificationSourceUrl`、`pendingVerificationLoginUrl`。宿主的验证页读取这些值。 |
| QuickJS 诊断刷新 | 存储变化时更新 AppStorage 的 `quickJsMigrationRevision`、`quickJsValidationRevision`、`quickJsRegressionArtifactRevision`，界面可以监听这些值来刷新。 |

## 可选宿主端口

`SourceEngineHost.install(adapter)` 在启动时、执行书源前调用一次。所有端口均可省略；轻页保持原有 ArkWeb 串行执行、CookieStore 和 `BookSourceRuntimeStore.install` 行为。不要在任务执行期间切换 adapter。

- `cookies(sourceUrl)` / `persistence(source)`：提供按源隔离的会话与状态存储。
- `scripts`：注入有预算限制的脚本执行器。只有独立上下文才能声明 `concurrent: true`；共享 ArkWeb 控制器必须串行。可强制完整脚本路由，并禁止同步 QuickJS 入口。
- `requests`：宿主选择等待者优先级和取消状态；频率窗口仍由公共包维护，不因优先级而额外发放额度。
- `web`：宿主管理网页会话租约；`state` 绑定源副本的上下文和错误；`diagnostics` 接收分段耗时。

这些端口只给可信宿主使用，不暴露给书源脚本。简听保留加密存储、有界 QuickJS、播放优先级、Cookie 隔离和网页会话租约，公共包不依赖简听模块。

`NativeSourceImport.importObject` / `toBookSource` 仅转换定义，不清理缓存、不访问网络或数据库；实际导入仍可使用 `NativeSourceService.importObject`，保留原来的缓存失效行为。原生声明式缓存按定义、登录信息和登录站点 Cookie 区分上下文。

## 宿主兼容性回归

设置 `DEVECO_HOME` 为已安装的 Release DevEco Studio，执行 `node scripts/source-engine-host-check.cjs`，覆盖默认串行与注入并发执行、Cookie、持久化及取消。平台 API 使用测试替身，不能替代设备验证。

## 回归检查

`scripts/` 里的 Node 回归脚本通过 `scripts/lib/ets-module-staging.mjs` 加载本模块的源码。这个工具把 `entry` 和 `sourceengine` 两个源码根合并成同一棵目录树，并把 `@legado/sourceengine` 的导入按名字改写成指向定义文件的相对导入。改动内核后至少运行：

```bash
node --experimental-strip-types scripts/native-source-check.mjs
node scripts/neutral-source-engine-check.mjs
```
