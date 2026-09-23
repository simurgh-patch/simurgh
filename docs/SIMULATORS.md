# 模拟器功能验证

模拟器仅验证样例功能，不作为M0双端真机或性能验收。Android ARM64可运行源码引擎Release；本轮iOS模拟器使用固定Flutter 3.44.8官方Debug引擎，真机ios_release引擎不能用于模拟器。

## 同一套测试

`examples/runtime_probe/integration_test/scenarios_test.dart`复用widget_test.dart的7项语义和交互断言，通过IntegrationTestWidgetsFlutterBinding在应用进程内执行。入口仅属于测试，不加入业务main.dart；Release没有VM service，因此输出`SIMURGH_INTEGRATION_RESULT`及JSON结果供原生日志收集。宿主widget测试和模拟器测试须分别记录。

在独立样例目录运行iOS测试：

```sh
../../.engine-workspace/framework/bin/flutter test integration_test/scenarios_test.dart -d <simulator-id> --reporter expanded
```

Android源码引擎Release测试包：

```sh
PROJECT_ROOT=/absolute/path/to/simurgh
export GRADLE_USER_HOME="$PROJECT_ROOT/.tools/gradle"
"$PROJECT_ROOT/.engine-workspace/framework/bin/flutter" \
  --local-engine-src-path "$PROJECT_ROOT/.engine-workspace/engine/engine/src" \
  --local-engine android_release_arm64 --local-engine-host host_release_arm64 \
  build apk --release --target-platform android-arm64 \
  --target integration_test/scenarios_test.dart
```

切换Debug/Release后不跳过Flutter插件元数据生成，否则可能残留Debug的测试插件注册。Release不包含dev-only原生测试插件；独立运行测试APK时，结果以完整日志及测试完成标记核对，不能用进程存活代替通过。安装测试包后应恢复普通样例包，方便手动交互；恢复安装仅针对独立runtime_probe应用。

同一个样例的Flutter build/test/analyze须串行执行：即使目标平台不同，也可能重写共用的插件注册文件。首次Android Release表单测试失败。增加布局等待后定位到输入仍为空；固定Flutter源码text_input.dart证实TestTextInput默认client=-1只在Debug放行。Release测试显式注册测试输入通道以捕获实际client ID，输入值和问候文字断言均保留；该用例不验证原生键盘实现。输入后仍等待布局稳定，避免Debug设备键盘动画影响点击坐标。
