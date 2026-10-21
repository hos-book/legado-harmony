import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { MembershipCommerceService } from '../account/MembershipCommerceService';
import { MembershipProduct, MembershipSnapshot, MembershipOrder } from '../account/MembershipModels';
import { CloudSyncSummary } from '../account/CloudSyncModels';
import { HdsFeedback } from '../utils/HdsFeedback';
import { syncSystemBars } from '../utils/SystemBars';
import { MembershipIcons } from '../account/MembershipIcons';

@Entry
@Component
struct MembershipCenterPage {
  @StorageLink('appDarkMode') dark: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('accountPaidPoints') paidPoints: number = 0;
  @StorageLink('accountPromoPoints') promoPoints: number = 0;
  @StorageLink('accountLoggedIn') loggedIn: boolean = false;
  @State products: MembershipProduct[] = [];
  @State membership: MembershipSnapshot = new MembershipSnapshot();
  @State selectedSku: string = 'ANNUAL';
  @State busy: boolean = false;
  @State agreed: boolean = false;
  @State errorText: string = '';
  @State orders: MembershipOrder[] = [];
  @State sourceUsage: CloudSyncSummary = new CloudSyncSummary();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    syncSystemBars(this.context, this.dark, ThemeRuntime.pageColor(this.dark));
    this.refresh();
  }

  onPageShow(): void { this.refresh(); }

  build() {
    Column() {
      PageScaffold({ title: '会员中心', content: () => { this.content() } })
        .layoutWeight(1)
      Column({ space: 8 }) {
        Button(this.purchaseLabel())
          .width('100%').height(48)
          .backgroundColor(ThemeRuntime.accentColor(this.dark))
          .fontColor(Color.White)
          .enabled(!this.busy && this.agreed && this.selectedProduct()?.salesEnabled === true)
          .onClick(() => { this.buy() })
        Text('仅使用充值点 · 不自动续费')
          .fontSize(12).fontColor(ThemeRuntime.subTextColor(this.dark))
      }.padding({ left: 20, right: 20, top: 12, bottom: 16 })
        .backgroundColor(ThemeRuntime.cardColor(this.dark))
    }
    .width('100%').height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.dark))
  }

  @Builder
  content() {
    Column({ space: 18 }) {
      this.identityCard()
      if (this.errorText) {
        Text(this.errorText).fontSize(13).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
      }
      if (this.membership.active) { this.giftCard() }
      Button('我的云文件 · 书籍 / 字体 / 书源').width('100%')
        .onClick(() => { router.pushUrl({ url: 'pages/CloudFiles' }) })
      Row() {
        Text('选择会员').fontSize(20).fontWeight(FontWeight.Bold)
        Blank()
        Text('刷新').fontSize(14).fontColor(ThemeRuntime.accentColor(this.dark))
          .onClick(() => { this.refresh() })
      }.width('100%')
      Grid() {
        ForEach(this.products, (product: MembershipProduct) => {
          GridItem() { this.productCard(product) }
        }, (product: MembershipProduct) => product.sku)
      }.columnsTemplate('1fr 1fr').columnsGap(12).rowsGap(12).height(420)
      this.benefitsCard()
      if (this.loggedIn) {
        Text(`已同步书源 ${this.sourceUsage.sourceCount} 个${this.sourceUsage.membershipLimitsEnabled ?
          ` · 当前限额 ${this.membership.benefits.sourceCount === null ? '按总空间' : this.membership.benefits.sourceCount + ' 个'}` : ''}`)
          .fontSize(13).fontColor(ThemeRuntime.subTextColor(this.dark))
        Button('查看最近会员订单').onClick(() => { this.loadOrders() })
        ForEach(this.orders, (order: MembershipOrder) => {
          Row({ space: 12 }) {
            Image(MembershipIcons.forSku(order.sku)).width(32).height(32)
            Column({ space: 4 }) {
              Text(this.products.find((product: MembershipProduct) => product.sku === order.sku)?.name || '会员订单').fontSize(14)
              Text(`${new Date(Number(order.createdAt)).toLocaleDateString()} · 支付 ${order.pointsSpent} 充值点`).fontSize(12)
            }.alignItems(HorizontalAlign.Start)
          }.width('100%')
        }, (order: MembershipOrder) => order.id)
      }
      Column({ space: 10 }) {
        Text('购买与领取说明').fontSize(17).fontWeight(FontWeight.Medium)
        Text('1. 会员主题包含现有及未来加入会员库的主题，独立付费主题除外；已购主题保留原有效期。\n2. 月礼包按开通日起的权益月领取，每期标准／精品二选一；升级不重复领取。\n3. 已领字数在本次连续会员有效期内有效；续费顺延，永久会员长期有效。到期后重新开通不恢复旧周期赠额。\n4. 升级抵扣按服务端确认报价展示；永久权益无需重复购买。')
          .fontSize(13).lineHeight(21).fontColor(ThemeRuntime.subTextColor(this.dark))
        Row({ space: 8 }) {
          Checkbox({ name: 'membership-agreement' }).select(this.agreed)
            .onChange((checked: boolean) => { this.agreed = checked })
          Text('我已阅读并同意上述会员权益与购买说明').fontSize(13).layoutWeight(1)
        }.width('100%')
      }.alignItems(HorizontalAlign.Start).padding(18).width('100%')
        .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(20)
    }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
      .foregroundColor(ThemeRuntime.primaryTextColor(this.dark))
  }

  @Builder
  identityCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 5 }) {
          Text(this.identityTitle()).fontSize(23).fontWeight(FontWeight.Bold)
          Text(this.validityText()).fontSize(13).fontColor(ThemeRuntime.subTextColor(this.dark))
        }.alignItems(HorizontalAlign.Start)
        Blank()
        Image(MembershipIcons.forSku(this.membership.state?.sku || this.selectedSku))
          .width(64).height(64).objectFit(ImageFit.Contain)
      }.width('100%')
      Divider().opacity(0.2)
      Row() {
        Column({ space: 4 }) {
          Text(`充值点 ${this.paidPoints}`).fontSize(17).fontWeight(FontWeight.Medium)
          Text(`赠送点 ${this.promoPoints} · 不可开通会员`).fontSize(12)
            .fontColor(ThemeRuntime.subTextColor(this.dark))
        }.alignItems(HorizontalAlign.Start)
        Blank()
        Button(this.loggedIn ? '充值' : '登录').fontSize(13)
          .onClick(() => { router.pushUrl({ url: 'pages/AccountCenter' }) })
      }.width('100%')
    }.padding(20).width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(24)
  }

  @Builder
  giftCard() {
    Column({ space: 10 }) {
      Text('本月朗读礼包').fontSize(18).fontWeight(FontWeight.Medium)
      Text(this.membership.claim ?
        `已领取${this.membership.claim.tier === 'STANDARD' ? '标准' : '精品'} ${this.membership.claim.chars} 字` :
        '标准或精品，任选一档').fontSize(13).fontColor(ThemeRuntime.subTextColor(this.dark))
      Row({ space: 10 }) {
        Button(`标准 ${this.membership.benefits.standardGiftChars} 字`).layoutWeight(1).fontSize(13)
          .enabled(!this.busy && !this.membership.claim).onClick(() => { this.claim('STANDARD') })
        Button(`精品 ${this.membership.benefits.premiumGiftChars} 字`).layoutWeight(1).fontSize(13)
          .enabled(!this.busy && !this.membership.claim).onClick(() => { this.claim('PREMIUM') })
      }.width('100%')
      Text('已领额度在本次连续会员有效期内有效').fontSize(12).fontColor(ThemeRuntime.subTextColor(this.dark))
    }.padding(18).width('100%').alignItems(HorizontalAlign.Start)
      .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(20)
  }

  @Builder
  productCard(product: MembershipProduct) {
    Column({ space: 8 }) {
      Image(MembershipIcons.forSku(product.sku)).width(54).height(54).objectFit(ImageFit.Contain)
      Text(product.name).fontSize(17).fontWeight(FontWeight.Medium)
      Row({ space: 4 }) {
        Text(`${product.points}`).fontSize(28).fontWeight(FontWeight.Bold)
        Text('点').fontSize(13)
      }
      Text(product.months === null ? '一次购买，永久有效' : `${product.months} 个月 · 手动续费`)
        .fontSize(12).fontColor(ThemeRuntime.subTextColor(this.dark))
      Text(product.salesEnabled ? (product.sku === 'ANNUAL' ? '适合长期阅读' : '充值点开通') : '准备中')
        .fontSize(12).fontColor(ThemeRuntime.accentColor(this.dark))
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(20)
      .border({ width: product.sku === this.selectedSku ? 2 : 0,
        color: ThemeRuntime.accentColor(this.dark) })
      .onClick(() => { if (!this.busy) this.selectedSku = product.sku; })
  }

  @Builder
  benefitsCard() {
    Column({ space: 13 }) {
      Text('会员权益').fontSize(18).fontWeight(FontWeight.Medium)
      Text('会员主题库\n现有及未来加入会员库的主题免费使用').fontSize(14).lineHeight(22)
      Text(this.sourceUsage.membershipLimitsEnabled ? '书源云同步\n普通会员 500 个 / 单个 512KB' :
        '书源云同步\n继续使用现有书源同步功能').fontSize(14).lineHeight(22)
      Text('在线朗读\n高峰期优先处理，每月标准 2000 字或精品 1000 字').fontSize(14).lineHeight(22)
      Divider().opacity(0.2)
      Text('永久超级会员额外享有').fontSize(15).fontWeight(FontWeight.Medium)
      Text('每月标准 3000 字或精品 1500 字\n书籍、字体与书源共用 1GB 云空间\n每月 1GB 下载授权额度（按签发分块计量）\n书源不设独立套餐数量与单项大小限额，受总空间和技术安全限制')
        .fontSize(13).lineHeight(22).fontColor(ThemeRuntime.subTextColor(this.dark))
    }.padding(18).width('100%').alignItems(HorizontalAlign.Start)
      .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(20)
  }

  selectedProduct(): MembershipProduct | undefined {
    return this.products.find((item: MembershipProduct) => item.sku === this.selectedSku);
  }

  purchaseLabel(): string {
    if (this.busy) return '正在处理…';
    const product = this.selectedProduct();
    if (!product?.salesEnabled) return '暂未开放购买';
    return this.membership.active ? '查看续费 / 升级价格' : `使用 ${product.points} 充值点开通`;
  }

  identityTitle(): string {
    if (this.membership.restricted) return '会员权益暂不可用';
    if (!this.membership.active) return '轻页会员';
    return this.products.find((item: MembershipProduct) => item.sku === this.membership.state?.sku)?.name || '轻页会员';
  }

  validityText(): string {
    if (!this.loggedIn) return '登录后查看会员与点数';
    if (this.membership.restricted) return '请到账号中心处理退款欠款';
    if (!this.membership.active || !this.membership.state) return '让阅读更自在';
    return this.membership.state.expiresAt === null ? '永久有效' :
      `有效至 ${new Date(this.membership.state.expiresAt).toLocaleDateString()}`;
  }

  async refresh(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.errorText = '';
    try {
      this.products = (await AccountCommerceApi.fetchMembershipCatalog(AccountSessionStore.token())).products;
      if (!this.selectedProduct()?.salesEnabled) {
        const available = this.products.find((item: MembershipProduct) => item.salesEnabled);
        if (available) this.selectedSku = available.sku;
      }
      if (AccountSessionStore.isLoggedIn()) {
        await MembershipCommerceService.recover(this.context);
        const account = await AccountCommerceApi.fetchAccount(AccountSessionStore.token());
        await AccountSessionStore.updateSnapshot(this.context, account);
        this.membership = account.membership || new MembershipSnapshot();
        this.sourceUsage = await AccountCommerceApi.fetchSyncSummary(AccountSessionStore.token());
      }
    } catch (error) {
      this.errorText = (error as Error).message || '会员信息暂时无法加载，请稍后刷新';
    } finally { this.busy = false; }
  }

  async buy(): Promise<void> {
    if (this.busy || !this.agreed || !this.selectedProduct()?.salesEnabled) return;
    if (!AccountSessionStore.isLoggedIn()) { router.pushUrl({ url: 'pages/AccountCenter' }); return; }
    this.busy = true;
    try {
      const purchaseUserId = AccountSessionStore.account().userId;
      const quote = await AccountCommerceApi.quoteMembership(this.selectedSku, AccountSessionStore.token());
      const decision = await promptAction.showDialog({
        title: `开通${this.selectedProduct()?.name || '会员'}`,
        message: `商品价格 ${quote.listPoints} 点\n升级抵扣 ${quote.creditPoints} 点\n本次扣除 ${quote.payablePoints} 充值点\n赠送点不可抵扣，不自动续费。`,
        buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.dark) },
          { text: '确认开通', color: ThemeRuntime.accentColor(this.dark) }]
      });
      if (decision.index !== 1) return;
      await MembershipCommerceService.purchase(this.context, quote.quoteId, purchaseUserId);
      this.membership = AccountSessionStore.account().membership || new MembershipSnapshot();
      HdsFeedback.showToast('会员权益已更新');
    } catch (error) { HdsFeedback.showToast((error as Error).message || '购买未完成，请刷新重试'); }
    finally { this.busy = false; }
  }

  async loadOrders(): Promise<void> {
    try {
      this.orders = (await AccountCommerceApi.membershipOrders(AccountSessionStore.token())).orders;
      if (!this.orders.length) HdsFeedback.showToast('暂无会员订单');
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }

  async claim(tier: string): Promise<void> {
    if (this.busy || this.membership.claim) return;
    this.busy = true;
    try {
      const result = await AccountCommerceApi.claimMembershipGift(tier, AccountSessionStore.token());
      this.membership = result.membership;
      HdsFeedback.showToast('朗读额度已到账');
    } catch (error) { HdsFeedback.showToast((error as Error).message || '领取失败，请刷新重试'); }
    finally { this.busy = false; }
  }
}
