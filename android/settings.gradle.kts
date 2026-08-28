// 책갈피 Android — Hotwire Native 셸
// 저장소는 명시적으로 고정한다(P4 재현 가능한 빌드). 동적 버전(`1.+`, `latest.release`)은 쓰지 않는다.
pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "chaekgalpi"
include(":app")
