# Bottlerocket Admin Container

This is the default admin container for [Bottlerocket](https://github.com/bottlerocket-os/bottlerocket).
The admin container has an SSH server that lets you log in as ec2-user using your EC2-registered SSH key.
It runs outside of Bottlerocket's container orchestrator in a separate instance of containerd.

The admin container is disabled by default in Bottlerocket.
For more information about how the admin container fits into the Bottlerocket operating system, please see the [Bottlerocket documentation](https://github.com/bottlerocket-os/bottlerocket/blob/develop/README.md#admin-container).

## Building the Container Image

You'll need Docker 17.06.2 or later, for multi-stage build support.
Then run `make`!
