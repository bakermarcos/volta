import 'room_service.dart';

void initializeBrowserPlatform() {}
bool get canHostBrowserRoom => false;
Future<RoomHost> connectBrowserRoom() =>
    Future.error(UnsupportedError('Browser relay unavailable'));
String? readBrowserHistory() => null;
void writeBrowserHistory(String contents) {}
Future<void> setBrowserFullscreen(bool enabled) async {}

void syncBrowserHistory(RoomHost room, Map<String, Object> history) {}
