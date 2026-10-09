# Keep pointycastle/ed25519 primitives (reflection-free, but be safe with R8)
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Flutter plugin linkage
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
