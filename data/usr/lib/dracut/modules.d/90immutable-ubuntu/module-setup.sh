#!/bin/bash
# /usr/lib/dracut/modules.d/90immutable-ubuntu/module-setup.sh

check() {
    require_binaries btrfs || return 1
    return 0
}

depends() {
    echo "btrfs"
}

install() {
    # systemd generator — creates the service + sysroot.mount drop-in
    inst_simple "$moddir/immutable-ubuntu-generator" \
        /usr/lib/systemd/system-generators/immutable-ubuntu-generator
    chmod 0755 "${initdir}/usr/lib/systemd/system-generators/immutable-ubuntu-generator"

    # Setup script called by the generated service unit
    inst_simple "$moddir/immutable-ubuntu-setup.sh" /bin/immutable-ubuntu-setup.sh
    chmod 0755 "${initdir}/bin/immutable-ubuntu-setup.sh"

    inst_multiple btrfs sed awk sort seq sleep
}

installkernel() {
    return 0
}
