import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CloudRemoteFont } from './CloudAutoSync';

/**
 * 字体下拉框的菜单项：索引从 remoteStart 起是云端尚未下载的字体，文字置灰并带下载图标，
 * 选中后由页面下载导入再应用。系统 Select 不能单独设置某一项的颜色，所以自绘菜单项。
 */
@Builder
function cloudFontMenuItem(config: MenuItemConfiguration) {
  Row({ space: AppSpacing.MD }) {
    Text(config.value)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor(config.index >= (config.contentModifier as CloudFontMenuModifier).remoteStart ?
        (config.contentModifier as CloudFontMenuModifier).mutedColor :
        (config.selected ? (config.contentModifier as CloudFontMenuModifier).accentColor :
          (config.contentModifier as CloudFontMenuModifier).textColor))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)
    if (config.index >= (config.contentModifier as CloudFontMenuModifier).remoteStart) {
      SymbolGlyph($r('sys.symbol.download'))
        .fontSize(16)
        .fontColor([(config.contentModifier as CloudFontMenuModifier).mutedColor])
    }
  }
  .width('100%')
  .constraintSize({ minHeight: 48 })
  .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
  .borderRadius(8)
  .backgroundColor(config.selected ? (config.contentModifier as CloudFontMenuModifier).selectedBackground :
    Color.Transparent)
  .accessibilityText(config.index >= (config.contentModifier as CloudFontMenuModifier).remoteStart ?
    `${config.value}，云端字体，选择后下载` : `${config.value}`)
  .onClick(() => {
    config.triggerSelect(config.index, config.value.toString());
  })
}

export class CloudFontMenuModifier implements ContentModifier<MenuItemConfiguration> {
  remoteStart: number;
  textColor: string;
  mutedColor: string;
  accentColor: string;
  selectedBackground: string;

  constructor(remoteStart: number, textColor: string, mutedColor: string, accentColor: string,
    selectedBackground: string) {
    this.remoteStart = remoteStart;
    this.textColor = textColor;
    this.mutedColor = mutedColor;
    this.accentColor = accentColor;
    this.selectedBackground = selectedBackground;
  }

  applyContent(): WrappedBuilder<[MenuItemConfiguration]> {
    return wrapBuilder(cloudFontMenuItem);
  }

  /** 下拉框里显示的名字：去掉文件扩展名。 */
  static label(font: CloudRemoteFont): string {
    return (font.name || '云端字体').replace(/\.(ttf|otf|ttc)$/i, '');
  }
}
