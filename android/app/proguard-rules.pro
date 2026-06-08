# Bixolon Label Printer SDK
-keep class com.bixolon.labelprinter.** { *; }
-keep class com.bxl.** { *; }
-dontwarn com.bixolon.labelprinter.**
-dontwarn com.bxl.**

# Keep native methods (JNI)
-keepclasseswithmembernames class * {
    native <methods>;
}
