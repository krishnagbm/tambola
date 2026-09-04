import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/core/theme/app_theme.dart';

void main() {
  test('App theme configuration smoke test', () {
    final theme = AppTheme.darkTheme;
    expect(theme.scaffoldBackgroundColor, AppTheme.darkBackground);
    expect(theme.colorScheme.primary, AppTheme.primaryColor);
    expect(theme.colorScheme.secondary, AppTheme.secondaryColor);
  });
}
