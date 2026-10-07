# Release builds are shrunk by R8. ML Kit instantiates its component registrars by reflection
# (MlKitInitProvider -> NaturalLanguageTranslateRegistrar, CommonComponentRegistrar...), so their
# no-argument constructors must survive shrinking. Without these rules ML Kit fails to initialise
# at start-up, the translation plugin throws while registering, and every translate call then
# fails with MissingPluginException (seen on a Pixel 10 Pro with Ganj 1.1.1).
#
# Kept narrow on purpose: a blanket rule over all of com.google.mlkit fixes it too, but keeping
# only the constructors leaves the shrinker free to drop whatever else it can prove unused.
-keep class * extends com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.mlkit.common.internal.MlKitInitProvider { *; }
-keep class com.google_mlkit_translation.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-dontwarn com.google.mlkit.**
