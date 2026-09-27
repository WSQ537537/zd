allprojects {
    repositories {
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/gradle-plugin")
        maven("https://maven.aliyun.com/repository/public")
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
    val projectDirPath = project.projectDir.toPath()
    val rootDirPath = rootProject.projectDir.toPath()
    if (projectDirPath.startsWith(rootDirPath)) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}
// 仅保留 arm64-v8a，避免预编译 AAR 插件（jni 等）打进全部 ABI 导致 APK 体积翻倍
subprojects {
    plugins.withId("com.android.library") {
        project.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
            defaultConfig.ndk.abiFilters += listOf("arm64-v8a")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
