with open('pubspec.yaml', 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = lines[:105]
new_lines.extend([
    '  #       - asset: fonts/TrajanPro_Bold.ttf\n',
    '  #         weight: 700\n',
    '  #\n',
    '  # For details regarding fonts from package dependencies,\n',
    '  # see https://flutter.dev/to/font-from-package\n',
    '\n',
    'flutter_native_splash:\n',
    '  color: "#ffffff"\n',
    '  image: "assets/splash_icon_light.png"\n',
    '  color_dark: "#121212"\n',
    '  image_dark: "assets/splash_icon_dark.png"\n',
    '  android_12:\n',
    '    color: "#ffffff"\n',
    '    image: "assets/splash_icon_light.png"\n',
    '    color_dark: "#121212"\n',
    '    image_dark: "assets/splash_icon_dark.png"\n'
])

with open('pubspec.yaml', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
