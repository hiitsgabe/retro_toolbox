# Local changes to ftpconnect 2.0.10

Vendored from https://github.com/salim-lachdhaf/dartFTP (MIT, see LICENSE).

- `lib/src/ftp_socket.dart` (`readResponse`): poll the control socket every
  5 ms instead of 300 ms. Every command reply paid that wait, several times
  per downloaded file.
