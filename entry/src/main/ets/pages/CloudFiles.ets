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
      PageScaffold({ title: '我的云文件', content: () => { this.content() } })
    }.width('100%').height('100%').backgroundColor(ThemeRuntime.pageColor(this.dark))
  }
  @Builder
  content() {
    Column({ space: 16 }) {
      Column({ space: 10 }) {
        Text(this.summary.configured ? '永久超级会员云空间' : '云文件服务尚未启用').fontSize(20).fontWeight(FontWeight.Bold)
        Text(`空间 ${this.formatBytes(this.summary.usedBytes)} / 1GB`).fontSize(14)
        Text(`本月下载授权 ${this.formatBytes(this.summary.downloadBytes)} / 1GB`).fontSize(14)
        if (this.summary.cycleEndsAt) {
          Text(`流量重置：${new Date(this.summary.cycleEndsAt).toLocaleDateString()}`).fontSize(12)
        }
        Text('书籍、字体与书源共用空间。下载按签发授权的分块大小扣额度；短时重试复用授权，过期重领再次扣除，失败不自动退额。上传中与待清理文件仍占空间。')
          .fontSize(12).lineHeight(20).fontColor(ThemeRuntime.subTextColor(this.dark))
      }.padding(18).width('100%').alignItems(HorizontalAlign.Start)
        .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(20)
      if (this.error) { Text(this.error).fontSize(13).fontColor(ThemeRuntime.subTextColor(this.dark)) }
      if (this.progress) { Text(this.progress).fontSize(14) }
      if (this.busy) {
        Button('暂停传输').onClick(() => { CloudFileClient.pause(); })
      } else {
        Row({ space: 8 }) {
          Button('上传书籍').fontSize(13).layoutWeight(1).enabled(this.summary.eligible).onClick(() => { this.pick('BOOK') })
          Button('上传字体').fontSize(13).layoutWeight(1).enabled(this.summary.eligible).onClick(() => { this.pick('FONT') })
          Button('上传书源').fontSize(13).layoutWeight(1).enabled(this.summary.eligible).onClick(() => { this.pick('SOURCE') })
        }.width('100%')
        Button('从 App 本机内容选择').enabled(this.summary.eligible).onClick(() => { this.loadLocal() })
        ForEach(this.localFiles.slice(0, this.localShown), (file: LocalCloudFile) => {
          Row({ space: 8 }) {
            Text(`${this.kind(file.kind)} · ${file.name}`).layoutWeight(1).fontSize(13).maxLines(1)
            Button('上传').fontSize(12).onClick(() => { this.uploadLocal(file) })
          }.width('100%')
        }, (file: LocalCloudFile) => file.kind + (file.sourceUrl || file.path))
        if (this.localShown < this.localFiles.length) {
          Button('更多本机内容').onClick(() => { this.localShown += 30; })
        }
        if (this.pendingName) {
          Text(`待上传：${this.pendingName}`).fontSize(13)
          Row({ space: 12 }) {
            Button('继续上传').enabled(this.summary.eligible).onClick(() => { this.resume() })
            Button('取消任务').onClick(() => { this.cancelUpload() })
          }
        }
        Button('刷新').onClick(() => { this.refresh() })
      }
      ForEach(this.files, (file: CloudFileItem) => {
        Column({ space: 9 }) {
          Text(file.name).fontSize(16).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.kind(file.kind)} · ${this.formatBytes(file.bytes)} · ${this.status(file.state)}`)
            .fontSize(12).fontColor(ThemeRuntime.subTextColor(this.dark))
          Row({ space: 10 }) {
            Button('下载并导入').fontSize(13).enabled(!this.busy && this.summary.eligible && file.state === 'READY')
              .onClick(() => { this.download(file) })
            Button('删除云端').fontSize(13).enabled(!this.busy && file.state !== 'DELETING')
              .onClick(() => { this.remove(file) })
          }
        }.padding(16).width('100%').alignItems(HorizontalAlign.Start)
          .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(18)
      }, (file: CloudFileItem) => file.id)
      if (this.nextCursor) { Button('加载更多').enabled(!this.busy).onClick(() => { this.more() }) }
      if (this.summary.configured && this.files.length === 0) { Text('云端还没有文件').fontSize(14) }
    }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
      .foregroundColor(ThemeRuntime.primaryTextColor(this.dark))
  }
  formatBytes(bytes: number): string { return bytes < 1048576 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1048576).toFixed(1)} MB`; }
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
            await fs.unlink(path);
            HdsFeedback.showToast('已保存书源文件；当前导入器仅支持 25MB 以内的 JSON');
          }
          return;
        }
        // Existing source importer provides validation and explicit conflict choices.
        AppStorage.setOrCreate('pendingBookSourceImportUri', fileUri.getUriFromPath(path));
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
