buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.firebase:firebase-crashlytics-gradle:3.0.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    project.evaluationDependsOn(":app")

    // AGP 8 requires every Android module to declare a `namespace`. Some older,
    // unmaintained Flutter plugins (e.g. flutter_jailbreak_detection 1.10.0) predate
    // this and still rely on the legacy `package` attribute in their manifest, which
    // breaks configuration with "Namespace not specified". Backfill the namespace from
    // that manifest package so those plugins build. Reflection avoids needing the AGP
    // type on the root buildscript classpath. No-op for plugins that already set one.
    // Skip already-evaluated projects (e.g. :app, forced by evaluationDependsOn above) —
    // calling afterEvaluate on them throws, and they already declare a namespace anyway.
    if (state.executed) return@subprojects
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        val getNamespace = androidExt.javaClass.methods.firstOrNull { it.name == "getNamespace" }
        if (getNamespace?.invoke(androidExt) == null) {
            val manifest = file("src/main/AndroidManifest.xml")
            if (manifest.exists()) {
                val pkg = Regex("""package\s*=\s*"([^"]+)"""")
                    .find(manifest.readText())?.groupValues?.get(1)
                if (!pkg.isNullOrEmpty()) {
                    androidExt.javaClass.methods.firstOrNull { it.name == "setNamespace" }
                        ?.invoke(androidExt, pkg)
                    logger.lifecycle("Backfilled namespace '$pkg' for module ':${project.name}'")
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
