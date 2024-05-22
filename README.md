# arbitrum-building-script

arbitrum test node script repo

### Init

```bash
./test-node-custom.bash --init --build --validate --batchposters 1 --redundantsequencers 0 --blockscout --tokenbridge --l2-fee-token --detach
```

### Running

```bash
./test-node-custom.bash --validate --batchposters 1 --redundantsequencers 0 --blockscout --tokenbridge --l2-fee-token --detach
```

### Scripts code build

```bash
docker compose build scripts
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
