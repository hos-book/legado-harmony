export class MembershipIcons {
  static forSku(sku: string): Resource {
    if (sku === 'MONTHLY') return $r('app.media.membership_monthly');
    if (sku === 'LIFETIME') return $r('app.media.membership_lifetime');
    if (sku === 'SUPER_LIFETIME') return $r('app.media.membership_super_lifetime');
    return $r('app.media.membership_annual');
  }
}
