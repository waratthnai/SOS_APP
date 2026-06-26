# Nearby Connections SDK
-keep class com.google.android.gms.nearby.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-dontwarn com.google.android.gms.**

# Flutter engine & plugin channels
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep plugin method channel handlers
-keep class com.example.offgrid_sos.** { *; }

# Firebase (ถ้าใช้)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Kotlin coroutines / serialization
-keepclassmembers class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Play Core (Flutter deferred components — not used in this app)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
