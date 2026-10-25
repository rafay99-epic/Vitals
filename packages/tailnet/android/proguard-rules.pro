# The Go side of the gomobile bindings calls these Java classes by name over JNI.
# If R8 renames or strips them, the app aborts with "failed to find method Seq.getRef"
# the moment built-in Tailscale starts.
-keep class go.** { *; }
-keep class dev.vitals.** { *; }
# Drop transfers call back into the Kotlin listener from Go threads by interface method name.
-keep class * implements dev.vitals.tailnet.DropListener { *; }
