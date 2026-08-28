// 루트 빌드 스크립트. 플러그인 버전은 여기서 한 번만 고정하고 모듈은 `apply false` 로 받는다.
//   AGP 8.13.2 는 Gradle 8.13+ 를 요구한다(래퍼는 8.14.5 로 고정).
//   Kotlin 2.3.0 은 dev.hotwire:core:1.3.1 이 가져오는 kotlin-stdlib 2.3.0 에 맞춘 값이다.
//   버전을 올릴 때는 셋을 함께 검토한다(AGP · Gradle wrapper · Kotlin).
plugins {
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.3.0" apply false
}
