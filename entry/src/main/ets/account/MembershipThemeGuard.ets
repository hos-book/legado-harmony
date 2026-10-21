import { common } from '@kit.AbilityKit';
import { AccountSessionStore } from './AccountSessionStore';
import { AccountCommerceApi } from './AccountCommerceApi';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ThemeIds } from '../theme/ThemeModels';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { ThemeTrialManager } from '../utils/ThemeTrialManager';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';

export class MembershipThemeGuard {
  private static checking: boolean = false;
  private static lastRefreshAttempt: number = 0;
  static async refresh(context: common.UIAbilityContext): Promise<void> {
    if (MembershipThemeGuard.checking || ThemeTrialManager.isActive()) return;
    MembershipThemeGuard.checking = true;
    try {
      const account = AccountSessionStore.account();
      if (AccountSessionStore.isLoggedIn() && account.membership?.state &&
        Date.now() - account.memberVerifiedAt > 6 * 60 * 60 * 1000 &&
        Date.now() - MembershipThemeGuard.lastRefreshAttempt > 15 * 60 * 1000) {
        MembershipThemeGuard.lastRefreshAttempt = Date.now();
        try {
          const latest = await AccountCommerceApi.fetchAccount(AccountSessionStore.token());
          if (AccountSessionStore.account().userId === account.userId) await AccountSessionStore.updateSnapshot(context, latest);
        } catch (_) { /* Keep the bounded offline grant when the network is unavailable. */ }
      }
      const settings = await AppThemeSettingsStore.load(context);
      if (!settings.themeId || settings.themeId === ThemeIds.CUSTOM || BuiltinThemeRegistry.isFree(settings.themeId)
        || AccountSessionStore.hasValidEntitlement(settings.themeId)) return;
      const fallback = AppThemeSettingsStore.activateTheme(AppThemeSettingsStore.DEFAULT_THEME_ID, settings);
      await AppThemeSettingsStore.save(context, fallback);
      AppThemeSettingsStore.applyToStorage(fallback);
      ReaderFontBootstrap.applyApplicationFont(context, 'membership-expired');
    } finally { MembershipThemeGuard.checking = false; }
  }
}
