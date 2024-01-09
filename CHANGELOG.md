# 0.11.3

* Allow setting MACs in SSHD config. ([#91], **thanks  @mlacko64!**)

[#91]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/91

# 0.11.2

* Rebuilt to get the latest AL2 updates.

# 0.11.1

* Rebuilt to get the latest AL2 updates.

# 0.11.0

* Rebuilt to get the latest AL2 updates.
* Add sshd config update to stop unnecessary reverse lookups of incoming connections ([#85])

[#85]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/85

# 0.10.2

* Rebuilt to get the latest AL2 updates.

# 0.10.1

* Rebuilt to get the latest AL2 updates.

# 0.10.0

* Add support for running on a host with cgroup v2 (unified cgroup hierarchy) enabled. ([#76])
* Fix systemd warning about conflicting jobs when the admin container exits. ([#79])
* Pick up latest AL2 updates.

[#76]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/76
[#79]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/79

# 0.9.4

* Rebuilt to get the latest AL2 updates.

# 0.9.3

* Remove check for EC2 Instance Connect hostkey harvesting. ([#71])

[#71]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/71

# 0.9.2

* Remove `/etc/config/selinux` from image. ([#69])

[#69]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/69

# 0.9.1

* Update to the latest musl release. ([#67])

[#67]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/67

# 0.9.0

* Add support for serial console access. ([#59])
* Symlink logger with true. ([#60])

[#59]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/59
[#60]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/60

# 0.8.0

* Update bash to 5.1.16. ([#55])
* Add some art to MOTD. ([#53])
* Switch to ECR Public, fix multi-arch builds, and more. ([#54])

[#53]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/53
[#54]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/54
[#55]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/55

# 0.7.4

* Rebuilt to get the latest AL2 updates. ([#52])

[#52]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/52

# 0.7.3

* Add support for custom username. ([#45])
* Allow setting key exchange algorithms. ([#46], **thanks  @willthames!**)
* Add support for passing single commands through sheltie. ([#50])

[#45]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/45
[#46]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/46
[#50]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/50

# 0.7.2

* Add support for EC2 Instance Connect. ([#39], **thanks @samjo-nyang!**)
* Disable root login and allow for custom SSH cipher list. ([#42], **thanks  @willthames!**)

[#39]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/39
[#42]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/42

# 0.7.1

* Remove exits added to the sshd configuration script in v0.7.0. ([#33])
* Update musl to 1.2.2. ([#34])
* Pull bash and musl sources from lookaside cache, instead of from upstream. ([#35])

[#33]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/33
[#34]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/34
[#35]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/35

# 0.7.0

* Switch paths from `/.bottlerocket/host-containers/admin` to `/.bottlerocket/host-containers/current` ([#21])
* Export Bottlerocket proxy ENV variables for all login shells. ([#24])
* Add support for `user-data` settings in kebab-case (recommended default). ([#26])
* Switch from old docker build environment to docker buildkit by default. ([#14])
* Improve error handling and logging during ssh setup. ([#20])
* Fix condensed output of user data in error messages to keep intentional spaces. ([#25])
* Clean up the start sshd script to be more consistent with recent control container updates. ([#22])

[#14]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/14
[#20]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/20
[#21]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/21
[#22]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/22
[#24]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/24
[#25]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/25
[#26]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/26

# 0.6.0

* Use user-data file rather than IMDS directly to set public keys. ([#19])

[#19]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/19

# 0.5.0

* Use /proc to find the bash binary in sheltie. ([#8])

[#8]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/8

# 0.4.0

Initial release of **bottlerocket-admin-container** - the default admin container for Bottlerocket.

See the [README](README.md) for additional information.
