/// 免费版 / 高级版的权益规则。
///
/// 目前只限制「角色卡仓库」的卡片数量：
/// * 免费版：最多 [freeCardLimit] 张；
/// * 高级版（输入激活码后）：不限张数。
///
/// 编辑器的普通 / 高级模式本身不设限，免费用户两种模式都能用。
class LicensePolicy {
  const LicensePolicy._();

  /// 免费版可保存的角色卡数量
  static const int freeCardLimit = 2;

  /// 给定已用张数与是否高级版，返回还能再存几张（-1 表示不限）
  static int remaining(int used, bool premium) {
    if (premium) return -1;
    final left = freeCardLimit - used;
    return left < 0 ? 0 : left;
  }

  /// 是否还能再存一张
  static bool canAdd(int used, bool premium) =>
      premium || used < freeCardLimit;

  /// 免费额度用尽时的说明文案
  static String limitMessage(int used) =>
      '免费版最多保存 $freeCardLimit 张角色卡（当前 $used 张）。'
      '输入激活码解锁高级版后不再限制张数。';
}
