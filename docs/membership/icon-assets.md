# C 套星轨羽翼资产

最终选择为 C，覆盖此前误选 A。四档均为即梦 CLI 生成的原设计，再使用内置 imagegen 做透明背景提取；保留原书页、珠光盾牌和金属主体。

正式 256×256 RGBA 资源：

- `entry/src/main/resources/base/media/membership_monthly.png`
- `entry/src/main/resources/base/media/membership_annual.png`
- `entry/src/main/resources/base/media/membership_lifetime.png`
- `entry/src/main/resources/base/media/membership_super_lifetime.png`

接入 `MembershipIcons.ets`、会员中心四档商品卡和账号中心徽章。三个候选方案及 12 个即梦任务记录在本地 `output/membership-icons/`，该目录是忽略的工作产物；正式资源已保存在应用目录。

透明提取提示词（四枚各自输入对应原图）：

> Use case: background-extraction. Edit target: the supplied approved membership icon. Remove only the exterior white backdrop and ground shadow to actual alpha transparency. Preserve the entire emblem pixel appearance, original design, color, materials, shape and front angle: particularly opaque white book pages, pearl shield, silver and gold surfaces are part of the subject and MUST NOT be erased. Exterior gaps around orbit rings should be transparent. One centered isolated icon, no text, no additions, square canvas. This is a clean production cutout, not a redesign.

`scripts/prepare-membership-icons.mjs` 只缩放批准的透明输出，不再用白色阈值抠除主体。输入为 `output/membership-icons/approved/{monthly,annual,lifetime,super_lifetime}.png`。
