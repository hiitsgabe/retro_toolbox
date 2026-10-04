# Local changes to smb_connect 0.0.9

Vendored from https://github.com/vadia/smb_connect (Apache-2.0, see LICENSE)
because the published package has no fix for the issues below.

- `lib/src/utils/socket/socket_reader.dart` (`SocketReader2`): wait for
  incoming data with a completer instead of polling every 1 ms, and allow 60 s
  without data (was ~3 s) before failing a read. The poll made every response
  pay several timer ticks and broke transfers on short network pauses.
- `lib/src/connect/smb_random_access_file.dart` (`readFromBuffer`): block copy
  bounded by the requested length instead of a byte-by-byte loop.
- `lib/src/connect/smb_transport.dart`: set `TCP_NODELAY` on the socket
  (requests go out in pieces; with Nagle each waited on a delayed ACK, which
  doubled the time of large reads), and wait 60 s for a response (was 3 s,
  shorter than a screen-lock or Wi-Fi pause).
