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
