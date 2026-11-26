import Toybox.Activity;
import Toybox.Application;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

typedef Font as WatchUi.FontResource or Graphics.FontDefinition;

// zzGradePlus
//  경사도 계산: 기존 zzGrade 방식 (3초 구간 고도차 ÷ 3초간 이동거리, N개 이동평균) + 개선 3가지
//   1) 매 구간 속도 3개를 정확히 누적 (기존: 첫 구간은 2개)
//   2) 재출발 후 첫 구간 값으로 필터를 채워 바로 실제 경사도 표시 (기존: 0부터 서서히 상승)
//   3) 정지 중에는 마지막 경사도 유지 (기존: 0 표시)
//  화면: 10필드 칸 / 넓은 칸 자동 전환, 글자 크기는 zzSpeedPlus·zzCadence와 동일(넓은 칸만 4자리 고도에 맞춰 축소)
//  FIT: "Grade" (FLOAT, %, record) 1초마다 기록 - 기존 zzGrade와 같은 필드
class zzGradePlusView extends WatchUi.DataField {

    // 메인 값 / 두 번째 값이 같이 쓰는 목록. 두 설정의 번호가 같다
    enum { VAL_GRADE, VAL_ALT, VAL_ASC, VAL_LAP, VAL_NONE }
    // 배경색 : 0 기기 화면색에 맞춤 (1050/1060 은 #17181D / 남색 글씨)
    //          1 기기가 알려준 검정·흰색 그대로 (기본, 지금까지의 동작)
    //          2 투명 - 배경을 칠하지 않아 기기 배경이 그대로 비친다
    enum { BG_AUTO, BG_PLAIN, BG_CLEAR }
    private const DIV = 3;                       // 3초마다 계산
    private const FIT_GRADE_FIELD_ID = 0;
    private const COLORS = [0, 0xFF0000, 0xFF55AA, 0xFF00FF, 0xFF5500, 0xFFAA00, 0x00AA00, 0x00AAFF, 0x0000FF, 0xAA00FF];

    // ---- 설정 ----
    private var _mainKind as Number = VAL_GRADE;     // 큰 글씨에 무엇을
    private var _secondKind as Number = VAL_ASC;     // 작은 글씨에 무엇을
    private var _metric as Boolean = true;
    private var _unit as String = "m";
    private var _label as String = "";
    private var _thr10 as Number = 10;           // 색 기준 (경사도 ×10), 기본 1%
    private var _dayHigh as Number = 0xFF0000, _dayLow as Number = 0x0000FF;
    private var _nightHigh as Number = 0xFF55AA, _nightLow as Number = 0x00AAFF;
    private var _colorOn as Boolean = true;
    private var _bgMode as Number = BG_PLAIN;

    // ---- 경사도 계산 상태 ----
    private var _filter as AvgFilter = new AvgFilter(3);
    private var _cnt as Number = 0;
    private var _way as Float = 0.0f;
    private var _prevAlt as Float = 0.0f;
    private var _init as Boolean = true;         // 다음 구간에서 기준 고도부터 다시 잡기
    private var _seed as Boolean = true;         // 다음 계산값으로 필터 채우기
    private var _grade10 as Number = 0;          // 경사도 ×10 (색상·FIT용)
    private var _gradeValid as Boolean = false;
    private var _fitField as FitContributor.Field? = null;

    // ---- 표시 문자열 캐시 ----
    private var _gI as String = "--", _gD as String = "", _gS as String = "--";
    private var _mainV as Number = -999999;
    private var _mainS as String = "--";
    private var _sub as Number = -999999;
    private var _subS as String = "--";
    private var _lapStart as Float = 0.0f;
    private var _ascent as Float = 0.0f;

    // ---- 레이아웃 ----
    private var _wide as Boolean = false;
    // 1050 / 1060 (화면폭 480 이상). onUpdate 에서 매번 묻지 않는다
    private var _big as Boolean = false;
    private var _titleOn as Boolean = true;
    private var _wTitle as Number = 0;          // 제목 "zzGrade+" 너비
    private var _labelW as Number = -1;         // 라벨 너비 (바뀔 때만 다시 잼)
    private var _L as Number = 0, _T as Number = 0, _R as Number = 0, _B as Number = 0;
    private var _fMain as Font = Graphics.FONT_XTINY, _fMainDec as Font = Graphics.FONT_XTINY, _fSub as Font = Graphics.FONT_XTINY;
    private var _fMain4 as Font = Graphics.FONT_XTINY;   // 경사도용 큰 글꼴과 소수점 글꼴 사이
    private var _fUnitMain as Font = Graphics.FONT_XTINY, _fUnitSub as Font = Graphics.FONT_XTINY;
    private var _fVal5 as Font = Graphics.FONT_XTINY, _fVal as Font = Graphics.FONT_XTINY, _fTitle as Font = Graphics.FONT_XTINY, _fLabel as Font = Graphics.FONT_XTINY;
    private var _c10Loaded as Boolean = false;
    private var _xMainValG as Number = 0, _xMainValA as Number = 0;   // 큰 글씨 값의 오른쪽 끝 (경사도 / 고도)
    private var _yMain as Number = 0, _yMainDec as Number = 0, _yMain4 as Number = 0;
    private var _yMainSub as Number = 0, _wMainDec as Number = 0;
    private var _xSubValG as Number = 0, _xSubValA as Number = 0;     // 작은 글씨 값의 오른쪽 끝
    private var _xSubNoUnit as Number = 0, _xSubMax4 as Number = 0;
    private var _xMainValK as Number = 0, _xSubValK as Number = 0;   // 천 단위(km / kft) 표시용
    private var _wIcon as Number = 0;           // 좌상단 산 아이콘 폭
    // 각 글꼴로 칸에 들어가는 숫자 자리수 (경사도는 길어야 3글자지만 고도는 4~5자리)
    private var _nMain as Number = 3;           // 큰 글꼴로 칸에 들어가는 자리수
    private var _nMain4 as Number = 4;          // 중간 글꼴로 들어가는 자리수 (고도 4자리용)
    private var _nMainDec as Number = 5;        // 소수점 글꼴로 들어가는 자리수
    private var _nMainSub as Number = 5;        // 가장 작은 글꼴(작은 값용)로 들어가는 자리수
    private var _nMainBare as Number = 5;       // 단위를 뺐을 때 들어가는 자리수
    private var _nSubPlain as Number = 5;       // 작은 값 자리에 단위 없이 들어가는 자리수
    private var _nVal as Number = 4;            // 넓은 칸 글꼴로 들어가는 자리수
    private var _xTitleText as Number = 0, _yLabel as Number = 0;
    private var _yVal as Number = 0, _yValSmall as Number = 0, _xc1 as Number = 0, _xc2 as Number = 0, _xcMid as Number = 0, _yDiv1 as Number = 0;

    function initialize() {
        DataField.initialize();
        readSettings();
        _fitField = createField("Grade", FIT_GRADE_FIELD_ID, FitContributor.DATA_TYPE_FLOAT,
                                { :msgType => FitContributor.MESG_TYPE_RECORD, :units => "%" });
        if (_fitField != null) { _fitField.setData(0.0f); }
    }

    // App.onSettingsChanged()에서 호출 → WatchUi.requestUpdate()
    function readSettings() as Void {
        _metric = (System.getDeviceSettings().elevationUnits == System.UNIT_METRIC);
        _unit = _metric ? "m" : "ft";

        // 배경색 : 0 기기 화면색에 맞춤, 1 검정·흰색 그대로(기본), 2 투명
        var bm = Application.Properties.getValue("bgMode");
        _bgMode = (bm instanceof Number && bm >= 0 && bm <= 2) ? bm : BG_PLAIN;

        // 메인 값(큰 글씨)과 두 번째 값(작은 글씨)을 같은 목록에서 따로 고른다.
        //  제약은 하나, 둘이 같으면 안 된다. 같으면 두 번째를 바꿔서 저장한다.
        var mv = Application.Properties.getValue("mainValue");
        var main = (mv instanceof Number && mv >= VAL_GRADE && mv <= VAL_LAP)
                 ? mv as Number : VAL_GRADE;

        var d = Application.Properties.getValue("dataType");
        var second = (d instanceof Number && d >= VAL_GRADE && d <= VAL_NONE)
                   ? d as Number : VAL_ASC;

        // 둘이 같으면 두 번째를 바꾼다 (경사도끼리면 고도로, 고도끼리면 경사도로)
        if (second == main) {
            second = (main == VAL_GRADE) ? VAL_ALT : VAL_GRADE;
        }
        _mainKind = main;
        _secondKind = second;
        // 고친 값을 저장해 설정 화면에도 그대로 보이게 한다
        if (second != d) {
            try { Application.Properties.setValue("dataType", second); }
            catch (ex) { }
        }

        var names = ["%", "ALT " + _unit, "ASC " + _unit, "LAP " + _unit, ""];
        _labelW = -1;
        _label = (_secondKind == VAL_NONE)
               ? (names[_mainKind] as String)
               : ((names[_mainKind] as String) + "  /  " + (names[_secondKind] as String));

        var n = Application.Properties.getValue("filterlen");
        var len = (n instanceof Number && n >= 1 && n <= 5) ? n : 3;
        _filter = new AvgFilter(len);
        _init = true; _seed = true;

        var t = Application.Properties.getValue("threshold");
        _thr10 = ((t instanceof Number && t >= 0) ? t : 1) * 10;

        _dayHigh   = colorAt(Application.Properties.getValue("dayHighColor"), 1);
        _dayLow    = colorAt(Application.Properties.getValue("dayLowColor"), 8);
        _nightHigh = colorAt(Application.Properties.getValue("nightHighColor"), 2);
        _nightLow  = colorAt(Application.Properties.getValue("nightLowColor"), 7);
        _colorOn = (_dayHigh != 0 || _dayLow != 0 || _nightHigh != 0 || _nightLow != 0);
        _sub = -999999; _mainV = -999999;
    }

    private function colorAt(v as Application.Properties.ValueType or Null, def as Number) as Number {
        var i = (v instanceof Number && v >= 0 && v < COLORS.size()) ? v : def;
        return COLORS[i] as Number;
    }

    // =========================================================
    // 레이아웃
    // =========================================================
    function onLayout(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight();
        var sw = System.getDeviceSettings().screenWidth;
        _wide = w > sw * 0.75f;
        _big = (sw >= 480);
        _L = (w * 0.05f + 0.5f).toNumber();
        _T = (h * 0.05f + 0.5f).toNumber();
        _R = w - _L;
        _B = h - _T;
        if (_wide) { layoutWide(dc, w, h); } else { layoutCell10(dc, w); }
    }

    private function loadCell10() as Void {
        if (!_c10Loaded) {
            _fMain     = WatchUi.loadResource(Rez.Fonts.C10Main) as WatchUi.FontResource;
            _fMainDec  = WatchUi.loadResource(Rez.Fonts.C10MainDec) as WatchUi.FontResource;
            _fMain4    = WatchUi.loadResource(Rez.Fonts.C10Main4) as WatchUi.FontResource;
            _fSub      = WatchUi.loadResource(Rez.Fonts.C10Sub) as WatchUi.FontResource;
            _fUnitMain = WatchUi.loadResource(Rez.Fonts.C10UnitMain) as WatchUi.FontResource;
            _fUnitSub  = WatchUi.loadResource(Rez.Fonts.C10UnitSub) as WatchUi.FontResource;
            _c10Loaded = true;
        }
    }

    private function layoutCell10(dc as Graphics.Dc, w as Number) as Void {
        _fVal = Graphics.FONT_XTINY; _fVal5 = Graphics.FONT_XTINY; _fTitle = Graphics.FONT_XTINY; _fLabel = Graphics.FONT_XTINY;
        loadCell10();
        var ug = (w * 0.02f).toNumber(); if (ug < 2) { ug = 2; }
        var aMain = Graphics.getFontAscent(_fMain);
        _yMain    = _B - aMain;
        _yMainDec = _yMain + aMain - Graphics.getFontAscent(_fMainDec);
        _yMain4   = _yMain + aMain - Graphics.getFontAscent(_fMain4);   // 바닥선 맞춤
        _yMainSub = _yMain + aMain - Graphics.getFontAscent(_fSub);
        // 설정이 바뀌어도 onLayout 이 다시 불리지 않을 수 있어, 두 경우를 모두 계산해 둔다
        _xMainValG = _R - dc.getTextWidthInPixels("%", _fUnitMain) - ug;
        _xMainValA = _R - maxUnitW(dc, _fUnitMain) - ug;
        _wMainDec = dc.getTextWidthInPixels(".0", _fMainDec);
        // 큰 글씨 자리에 고도가 들어갈 때 몇 자리까지 칸에 들어가는가
        _nMain    = fitDigits(dc, _fMain,    _xMainValA - _L);
        _nMain4   = fitDigits(dc, _fMain4,   _xMainValA - _L);
        _nMainDec = fitDigits(dc, _fMainDec, _xMainValA - _L);
        _nMainSub  = fitDigits(dc, _fSub, _xMainValA - _L);
        _nMainBare = fitDigits(dc, _fSub, _R - _L);          // 단위를 숨겼을 때
        _xMainValK = _R - kiloUnitW(dc, _fUnitMain) - ug;
        var uw = maxUnitW(dc, _fUnitSub);
        _xSubValA   = _R - uw - ug;                  // 단위 표시할 때 값의 오른쪽 끝
        _xSubValG   = _R - dc.getTextWidthInPixels("%", _fUnitSub) - ug;
        _xSubNoUnit = _R;                            // 단위를 숨길 때
        // 이 폭 안에 4자리+단위가 들어가는지 (안 들어가면 4자리 이상은 단위 숨김)
        _xSubMax4 = _xSubValA - dc.getTextWidthInPixels("8888", _fSub) - dc.getTextWidthInPixels("@", _fSub);
        _nSubPlain = fitDigits(dc, _fSub, _R - _L);
        _wIcon = dc.getTextWidthInPixels("@", _fSub);
        _xSubValK  = _R - kiloUnitW(dc, _fUnitSub) - ug;
    }

    // 단위는 설정에 따라 "m" 또는 "ft" 이므로 넓은 쪽을 기준으로 자리를 비워둔다
    private function maxUnitW(dc as Graphics.Dc, f as Font) as Number {
        var a = dc.getTextWidthInPixels("ft", f);
        var b = dc.getTextWidthInPixels("m", f);
        return (b > a) ? b : a;
    }

    // 천 단위 단위 글자 ("km" 또는 "kft") 중 넓은 쪽
    private function kiloUnitW(dc as Graphics.Dc, f as Font) as Number {
        var a = dc.getTextWidthInPixels("km", f);
        var b = dc.getTextWidthInPixels("kft", f);
        return (b > a) ? b : a;
    }

    // 1만이 넘어 칸에 안 들어갈 때 12345 -> "12.3" (단위는 km / kft)
    private function kiloStr(v as Number) as String {
        var a = (v < 0) ? -v : v;
        return ((v < 0) ? "-" : "") + (a / 1000).toString() + "." + ((a % 1000) / 100).toString();
    }

    // avail 폭에 그 글꼴로 숫자가 몇 자리 들어가는지
    private function fitDigits(dc as Graphics.Dc, f as Font, avail as Number) as Number {
        var w = dc.getTextWidthInPixels("8888", f);
        if (w <= 0) { return 99; }
        var n = (avail * 4) / w;
        return (n < 1) ? 1 : n;
    }

    private function layoutWide(dc as Graphics.Dc, w as Number, h as Number) as Void {
        _fMainDec = Graphics.FONT_XTINY; _fMain4 = Graphics.FONT_XTINY;
        _fUnitMain = Graphics.FONT_XTINY; _fUnitSub = Graphics.FONT_XTINY;
        _c10Loaded = false;
        _fTitle = WatchUi.loadResource(Rez.Fonts.WideTitle) as WatchUi.FontResource;
        _fLabel = WatchUi.loadResource(Rez.Fonts.WideLabel) as WatchUi.FontResource;
        var fv  = WatchUi.loadResource(Rez.Fonts.WideVal) as WatchUi.FontResource;
        _fVal5  = WatchUi.loadResource(Rez.Fonts.WideVal5) as WatchUi.FontResource; // 5자리(1만 이상) 전용

        var gap = (w * 0.04f).toNumber(); if (gap < 4) { gap = 4; }
        var vg  = (h * 0.05f).toNumber(); if (vg < 2) { vg = 2; }
        var hTitle = Graphics.getFontHeight(_fTitle);
        var hu = _B - _T;
        _titleOn = (hu - hTitle - vg) >= Graphics.getFontAscent(fv);
        if (_titleOn) {
            _fVal = fv; _fMain = Graphics.FONT_XTINY;
        } else {
            _fTitle = Graphics.FONT_XTINY; _fLabel = Graphics.FONT_XTINY;
            if (Graphics.getFontAscent(fv) <= hu) { _fVal = fv; _fMain = Graphics.FONT_XTINY; }
            else { _fMain = WatchUi.loadResource(Rez.Fonts.C10Main) as WatchUi.FontResource; _fVal = _fMain; }
        }
        var top = _T;
        if (_titleOn) {
            _xTitleText = _L + dc.getTextWidthInPixels("@", _fTitle);
            _wTitle = dc.getTextWidthInPixels("zzGrade+", _fTitle);
            _yLabel = _T + Graphics.getFontAscent(_fTitle) - Graphics.getFontAscent(_fLabel);
            top = _T + hTitle + vg;
        }
        var aVal = Graphics.getFontAscent(_fVal);
        _yVal      = top + (_B - top - aVal) / 2;
        _yValSmall = _yVal + aVal - Graphics.getFontAscent(_fVal5);  // 5자리 폰트도 같은 바닥선
        _yDiv1 = top;
        var mid = w / 2;
        _xc1 = (_L + mid - gap / 2) / 2;
        _xc2 = (mid + gap / 2 + _R) / 2;
        _xcMid = mid;
        // 두 값이 나란히 설 때 한쪽에 주어지는 폭
        var half = (mid - gap / 2) - _L;
        _nVal = fitDigits(dc, _fVal, half);
    }

    // =========================================================
    // 계산
    // =========================================================
    function onTimerLap() as Void { _lapStart = _ascent; }

    function onTimerReset() as Void {
        _lapStart = 0.0f; _ascent = 0.0f;
        _init = true; _seed = true; _cnt = 0; _way = 0.0f;
    }

    function compute(info as Activity.Info) as Void {
        var alt = info.altitude;
        var asc = info.totalAscent;
        _ascent = (asc != null) ? asc.toFloat() : 0.0f;

        // ---- 경사도 ----
        if (alt == null) {
            _init = true; _seed = true; _gradeValid = false;
            setGradeText();
        } else {
            updateGrade(info.currentSpeed, alt);
        }
        if (_fitField != null) { _fitField.setData(_gradeValid ? _grade10 / 10.0f : 0.0f); }

        // ---- 고도 계열 값 (m 또는 ft, 정수). 두 자리 각각 따로 계산한다 ----
        if (_mainKind != VAL_GRADE) {
            var im = altValue(_mainKind, alt);
            if (im != _mainV) { _mainV = im; _mainS = (im == -999998) ? "--" : im.toString(); }
        }
        if (_secondKind != VAL_GRADE && _secondKind != VAL_NONE) {
            var iv = altValue(_secondKind, alt);
            if (iv != _sub) { _sub = iv; _subS = (iv == -999998) ? "--" : iv.toString(); }
        }
    }

    // 고도 / 총 획득고도 / Lap 획득고도 를 표시 단위의 정수로
    private function altValue(kind as Number, alt as Float?) as Number {
        var v = null as Float?;
        if (kind == VAL_ALT)      { v = (alt != null) ? alt.toFloat() : null; }
        else if (kind == VAL_ASC) { v = _ascent; }
        else                      { v = _ascent - _lapStart; }
        if (v == null) { return -999998; }
        return (_metric ? v : v * 3.28084f).toNumber();
    }

    private function updateGrade(spd as Float?, alt as Float) as Void {
        var s = (spd == null) ? 0.0f : spd;
        _way += s; _cnt += 1;
        if (_cnt < DIV) { return; }                 // 3초 모일 때까지 이전 값 유지
        var way = _way;
        _way = 0.0f; _cnt = 0;

        // 정지/저속: 마지막 경사도 유지, 다음 이동 때 기준 고도부터 다시 시작 (개선 3)
        if (way < 3.0f || s < 0.5f) { _init = true; _seed = true; return; }

        if (_init) { _prevAlt = alt; _init = false; return; }   // 이번 구간은 기준 고도만 잡음
        var g = (alt - _prevAlt) / way;             // 고도차 ÷ 이동거리 (비율)
        _prevAlt = alt;

        var gf;
        if (_seed) { _filter.reset(g); gf = g; _seed = false; }   // 개선 2: 첫 값으로 필터 채움
        else       { gf = _filter.push(g); }

        if (gf.abs() >= 0.5f) { return; }           // ±50% 이상은 버리고 이전 값 유지
        _grade10 = (gf * 1000.0f + (gf < 0 ? -0.5f : 0.5f)).toNumber();   // % ×10, 반올림
        _gradeValid = true;
        setGradeText();
    }

    // 10% 미만은 소수 한 자리, 10% 이상은 정수
    private function setGradeText() as Void {
        if (!_gradeValid) { _gI = "--"; _gD = ""; _gS = "--"; return; }
        var a = _grade10.abs();
        var sign = (_grade10 < 0) ? "-" : "";
        if (a < 100) { _gI = sign + (a / 10).toString(); _gD = "." + (a % 10); }
        else         { _gI = sign + ((a + 5) / 10).toString(); _gD = ""; }
        _gS = _gI + _gD;
    }

    // =========================================================
    // 그리기
    // =========================================================
    function onUpdate(dc as Graphics.Dc) as Void {
        var sys = getBackgroundColor();
        var sysClear = (sys == Graphics.COLOR_TRANSPARENT);   // 기기가 "투명"이라고 알려준 경우
        var night = (sys == Graphics.COLOR_BLACK || sysClear);
        var soft = (_bgMode == BG_AUTO) && _big;   // _big = 1050 / 1060
        var fg = night ? Graphics.COLOR_WHITE
                       : (soft ? 0x313152 : Graphics.COLOR_BLACK);
        var bg = night ? (soft ? 0x17181D : Graphics.COLOR_BLACK)
                       : (soft ? 0xDCDCDC : Graphics.COLOR_WHITE);   // 밝은 배경도 순백이 아니다
        // 투명 : 아예 칠하지 않아 기기 배경이 그대로 비친다 (테마가 무엇이든 일치)
        if (_bgMode == BG_CLEAR || (_bgMode == BG_AUTO && sysClear)) {
            bg = Graphics.COLOR_TRANSPARENT;
        }
        dc.setColor(fg, bg);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        var mc = 0;
        if (_colorOn && _gradeValid) {
            if (_grade10 > _thr10)       { mc = night ? _nightHigh : _dayHigh; }
            else if (_grade10 < -_thr10) { mc = night ? _nightLow : _dayLow; }
        }
        if (mc == 0) { mc = fg; }
        var ic = night ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GREEN;
        if (_wide) { drawWide(dc, fg, mc, ic); } else { drawCell10(dc, fg, mc, ic); }
    }

    private function drawCell10(dc as Graphics.Dc, fg as Number, mc as Number, ic as Number) as Void {
        // 아래쪽(큰 글씨)
        if (_mainKind == VAL_GRADE) {
            dc.setColor(mc, Graphics.COLOR_TRANSPARENT);
            var x = _xMainValG;
            if (_gD.length() > 0) {
                dc.drawText(x, _yMainDec, _fMainDec, _gD, Graphics.TEXT_JUSTIFY_RIGHT);
                x -= _wMainDec;
            }
            dc.drawText(x, _yMain, _fMain, _gI, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_R, _yMain, _fUnitMain, "%", Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            // 칸에 맞게: 단위와 같이 -> 단위 숨김 -> 천 단위 (12345 m -> 12.3 km)
            var s = _mainS;
            var u = _unit;
            var xa = _xMainValA;
            var n = s.length();
            if (n > _nMainSub) {
                if (n <= _nMainBare) {
                    u = "";                     // 단위를 빼면 숫자가 그대로 들어간다
                    xa = _R;
                } else {
                    s = kiloStr(_mainV);
                    u = _metric ? "km" : "kft";
                    xa = _xMainValK;
                    n = s.length();
                }
            }
            // 칸에 들어가는 가장 큰 글꼴을 쓴다 (경사도용 > 4자리용 > 소수점용 > 작은값용)
            if (n <= _nMain) {
                dc.drawText(xa, _yMain, _fMain, s, Graphics.TEXT_JUSTIFY_RIGHT);
            } else if (n <= _nMain4) {
                dc.drawText(xa, _yMain4, _fMain4, s, Graphics.TEXT_JUSTIFY_RIGHT);
            } else if (n <= _nMainDec) {
                dc.drawText(xa, _yMainDec, _fMainDec, s, Graphics.TEXT_JUSTIFY_RIGHT);
            } else {
                dc.drawText(xa, _yMainSub, _fSub, s, Graphics.TEXT_JUSTIFY_RIGHT);
            }
            if (!u.equals("")) {
                dc.drawText(_R, _yMain, _fUnitMain, u, Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }

        // 위쪽: 아이콘 + 작은 값
        var topS = (_secondKind == VAL_GRADE) ? _gS
                 : ((_secondKind == VAL_NONE) ? "" : _subS);
        // 값이 왼쪽까지 밀고 들어오면 아이콘을 생략한다
        if ((_R - dc.getTextWidthInPixels(topS, _fSub)) > (_L + _wIcon)) {
            dc.setColor(ic, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_L, _T, _fSub, "@", Graphics.TEXT_JUSTIFY_LEFT);
        }
        if (_secondKind == VAL_NONE) { return; }
        if (_secondKind == VAL_GRADE) {
            dc.setColor(mc, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_xSubValG, _T, _fSub, _gS, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_R, _T, _fUnitSub, "%", Graphics.TEXT_JUSTIFY_RIGHT);
            return;
        }
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        if (topS.length() > _nSubPlain) {        // 단위를 빼도 안 들어가면 천 단위로
            dc.drawText(_xSubValK, _T, _fSub, kiloStr(_sub), Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(_R, _T, _fUnitSub, _metric ? "km" : "kft", Graphics.TEXT_JUSTIFY_RIGHT);
            return;
        }
        var showUnit = (topS.length() < 4) || (_xSubMax4 >= _L);   // 4자리 이상은 칸에 들어갈 때만 단위 표시
        if (showUnit) {
            dc.drawText(_xSubValA, _T, _fSub, _subS, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(_R, _T, _fUnitSub, _unit, Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            dc.drawText(_xSubNoUnit, _T, _fSub, _subS, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    private function drawWide(dc as Graphics.Dc, fg as Number, mc as Number, ic as Number) as Void {
        if (_titleOn) {
            dc.setColor(ic, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_L, _T, _fTitle, "@", Graphics.TEXT_JUSTIFY_LEFT);
            if (_labelW < 0) { _labelW = dc.getTextWidthInPixels(_label, _fLabel); }
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_R, _yLabel, _fLabel, _label, Graphics.TEXT_JUSTIFY_RIGHT);
            // 라벨이 길어 제목과 겹치면 제목을 생략한다
            if (_xTitleText + _wTitle + 6 <= _R - _labelW) {
                dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
                dc.drawText(_xTitleText, _T, _fTitle, "zzGrade+", Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
        var mainIsGrade = (_mainKind == VAL_GRADE);
        var mainS = mainIsGrade ? _gS : _mainS;
        if (_secondKind == VAL_NONE) {               // 값이 하나뿐이면 가운데에
            drawWideVal(dc, _xcMid, mainS, mainIsGrade ? mc : fg);
            return;
        }
        // 왼쪽이 메인 값, 오른쪽이 두 번째 값. 경사도 쪽에만 오르막·내리막 색이 붙는다
        var secondIsGrade = (_secondKind == VAL_GRADE);
        drawWideVal(dc, _xc1, mainS, mainIsGrade ? mc : fg);
        drawWideVal(dc, _xc2, secondIsGrade ? _gS : _subS, secondIsGrade ? mc : fg);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_xcMid, _yDiv1, _xcMid, _B);
    }

    private function drawWideVal(dc as Graphics.Dc, x as Number, v as String, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        if (v.length() > _nVal) {                   // 칸을 넘으면 한 단계 작은 글씨
            dc.drawText(x, _yValSmall, _fVal5, v, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(x, _yVal, _fVal, v, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

// 이동평균 필터 (기존 DataFieldUtils.AvgFilter와 같은 동작, 결과는 비율 그대로)
class AvgFilter {
    private var _n as Number;
    private var _buf as Array<Float>;
    private var _ptr as Number = 0;
    private var _sum as Float = 0.0f;

    function initialize(len as Number) {
        _n = (len > 0) ? len : 1;
        _buf = new Array<Float>[_n];
        reset(0.0f);
    }

    function reset(v as Float) as Void {
        for (var i = 0; i < _n; i++) { _buf[i] = v; }
        _sum = v * _n; _ptr = 0;
    }

    function push(x as Float) as Float {
        _sum = _sum - _buf[_ptr] + x;
        _buf[_ptr] = x;
        _ptr = (_ptr + 1) % _n;
        return _sum / _n;
    }
}
