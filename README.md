
# Deploy 
PUBLISHER_PROFILE=test2 && \
PUBLISHER_ADDR=6c2771d30dc669120be227362ea19141fa72ddc8bb5819409e4da54f0d09b573 && \
aptos move create-object-and-publish-package \
--address-name slime \
--named-addresses \
deployer=6c2771d30dc669120be227362ea19141fa72ddc8bb5819409e4da54f0d09b573 \
--profile $PUBLISHER_PROFILE \
--assume-yes --included-artifacts none

# Upgrade
PUBLISHER_PROFILE=test2 && \
PUBLISHER_ADDR=6c2771d30dc669120be227362ea19141fa72ddc8bb5819409e4da54f0d09b573  && \
OBJECT_ADDR="0xff5e81f5ed6b859bebdda1d4269926fe67874c6edb96fe74ae3abbc19ee81ad0" && \
aptos move upgrade-object-package \
--object-address $OBJECT_ADDR \
--named-addresses \
slime=$OBJECT_ADDR,deployer=$PUBLISHER_ADDR --profile $PUBLISHER_PROFILE \
--assume-yes --included-artifacts none