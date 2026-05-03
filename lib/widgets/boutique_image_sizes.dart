import 'package:image_cropper/image_cropper.dart';

class BoutiqueImageSizes {
  static const double homeLogo = 100;
  static const double boutiquesPageLogo = 52;
  static const double storefrontLogo = 90;
  static const double myBoutiquePreviewLogo = 140;

  static const double storefrontBannerHeight = 260;
  static const double myBoutiqueBannerPreviewHeight = 180;

  static final CropAspectRatio logoCropRatio =
  CropAspectRatio(ratioX: 1, ratioY: 1);

  static final CropAspectRatio bannerCropRatio =
  CropAspectRatio(ratioX: 16, ratioY: 9);

  static const int logoMaxWidth = 800;
  static const int logoMaxHeight = 800;

  static const int bannerMaxWidth = 1600;
  static const int bannerMaxHeight = 900;
}