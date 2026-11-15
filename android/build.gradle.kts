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

// serious_python_android downloads one Python dist per ABI with
// gradle-download-task. Those tasks run in parallel and, by default, share one
// etags.json whose lock is per task, so concurrent writes can corrupt it and
// fail the build ("Unable to determine the current character ... '^@'").
// Give each download task its own ETag cache file.
subprojects {
    if (name == "serious_python_android") {
        plugins.withId("de.undercouch.download") {
            tasks.matching { it.name.startsWith("download") }.configureEach {
                val etags = project.layout.buildDirectory.file("gradle-download-task/etags-$name.json").get().asFile
                withGroovyBuilder { "cachedETagsFile"(etags) }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
