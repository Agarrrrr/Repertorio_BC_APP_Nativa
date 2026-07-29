allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val proj = this
    fun configureNamespace() {
        if (proj.plugins.hasPlugin("com.android.library")) {
            val androidExtension = proj.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            if (androidExtension != null && androidExtension.namespace == null) {
                androidExtension.namespace = "com.example.${proj.name.replace("-", "_").replace(" ", "_")}"
            }
        }
    }
    if (proj.state.executed) {
        configureNamespace()
    } else {
        proj.afterEvaluate { configureNamespace() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
