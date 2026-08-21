allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Some Flutter plugins still hardcode JVM target 1.8 in their own build.gradle
// (home_widget 0.9.1 does) while depending on AndroidX artifacts compiled for
// JVM 11+, which breaks Kotlin inlining:
//   "Cannot inline bytecode built with JVM target 11 into bytecode that is
//    being built with JVM target 1.8"
// Raise every plugin module to the same JVM target the app module uses. Java
// and Kotlin must be raised together or AGP fails its jvm-target consistency
// check.
//
// This must be declared before the evaluationDependsOn(":app") block below:
// that block evaluates :app eagerly, and afterEvaluate cannot be registered on
// an already-evaluated project.
subprojects {
    afterEvaluate {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
            ?.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>()
            .configureEach {
                compilerOptions.jvmTarget.set(
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
                )
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
