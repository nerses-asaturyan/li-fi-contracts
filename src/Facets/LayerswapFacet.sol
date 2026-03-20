// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.17;

import { ILiFi } from "../Interfaces/ILiFi.sol";
import { ILayerswapDepository } from "../Interfaces/ILayerswapDepository.sol";
import { LibAsset, IERC20 } from "../Libraries/LibAsset.sol";
import { LibSwap } from "../Libraries/LibSwap.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { SwapperV2 } from "../Helpers/SwapperV2.sol";
import { Validatable } from "../Helpers/Validatable.sol";
import { InvalidCallData } from "../Errors/GenericErrors.sol";

/// @title LayerswapFacet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for bridging through Layerswap Protocol
/// @notice WARNING: We cannot guarantee that our bridgeData corresponds to (off-chain-)
/// @notice          data associated with the provided orderId
/// @custom:version 1.0.0
contract LayerswapFacet is ILiFi, ReentrancyGuard, SwapperV2, Validatable {
    /// Storage ///

    /// @notice The address of the Layerswap Depository contract
    address public immutable LAYERSWAP_DEPOSITORY;

    /// Types ///

    /// @dev Layerswap specific parameters
    /// @param orderId Unique identifier for this deposit (correlates with off-chain order)
    /// @param receiver Whitelisted receiver address in the Layerswap Depository
    struct LayerswapData {
        bytes32 orderId;
        address receiver;
    }

    /// Constructor ///

    /// @param _layerswapDepository The address of the Layerswap Depository contract
    constructor(address _layerswapDepository) {
        if (_layerswapDepository == address(0)) {
            revert InvalidCallData();
        }
        LAYERSWAP_DEPOSITORY = _layerswapDepository;
    }

    /// External Methods ///

    /// @notice Bridges tokens via Layerswap
    /// @param _bridgeData The core information needed for bridging
    /// @param _layerswapData Data specific to Layerswap including orderId and receiver
    function startBridgeTokensViaLayerswap(
        ILiFi.BridgeData calldata _bridgeData,
        LayerswapData calldata _layerswapData
    )
        external
        payable
        nonReentrant
        refundExcessNative(payable(msg.sender))
        validateBridgeData(_bridgeData)
        doesNotContainSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
    {
        LibAsset.depositAsset(
            _bridgeData.sendingAssetId,
            _bridgeData.minAmount
        );
        _startBridge(_bridgeData, _layerswapData);
    }

    /// @notice Performs a swap before bridging via Layerswap
    /// @param _bridgeData The core information needed for bridging
    /// @param _swapData An array of swap related data for performing swaps before bridging
    /// @param _layerswapData Data specific to Layerswap
    function swapAndStartBridgeTokensViaLayerswap(
        ILiFi.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        LayerswapData calldata _layerswapData
    )
        external
        payable
        nonReentrant
        refundExcessNative(payable(msg.sender))
        containsSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
        validateBridgeData(_bridgeData)
    {
        _bridgeData.minAmount = _depositAndSwap(
            _bridgeData.transactionId,
            _bridgeData.minAmount,
            _swapData,
            payable(msg.sender)
        );
        _startBridge(_bridgeData, _layerswapData);
    }

    /// Internal Methods ///

    /// @dev Contains the business logic for bridging via Layerswap
    /// @param _bridgeData The core information needed for bridging
    /// @param _layerswapData Data specific to Layerswap
    function _startBridge(
        ILiFi.BridgeData memory _bridgeData,
        LayerswapData calldata _layerswapData
    ) internal {
        // Validate receiver is not zero address
        if (_layerswapData.receiver == address(0)) {
            revert InvalidCallData();
        }

        if (LibAsset.isNativeAsset(_bridgeData.sendingAssetId)) {
            // Native token deposit
            ILayerswapDepository(LAYERSWAP_DEPOSITORY).depositNative{
                value: _bridgeData.minAmount
            }(_layerswapData.orderId, _layerswapData.receiver);
        } else {
            // ERC20 token deposit - approve depository to pull tokens
            LibAsset.maxApproveERC20(
                IERC20(_bridgeData.sendingAssetId),
                LAYERSWAP_DEPOSITORY,
                _bridgeData.minAmount
            );

            ILayerswapDepository(LAYERSWAP_DEPOSITORY).depositERC20(
                _layerswapData.orderId,
                _bridgeData.sendingAssetId,
                _layerswapData.receiver,
                _bridgeData.minAmount
            );
        }

        emit LiFiTransferStarted(_bridgeData);
    }
}
