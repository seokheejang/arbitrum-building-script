# arbitrum-building-script

arbitrum test node script repo

## Building Scenario

1. L1(local) / L2(local)
2. L1(private geth) / L2(local)
3. Minimal Chain
4. Send Tx

## 1. L1(local) / L2(local)

### Init

```bash
./test-node-custom.bash --init --build --validate --batchposters 1 --redundantsequencers 0 --blockscout --tokenbridge --l2-fee-token --detach
```

### Running

```bash
./test-node-custom.bash --validate --batchposters 1 --redundantsequencers 0 --blockscout --tokenbridge --l2-fee-token --detach
```

## 2. L1(private geth) / L2(local)

```bash
cp .env.sample .env
```

### Init

```bash
./test-node-custom.bash --init --build --validate --batchposters 1 --redundantsequencers 0 --blockscout --tokenbridge --l2-fee-token --detach --priv-geth
```

### Running

```bash
./test-node-custom.bash --validate --batchposters 1 --redundantsequencers 0 --blockscout --tokenbridge --l2-fee-token --detach --priv-geth
```

## 3. Minimal Chain

```bash
cp .env.sample .env
# writing env value
```

L1 Funding

```bash
./minimal-node.bash --l1-fund
```

L2 Node Setting

```bash
./minimal-node.bash --init --build --detach --l2-node
```

L3 Node Setting

```bash
./minimal-node.bash --init --build --detach --l3-node
```

L3 Service Provider Node Setting

```bash
./minimal-node.bash --init --build --detach --l3-nodesp
```

Run node

```bash
./minimal-node.bash --run --detach --l2-node
./minimal-node.bash --run --detach --l3-node
./minimal-node.bash --run --detach --l3-nodesp
```

## Send Tx

```bash
./minimal-node.bash script send-l2 --wait
./minimal-node.bash script send-l3 --wait
./minimal-node.bash script send-l3 --wait --l3url ${l3-node-sp}
```

## Scripts code build

```bash
NITRO_NODE_DEV_IMAGE=nitro-node-dev-testnode docker compose build scripts
```

## Named accounts

```bash
./test-node-custom.bash script print-address --account sequencer
```

```
sequencer:                  0xe2148eE53c0755215Df69b2616E552154EdC584f
validator:                  0x6A568afe0f82d34759347bb36F14A6bB171d2CBe
l2owner:                    0x5E1497dD1f08C87b2d8FE23e9AAB6c1De833D927
l3owner:                    0x863c904166E801527125D8672442D736194A3362
l3sequencer:                0x3E6134aAD4C4d422FF2A4391Dc315c4DDf98D1a5
user_l1user:                0x058E6C774025ade66153C65672219191c72c7095
user_token_bridge_deployer: 0x3EaCb30f025630857aDffac9B2366F953eFE4F98
user_fee_token_deployer:    0x2AC5278D230f88B481bBE4A94751d7188ef48Ca2
```

While not a named account, 0x3f1eae7d46d88f08fc2f8ed27fcb2ab183eb2d0e is funded on all test chains.
