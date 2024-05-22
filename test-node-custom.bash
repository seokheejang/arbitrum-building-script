#!/usr/bin/env bash

set -e

ENV_FILE=".env"

if [ -f "$ENV_FILE" ]; then
  export $(grep -v '^#' $ENV_FILE | xargs)
else
  echo "$ENV_FILE not find file."
  exit 1
fi

NITRO_NODE_VERSION=offchainlabs/nitro-node:v2.3.3-6a1c1a7-dev
BLOCKSCOUT_VERSION=offchainlabs/blockscout:v1.0.0-c8db5b1

# This commit matches the v1.2.1 contracts, with additional fixes for rollup deployment script.
# Once v1.2.2 is released, we can switch to that version.
DEFAULT_NITRO_CONTRACTS_VERSION="a00d2faac01e050339ff7b0ac5bc91df06e8dbff"
DEFAULT_TOKEN_BRIDGE_VERSION="v1.2.1"

# Set default versions if not overriden by provided env vars
: ${NITRO_CONTRACTS_BRANCH:=$DEFAULT_NITRO_CONTRACTS_VERSION}
: ${TOKEN_BRIDGE_BRANCH:=$DEFAULT_TOKEN_BRIDGE_VERSION}
export NITRO_CONTRACTS_BRANCH
export TOKEN_BRIDGE_BRANCH

echo "Using NITRO_CONTRACTS_BRANCH: $NITRO_CONTRACTS_BRANCH"
echo "Using TOKEN_BRIDGE_BRANCH: $TOKEN_BRIDGE_BRANCH"

mydir=`dirname $0`
cd "$mydir"

if [[ $# -gt 0 ]] && [[ $1 == "script" ]]; then
    shift
    docker compose run --rm scripts "$@"
    exit $?
fi

num_volumes=`docker volume ls --filter label=com.docker.compose.project=arbitrum-building-script -q | wc -l`

if [[ $num_volumes -eq 0 ]]; then
    force_init=true
else
    force_init=false
fi

run=true
force_build=false
validate=false
detach=false
blockscout=false
tokenbridge=false
l3node=false
redundantsequencers=0
dev_build_nitro=false
dev_build_blockscout=false
l2_custom_fee_token=false
batchposters=1
devprivkey=b6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659
l1chainid=1337
simple=false
geth_http_rpc=http://geth:8545
geth_ws_rpc=ws://geth:8546
priv_geth=false
priv_geth_http_url=$ETH_HTTP_URL
priv_geth_ws_url=$ETH_WS_URL
priv_geth_chainId=$ETH_CHAIN_ID
priv_dev_key=$DEV_PRIV_KEY

while [[ $# -gt 0 ]]; do
    case $1 in
        --init)
            if ! $force_init; then
                echo == Warning! this will remove all previous data
                read -p "are you sure? [y/n]" -n 1 response
                if [[ $response == "y" ]] || [[ $response == "Y" ]]; then
                    force_init=true
                    echo
                else
                    exit 0
                fi
            fi
            shift
            ;;
        --init-force)
            force_init=true
            shift
            ;;
        --dev)
            simple=false
            shift
            if [[ $# -eq 0 || $1 == -* ]]; then
                # If no argument after --dev, set both flags to true
                dev_build_nitro=true
                dev_build_blockscout=true
            else
                while [[ $# -gt 0 && $1 != -* ]]; do
                    if [[ $1 == "nitro" ]]; then
                        dev_build_nitro=true
                    elif [[ $1 == "blockscout" ]]; then
                        dev_build_blockscout=true
                    fi
                    shift
                done
            fi
            ;;
        --build)
            force_build=true
            shift
            ;;
        --validate)
            simple=false
            validate=true
            shift
            ;;
        --blockscout)
            blockscout=true
            shift
            ;;
        --tokenbridge)
            tokenbridge=true
            shift
            ;;
        --no-tokenbridge)
            tokenbridge=false
            shift
            ;;
        --no-run)
            run=false
            shift
            ;;
        --detach)
            detach=true
            shift
            ;;
        --batchposters)
            simple=false
            batchposters=$2
            if ! [[ $batchposters =~ [0-3] ]] ; then
                echo "batchposters must be between 0 and 3 value:$batchposters."
                exit 1
            fi
            shift
            shift
            ;;
        --l3node)
            l3node=true
            shift
            ;;
        --l2-fee-token)
            l2_custom_fee_token=true
            shift
            ;;
        --redundantsequencers)
            simple=false
            redundantsequencers=$2
            if ! [[ $redundantsequencers =~ [0-3] ]] ; then
                echo "redundantsequencers must be between 0 and 3 value:$redundantsequencers."
                exit 1
            fi
            shift
            shift
            ;;
        --simple)
            simple=true
            shift
            ;;
        --no-simple)
            simple=false
            shift
            ;;
        --priv-geth)
            priv_geth=true
            geth_http_rpc=$priv_geth_http_url
            geth_ws_rpc=$priv_geth_ws_url
            l1chainid=$priv_geth_chainId
            shift
            ;;
        *)
            echo Usage: $0 \[OPTIONS..]
            echo        $0 script [SCRIPT-ARGS]
            echo
            echo OPTIONS:
            echo --build           rebuild docker images
            echo --dev             build nitro and blockscout dockers from source instead of pulling them. Disables simple mode
            echo --init            remove all data, rebuild, deploy new rollup
            echo --validate        heavy computation, validating all blocks in WASM
            echo --l2-fee-token    L3 chain is set up to use custom fee token. Only valid if also '--l3node' is provided
            echo --batchposters    batch posters [0-3]
            echo --redundantsequencers redundant sequencers [0-3]
            echo --detach          detach from nodes after running them
            echo --blockscout      build or launch blockscout
            echo --tokenbridge     deploy L1-L2 token bridge.
            echo --no-tokenbridge  don\'t build or launch tokenbridge
            echo --no-run          does not launch nodes \(useful with build or init\)
            echo --priv-geth       l1 private geth dev key
            echo
            echo script runs inside a separate docker. For SCRIPT-ARGS, run $0 script --help
            exit 0
    esac
done

if $force_init; then
  force_build=true
fi

if $dev_build_nitro; then
  if [[ "$(docker images -q nitro-node-dev:latest 2> /dev/null)" == "" ]]; then
    force_build=true
  fi
fi

if $dev_build_blockscout; then
  if [[ "$(docker images -q blockscout:latest 2> /dev/null)" == "" ]]; then
    force_build=true
  fi
fi

NODES="sequencer"
INITIAL_SEQ_NODES="sequencer"

if ! $simple; then
    NODES="$NODES redis"
fi
if [ $redundantsequencers -gt 0 ]; then
    NODES="$NODES sequencer_b"
    INITIAL_SEQ_NODES="$INITIAL_SEQ_NODES sequencer_b"
fi
if [ $redundantsequencers -gt 1 ]; then
    NODES="$NODES sequencer_c"
fi
if [ $redundantsequencers -gt 2 ]; then
    NODES="$NODES sequencer_d"
fi

if [ $batchposters -gt 0 ] && ! $simple; then
    NODES="$NODES poster"
fi
if [ $batchposters -gt 1 ]; then
    NODES="$NODES poster_b"
fi
if [ $batchposters -gt 2 ]; then
    NODES="$NODES poster_c"
fi

if $validate; then
    NODES="$NODES validator"
elif ! $simple; then
    NODES="$NODES staker-unsafe"
fi
if $blockscout; then
    NODES="$NODES blockscout"
fi
if $force_build; then
  echo == Building..
  if $dev_build_nitro; then
    if ! [ -n "${NITRO_SRC+set}" ]; then
        NITRO_SRC=`dirname $PWD`
    fi
    if ! grep ^FROM "${NITRO_SRC}/Dockerfile" | grep nitro-node 2>&1 > /dev/null; then
        echo nitro source not found in "$NITRO_SRC"
        echo execute from a sub-directory of nitro or use NITRO_SRC environment variable
        exit 1
    fi
    docker build "$NITRO_SRC" -t nitro-node-dev --target nitro-node-dev
  fi
  if $dev_build_blockscout; then
    if $blockscout; then
      docker build blockscout -t blockscout -f blockscout/docker/Dockerfile
    fi
  fi

  LOCAL_BUILD_NODES="scripts rollupcreator"
  if $tokenbridge; then
    LOCAL_BUILD_NODES="$LOCAL_BUILD_NODES tokenbridge"
  fi
  docker compose build --no-rm $LOCAL_BUILD_NODES
fi

if $dev_build_nitro; then
  docker tag nitro-node-dev:latest nitro-node-dev-testnode
else
  docker pull $NITRO_NODE_VERSION
  docker tag $NITRO_NODE_VERSION nitro-node-dev-testnode
fi

if $dev_build_blockscout; then
  if $blockscout; then
    docker tag blockscout:latest blockscout-testnode
  fi
else
  if $blockscout; then
    docker pull $BLOCKSCOUT_VERSION
    docker tag $BLOCKSCOUT_VERSION blockscout-testnode
  fi
fi

if $force_build; then
    docker compose build --no-rm $NODES scripts
fi

if $force_init; then
    echo == Removing old data..
    docker compose down
    leftoverContainers=`docker container ls -a --filter label=com.docker.compose.project=arbitrum-building-script -q | xargs echo`
    if [ `echo $leftoverContainers | wc -w` -gt 0 ]; then
        docker rm $leftoverContainers
    fi
    docker volume prune -f --filter label=com.docker.compose.project=arbitrum-building-script
    leftoverVolumes=`docker volume ls --filter label=com.docker.compose.project=arbitrum-building-script -q | xargs echo`
    if [ `echo $leftoverVolumes | wc -w` -gt 0 ]; then
        docker volume rm $leftoverVolumes
    fi

    #-----------------------------------------------------------------------------------------------------------------
    # L1 Geth 세팅 Start
    #-----------------------------------------------------------------------------------------------------------------
    echo == Generating l1 keys
    docker compose run --rm scripts write-accounts
    docker compose run --rm --entrypoint sh geth -c "echo passphrase > /datadir/passphrase"
    docker compose run --rm --entrypoint sh geth -c "chown -R 1000:1000 /keystore"
    docker compose run --rm --entrypoint sh geth -c "chown -R 1000:1000 /config"

    if $priv_geth; then
        echo "== ENV" 
        echo " priv_geth_http_url :" $priv_geth_http_url
        echo " priv_geth_ws_url   :" $priv_geth_ws_url
        echo " priv_geth_chainId  :" $priv_geth_chainId
        echo " priv_dev_key       :" $priv_dev_key
        docker compose run --rm scripts send-l1 --ethamount 0.1 --from ${priv_dev_key} --to validator --l1url ${geth_ws_rpc} --wait 
        docker compose run --rm scripts send-l1 --ethamount 0.1 --from ${priv_dev_key} --to sequencer --l1url ${geth_ws_rpc} --wait
        docker compose run --rm scripts send-l1 --ethamount 0.1 --from ${priv_dev_key} --to l2owner --l1url ${geth_ws_rpc} --wait 
        docker compose run --rm scripts send-l1 --ethamount 0.1 --from ${priv_dev_key} --to user_fee_token_deployer --l1url ${geth_ws_rpc} --wait
        docker compose run --rm scripts send-l1 --ethamount 0.1 --from ${priv_dev_key} --to user_token_bridge_deployer --l1url ${geth_ws_rpc} --wait
    else
        docker compose up --wait geth

        echo == Funding validator, sequencer and l2owner
        docker compose run --rm scripts send-l1 --ethamount 1000 --to validator --wait 
        docker compose run --rm scripts send-l1 --ethamount 1000 --to sequencer --wait
        docker compose run --rm scripts send-l1 --ethamount 1000 --to l2owner --wait

        # echo == create l1 traffic
        # docker compose run --rm scripts send-l1 --ethamount 1000 --to user_l1user --wait
        # docker compose run --rm scripts send-l1 --ethamount 0.0001 --from user_l1user --to user_l1user_b --wait --delay 500 --times 1000000 > /dev/null &

        echo == Funding l1 token deployer
        docker compose run --rm scripts send-l1 --ethamount 100 --to user_fee_token_deployer --wait
        docker compose run --rm scripts send-l1 --ethamount 100 --to user_token_bridge_deployer --wait
    fi
    #-----------------------------------------------------------------------------------------------------------------
    # L1 Geth 세팅 End
    #-----------------------------------------------------------------------------------------------------------------

    #-----------------------------------------------------------------------------------------------------------------
    # L2 Nitro 세팅 Start
    #-----------------------------------------------------------------------------------------------------------------
    echo == Writing l2 chain config
    docker compose run --rm scripts write-l2-chain-config

    if $l2_custom_fee_token; then
        echo == Deploying custom fee token
        # L1 Chain 에 ERC-20 Deploy
        nativeTokenAddress=`docker compose run --rm scripts create-erc20-l1 --l1url ${geth_ws_rpc} --deployer user_fee_token_deployer --mintTo user_token_bridge_deployer | tail -n 1 | awk '{ print $NF }'`
        docker compose run --rm scripts transfer-erc20-l1 --l1url ${geth_ws_rpc} --token $nativeTokenAddress --amount 1000 --from user_token_bridge_deployer --to l2owner
        EXTRA_L2_DEPLOY_FLAG="-e FEE_TOKEN_ADDRESS=$nativeTokenAddress"
        echo EXTRA_L2_DEPLOY_FLAG: $EXTRA_L2_DEPLOY_FLAG

        docker compose run --rm scripts balanceOf-erc20-l1 --l1url ${geth_ws_rpc} --token $nativeTokenAddress --from user_token_bridge_deployer
        docker compose run --rm scripts balanceOf-erc20-l1 --l1url ${geth_ws_rpc} --token $nativeTokenAddress --from l2owner
    fi

    echo == Deploying L2 chain
    l2ownerAddress=`docker compose run --rm scripts print-address --account l2owner | tail -n 1 | tr -d '\r\n'`
    l2ownerKey=`docker compose run --rm scripts print-private-key --account l2owner | tail -n 1 | tr -d '\r\n'`
    sequenceraddress=`docker compose run --rm scripts print-address --account sequencer | tail -n 1 | tr -d '\r\n'`
    wasmroot=`docker compose run --entrypoint sh sequencer -c "cat /home/user/target/machines/latest/module-root.txt"`
    
    # Custom Fee Token Address 추가
    docker compose run -e PARENT_CHAIN_RPC=$geth_http_rpc -e DEPLOYER_PRIVKEY=$l2ownerKey -e PARENT_CHAIN_ID=$l1chainid -e CHILD_CHAIN_NAME="arb-dev-test" -e MAX_DATA_SIZE=117964 -e OWNER_ADDRESS=$l2ownerAddress -e WASM_MODULE_ROOT=$wasmroot -e SEQUENCER_ADDRESS=$sequenceraddress -e AUTHORIZE_VALIDATORS=10 -e CHILD_CHAIN_CONFIG_PATH="/config/l2_chain_config.json" -e CHAIN_DEPLOYMENT_INFO="/config/deployment.json" -e CHILD_CHAIN_INFO="/config/deployed_chain_info.json" $EXTRA_L2_DEPLOY_FLAG rollupcreator create-rollup-testnode
    docker compose run --entrypoint sh rollupcreator -c "jq [.[]] /config/deployed_chain_info.json > /config/l2_chain_info.json"

    echo == Writing configs
    if $priv_geth; then
        docker compose run --rm scripts write-config --l1url ${priv_geth_ws_url}
    else
        docker compose run --rm scripts write-config
    fi
    
    echo == Initializing redis
    docker compose up --wait redis
    docker compose run --rm scripts redis-init --redundancy $redundantsequencers

    # Running sequencer
    echo == Funding l2 funnel and dev key 
    docker compose up --wait $INITIAL_SEQ_NODES

    if $tokenbridge; then
        echo == Deploying L1-L2 token bridge
        deployer_key=`printf "%s" "user_token_bridge_deployer" | openssl dgst -sha256 | sed 's/^.*= //'`
        rollupAddress=`docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.rollup' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'"`
        echo deployer_key: $deployer_key 
        echo rollupAddress: $rollupAddress
        docker compose run -e ROLLUP_OWNER_KEY=$l2ownerKey -e ROLLUP_ADDRESS=$rollupAddress -e PARENT_RPC=$geth_http_rpc -e PARENT_KEY=$deployer_key -e CHILD_RPC=http://sequencer:8547 -e CHILD_KEY=$deployer_key tokenbridge deploy:local:token-bridge
        docker compose run --entrypoint sh tokenbridge -c "cat network.json && cp network.json l1l2_network.json && cp network.json localNetwork.json"
        echo
    fi

    echo == Funding l2 deployers
    if $l2_custom_fee_token; then
        docker compose run --rm scripts bridge-native-token-to-l2 --l1url ${geth_ws_rpc} --amount 50000 --from user_token_bridge_deployer --wait
        docker compose run --rm scripts send-l2 --ethamount 500 --from user_token_bridge_deployer --wait
        docker compose run --rm scripts send-l2 --ethamount 500 --from user_token_bridge_deployer --to "key_0x$devprivkey" --wait
    else
        docker compose run --rm scripts bridge-funds --ethamount 100000 --wait
        docker compose run --rm scripts bridge-funds --ethamount 1000 --wait --from "key_0x$devprivkey"
    fi
    #-----------------------------------------------------------------------------------------------------------------
    # L2 Nitro 세팅 End
    #-----------------------------------------------------------------------------------------------------------------
fi

if $run; then
    UP_FLAG=""
    if $detach; then
        UP_FLAG="--wait"
    fi

    echo == Launching Sequencer
    echo if things go wrong - use --init to create a new chain
    echo

    echo == Launching NODES: $NODES
    docker compose up $UP_FLAG $NODES
fi
