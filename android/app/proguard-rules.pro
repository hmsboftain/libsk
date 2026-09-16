-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivity$g
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Args
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Error
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningEphemeralKeyProvider
-dontwarn kotlinx.parcelize.Parceler$DefaultImpls
-dontwarn kotlinx.parcelize.Parceler
-dontwarn kotlinx.parcelize.Parcelize
# Keep Stripe classes
-keep class com.stripe.** { *; }

# androidx.window optional foldable/rear-display API surface. These extension
# classes are referenced reflectively by androidx.window's reflection guards but
# are absent at runtime on standard (non-foldable) devices, so R8 flags them as
# missing. Suppressing the warning is safe — the code path is never exercised on
# devices that lack the extension. Rule suggested by R8 in
# build/outputs/mapping/release/missing_rules.txt.
-dontwarn androidx.window.extensions.area.ExtensionWindowAreaPresentation