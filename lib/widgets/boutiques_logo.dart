import 'package:flutter/material.dart';
import 'boutique_logo_avatar.dart';

Widget buildBoutiquesLogo(
    String imageUrl, {
      VoidCallback? onTap,
    }) {
  return BoutiqueLogoAvatar(
    imageUrl: imageUrl,
    size: 100,
    onTap: onTap,
  );
}