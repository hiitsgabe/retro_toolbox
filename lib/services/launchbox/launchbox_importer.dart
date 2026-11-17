import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'launchbox_parser.dart';
import 'launchbox_store.dart';

const launchboxMetadataUrl = 'https://gamesdb.launchbox-app.com/Metadata.zip';

enum LaunchboxImportResult { updated, upToDate }

/// Downloads LaunchBox's Metadata.zip and keeps the requested platforms in
/// [store]. Nothing in the store changes until the parse has finished, so a
/// failed or cancelled import leaves the previous one working.
class LaunchboxImporter {
  LaunchboxImporter({required this.store, required this.cacheDir, this.url = launchboxMetadataUrl});

  final LaunchboxStore store;

  /// Where the zip is downloaded; it never stays there after [run].
  final Directory cacheDir;
  final String url;

  /// Brings the store up to date for [platforms]. [onProgress] gets
  /// (done, total) in permille units: the download fills 0..500, the parse
  /// 500..1000. It may throw to cancel; the exception propagates after the
  /// zip is deleted and any parse isolate is killed.
  Future<LaunchboxImportResult> run(Set<String> platforms, {required void Function(int done, int total) onProgress}) async {
    var reported = -1;
    void report(int done) {
      if (done <= reported) return;
      reported = done;
      onProgress(done, 1000);
    }

    final part = File('${cacheDir.path}/launchbox_Metadata.zip.part');
    final zip = File('${cacheDir.path}/launchbox_Metadata.zip');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    final port = ReceivePort();
    Isolate? isolate;
    try {
      final manifest = await store.readManifest();
      final request = await client.getUrl(Uri.parse(url));
      // The ETag only says the zip has not changed; a platform the last import
      // did not keep is still missing, so then it has to be downloaded again.
      final etag = manifest?.etag;
      if (etag != null && manifest!.platforms.containsAll(platforms)) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      // A captive portal can accept the connection and never answer.
      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode == HttpStatus.notModified) return LaunchboxImportResult.upToDate;
      if (response.statusCode != HttpStatus.ok) throw HttpException('LaunchBox answered HTTP ${response.statusCode}');

      await cacheDir.create(recursive: true);
      final total = response.contentLength;
      var received = 0;
      report(0);
      final sink = part.openWrite();
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) report(500 * received ~/ total);
        }
      } finally {
        await sink.close();
      }
      await part.rename(zip.path);
      report(500);

      // One port carries everything, so the result or error always arrives
      // before the exit notice: a double is progress, a map the result, a list
      // an error (ours or the isolate's own uncaught one), null the exit.
      final parsed = Completer<Map<String, List<int>>>();
      port.listen((message) {
        if (parsed.isCompleted) return;
        try {
          switch (message) {
            // Up to 990: the isolate still encodes after its last report, so
            // the 1000 below is a separate call and the last cancel point
            // before anything is written.
            case double fraction:
              report(500 + (fraction * 490).floor());
            case Map<String, List<int>> result:
              parsed.complete(result);
            case [final Object error, final String? stack]:
              parsed.completeError(error is String ? RemoteError(error, stack ?? '') : error, StackTrace.fromString(stack ?? ''));
            case null:
              parsed.completeError(StateError('The LaunchBox parse stopped without a result'));
          }
        } catch (e, st) {
          parsed.completeError(e, st);
        }
      });
      isolate = await Isolate.spawn(
        _parseInIsolate,
        (port.sendPort, zip.path, platforms),
        onError: port.sendPort,
        onExit: port.sendPort,
      );
      final files = await parsed.future;
      report(1000);

      for (final platform in platforms) {
        await store.writePlatformBytes(platform, files[platform]!);
      }
      // Last, so a manifest on disk always names complete files.
      await store.writeManifest(
        LaunchboxManifest(
          etag: response.headers.value(HttpHeaders.etagHeader),
          importedAt: DateTime.now().toUtc(),
          platforms: {...platforms},
        ),
      );
      return LaunchboxImportResult.updated;
    } finally {
      isolate?.kill(priority: Isolate.immediate);
      port.close();
      client.close(force: true);
      for (final f in [part, zip]) {
        try {
          if (await f.exists()) await f.delete();
        } on FileSystemException {
          // Best effort: the cache dir is the OS's to clear.
        }
      }
    }
  }
}

/// Parses and gzip-encodes here, so the main isolate only writes bytes.
Future<void> _parseInIsolate((SendPort, String, Set<String>) args) async {
  final (out, zipPath, platforms) = args;
  try {
    final games = await parseLaunchboxZip(zipPath, platforms, onProgress: out.send);
    out.send(<String, List<int>>{for (final e in games.entries) e.key: LaunchboxStore.encodePlatform(e.value)});
  } catch (e, st) {
    out.send([e, '$st']);
  }
}
