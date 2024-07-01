#!/usr/bin/env bash

set -e

ENV_FILE=".env"

if [ -f "$ENV_FILE" ]; then
  export $(grep -v '^#' $ENV_FILE | xargs)
else
  echo "$ENV_FILE not find file."
  exit 1
fi
LOG_FILE="./node-build-result.log"

NITRO_NODE_VERSION=offchainlabs/nitro-node:v3.0.2-9efbc16
BLOCKSCOUT_VERSION=offchainlabs/blockscout:v1.0.0-c8db5b1

# This commit matches the v1.2.1 contracts, with additional fixes for rollup deployment script.
# Once v1.2.2 is released, we can switch to that version.
DEFAULT_NITRO_CONTRACTS_VERSION="a00d2faac01e050339ff7b0ac5bc91df06e8dbff"
DEFAULT_TOKEN_BRIDGE_VERSION="v1.2.1"

# debug compose file
COMPOSE_FILE="docker-compose.yaml"
DEBUG_DOCKER_HUB_IMAGE="nitro-node-dev-testnode"
REPO_NAME="arbitrum-building-script"

# Set default versions if not overriden by provided env vars
: ${NITRO_CONTRACTS_BRANCH:=$DEFAULT_NITRO_CONTRACTS_VERSION}
: ${TOKEN_BRIDGE_BRANCH:=$DEFAULT_TOKEN_BRIDGE_VERSION}
export NITRO_CONTRACTS_BRANCH
export TOKEN_BRIDGE_BRANCH
export NITRO_NODE_DEV_IMAGE=${DEBUG_DOCKER_HUB_IMAGE}

echo "Using NITRO_NODE_VERSION: $NITRO_NODE_VERSION"
echo "Using NITRO_CONTRACTS_BRANCH: $NITRO_CONTRACTS_BRANCH"
echo "Using TOKEN_BRIDGE_BRANCH: $TOKEN_BRIDGE_BRANCH"

mydir=`dirname $0`
cd "$mydir"

if [[ $# -gt 0 ]] && [[ $1 == "script" ]]; then
    shift
    docker compose -f $COMPOSE_FILE run --rm scripts "$@"
    exit $?
fi

if [[ $# -gt 0 ]] && [[ $1 == "docker" ]]; then
    shift
    docker compose -f $COMPOSE_FILE "$@"
    exit $?
fi

num_volumes=`docker volume ls --filter label=com.docker.compose.project=$REPO_NAME -q | wc -l`

if [[ $num_volumes -eq 0 ]]; then
    force_init=true
else
    force_init=false
fi

run=false
force_build=false
validate=false
detach=false
blockscout=false
tokenbridge=false
dev_build_nitro=false
dev_build_blockscout=false
devprivkey=b6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659
simple=false
docker_prune=true
l1fund=false
l2node=false
l3node=false
l3nodesp=false

l1_http_rpc=$ETH_HTTP_URL
l1_ws_rpc=$ETH_WS_URL
l1_chainid=$ETH_CHAIN_ID
l1_dev_privkey=$ETH_DEV_PRIV_KEY

l2_http_rpc=$L2_HTTP_URL
l2_ws_rpc=$L2_WS_URL
l2_chainid=$L2_CHAIN_ID

l3_http_rpc=$L3_HTTP_URL
l3_ws_rpc=$L3_WS_URL
l3_chainid=$L3_CHAIN_ID

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
        --run)
            run=true
            shift
            ;;
        --detach)
            detach=true
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
        --debug)
            COMPOSE_FILE="docker-compose.yaml"
            DEBUG_DOCKER_HUB_IMAGE=$2
            export NITRO_NODE_DEV_IMAGE=${DEBUG_DOCKER_HUB_IMAGE}
            shift
            shift
            ;;
        --no-prune)
            docker_prune=false
            shift
            ;;
        --l1-fund)
            l1fund=true
            shift
            ;;
        --l2-node)
            l2node=true
            shift
            ;;
        --l3-node)
            l3node=true
            shift
            ;;
        --l3-node-sp)
            l3nodesp=true
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
            echo --detach          detach from nodes after running them
            echo --blockscout      build or launch blockscout
            echo --tokenbridge     deploy L1-L2 token bridge.
            echo --no-tokenbridge  don\'t build or launch tokenbridge
            echo --debug           developer debugging mode
            echo ------------------------------------------
            echo --run
            echo --no-prune
            echo --l1-fund
            echo --l2-node
            echo --l3-node
            echo --l3-node-sp
            echo
            echo script runs inside a sepwarate docker. For SCRIPT-ARGS, run $0 script --help
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

NODES=""
INITIAL_SEQ_NODES="sequencer"

if ! $simple; then
    NODES="$NODES redis"
fi
if $l2node; then
    NODES="$NODES sequencer"
fi
if $l3node; then
    NODES="$NODES l3node"
fi
if $l3nodesp; then
    NODES="$NODES l3node_full_node"
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
  docker compose -f $COMPOSE_FILE build --no-rm $LOCAL_BUILD_NODES
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
    docker compose -f $COMPOSE_FILE build --no-rm $NODES scripts
fi

### Function Area Start
func_project_docker_prune()
{
    echo == Removing old data..
    docker compose -f $COMPOSE_FILE down
    leftoverContainers=`docker container ls -a --filter label=com.docker.compose.project=$REPO_NAME -q | xargs echo`
    if [ `echo $leftoverContainers | wc -w` -gt 0 ]; then
        docker rm $leftoverContainers
    fi
    docker volume prune -f --filter label=com.docker.compose.project=$REPO_NAME
    leftoverVolumes=`docker volume ls --filter label=com.docker.compose.project=$REPO_NAME -q | xargs echo`
    if [ `echo $leftoverVolumes | wc -w` -gt 0 ]; then
        docker volume rm $leftoverVolumes
    fi
}
### Fuction Area End

if $l1fund; then 
    echo == Funding L1 chain
    echo " NITRO_NODE_DEV_IMAGE :" $NITRO_NODE_DEV_IMAGE
    echo " l1_http_rpc          :" $l1_http_rpc
    echo " l1_ws_rpc            :" $l1_ws_rpc
    echo " l1_chainid           :" $l1_chainid
    echo " l1_dev_privkey       :" $l1_dev_privkey
    docker compose -f $COMPOSE_FILE run --rm scripts send-l1 --ethamount 1000 --from ${l1_dev_privkey} --to validator --l1url ${l1_ws_rpc} --wait 
    docker compose -f $COMPOSE_FILE run --rm scripts send-l1 --ethamount 1000 --from ${l1_dev_privkey} --to sequencer --l1url ${l1_ws_rpc} --wait
    docker compose -f $COMPOSE_FILE run --rm scripts send-l1 --ethamount 1000 --from ${l1_dev_privkey} --to l2owner --l1url ${l1_ws_rpc} --wait 
    docker compose -f $COMPOSE_FILE run --rm scripts send-l1 --ethamount 1000 --from ${l1_dev_privkey} --to user_fee_token_deployer --l1url ${l1_ws_rpc} --wait
    docker compose -f $COMPOSE_FILE run --rm scripts send-l1 --ethamount 1000 --from ${l1_dev_privkey} --to user_token_bridge_deployer --l1url ${l1_ws_rpc} --wait
    docker compose -f $COMPOSE_FILE run --rm scripts send-l1 --ethamount 10000 --from ${l1_dev_privkey} --to key_0x$devprivkey --l1url ${l1_ws_rpc} --wait
    docker compose -f $COMPOSE_FILE run --rm scripts send-l1 --ethamount 1000000 --from ${l1_dev_privkey} --to funnel --l1url ${l1_ws_rpc} --wait
    exit 0
fi

if $force_init; then
    run=true
    if $docker_prune; then
        > $LOG_FILE
        exec > >(tee -a $LOG_FILE) 2>&1
        func_project_docker_prune
    fi
    echo == Generating l1 keys and config setting
    docker compose -f $COMPOSE_FILE run --rm scripts write-accounts
    docker compose -f $COMPOSE_FILE run --rm --entrypoint sh geth -c "echo passphrase > /datadir/passphrase"
    docker compose -f $COMPOSE_FILE run --rm --entrypoint sh geth -c "chown -R 1000:1000 /keystore"
    docker compose -f $COMPOSE_FILE run --rm --entrypoint sh geth -c "chown -R 1000:1000 /config"

    if $l2node; then
        l2ownerAddress=`docker compose -f $COMPOSE_FILE run --rm scripts print-address --account l2owner | tail -n 1 | tr -d '\r\n'`
        l2ownerKey=`docker compose -f $COMPOSE_FILE run --rm scripts print-private-key --account l2owner | tail -n 1 | tr -d '\r\n'`
        sequenceraddress=`docker compose -f $COMPOSE_FILE run --rm scripts print-address --account sequencer | tail -n 1 | tr -d '\r\n'`
        wasmroot=`docker compose -f $COMPOSE_FILE run --rm --entrypoint sh sequencer -c "cat /home/user/target/machines/latest/module-root.txt"`

        echo == Writing l2 chain config
        docker compose -f $COMPOSE_FILE run --rm scripts write-l2-chain-config --l2owner $l2ownerAddress
        echo == Deploying L2 chain
        docker compose -f $COMPOSE_FILE run --rm -e PARENT_CHAIN_RPC=$l1_http_rpc -e DEPLOYER_PRIVKEY=$l2ownerKey -e PARENT_CHAIN_ID=$l1_chainid -e CHILD_CHAIN_NAME="minimal-l2-chain" -e MAX_DATA_SIZE=117964 -e OWNER_ADDRESS=$l2ownerAddress -e WASM_MODULE_ROOT=$wasmroot -e SEQUENCER_ADDRESS=$sequenceraddress -e AUTHORIZE_VALIDATORS=10 -e CHILD_CHAIN_CONFIG_PATH="/config/l2_chain_config.json" -e CHAIN_DEPLOYMENT_INFO="/config/deployment.json" -e CHILD_CHAIN_INFO="/config/deployed_chain_info.json" rollupcreator create-rollup-testnode
        docker compose -f $COMPOSE_FILE run --rm --entrypoint sh rollupcreator -c "jq [.[]] /config/deployed_chain_info.json > /config/l2_chain_info.json"

        # l2 sequencer(poster, validator)
        docker compose -f $COMPOSE_FILE run --rm scripts write-config  --simple --l1url ${l1_ws_rpc}

        # Running sequencer
        echo == Funding l2 funnel and dev key 
        docker compose -f $COMPOSE_FILE up --wait $INITIAL_SEQ_NODES

        # TODO: devprivkey와 bridge-funds 계정에 이더 얼마나 넣을지 확인 필요
        docker compose -f $COMPOSE_FILE run --rm scripts bridge-funds --l1url ${l1_ws_rpc} --ethamount 100000 --wait
        docker compose -f $COMPOSE_FILE run --rm scripts bridge-funds --l1url ${l1_ws_rpc} --ethamount 10000 --wait --from "key_0x$devprivkey"
        docker compose -f $COMPOSE_FILE run --rm scripts send-l2 --l2url ${l2_ws_rpc} --ethamount 100 --to l2owner --wait

        if $tokenbridge; then
            echo == Deploying L1-L2 token bridge
            deployer_key=`printf "%s" "user_token_bridge_deployer" | openssl dgst -sha256 | sed 's/^.*= //'`
            sleep 5
            rollupAddress=`docker compose -f $COMPOSE_FILE run --rm --entrypoint sh poster -c "jq -r '.[0].rollup.rollup' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'"`
            echo deployer_key: $deployer_key ", rollupAddress:" $rollupAddress
            docker compose -f $COMPOSE_FILE run --rm -e ROLLUP_OWNER_KEY=$l2ownerKey -e ROLLUP_ADDRESS=$rollupAddress -e PARENT_RPC=$l1_http_rpc -e PARENT_KEY=$deployer_key -e CHILD_RPC=$l2_http_rpc -e CHILD_KEY=$deployer_key tokenbridge deploy:local:token-bridge
            docker compose -f $COMPOSE_FILE run --rm --entrypoint sh tokenbridge -c "cat network.json && cp network.json l1l2_network.json && cp network.json localNetwork.json"
            echo
        fi
    fi

    if $l3node; then
        echo == Funding l3 users
        docker compose -f $COMPOSE_FILE run --rm scripts send-l2 --l2url ${l2_ws_rpc} --ethamount 100 --to l3owner --wait
        docker compose -f $COMPOSE_FILE run --rm scripts send-l2 --l2url ${l2_ws_rpc} --ethamount 100 --to l3sequencer --wait

        echo == Funding l2 deployers
        docker compose -f $COMPOSE_FILE run --rm scripts send-l1 --l1url ${l1_ws_rpc} --from ${l1_dev_privkey} --ethamount 10 --to user_token_bridge_deployer --wait
        docker compose -f $COMPOSE_FILE run --rm scripts send-l2 --l2url ${l2_ws_rpc} --ethamount 100 --to user_token_bridge_deployer --wait

        echo == Funding token deployer
        docker compose -f $COMPOSE_FILE run --rm scripts send-l1 --l1url ${l1_ws_rpc} --from ${l1_dev_privkey} --ethamount 10 --to user_fee_token_deployer --wait
        docker compose -f $COMPOSE_FILE run --rm scripts send-l2 --l2url ${l2_ws_rpc} --ethamount 100 --to user_fee_token_deployer --wait

        # L2 Chain 에 ERC-20 Deploy, --bridgeable false
        echo == Deploying custom fee token
        nativeTokenAddress=`docker compose -f $COMPOSE_FILE run --rm scripts create-erc20 --l1url ${l1_ws_rpc} --l2url ${l2_ws_rpc} --deployer user_fee_token_deployer --mintTo user_token_bridge_deployer --bridgeable false | tail -n 1 | awk '{ print $NF }'`
        EXTRA_L3_DEPLOY_FLAG="-e FEE_TOKEN_ADDRESS=$nativeTokenAddress"
        echo EXTRA_L3_DEPLOY_FLAG: $EXTRA_L3_DEPLOY_FLAG
        docker compose -f $COMPOSE_FILE run --rm scripts transfer-erc20 --l2url ${l2_ws_rpc} --token $nativeTokenAddress --amount 1000 --from user_token_bridge_deployer --to l3owner

        echo == Deploying L3
        l3owneraddress=`docker compose -f $COMPOSE_FILE run --rm scripts print-address --account l3owner | tail -n 1 | tr -d '\r\n'`
        l3ownerkey=`docker compose -f $COMPOSE_FILE run --rm scripts print-private-key --account l3owner | tail -n 1 | tr -d '\r\n'`
        l3sequenceraddress=`docker compose -f $COMPOSE_FILE run --rm scripts print-address --account l3sequencer | tail -n 1 | tr -d '\r\n'`
        wasmroot=`docker compose -f $COMPOSE_FILE run --rm --entrypoint sh sequencer -c "cat /home/user/target/machines/latest/module-root.txt"`

        echo l3sequenceraddress: $l3sequenceraddress
        echo l3owneraddress: $l3owneraddress
        echo l3ownerkey: $l3ownerkey
        echo wasmroot: $wasmroot
        
        echo == Writing l3 chain config
        docker compose -f $COMPOSE_FILE run --rm scripts write-l3-chain-config --l3owner $l3owneraddress
        docker compose -f $COMPOSE_FILE run --rm scripts write-config --simple --l1url ${l1_ws_rpc} --l2url ${l2_ws_rpc}

        # Custom Fee Token Address 추가
        docker compose -f $COMPOSE_FILE run --rm -e PARENT_CHAIN_RPC=$l2_http_rpc -e DEPLOYER_PRIVKEY=$l3ownerkey -e PARENT_CHAIN_ID=$l2_chainid -e CHILD_CHAIN_NAME="minimal-l3-chain" -e MAX_DATA_SIZE=117964 -e OWNER_ADDRESS=$l3owneraddress -e WASM_MODULE_ROOT=$wasmroot -e SEQUENCER_ADDRESS=$l3sequenceraddress -e AUTHORIZE_VALIDATORS=10 -e CHILD_CHAIN_CONFIG_PATH="/config/l3_chain_config.json" -e CHAIN_DEPLOYMENT_INFO="/config/l3deployment.json" -e CHILD_CHAIN_INFO="/config/deployed_l3_chain_info.json" $EXTRA_L3_DEPLOY_FLAG rollupcreator create-rollup-testnode
        docker compose -f $COMPOSE_FILE run --rm --entrypoint sh rollupcreator -c "jq [.[]] /config/deployed_l3_chain_info.json > /config/l3_chain_info.json"

        echo == Funding l3 funnel and dev key
        docker compose -f $COMPOSE_FILE up --wait l3node

        echo == Deploying L2-L3 token bridge
        deployer_key=`printf "%s" "user_token_bridge_deployer" | openssl dgst -sha256 | sed 's/^.*= //'`
        rollupAddress=`docker compose -f $COMPOSE_FILE run --rm --entrypoint sh poster -c "jq -r '.[0].rollup.rollup' /config/deployed_l3_chain_info.json | tail -n 1 | tr -d '\r\n'"`
        l2Weth=""
        # @TODO: L1 tokenbridge 스크립트 문제가 있어 진행 불가
        # l2Weth=`docker compose -f $COMPOSE_FILE run --rm --entrypoint sh tokenbridge -c "cat l1l2_network.json" | jq -r '.l2Network.tokenBridge.l2Weth'`
        # echo l2Weth: $l2Weth

        docker compose -f $COMPOSE_FILE run --rm -e PARENT_WETH_OVERRIDE=$l2Weth -e ROLLUP_OWNER_KEY=$l3ownerkey -e ROLLUP_ADDRESS=$rollupAddress -e PARENT_RPC=$l2_http_rpc -e PARENT_KEY=$deployer_key -e CHILD_RPC=$l3_http_rpc -e CHILD_KEY=$deployer_key tokenbridge deploy:local:token-bridge
        docker compose -f $COMPOSE_FILE run --rm --entrypoint sh tokenbridge -c "cat network.json && cp network.json l2l3_network.json"

        echo == Fund L3 accounts
        docker compose -f $COMPOSE_FILE run --rm scripts bridge-native-token-to-l3 --l2url ${l2_ws_rpc} --amount 5000000 --from user_token_bridge_deployer --wait
        docker compose -f $COMPOSE_FILE run --rm scripts send-l3 --ethamount 500 --from user_token_bridge_deployer --wait
        docker compose -f $COMPOSE_FILE run --rm scripts send-l3 --ethamount 500 --from user_token_bridge_deployer --to "key_0x$devprivkey" --wait
        docker compose -f $COMPOSE_FILE run --rm scripts send-l3 --ethamount 500 --from user_token_bridge_deployer --to l3owner --wait
    fi
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
    docker compose -f $COMPOSE_FILE up $UP_FLAG $NODES
fi
