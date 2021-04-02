# 0.6.1

* Fix condensed output of user data in error messages to keep intentional spaces. ([#25])
* Export Bottlerocket proxy ENV variables for all login shells. ([#24])
* Clean up the start sshd script to be more consistent with recent control container updates. ([#22])
* Switch paths from `/.bottlerocket/host-containers/admin` to `/.bottlerocket/host-containers/current` ([#21])
* Improve error handling and logging during ssh setup. ([#20])
* Switch from old docker build environment to docker buildkit by default. ([#14])

[#25]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/25
[#24]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/24
[#22]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/22
[#21]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/21
[#20]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/20
[#14]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/14

# 0.6.0

* Use user-data file rather than IMDS directly to set public keys. ([#19])

[#19]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/19

# 0.5.0

* Use /proc to find the bash binary in sheltie. ([#8])

[#8]: https://github.com/bottlerocket-os/bottlerocket-admin-container/pull/8

# 0.4.0

Initial release of **bottlerocket-admin-container** - the default admin container for Bottlerocket.

See the [README](README.md) for additional information.
