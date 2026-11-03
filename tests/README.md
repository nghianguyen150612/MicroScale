# P001 validation

`scripts/verify.sh` checks ELF architecture, executable permission, stripped debug sections, binary size and delta against the supplied baseline, and CLI/daemon version commands on a matching Linux host. CI runs executable smoke tests on its native Linux AMD64 build and checks the Linux ARM64 artifact's format and size. Hardware VPN behavior is not tested in P001.
