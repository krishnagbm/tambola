import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/core/constants/app_assets.dart';
import 'package:tambola/core/theme/app_theme.dart';

void main() {
  test('App theme configuration smoke test', () {
    final theme = AppTheme.darkTheme;
    expect(theme.scaffoldBackgroundColor, AppTheme.darkBackground);
    expect(theme.colorScheme.primary, AppTheme.primaryColor);
    expect(theme.colorScheme.secondary, AppTheme.secondaryColor);
  });

  test('DebHousie brand assets paths verification', () {
    expect(AppAssets.horizontalLogo, contains('debhousie_horizontal_logo.png'));
    expect(AppAssets.mainLogo, contains('debhousie_main_logo.png'));
    expect(AppAssets.monogramDH, contains('debhousie_monogram_DH.png'));
    expect(AppAssets.appIcon1024, contains('debhousie_app_icon_1024.png'));
    expect(AppAssets.androidIcon512, contains('debhousie_android_icon_512.png'));
    expect(AppAssets.iosIcon1024, contains('debhousie_ios_icon_1024.png'));
    expect(AppAssets.favicon192, contains('debhousie_favicon_192.png'));
  });
}
