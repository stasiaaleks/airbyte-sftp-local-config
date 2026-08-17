# No explicit configuration: the provider falls back to the local Juju CLI
# configuration in ~/.local/share/juju and uses the currently selected
# controller. Override with JUJU_CONTROLLER_ADDRESSES / JUJU_USERNAME /
# JUJU_PASSWORD / JUJU_CA_CERT if you need to target a different controller.
provider "juju" {}
