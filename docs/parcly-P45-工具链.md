# P45 可复现工具链约定

本PR以 Flutter **3.41.9** / revision **00b0c91f06209d9e4a41f71b7a512d6eb3b9c694**，engine **42d3d75a56efe1a2e9902f52dc8006099c45d937**，Dart **3.11.5** 验证。该revision与项目.metadata一致；matcher0.12.19/meta1.17.0/test_api0.7.10/vector_math2.2.0与原lock完全一致。

官方来源：https://github.com/flutter/flutter/tree/3.41.9 及 https://docs.flutter.dev/install/archive 。官方Linux归档清单本轮404，因此采用官方Git tag + 该版本工具自举的专属Dart/engine cache；没有借用新SDK的Dart cache，不将本地hash冒充官方归档校验值。

只在自有workspace安装，不切共享SDK，不在用户电脑checkout。示例：

```bash
git clone --depth 1 --branch 3.41.9 https://github.com/flutter/flutter.git /workspace/p45-sdk/flutter-3.41.9
export PATH=/workspace/p45-sdk/flutter-3.41.9/bin:$PATH
export PUB_CACHE=/workspace/p45-sdk/pub-cache-3.41.9
export GRADLE_USER_HOME=/workspace/p45-sdk/gradle-home
# JAVA_HOME及ANDROID_HOME指向已有的授权工具链；本轮Android SDK也复制到/workspace下隔离。
flutter --version --machine
python3 tools/check_p45_toolchain.py
flutter clean
flutter pub get --enforce-lockfile
python3 tools/check_p45_toolchain.py
flutter test --no-pub
flutter analyze --no-pub
bash tools/check_no_pii.sh
flutter build apk --release --no-pub --target-platform android-arm64
```

`tools/check_p45_toolchain.py`是可执行失败门禁：检查精确framework/engine/Dart、Dart cache stamps、项目.metadata及原lock SHA256。可用FLUTTER_BIN指定工具路径。它不能代替测试/构建；错误SDK时必须失败，不临时重解依赖后恢复lock。

原lock SHA256：`956981f554bb63318109639552c683a032bf3764583c70e0d6879e7f68bc7383`。本次不改依赖/lock，不升级Gradle/AGP/Kotlin。真机/录屏/OS无障碍/profile仍单独待QA，不以组件测试冒充。
