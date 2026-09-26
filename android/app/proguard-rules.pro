# Flutter 引擎与 Dart 运行时
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class androidx.lifecycle.** { *; }

# sqflite / path_provider / shared_preferences 等插件的 JNI 回调
-keepclassmembers class ** { @android.webkit.JavascriptInterface <methods>; }
-keep class com.tekartik.sqflite.** { *; }

# excel 包（archive/collection 依赖图较大，保留注解元数据避免反射失败）
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# flutter_local_notifications 反序列化所需要的构造函数
-keepclassmembers class * {
    public <init>(android.content.Context);
}
-dontwarn org.apache.commons.compress.**

# Flutter 引擎的延迟组件（deferred components）会引用 Play Core，
# 本项目未接入动态交付，相关类在类路径上不存在，需显式抑制告警
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
