#include "embedder.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <queue>
#include <thread>

struct Pending {
  uint64_t time;
  uint64_t sequence;
  FlutterTask task;
  bool operator<(const Pending &other) const {
    return time > other.time ||
           (time == other.time && sequence > other.sequence);
  }
};
struct Context {
  std::thread::id platform = std::this_thread::get_id();
  std::mutex mutex;
  std::condition_variable changed;
  std::priority_queue<Pending> tasks;
  uint64_t sequence = 0;
  std::atomic<bool> completed{false};
  const char *completion_output = nullptr;
};
int main(int argc, char **argv) {
  if ((argc != 5 && argc != 6) || argv[4][0] == '\0') {
    std::fprintf(stderr, "Usage: probe AOT ASSETS ICU COMPLETION_OUTPUT [BYTECODE]\n");
    return 2;
  }
  if (!FlutterEngineRunsAOTCompiledDartCode()) {
    std::fprintf(stderr, "Engine is not AOT\n");
    return 3;
  }
  Context context;
  context.completion_output = argv[4];
  FlutterEngineAOTData data = nullptr;
  FlutterEngineAOTDataSource source{};
  source.type = kFlutterEngineAOTDataSourceTypeElfPath;
  source.elf_path = argv[1];
  if (FlutterEngineCreateAOTData(&source, &data) != kSuccess)
    return 4;
  FlutterTaskRunnerDescription runner{};
  runner.struct_size = sizeof(runner);
  runner.user_data = &context;
  runner.identifier = 1;
  runner.runs_task_on_current_thread_callback = [](void *user) {
    return std::this_thread::get_id() == static_cast<Context *>(user)->platform;
  };
  runner.post_task_callback = [](FlutterTask task, uint64_t time, void *user) {
    auto &ctx = *static_cast<Context *>(user);
    {
      std::lock_guard<std::mutex> lock(ctx.mutex);
      ctx.tasks.push({time, ctx.sequence++, task});
    }
    ctx.changed.notify_one();
  };
  FlutterCustomTaskRunners runners{};
  runners.struct_size = sizeof(runners);
  runners.platform_task_runner = &runner;
  FlutterRendererConfig renderer{};
  renderer.type = kSoftware;
  renderer.software.struct_size = sizeof(renderer.software);
  renderer.software.surface_present_callback = [](void *, const void *, size_t,
                                                  size_t) { return true; };
  FlutterProjectArgs project{};
  project.struct_size = sizeof(project);
  project.assets_path = argv[2];
  project.icu_data_path = argv[3];
  project.aot_data = data;
  project.custom_task_runners = &runners;
  project.shutdown_dart_vm_when_done = true;
  project.dart_entrypoint_argc = argc == 6 ? 1 : 0;
  project.dart_entrypoint_argv =
      argc == 6 ? const_cast<const char **>(&argv[5]) : nullptr;
  project.log_message_callback = [](const char *, const char *message,
                                    void *user) {
    std::printf("%s\n", message);
    std::fflush(stdout);
    auto &ctx = *static_cast<Context *>(user);
    if (std::strcmp(message, ctx.completion_output) == 0) {
      ctx.completed = true;
      ctx.changed.notify_one();
    }
  };
  FlutterEngine engine = nullptr;
  const auto result = FlutterEngineRun(FLUTTER_ENGINE_VERSION, &renderer,
                                       &project, &context, &engine);
  if (result != kSuccess) {
    std::fprintf(stderr, "FlutterEngineRun failed: %d\n", result);
    FlutterEngineCollectAOTData(data);
    return 5;
  }
  const uint64_t deadline = FlutterEngineGetCurrentTime() + 15000000000ULL;
  bool failed = false;
  while (!context.completed && FlutterEngineGetCurrentTime() < deadline) {
    std::unique_lock<std::mutex> lock(context.mutex);
    const auto now = FlutterEngineGetCurrentTime();
    if (!context.tasks.empty() && context.tasks.top().time <= now) {
      auto pending = context.tasks.top();
      context.tasks.pop();
      lock.unlock();
      if (FlutterEngineRunTask(engine, &pending.task) != kSuccess) {
        failed = true;
        break;
      }
    } else {
      uint64_t delay =
          context.tasks.empty()
              ? 10000000ULL
              : std::min<uint64_t>(context.tasks.top().time - now, 10000000ULL);
      context.changed.wait_for(lock, std::chrono::nanoseconds(delay));
    }
  }
  const bool done = context.completed;
  const auto stopped = FlutterEngineShutdown(engine);
  const auto collected = FlutterEngineCollectAOTData(data);
  if (!done)
    std::fprintf(stderr, "No completion output before deadline\n");
  return done && !failed && stopped == kSuccess && collected == kSuccess ? 0
                                                                         : 6;
}
