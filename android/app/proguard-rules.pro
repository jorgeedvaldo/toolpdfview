# Flutter and its plugins ship their own consumer rules; these only cover the
# bits R8 cannot see because they are reached through platform channels.
-keep class com.toolodfview.app.** { *; }

# pdfrx loads pdfium through dart:ffi, nothing on the JVM side to keep, but the
# Play Core split-install stubs referenced by the Flutter embedding are optional.
-dontwarn com.google.android.play.core.**
