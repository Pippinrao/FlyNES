# SQLite amalgamation

Version: **3.53.4**. Only `sqlite3.c` and `sqlite3.h` are vendored.

Source archive: https://www.sqlite.org/2026/sqlite-amalgamation-3530400.zip

Archive SHA3-256:
`628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e`

Downloaded 2026-09-28 and checked using Python `hashlib.sha3_256` against the
hash published on https://www.sqlite.org/download.html. There is no build-time
network fetch. SQLite is in the public domain; see the notices at the beginning
of both vendored source files and https://www.sqlite.org/copyright.html.

Build defines `SQLITE_THREADSAFE=1`, `SQLITE_OMIT_LOAD_EXTENSION`, and
`SQLITE_DQS=0`. SQLite headers are private to this library. The SQLite objects
are included in the static archive; consumers do not need a SQLite installation.
