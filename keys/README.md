# Linux release signing key

`linux-stable.asc` — публичный ключ Greg Kroah-Hartman, полученный с
keyserver.ubuntu.com и сокращённый через GnuPG export-minimal.

Fingerprint: `647F28654894E3BD457199BE38DBBDC86092693E`.
Сверен с официальной страницей https://www.kernel.org/signature.html
2026-09-23. Сборка повторно проверяет fingerprint и подпись несжатого tar.
Пользовательский keyring не используется. При смене ключа нужен отдельный
review; автоматического доверия новому ключу нет.
