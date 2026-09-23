# Release 真机性能数据

`performance` 只验证输入和计算门槛，不采集指标，也不能证明 JSON 是真机数据。当前没有混合运行时，不能生成有效的三方验收数据。

一次输入对应一台匿名编号真机、一个固定 OS、一个目标平台。不得混合机型或将 iOS/Android 样本合并。顶层字段：

```json
{
  "schema_version": 1,
  "mode": "release",
  "target": "ios-arm64",
  "device_alias": "ios-reference-01",
  "os_version": "填写实际系统版本",
  "benchmark_revision": "填写测试脚本revision",
  "conditions": "填写电量/温度/网络/屏幕刷新率/后台状态/采集工具版本",
  "variants": {}
}
```

variants 必须包含 official、custom_base、custom_patch。每组包含 artifact_sha256、logical_source_sha256 和 scenarios。哈希必须为64位小写十六进制；logical_source_sha256表示**生效后的逻辑源码**，三组相同，custom_patch不是拿旧基线源码来代替。

scenarios 必须有 form、list、navigation、animation、async。每个场景包含：

| 字段 | 样本数量 | 单位/含义 | 聚合 |
| --- | --- | --- | --- |
| cold_start_ms | ≥30 | 从原生进程启动到首个有效页面，毫秒 | nearest-rank P95 |
| ui_frame_p95_ms | ≥5 | 每轮全部有效帧的 UI P95，毫秒 | 各轮最大值 |
| raster_frame_p95_ms | ≥5 | 每轮全部有效帧的 raster P95，毫秒 | 各轮最大值 |
| peak_memory_bytes | ≥5 | 每轮进程峰值内存，字节 | 各轮最大值 |

数组全部为有限正数。不使用 Dart main 起点冒充原生冷启动；不使用堆内存代替进程内存；不以 Debug/Profile 数据通过 Release 关卡。UI/raster 原生采集入口、自动场景驱动及数据导出尚未实现。

custom_base/custom_patch 分别与 official 比较：前三项≤1.10倍，内存≤1.15倍。采用各轮 P95 的最大值避免平均值掩盖一次明显退化。接近门槛且方差较大时仍需审查原始数据并重测；本数值工具不会自动识别设备热降频。

计算热点另行报告，不纳入“全部函数同速”的承诺。test/performance_test.dart 的合成数据只用于判定器单测，不是性能报告，不允许复制为验收证据。
