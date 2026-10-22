import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import picker from '@ohos.file.picker';
import fileUri from '@ohos.file.fileuri';
import fs from '@ohos.file.fs';
import { PageScaffold } from '../components/common/PageScaffold';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { CloudFileClient } from '../account/CloudFileClient';
import { CloudFontImport } from '../account/CloudFontImport';
import { CloudFileItem, CloudFileSummary } from '../account/CloudFileModels';
import { LocalBookService } from '../core/book/LocalBookService';
import { HdsFeedback } from '../utils/HdsFeedback';
import { syncSystemBars } from '../utils/SystemBars';
import { AppDatabase } from '../model/data/AppDatabase';
import { BookSourceExport } from '../utils/BookSourceExport';
import { util } from '@kit.ArkTS';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { MembershipIcons } from '../account/MembershipIcons';

class LocalCloudFile {
  name: string = '';
  path: string = '';
  kind: string = '';
  sourceUrl: string = '';
}
class LocalCloudFont { filePath: string = ''; sourceName: string = ''; }
class LocalCloudFonts { fonts: LocalCloudFont[] = []; }

@Entry
@Component
struct CloudFilesPage {
  @StorageLink('appDarkMode') dark: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @State summary: CloudFileSummary = new CloudFileSummary();
  @State files: CloudFileItem[] = [];
  @State nextCursor: string = '';
  @State busy: boolean = false;
  @State progress: string = '';
  @State error: string = '';
  @State pendingName: string = '';
  @State localFiles: LocalCloudFile[] = [];
  @State localShown: number = 30;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  aboutToAppear(): void {
    syncSystemBars(this.context, this.dark, ThemeRuntime.pageColor(this.dark)); this.refresh();
  }
  aboutToDisappear(): void { CloudFileClient.pause(); }
  build() {
    Column() {
      PageScaffold({ title: '我的云空间', content: () => { this.content() } })
    }.width('100%').height('100%').backgroundColor(ThemeRuntime.pageColor(this.dark))
  }

  @Builder
  content() {
    Column({ space: AppSpacing.LG }) {
      this.usageCard()
      if (this.error) {
        Text(this.error)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.dangerColor(this.dark))
          .width('100%')
          .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
      }
      if (this.busy) {
        this.transferCard()
      } else {
        this.uploadCard()
        if (this.pendingName) {
          this.pendingCard()
        }
      }
      Row() {
        Text('云端文件')
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark))
          .layoutWeight(1)
        Text('刷新')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.accentColor(this.dark))
          .enabled(!this.busy)
          .onClick(() => { this.refresh() })
      }
      .width('100%')
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
      if (this.summary.configured && this.files.length === 0) {
        Text('云端还没有文件')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.subTextColor(this.dark))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(AppSpacing.XXL)
      }
      ForEach(this.files, (file: CloudFileItem) => {
        this.fileRow(file)
      }, (file: CloudFileItem) => file.id + file.state)
      if (this.nextCursor) {
        Text('加载更多')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.accentColor(this.dark))
          .enabled(!this.busy)
          .padding(AppSpacing.LG)
          .onClick(() => { this.more() })
      }
      Text('书籍、字体与书源共用 1GB。下载按签发授权的分块计量：短时重试复用授权，过期后重新下载会再次计量，失败不自动退还额度。上传中和待清理的文件仍占用空间。')
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(18)
        .fontColor(ThemeRuntime.subTextColor(this.dark))
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  usageCard() {
    Column({ space: AppSpacing.LG }) {
      Row({ space: AppSpacing.LG }) {
        Image(MembershipIcons.forSku('SUPER_LIFETIME'))
          .width(44)
          .height(44)
          .objectFit(ImageFit.Contain)
        Column({ space: AppSpacing.XXS }) {
          Text(this.summary.configured ? '永久超级会员云空间' : '云空间服务尚未启用')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontColor(MembershipIcons.cardTextColor(this.dark))
          Text(this.summary.eligible ? '书籍 · 字体 · 书源' : '需要有效的永久超级会员')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(MembershipIcons.cardSubTextColor(this.dark))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      this.meter('存储空间', this.summary.usedBytes, this.summary.quotaBytes, '')
      this.meter('本月下载额度', this.summary.downloadBytes, this.summary.downloadQuotaBytes,
        this.summary.cycleEndsAt ? `${this.formatDate(this.summary.cycleEndsAt)} 重置` : '')
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .linearGradient({ angle: 135, colors: MembershipIcons.cardGradient('SUPER_LIFETIME', this.dark) })
  }

  @Builder
  meter(title: string, used: number, total: number, hint: string) {
    Column({ space: AppSpacing.XS }) {
      Row() {
        Text(title)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(MembershipIcons.cardSubTextColor(this.dark))
          .layoutWeight(1)
        Text(`${this.formatBytes(used)} / ${this.formatBytes(total)}` + (hint ? ` · ${hint}` : ''))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(MembershipIcons.cardTextColor(this.dark))
      }
      .width('100%')
      Progress({ value: Math.min(used, total), total: Math.max(1, total), type: ProgressType.Linear })
        .width('100%')
        .height(6)
        .color(MembershipIcons.accent('SUPER_LIFETIME', this.dark))
        .backgroundColor(this.dark ? '#33FFFFFF' : '#66FFFFFF')
    }
    .width('100%')
  }

  @Builder
  uploadCard() {
    Column({ space: AppSpacing.LG }) {
      Text('上传到云空间')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark))
        .width('100%')
      Row({ space: AppSpacing.MD }) {
        this.uploadTile($r('sys.symbol.book'), '书籍', 'BOOK')
        this.uploadTile($r('sys.symbol.textformat'), '字体', 'FONT')
        this.uploadTile($r('sys.symbol.externaldrive'), '书源', 'SOURCE')
      }
      .width('100%')
      Row() {
        Text('从本机书架、字体与书源中选择')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark))
          .layoutWeight(1)
        SymbolGlyph(this.localFiles.length > 0 ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([ThemeRuntime.subTextColor(this.dark)])
      }
      .width('100%')
      .opacity(this.summary.eligible ? 1 : 0.5)
      .onClick(() => {
        if (!this.summary.eligible) return;
        if (this.localFiles.length > 0) {
          this.localFiles = [];
        } else {
          this.loadLocal();
        }
      })
      ForEach(this.localFiles.slice(0, this.localShown), (file: LocalCloudFile) => {
        Row({ space: AppSpacing.MD }) {
          Text(this.kind(file.kind))
            .fontSize(AppFontSize.MICRO)
            .fontColor(ThemeRuntime.accentColor(this.dark))
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 2, bottom: 2 })
            .borderRadius(ThemeRuntime.smallRadius())
            .backgroundColor(ThemeRuntime.inputColor(this.dark))
          Text(file.name)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.primaryTextColor(this.dark))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text('上传')
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.accentColor(this.dark))
            .onClick(() => { this.uploadLocal(file) })
        }
        .width('100%')
      }, (file: LocalCloudFile) => file.kind + (file.sourceUrl || file.path))
      if (this.localShown < this.localFiles.length) {
        Text('显示更多')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.accentColor(this.dark))
          .onClick(() => { this.localShown += 30; })
      }
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.dark))
  }

  @Builder
  uploadTile(icon: Resource, title: string, kind: string) {
    Column({ space: AppSpacing.SM }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([ThemeRuntime.accentColor(this.dark)])
      Text(title)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark))
    }
    .layoutWeight(1)
    .padding({ top: AppSpacing.LG, bottom: AppSpacing.LG })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(ThemeRuntime.inputColor(this.dark))
    .opacity(this.summary.eligible ? 1 : 0.5)
    .onClick(() => {
      if (this.summary.eligible) this.pick(kind);
    })
  }

  @Builder
  transferCard() {
    Row({ space: AppSpacing.LG }) {
      LoadingProgress()
        .width(24)
        .height(24)
        .color(ThemeRuntime.accentColor(this.dark))
      Text(this.progress || '正在准备传输…')
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark))
        .layoutWeight(1)
      Text('暂停')
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.accentColor(this.dark))
        .onClick(() => { CloudFileClient.pause(); })
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.dark))
  }

  @Builder
  pendingCard() {
    Column({ space: AppSpacing.MD }) {
      Text(`未完成的上传：${this.pendingName}`)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: AppSpacing.MD }) {
        Button('继续上传')
          .layoutWeight(1)
          .height(38)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(ThemeRuntime.accentColor(this.dark))
          .enabled(this.summary.eligible)
          .onClick(() => { this.resume() })
        Button('取消任务')
          .layoutWeight(1)
          .height(38)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.subTextColor(this.dark))
          .backgroundColor(ThemeRuntime.inputColor(this.dark))
          .onClick(() => { this.cancelUpload() })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.dark))
  }

  @Builder
  fileRow(file: CloudFileItem) {
    Row({ space: AppSpacing.LG }) {
      SymbolGlyph(file.kind === 'BOOK' ? $r('sys.symbol.book') :
        (file.kind === 'FONT' ? $r('sys.symbol.textformat') : $r('sys.symbol.externaldrive')))
        .fontSize(22)
        .fontColor([ThemeRuntime.accentColor(this.dark)])
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(ThemeRuntime.inputColor(this.dark))
      Column({ space: AppSpacing.XXS }) {
        Text(file.name)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.kind(file.kind)} · ${this.formatBytes(file.bytes)} · ${this.status(file.state)}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.dark))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.download'))
        .fontSize(20)
        .fontColor([ThemeRuntime.accentColor(this.dark)])
        .opacity(!this.busy && this.summary.eligible && file.state === 'READY' ? 1 : 0.35)
        .accessibilityText('下载并导入')
        .onClick(() => {
          if (!this.busy && this.summary.eligible && file.state === 'READY') this.download(file);
        })
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(20)
        .fontColor([ThemeRuntime.subTextColor(this.dark)])
        .opacity(!this.busy && file.state !== 'DELETING' ? 1 : 0.35)
        .accessibilityText('删除云端副本')
        .onClick(() => {
          if (!this.busy && file.state !== 'DELETING') this.remove(file);
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.dark))
  }

  formatDate(value: number): string {
    const date = new Date(value);
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }

  formatBytes(bytes: number): string {
    if (bytes >= 1073741824) return `${(bytes / 1073741824).toFixed(bytes % 1073741824 === 0 ? 0 : 2)} GB`;
    return bytes < 1048576 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1048576).toFixed(1)} MB`;
  }
  kind(value: string): string { return value === 'BOOK' ? '书籍' : value === 'FONT' ? '字体' : '书源'; }
  status(value: string): string { return value === 'READY' ? '已同步' : value === 'DELETING' ? '清理中' : '上传中'; }
  async refresh(): Promise<void> {
    if (this.busy) return;
    try {
      this.summary = await CloudFileClient.summary();
      if (this.summary.configured) {
        const list = await CloudFileClient.list(); this.files = list.files; this.nextCursor = list.nextCursor;
        await CloudFontImport.saveNames(this.context, this.context.filesDir, list.files);
      }
      this.pendingName = (await CloudFileClient.pending(this.context))?.name || '';
    } catch (error) { this.error = (error as Error).message; }
  }
  async more(): Promise<void> {
    try {
      const list = await CloudFileClient.list(this.nextCursor);
      this.files = this.files.concat(list.files); this.nextCursor = list.nextCursor;
      await CloudFontImport.saveNames(this.context, this.context.filesDir, list.files);
    }
    catch (error) { this.error = (error as Error).message; }
  }
  async pick(kind: string): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1;
      options.fileSuffixFilters = kind === 'BOOK' ? ['书籍|.txt,.epub'] : kind === 'FONT' ? ['字体|.ttf,.otf,.ttc'] : ['书源|.json'];
      const picked = await new picker.DocumentViewPicker(this.context).select(options);
      if (!picked.length) return;
      const name = decodeURIComponent(picked[0].split('/').pop() || '云文件').replace(/[\\/\x00-\x1f]/g, '_');
      await CloudFileClient.stage(this.context, picked[0], name, kind);
      await this.resume();
    } catch (error) { this.error = (error as Error).message; }
  }
  async loadLocal(): Promise<void> {
    try {
      const db = AppDatabase.getInstance(); await db.initWithContext(this.context);
      const result: LocalCloudFile[] = [];
      for (const book of await db.getAllBooks()) {
        const path = book.getVariable('localFilePath');
        if (!path || !fs.accessSync(path)) continue;
        const item = new LocalCloudFile(); item.path = path; item.kind = 'BOOK';
        item.name = `${book.name}.${path.toLowerCase().endsWith('.epub') ? 'epub' : 'txt'}`; result.push(item);
      }
      const fontsRaw = AppStorage.get<string>('readerCustomFontsRaw') || '';
      if (fontsRaw) {
        const parsed = JSON.parse(fontsRaw) as LocalCloudFonts | LocalCloudFont[];
        const fonts = Array.isArray(parsed) ? parsed as LocalCloudFont[] : (parsed as LocalCloudFonts).fonts;
        for (const font of fonts || []) {
          if (!font.filePath || !fs.accessSync(font.filePath)) continue;
          const item = new LocalCloudFile(); item.path = font.filePath; item.kind = 'FONT';
          item.name = CloudFontImport.uploadName(font.sourceName, font.filePath); result.push(item);
        }
      }
      for (const source of await db.getBookSourceSummaries()) {
        const item = new LocalCloudFile(); item.sourceUrl = source.bookSourceUrl; item.kind = 'SOURCE';
        item.name = `${source.bookSourceName}.json`; result.push(item);
      }
      this.localFiles = result; this.localShown = 30;
      if (!result.length) HdsFeedback.showToast('本机暂无可上传的内容');
    } catch (error) { this.error = (error as Error).message; }
  }
  async uploadLocal(item: LocalCloudFile): Promise<void> {
    let temp = '';
    try {
      let path = item.path;
      if (item.kind === 'SOURCE') {
        const source = await AppDatabase.getInstance().getBookSource(item.sourceUrl);
        if (!source) throw new Error('书源已不存在');
        const bytes = new util.TextEncoder().encodeInto(JSON.stringify(BookSourceExport.toObject(source)));
        temp = `${this.context.cacheDir}/cloud_source_${util.generateRandomUUID()}.json`;
        const file = await fs.open(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        try {
          let offset = 0;
          while (offset < bytes.length) {
            const remaining = bytes.slice(offset);
            const count = await fs.write(file.fd, remaining.buffer);
            if (count <= 0) throw new Error('暂存书源失败');
            offset += count;
          }
        } finally { await fs.close(file); }
        path = temp;
      }
      await CloudFileClient.stage(this.context, path, item.name.replace(/[\\/\x00-\x1f]/g, '_').slice(0, 200), item.kind);
      await this.resume();
    } catch (error) { this.error = (error as Error).message; }
    finally { if (temp && fs.accessSync(temp)) await fs.unlink(temp); }
  }
  async resume(): Promise<void> {
    this.busy = true; this.error = '';
    try {
      await CloudFileClient.upload(this.context, (done: number, total: number) => { this.progress = `上传 ${Math.floor(done * 100 / total)}%`; });
      this.progress = '上传完成';
    } catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; await this.refresh(); }
  }
  async cancelUpload(): Promise<void> {
    try { await CloudFileClient.cancelUpload(this.context); await this.refresh(); }
    catch (error) { this.error = (error as Error).message; }
  }
  async download(file: CloudFileItem): Promise<void> {
    this.busy = true; this.error = '';
    try {
      const path = await CloudFileClient.download(this.context, file,
        (done: number, total: number) => { this.progress = `下载 ${Math.floor(done * 100 / total)}%`; });
      const extension = file.name.split('.').pop()?.toLowerCase() || '';
      if (file.kind === 'BOOK') {
        await LocalBookService.importExternalBook(this.context, path, extension, file.name);
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        await fs.unlink(path); HdsFeedback.showToast('已导入书架');
      } else if (file.kind === 'FONT') {
        const fontPath = CloudFontImport.localPath(this.context.filesDir, file);
        if (!fontPath) throw new Error('字体格式无效');
        const dir = `${this.context.filesDir}/reader_fonts`;
        if (!fs.accessSync(dir)) await fs.mkdir(dir);
        await fs.copy(fileUri.getUriFromPath(path), fileUri.getUriFromPath(fontPath));
        await CloudFontImport.saveNames(this.context, this.context.filesDir, [file]);
        await fs.unlink(path);
        router.pushUrl({ url: 'pages/CustomFontManager' });
      } else {
        if (file.bytes > 25 * 1024 * 1024) {
          const options = new picker.DocumentSaveOptions(); options.newFileNames = [file.name];
          const saved = await new picker.DocumentViewPicker(this.context).save(options);
          if (saved.length) {
            await fs.copy(fileUri.getUriFromPath(path), saved[0]);
            HdsFeedback.showToast('已保存书源文件；当前导入器仅支持 25MB 以内的 JSON');
          }
          // Saved or canceled, the local transfer copy is no longer needed.
          await fs.unlink(path);
          return;
        }
        // Existing source importer provides validation and explicit conflict choices. Hand it a cache copy so
        // the resumable transfer file is removed now; the system may reclaim cache files later.
        const importPath = `${this.context.cacheDir}/cloud_import_${file.id}.json`;
        if (fs.accessSync(importPath)) await fs.unlink(importPath);
        await fs.moveFile(path, importPath);
        AppStorage.setOrCreate('pendingBookSourceImportUri', fileUri.getUriFromPath(importPath));
        AppStorage.setOrCreate('pendingBookSourceImportNonce', Date.now());
        router.pushUrl({ url: 'pages/BookSource' });
      }
      this.progress = '下载完成';
    } catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; await this.refresh(); }
  }
  async remove(file: CloudFileItem): Promise<void> {
    const answer = await promptAction.showDialog({ title: '删除云文件', message: `删除“${file.name}”的云端副本？已下载到本机的文件会保留。`,
      buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.dark) }, { text: '删除', color: ThemeRuntime.accentColor(this.dark) }] });
    if (answer.index !== 1) return;
    try { await CloudFileClient.remove(file.id); await this.refresh(); }
    catch (error) { this.error = (error as Error).message; }
  }
}
