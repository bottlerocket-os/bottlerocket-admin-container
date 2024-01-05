# Bottlerocket Admin Container

This is the admin container for troubleshooting the [Bottlerocket](https://github.com/bottlerocket-os/bottlerocket) operating system.
It runs outside of Bottlerocket's container orchestrator in a separate instance of `containerd`.
The container hosts an SSH server to allow public key SSH access, as well as `agetty` services for serial console devices to allow console access.
You can also connect to the admin container via the control container by running `enter-admin-container`.
Unless otherwise specified through user-data, the default user is **ec2-user**.

The admin container is disabled by default in Bottlerocket.
For more information about how the admin container fits into the Bottlerocket operating system, please see the [Bottlerocket documentation](https://github.com/bottlerocket-os/bottlerocket/blob/develop/README.md#admin-container).

## Building the Container Image

You'll need Docker 20.10 or later for multi-stage build, BuildKit, and chmod on COPY/ADD support.
Then run `make`!

## Authenticating with the Admin Container

Starting from v0.6.0, users have the option to pass in their own ssh keys rather than the admin container relying on the AWS instance metadata service (IMDS).

Users can add their own keys by populating the admin container's user-data with a base64-encoded JSON block.
If user-data is populated then Bottlerocket will not fetch from IMDS at all, but if user-data is not set then Bottlerocket will continue to use the keys from IMDS.

To use custom public keys for `.ssh/authorized_keys` and/or custom CA keys for `/etc/ssh/trusted_user_ca_keys.pub` you will want to generate a JSON-structure like this:

```json
{
  "ssh": {
    "authorized-keys": [
      "ssh-rsa EXAMPLEAUTHORIZEDPUBLICKEYHERE my-key-pair"
    ],
    "trusted-user-ca-keys": [
      "ssh-rsa EXAMPLETRUSTEDCAPUBLICKEYHERE authority@ssh-ca.example.com"
    ]
  }
}
```

If you want to access to the admin container using [EC2 instance connect](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Connect-using-EC2-Instance-Connect.html), set `authorized-keys-command` and `authorized-keys-command-user` as follows:

```json
{
  "ssh": {
    "authorized-keys-command": "/opt/aws/bin/eic_run_authorized_keys %u %f",
    "authorized-keys-command-user": "ec2-instance-connect"
  }
}
```

To change allowed SSH ciphers to a specific set, you can add a ciphers section:

```json
{
  "ssh": {
    "authorized-keys...",
    "ciphers": [
        "chacha20-poly1305@openssh.com",
        "aes128-ctr",
        "aes192-ctr",
        "aes256-ctr",
        "aes128-gcm@openssh.com",
        "aes256-gcm@openssh.com"
    ]
  }
}
```

To change allowed key exchange algorithms to a specific set, you can add a
`key-exchange-algorithms` section:

```json
{
  "ssh": {
    "authorized-keys...",
    "key-exchange-algorithms": [
        "curve25519-sha256",
        "curve25519-sha256@libssh.org",
        "ecdh-sha2-nistp256",
        "ecdh-sha2-nistp384",
        "ecdh-sha2-nistp521",
        "diffie-hellman-group-exchange-sha256"
    ]
  }
}
```

To change allowed MACs to a specific set, you can add a `macs` section:

```json
{
  "ssh": {
    "authorized-keys...",
    "macs": [
      "hmac-sha2-256",
      "hmac-sha2-512",
      "umac-64@openssh.com",
      "umac-128@openssh.com",
      "hmac-sha2-256-etm@openssh.com",
      "hmac-sha2-512-etm@openssh.com",
      "hmac-md5-etm@openssh.com",
      "hmac-md5-96-etm@openssh.com",
      "umac-64-etm@openssh.com",
      "umac-128-etm@openssh.com"
    ]
  }
}
```

You can also tweak ciphers, key exchange algorithms and MACs following way (see https://man.openbsd.org/sshd_config for details):
- If the specified list begins with a ‘+’ character, then the specified entries will be appended to the default set instead of replacing them. If the specified list begins with a ‘-’ character, then the specified entries (including wildcards) will be removed from the default set instead of replacing them. If the specified list begins with a ‘^’ character, then the specified entries will be placed at the head of the default set.

By default, the admin container's local user will be `ec2-user`. If you would like to change this, you can set the user value like so:

```json
{
  "user": "bottlerocket",
  "ssh": {
    "authorized-keys...",
  }
}
```

For logging in via serial console, you can specify a password for the primary user like so:

```json
{
  "user": "bottlerocket",
  "password-hash": "$y$jFT$NER...",
  "ssh": {
    "authorized-keys...",
  }
}
```

Where the password-hash can be generated from:

```bash
mkpasswd -m yescrypt -R 11 <desired password>
```

Once you've created your JSON, you'll need to base64-encode it and set it as the value of the admin host container's user-data setting in your [instance user data toml](https://github.com/bottlerocket-os/bottlerocket#using-user-data).

```toml
[settings.host-containers.admin]
# ex: echo '{"ssh":{"authorized-keys":[]}}' | base64
user-data = "eyJzc2giOnsiYXV0aG9yaXplZC1rZXlzIjpbXX19Cg=="
```
