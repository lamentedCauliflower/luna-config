# Use Debian Libvirt VM For Hermes Agent

**Superseded by [ADR 0007](0007-hermes-agent-in-official-docker-image.md).** The Hermes VM is no longer imported by any host; `modules/features/hermes-vm.nix` is kept only until its qcow2 is drained. The requirements below still hold — 0007 explains what now satisfies each of them.

We will run the Hermes Agent gateway in a Debian stable virtual machine managed by libvirt/NixVirt on lunaServer, rather than using the upstream Hermes NixOS module's native or container modes. The **Hermes VM** needs guest systemd, hypervisor-enforced memory limits, qcow2 snapshot/reset workflows, and its own LAN IP; Debian stable also keeps the guest familiar for manual Hermes installation and operation.

Considered options were native NixOS service, Hermes container mode, microvm.nix, and a Debian libvirt/qemu VM. The Debian libvirt VM is heavier than a container and less declarative than a NixOS guest, but it matches the isolation and operational requirements while fitting the host's existing libvirt and `br0` setup.
