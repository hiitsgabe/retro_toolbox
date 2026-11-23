/// Whether this build launches games: Android or desktop, but neither the
/// PortMaster handheld nor the Docker server, which both report Linux.
bool launcherSupported({required bool isAndroid, required bool isDesktop, required bool handheld, required bool server}) =>
    (isAndroid || isDesktop) && !handheld && !server;
