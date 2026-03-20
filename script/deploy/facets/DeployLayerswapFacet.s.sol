// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.17;

import { DeployScriptBase } from "./utils/DeployScriptBase.sol";
import { stdJson } from "forge-std/Script.sol";
import { LayerswapFacet } from "lifi/Facets/LayerswapFacet.sol";

contract DeployScript is DeployScriptBase {
    using stdJson for string;

    constructor() DeployScriptBase("LayerswapFacet") {}

    function run()
        public
        returns (LayerswapFacet deployed, bytes memory constructorArgs)
    {
        constructorArgs = getConstructorArgs();

        deployed = LayerswapFacet(
            deploy(type(LayerswapFacet).creationCode)
        );
    }

    function getConstructorArgs() internal override returns (bytes memory) {
        string memory path = string.concat(root, "/config/layerswap.json");

        address layerswapDepository = _getConfigContractAddress(
            path,
            string.concat(".", network, ".layerswapDepository")
        );

        return abi.encode(layerswapDepository);
    }
}
