import 'package:flutter/widgets.dart';

/// Decode-size helpers for `CachedNetworkImage` (audit finding 2.1).
///
/// `memCacheWidth` is in *physical pixels*: a widget shown at N logical px on a
/// 3x screen needs a 3N-px bitmap to look sharp, but no more. Decoding the full
/// 1080px upload for a 190px tile wastes ~8x the memory. These helpers size the
/// decode to the display; fixed-size surfaces use the plain constants below.
///
/// DPR is capped at 3 so 4x devices don't decode absurdly large bitmaps for a
/// marginal sharpness gain.
int fullBleedCacheWidth(BuildContext context) {
  final mq = MediaQuery.of(context);
  final dpr = mq.devicePixelRatio.clamp(1.0, 3.0);
  return (mq.size.width * dpr).round();
}

/// Grid tiles / product thumbnails — ~190px logical at up to 3x ≈ 600px.
const int gridTileCacheWidth = 600;

/// Boutique logos / avatars — ~50px logical at up to 3x ≈ 150px.
const int logoCacheWidth = 150;

/// Disk-cache cap; matches the upload pipeline's 1080px longest edge so the
/// stored file is never larger than what was uploaded.
const int maxImageDiskCacheWidth = 1080;
