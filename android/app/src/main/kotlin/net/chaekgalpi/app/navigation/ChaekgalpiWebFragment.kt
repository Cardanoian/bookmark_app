package net.chaekgalpi.app.navigation

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.widget.Toolbar
import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireWebFragment
import net.chaekgalpi.app.R

/**
 * 기본 웹 화면. 공식 [HotwireWebFragment] 를 그대로 쓰되 **네이티브 AppBar 만** 제거한다.
 *
 * Rails 가 렌더하는 노란 브랜드 헤더가 이미 제목·내비게이션을 담당하므로 네이티브 툴바가 함께 뜨면
 * 화면 위쪽에 헤더가 두 겹으로 보인다.
 *
 * 주의: 레이아웃에서 AppBar 만 걷어내고 `@layout/hotwire_view` include 는 **유지**한다.
 * 그 안에 WebView 컨테이너뿐 아니라 로딩 progress 와 오류 화면이 들어 있어서,
 * 통째로 교체하면 툴바와 함께 오류·재시도 UI 까지 사라진다.
 *
 * Hotwire 내부 클래스를 복사하지 않고 공식 확장 지점(Fragment subclassing)만 쓴다.
 */
@HotwireDestinationDeepLink(uri = "hotwire://fragment/web")
class ChaekgalpiWebFragment : HotwireWebFragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return inflater.inflate(R.layout.fragment_chaekgalpi_web, container, false)
    }

    /**
     * 네이티브 툴바가 없으므로 null 을 돌려준다. Hotwire 는 이 값이 없으면 툴바 연동(제목 표시·
     * 뒤로가기 버튼)을 건너뛰고, **Android 시스템 뒤로가기와 내비게이션 스택은 그대로 동작한다.**
     */
    override fun toolbarForNavigation(): Toolbar? = null
}
