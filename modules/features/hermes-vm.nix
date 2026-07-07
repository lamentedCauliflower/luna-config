{ ... }:
{
  flake.nixosModules.hermesVm =
    { pkgs, ... }:
    let
      vmName = "hermes-vm";
      vmUuid = "4e071a9f-145a-492c-ae01-fb349943995a";
      vmDir = "/mnt/raidDrive/vms/hermes";
      baseImagePath = "${vmDir}/debian-13-genericcloud-amd64.qcow2";
      diskPath = "${vmDir}/${vmName}.qcow2";
      seedIsoPath = "${vmDir}/seed.iso";
      macAddress = "52:54:00:68:65:72";
      vmAddress = "192.168.0.50";

      isaacSshKey = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./ssh/isaac_ed25519.pub);

      debianImage = pkgs.fetchurl {
        url = "https://cloud.debian.org/images/cloud/trixie/20260518-2482/debian-13-genericcloud-amd64-20260518-2482.qcow2";
        hash = "sha512-d1KtKtzhvEndlk2ugwDteiOdC/PBMRL1WVOxEUR/5kLSzAGv7q0jSqbr42BVE/LnwOfFZ4XWdcOP9AEQ1cgzKw==";
      };

      cloudInitUserData = pkgs.writeText "hermes-vm-user-data.yaml" ''
        #cloud-config
        hostname: hermes
        manage_etc_hosts: true
        disable_root: true
        ssh_pwauth: false
        package_update: true
        package_upgrade: false
        packages:
          - ca-certificates
          - curl
          - docker-compose
          - docker.io
          - git
          - openssh-server
          - qemu-guest-agent
          - sudo
          - tmux
          - vim
        groups:
          - hermes
        users:
          - default
          - name: isaac
            groups: [sudo]
            shell: /bin/bash
            lock_passwd: true
            sudo: ["ALL=(ALL) NOPASSWD:ALL"]
            ssh_authorized_keys:
              - ${isaacSshKey}
          - name: hermes
            gecos: Hermes Agent
            primary_group: hermes
            homedir: /var/lib/hermes
            shell: /usr/sbin/nologin
            system: true
            lock_passwd: true
        runcmd:
          - systemctl enable --now qemu-guest-agent.service
          - systemctl enable --now docker.service
          - usermod -aG docker isaac
          - install -d -o hermes -g hermes -m 0750 /var/lib/hermes /var/lib/hermes/.hermes /var/lib/hermes/workspace
          - touch /etc/cloud/cloud-init.disabled
      '';

      cloudInitMetaData = pkgs.writeText "hermes-vm-meta-data.yaml" ''
        instance-id: hermes-vm
        local-hostname: hermes
      '';

      cloudInitNetworkConfig = pkgs.writeText "hermes-vm-network-config.yaml" ''
        version: 2
        ethernets:
          ens3:
            match:
              macaddress: "${macAddress}"
            set-name: ens3
            addresses:
              - ${vmAddress}/24
            routes:
              - to: default
                via: 192.168.0.1
            nameservers:
              addresses:
                - 1.1.1.1
                - 8.8.8.8
      '';

      seedIso = pkgs.runCommand "hermes-vm-seed.iso" { nativeBuildInputs = [ pkgs.cloud-utils ]; } ''
        cloud-localds --network-config=${cloudInitNetworkConfig} "$out" ${cloudInitUserData} ${cloudInitMetaData}
      '';

      domainXml = pkgs.writeText "hermes-vm.xml" ''
        <domain type='kvm'>
          <name>${vmName}</name>
          <uuid>${vmUuid}</uuid>
          <memory unit='MiB'>8192</memory>
          <currentMemory unit='MiB'>8192</currentMemory>
          <vcpu placement='static'>4</vcpu>
          <os>
            <type arch='x86_64' machine='pc'>hvm</type>
            <boot dev='hd'/>
          </os>
          <features>
            <acpi/>
            <apic/>
          </features>
          <clock offset='utc'/>
          <on_poweroff>destroy</on_poweroff>
          <on_reboot>restart</on_reboot>
          <on_crash>restart</on_crash>
          <devices>
            <emulator>/run/libvirt/nix-emulators/qemu-system-x86_64</emulator>
            <controller type='scsi' index='0' model='virtio-scsi'/>
            <controller type='sata' index='0'/>
            <controller type='virtio-serial' index='0'/>
            <disk type='file' device='disk'>
              <driver name='qemu' type='qcow2' cache='none' discard='unmap'/>
              <source file='${diskPath}'/>
              <target dev='sda' bus='scsi'/>
            </disk>
            <disk type='file' device='cdrom'>
              <driver name='qemu' type='raw'/>
              <source file='${seedIsoPath}'/>
              <target dev='sdb' bus='sata'/>
              <readonly/>
            </disk>
            <interface type='bridge'>
              <mac address='${macAddress}'/>
              <source bridge='br0'/>
              <model type='virtio'/>
            </interface>
            <serial type='pty'>
              <target type='isa-serial' port='0'/>
            </serial>
            <console type='pty'>
              <target type='serial' port='0'/>
            </console>
            <channel type='unix'>
              <source mode='bind'/>
              <target type='virtio' name='org.qemu.guest_agent.0'/>
            </channel>
            <graphics type='vnc' port='-1' autoport='yes' listen='127.0.0.1'/>
            <memballoon model='virtio'/>
          </devices>
        </domain>
      '';
    in
    {
      virtualisation.libvirt = {
        enable = true;
        connections."qemu:///system".domains = [
          {
            definition = domainXml;
            active = true;
          }
        ];
      };

      virtualisation.libvirtd = {
        allowedBridges = [
          "virbr0"
          "br0"
        ];
        onShutdown = "shutdown";
        shutdownTimeout = 300;
      };

      systemd.services.hermes-vm-storage = {
        description = "Prepare Hermes VM storage";
        requires = [ "mnt-raidDrive.mount" ];
        after = [ "mnt-raidDrive.mount" ];
        before = [ "nixvirt.service" ];
        path = [
          pkgs.coreutils
          pkgs.qemu
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -eu

          install -d -m 0755 "${vmDir}"

          if [ ! -e "${baseImagePath}" ]; then
            install -m 0444 "${debianImage}" "${baseImagePath}.tmp"
            mv "${baseImagePath}.tmp" "${baseImagePath}"
          fi
          chmod 0444 "${baseImagePath}"

          if [ ! -e "${diskPath}" ]; then
            qemu-img create -f qcow2 -F qcow2 -b "${baseImagePath}" "${diskPath}.tmp" 20G
            mv "${diskPath}.tmp" "${diskPath}"
          fi

          install -m 0644 "${seedIso}" "${seedIsoPath}.tmp"
          mv "${seedIsoPath}.tmp" "${seedIsoPath}"
        '';
      };

      systemd.services.nixvirt = {
        requires = [ "hermes-vm-storage.service" ];
        after = [ "hermes-vm-storage.service" ];
      };

      services.caddy.virtualHosts."hermes.luna.local" = {
        extraConfig = ''
          reverse_proxy ${vmAddress}:5678
        '';
      };
    };

}
