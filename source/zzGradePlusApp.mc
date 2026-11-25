import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class zzGradePlusApp extends Application.AppBase {
    private var _view as zzGradePlusView?;

    function initialize() { AppBase.initialize(); }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new zzGradePlusView();
        return [_view];
    }

    function onSettingsChanged() as Void {
        if (_view != null) { _view.readSettings(); }
        WatchUi.requestUpdate();
    }
}
