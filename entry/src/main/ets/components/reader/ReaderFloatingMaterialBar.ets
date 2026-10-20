import { uiMaterial } from '@kit.ArkUI';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';

/**
 * API 26 materials on layout containers only render inside supported system UI regions.
 * Keep the complete capsule inside one bottom TabBar, sized and clipped to the capsule itself.
 */
@Component
export struct ReaderFloatingMaterialBar {
  @Prop barWidth: number = 320;
  @Prop barHeight: number = 48;
  @Prop tintColor: ResourceColor = Color.Transparent;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  @Builder
  materialContent() {
    Stack({ alignContent: Alignment.Center }) {
      this.content()
    }
    .width('100%')
    .height(this.barHeight)
    .borderRadius(this.barHeight / 2)
    .systemMaterial(this.material())
  }

  private material(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: ImmersiveMaterialRuntime.materialStyle(),
      // Reuse the reader's glass tint and opacity instead of adding a white wash.
      materialColor: this.tintColor,
      applyShadow: false,
      // Sliders must not deform the whole capsule while the user drags them.
      interactive: false,
      lightEffect: ImmersiveMaterialRuntime.lightEffect(true)
    });
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: 0 }) {
      TabContent() {
        Column()
      }
      .tabBar(this.materialContent())
    }
    .barMode(BarMode.Fixed)
    .barHeight(this.barHeight)
    .barOverlap(true)
    .barBackgroundColor(Color.Transparent)
    .barBackgroundBlurStyle(BlurStyle.NONE)
    .scrollable(false)
    .onContentWillChange(() => false)
    .width(this.barWidth)
    .height(this.barHeight)
    .borderRadius(this.barHeight / 2, RenderStrategy.OFFSCREEN)
    .clip(true)
  }
}
