# The Juju provider reads ~/.local/share/juju by default and targets the
# currently selected controller (e.g. `juju bootstrap localhost lxd-controller`).
# Override with JUJU_CONTROLLER_ADDRESSES / JUJU_USERNAME / JUJU_PASSWORD /
# JUJU_CA_CERT to target a different controller.
provider "juju" {}
