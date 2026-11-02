# 07 — Result of the simplification

| | Big-Mount 2.6 | Big-Mount 3.0 |
| --- | --- | --- |
| Responsibility | automount + drive manager, diagnosis, removal, rescue, Secure Erase, notifier, GTK application | automount |
| Installed files | 45 | 7 |
| Installed size | 803 KB | 41 KB |
| Dependencies | 13 | 3 |
| Boot path (`/usr/bin/bigmount` without options) | — | identical code (only comments changed) |
| Code loaded at boot | `bigmount` | `bigmount` (unchanged) |
| Processes left after boot | FUSE daemons of NTFS volumes | the same |
| `bigmount --help` | 7 ms | 3 ms |
| Translations (pt_BR) | 1231 messages | 66 |
| Tests in CI | 7 suites, GTK on Broadway | 3 suites, bash and gettext only |

Times are the best of six runs on the development machine.

The boot time itself is not changed by the split, because the code that runs
at boot is the same; it was measured for 2.x in
`docs/history/08-performance.md` and `docs/history/11-final-report.md` (716 ms
for three internal partitions on a real boot).

## Not verified here

- A real boot with this package installed, and `pacman -U` of both packages
  together: the development machine had a GNU ddrescue recovery running
  through the installed Big-Mount 2.6, and replacing its files during that job
  was avoided on purpose. Run `tests/manual-check.sh` after installing.
- `tests/bench.sh` on real devices, for the same reason.
